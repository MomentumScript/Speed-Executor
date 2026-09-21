using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;





static class Multi {
    const int SYS_EXTENDED_HANDLES = 64;
    const int SYS_HANDLES = 16;
    const int OBJ_TYPE = 2, OBJ_NAME = 1;
    const int STATUS_INFO_LEN = unchecked((int)0xC0000004);

    [StructLayout(LayoutKind.Sequential)]
    struct HandleEx {
        public IntPtr Object;
        public UIntPtr UniqueProcessId;
        public UIntPtr HandleValue;
        public uint GrantedAccess;
        public ushort CreatorBackTraceIndex, ObjectTypeIndex;
        public uint HandleAttributes, Reserved;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Handle16 {
        public uint ProcessId;
        public byte ObjectTypeNumber, Flags;
        public ushort Handle;
        public IntPtr Object;
        public uint GrantedAccess;
    }

    static bool TypeIsMutant(IntPtr p) {
        var tn = Marshal.PtrToStructure<Native.UNICODE_STRING>(p);
        if (tn.Length != 12 || tn.Buffer == IntPtr.Zero) return false;
        string s = Marshal.PtrToStringUni(tn.Buffer, tn.Length / 2);
        return string.Equals(s, "Mutant", StringComparison.OrdinalIgnoreCase);
    }
    static bool NameHas(IntPtr p, string needle) {
        var nm = Marshal.PtrToStructure<Native.UNICODE_STRING>(p);
        if (nm.Buffer == IntPtr.Zero || nm.Length == 0) return false;
        string s = Marshal.PtrToStringUni(nm.Buffer, nm.Length / 2);
        return s != null && s.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    

    public static int Unlock(uint pid) {
        IntPtr hProc;
        try { hProc = Native.OpenProcess(Native.PROCESS_DUP_HANDLE | Native.PROCESS_QUERY_INFORMATION, false, pid); }
        catch { return -1; }
        if (hProc == IntPtr.Zero) return -1;
        try {
            int len = 1 << 20;
            IntPtr buf = IntPtr.Zero;
            try {
                uint ret;
                int st = 0;
                bool extended = true;
                for (int t = 0; t < 5; t++) {
                    if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
                    buf = Marshal.AllocHGlobal(len);
                    st = Native.NtQuerySystemInformation(64, buf, (uint)len, out ret);
                    if (st != STATUS_INFO_LEN) break;
                    len = (int)ret + (1 << 20);
                }
                if (st != 0) {
                    extended = false;
                    for (int t = 0; t < 5; t++) {
                        if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
                        buf = Marshal.AllocHGlobal(len);
                        st = Native.NtQuerySystemInformation(16, buf, (uint)len, out ret);
                        if (st != STATUS_INFO_LEN) break;
                        len = (int)ret + (1 << 20);
                    }
                }
                int closed = 0;
                if (st == 0) {
                    if (extended) {
                        ulong count = (ulong)Marshal.ReadIntPtr(buf).ToInt64();
                        int off = IntPtr.Size * 2;
                        int esz = Marshal.SizeOf(typeof(HandleEx));
                        for (ulong i = 0; i < count; i++) {
                            IntPtr e = new IntPtr(buf.ToInt64() + off + (long)(i * (ulong)esz));
                            var he = Marshal.PtrToStructure<HandleEx>(e);
                            if ((uint)he.UniqueProcessId.ToUInt64() != pid) continue;
                            if (TryCloseSingleton(hProc, (IntPtr)(long)he.HandleValue.ToUInt64())) closed++;
                        }
                    } else {
                        uint count = (uint)Marshal.ReadInt32(buf);
                        int off = IntPtr.Size;
                        int esz = Marshal.SizeOf(typeof(Handle16));
                        for (uint i = 0; i < count; i++) {
                            IntPtr e = new IntPtr(buf.ToInt64() + off + i * esz);
                            var he = Marshal.PtrToStructure<Handle16>(e);
                            if (he.ProcessId != pid) continue;
                            if (TryCloseSingleton(hProc, (IntPtr)(long)(ulong)he.Handle)) closed++;
                        }
                    }
                }
                if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
                return closed;
            } catch { return -1; }
        } finally { Native.CloseHandle(hProc); }
    }

    static bool TryCloseSingleton(IntPtr hProc, IntPtr hval) {
        IntPtr dup;
        if (Native.NtDuplicateObject(hProc, hval, Process.GetCurrentProcess().Handle,
                out dup, 0, 0, 0) != 0 || dup == IntPtr.Zero) return false;
        try {
            IntPtr tb = Marshal.AllocHGlobal(512);
            try {
                uint r;
                if (Native.NtQueryObject(dup, OBJ_TYPE, tb, 512, out r) != 0) return false;
                if (!TypeIsMutant(tb)) return false;
            } finally { Marshal.FreeHGlobal(tb); }
            IntPtr nb = Marshal.AllocHGlobal(1024);
            try {
                uint r2;
                if (Native.NtQueryObject(dup, OBJ_NAME, nb, 1024, out r2) != 0) return false;
                if (!NameHas(nb, "ROBLOX_singleton")) return false;
            } finally { Marshal.FreeHGlobal(nb); }
        } finally { Native.CloseHandle(dup); }
        IntPtr dummy;
        return Native.NtDuplicateObject(hProc, hval, IntPtr.Zero, out dummy, 0, 0, Native.DUPLICATE_CLOSE_SOURCE) == 0;
    }

    public static List<uint> AllRoblox() {
        var outList = new List<uint>();
        try {
            foreach (var p in Process.GetProcessesByName("RobloxPlayerBeta")) {
                outList.Add((uint)p.Id);
                p.Dispose();
            }
        } catch { }
        return outList;
    }

    public static string ExePath(uint pid) {
        try {
            using (var p = Process.GetProcessById((int)pid))
                return p.MainModule.FileName;
        } catch { return null; }
    }

    public static void DoUnlock(Form owner, Action<string> log) {
        var pids = AllRoblox();
        if (pids.Count == 0) { log("No Roblox client running"); return; }
        int total = 0, reachable = 0;
        foreach (uint pid in pids) {
            int c = Unlock(pid);
            if (c >= 0) { reachable++; if (c > 0) total += c; }
        }
        if (total > 0) log("Multi-instance unlocked — now Launch 2nd");
        else if (reachable > 0) log("No singleton lock found — Launch 2nd uses the --multiInstance flag anyway");
        else log("Unlock failed (run ares as admin)");
    }

    public static void DoLaunch2(Form owner, Action<string> log) {
        var pids = AllRoblox();
        if (pids.Count == 0) { log("Start your main client first"); return; }
        string exe = ExePath(pids[0]);
        if (exe == null) { log("Cannot locate Roblox exe"); return; }
        try {
            var psi = new ProcessStartInfo {
                FileName = exe,
                Arguments = "--multiInstance",
                WorkingDirectory = System.IO.Path.GetDirectoryName(exe),
                UseShellExecute = false,
            };
            Process.Start(psi);
        } catch { log("2nd client launch failed"); return; }
        log("2nd client launching as ALT — log in there");
    }
}
