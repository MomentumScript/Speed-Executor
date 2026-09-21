using System;
using System.Collections.Generic;
using System.Text;



static class Mem {
    public static IntPtr Proc = IntPtr.Zero;
    public static uint Pid;
    public static ulong Base;

    public static bool Valid(ulong p) { return p >= 0x10000 && p <= 0x7FFFFFFFFFFFUL; }

    public static byte[] Read(ulong a, int n) {
        var b = new byte[n];
        int r;
        if (!Native.ReadProcessMemory(Proc, (IntPtr)(long)a, b, n, out r) || r != n) return null;
        return b;
    }
    public static ulong U64(ulong a) { var b = Read(a, 8); return b == null ? 0 : BitConverter.ToUInt64(b, 0); }
    public static int I32(ulong a) { var b = Read(a, 4); return b == null ? 0 : BitConverter.ToInt32(b, 0); }
    public static bool Bool(ulong a) { var b = Read(a, 1); return b != null && b[0] != 0; }
    public static float F32(ulong a) { var b = Read(a, 4); return b == null ? 0 : BitConverter.ToSingle(b, 0); }
    public static bool Write(ulong a, byte[] b) {
        int w;
        return Native.WriteProcessMemory(Proc, (IntPtr)(long)a, b, b.Length, out w) && w == b.Length;
    }
    public static bool WriteU64(ulong a, ulong v) { return Write(a, BitConverter.GetBytes(v)); }
    public static bool WriteI32(ulong a, int v) { return Write(a, BitConverter.GetBytes(v)); }
    public static bool WriteBool(ulong a, bool v) { return Write(a, new byte[] { (byte)(v ? 1 : 0) }); }
    public static bool WriteF32(ulong a, float v) { return Write(a, BitConverter.GetBytes(v)); }
    public static bool WriteVec3(ulong a, Vec3 v) {
        var b = new byte[12];
        Buffer.BlockCopy(BitConverter.GetBytes(v.X), 0, b, 0, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(v.Y), 0, b, 4, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(v.Z), 0, b, 8, 4);
        return Write(a, b);
    }
    public static Vec3 ReadVec3(ulong a) {
        var b = Read(a, 12);
        if (b == null) return new Vec3();
        return new Vec3 {
            X = BitConverter.ToSingle(b, 0),
            Y = BitConverter.ToSingle(b, 4),
            Z = BitConverter.ToSingle(b, 8),
        };
    }
    public static IntPtr Alloc(int n) {
        return Native.VirtualAllocEx(Proc, IntPtr.Zero, n,
            Native.MEM_COMMIT | Native.MEM_RESERVE, Native.PAGE_READWRITE);
    }
    public static void Free(IntPtr p) { Native.VirtualFreeEx(Proc, p, 0, Native.MEM_RELEASE); }

    

    public static string ReadStdStr(ulong obj) {
        if (!Valid(obj)) return "";
        var raw = Read(obj, 32);
        if (raw == null) return "";
        ulong len = BitConverter.ToUInt64(raw, 0x10);
        ulong cap = BitConverter.ToUInt64(raw, 0x18);
        if (len == 0 || len > 512) return "";
        if (cap > 15) {
            ulong heap = BitConverter.ToUInt64(raw, 0);
            if (!Valid(heap)) return "";
            var b = Read(heap, (int)len);
            if (b == null) return "";
            return Encoding.UTF8.GetString(b);
        }
        return Encoding.UTF8.GetString(raw, 0, (int)len);
    }

    public static string Name(ulong inst) {
        if (!Valid(inst)) return "";
        ulong c = U64(inst + Off.Instance_NameContainer);
        if (!Valid(c)) return "";
        return ReadStdStr(c + Off.Instance_Name);
    }
    public static string ClassName(ulong inst) {
        if (!Valid(inst)) return "";
        ulong desc = U64(inst + Off.Instance_ClassDesc);
        if (!Valid(desc)) return "";
        ulong np = U64(desc + Off.Instance_ClassName);
        if (!Valid(np)) return "";
        return ReadStdStr(np);
    }
    public static List<ulong> Children(ulong inst) {
        var outList = new List<ulong>();
        if (!Valid(inst)) return outList;
        ulong container = U64(inst + Off.Instance_ChildrenStart);
        if (container == 0) return outList;
        ulong start = U64(container);
        ulong end = U64(container + Off.Instance_ChildrenEnd);
        if (!Valid(start) || end < start || end - start > 0xFFFFFF) return outList;
        for (ulong p = start; p < end; p += 16) {
            ulong c = U64(p);
            if (c != 0) outList.Add(c);
        }
        return outList;
    }
    public static ulong FindChild(ulong inst, string name) {
        foreach (var c in Children(inst)) {
            try { if (Name(c) == name) return c; } catch { }
        }
        return 0;
    }
    public static ulong Find(ulong inst, params string[] path) {
        ulong cur = inst;
        foreach (var p in path) {
            cur = FindChild(cur, p);
            if (cur == 0) return 0;
        }
        return cur;
    }
}

struct Vec3 { public float X, Y, Z; }

class Roblox {
    public ulong Datamodel;
    public ulong BaseAddress;
    public bool Init() {
        BaseAddress = Mem.Base;
        ulong fdm = Mem.U64(BaseAddress + Off.FDM_Pointer);
        if (!Mem.Valid(fdm)) return false;
        ulong real = Mem.U64(fdm + Off.FDM_RealDataModel);
        if (!Mem.Valid(real)) return false;
        Datamodel = real;
        return true;
    }
}

class ExploitRevert {
    public ulong Ptr, OrigBc, OrigSz, Buffer;
    public bool Valid;
    public void Run() {
        if (!Valid) return;
        Mem.WriteU64(Ptr + Off.BC_Ptr, OrigBc);
        Mem.WriteU64(Ptr + Off.BC_Size, OrigSz);
        Mem.Free((IntPtr)(long)Buffer);
    }
}

static class Win {
    public static IntPtr GetHwnd(uint pid) {
        IntPtr found = IntPtr.Zero;
        Native.EnumWindows((h, l) => {
            uint wpid;
            Native.GetWindowThreadProcessId(h, out wpid);
            if (wpid == pid && Native.IsWindowVisible(h)) {
                var sb = new StringBuilder(128);
                Native.GetWindowTextA(h, sb, sb.Capacity);
                if (sb.Length > 0) { found = h; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static void PressEsc() {
        var d = new Native.INPUT[1];
        d[0].type = 1;
        d[0].u.ki.wScan = 0x01;
        d[0].u.ki.dwFlags = 0x0008; 

        var u = new Native.INPUT[1];
        u[0].type = 1;
        u[0].u.ki.wScan = 0x01;
        u[0].u.ki.dwFlags = 0x0008 | 0x0002; 

        Native.SendInput(1, d, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
        Native.SendInput(1, u, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
        System.Threading.Thread.Sleep(100);
    }
    public static void ForceForeground(IntPtr hwnd) {
        IntPtr fg = Native.GetForegroundWindow();
        uint fgTid = 0, ourTid = GetCurrentThreadId();
        if (fg != IntPtr.Zero) Native.GetWindowThreadProcessId(fg, out fgTid);
        if (fgTid != 0 && fgTid != ourTid) Native.AttachThreadInput(ourTid, fgTid, true);
        Native.BringWindowToTop(hwnd);
        Native.ShowWindow(hwnd, Native.SW_SHOW);
        Native.SetForegroundWindow(hwnd);
        Native.SetFocus(hwnd);
        Native.SetActiveWindow(hwnd);
        if (fgTid != 0 && fgTid != ourTid) Native.AttachThreadInput(ourTid, fgTid, false);
        for (int i = 0; i < 10 && Native.GetForegroundWindow() != hwnd; i++)
            System.Threading.Thread.Sleep(30);
    }
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
}
