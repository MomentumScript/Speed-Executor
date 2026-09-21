using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Windows.Forms;





static class Executor {
    public static Roblox Rbx = new Roblox();

    static ulong GetBase(uint pid) {
        try {
            using (var p = Process.GetProcessById((int)pid))
                return (ulong)p.MainModule.BaseAddress.ToInt64();
        } catch { return 0; }
    }

    public static uint FindPid(string name) {
        uint best = 0; int bestScore = int.MinValue;
        Process[] procs;
        try { procs = Process.GetProcessesByName("RobloxPlayerBeta"); }
        catch { return 0; }
        foreach (var p in procs) {
            try {
                if (p.HasExited) continue;
                int score = 1;
                try {
                    if (p.MainWindowHandle != IntPtr.Zero && !string.IsNullOrEmpty(p.MainWindowTitle))
                        score += 100;
                } catch { }
                if (score > bestScore) { bestScore = score; best = (uint)p.Id; }
            } catch { }
            finally { try { p.Dispose(); } catch { } }
        }
        return best;
    }

    

    

    public static void SetOffsets(string text) { }

    public static bool Startup(uint pid) {
        try {
            Mem.Pid = pid;
            Mem.Base = GetBase(pid);
            Mem.Proc = Native.OpenProcess(Native.PROCESS_ALL_ACCESS, false, pid);
            if (Mem.Proc == IntPtr.Zero) return false;
            Fapi.EnsureWorkspace();
            Fapi.CompilerPath(); 

            try { Rbx.Init(); } catch { }
            Bridge.EnsureStarted();
            return true;
        } catch { return false; }
    }

    public static void Shutdown() {
        Bridge.Stop();
        if (Mem.Proc != IntPtr.Zero) { Native.CloseHandle(Mem.Proc); Mem.Proc = IntPtr.Zero; }
    }

    public static void EnsureBridge() {
        Fapi.EnsureWorkspace();
        Fapi.CompilerPath();
        Bridge.EnsureStarted();
    }

    public static bool Reattach(out string why) {
        why = null;
        uint pid = FindPid("RobloxPlayerBeta.exe");
        if (pid == 0) { why = "Roblox is not running"; return false; }
        if (pid != Mem.Pid || Mem.Proc == IntPtr.Zero) {
            IntPtr h = Native.OpenProcess(Native.PROCESS_ALL_ACCESS, false, pid);
            if (h == IntPtr.Zero) { why = "Cannot open Roblox (run as admin)"; return false; }
            if (Mem.Proc != IntPtr.Zero) Native.CloseHandle(Mem.Proc);
            Mem.Proc = h;
            Mem.Pid = pid;
            Mem.Base = GetBase(pid);
        } else {
            uint code;
            if (!Native.GetExitCodeProcess(Mem.Proc, out code) || code != Native.STILL_ACTIVE) {
                Native.CloseHandle(Mem.Proc);
                Mem.Proc = IntPtr.Zero; Mem.Pid = 0; Mem.Base = 0;
                return Reattach(out why);
            }
        }
        if (!Rbx.Init()) { why = "Join a game first"; return false; }
        return true;
    }

    public static string DatamodelName {
        get { try { return Mem.Name(Rbx.Datamodel); } catch { return ""; } }
    }

    public static bool IsInjected() {
        return Mem.Find(Rbx.Datamodel, "CoreGui", "_speedexecutor") != 0;
    }

    static ExploitRevert ScriptExploit(ulong script, byte[] bc) {
        var r = new ExploitRevert();
        ulong ptr = Mem.U64(script + Off.Module_BC);
        if (!Mem.Valid(ptr)) return r;
        ulong bcbuf = Mem.U64(ptr + Off.BC_Ptr);
        ulong size = Mem.U64(ptr + Off.BC_Size);
        IntPtr buffer = Mem.Alloc(bc.Length);
        if (buffer == IntPtr.Zero) return r;
        if (!Mem.Write((ulong)buffer.ToInt64(), bc)) { Mem.Free(buffer); return r; }
        var verify = Mem.Read((ulong)buffer.ToInt64(), bc.Length);
        if (verify == null) { Mem.Free(buffer); return r; }
        for (int i = 0; i < bc.Length; i++)
            if (verify[i] != bc[i]) { Mem.Free(buffer); return r; }
        Mem.WriteU64(ptr + Off.BC_Ptr, (ulong)buffer.ToInt64());
        Mem.WriteU64(ptr + Off.BC_Size, (ulong)bc.Length);
        r.Ptr = ptr; r.OrigBc = bcbuf; r.OrigSz = size;
        r.Buffer = (ulong)buffer.ToInt64(); r.Valid = true;
        return r;
    }

    public static bool Inject(out string log) {
        var sb = new StringBuilder();
        Action<string> plog = s => sb.Append(s).Append('\n');
        if (IsInjected()) { plog("Skipping injection, already injected."); log = sb.ToString(); return true; }
        plog("--- INJECTING ---");
        IntPtr hwnd = Win.GetHwnd(Mem.Pid);
        if (hwnd == IntPtr.Zero) { plog("[!] No Roblox window"); log = sb.ToString(); return false; }
        plog("Client HWND: 0x" + hwnd.ToInt64().ToString("X"));
        ulong plm = Mem.Find(Rbx.Datamodel, "CoreGui", "RobloxGui", "Modules", "PlayerList", "PlayerListManager");
        if (plm == 0) { plog("[!] PlayerListManager not found"); log = sb.ToString(); return false; }
        plog("got PlayerListManager: 0x" + plm.ToString("X"));
        ulong addr = Rbx.BaseAddress + Off.FFlag_EnableLoadModule;
        plog("got EnableLoadModule: 0x" + addr.ToString("X"));
        Mem.WriteBool(addr, true);
        Mem.WriteI32(plm + Off.Module_State, 0);
        plog("set PlayerListManager.ModuleState to 0");
        byte[] bc = Fapi.InitBin();
        if (bc == null || bc.Length == 0) { plog("[!] init.bin missing (bundle + disk)"); log = sb.ToString(); return false; }
        plog("init.bin: " + bc.Length + " bytes");
        var revert = ScriptExploit(plm, bc);
        if (!revert.Valid) { plog("[!] exploit() failed"); log = sb.ToString(); return false; }
        plog("replace bytecode in Jest");
        IntPtr oldfg = Native.GetForegroundWindow();
        Win.ForceForeground(hwnd);
        Win.PressEsc();
        plog("sent escape key (triggered plm)");
        revert.Run();
        Win.PressEsc();
        if (oldfg != IntPtr.Zero) Native.SetForegroundWindow(oldfg);
        plog("reverted bytecode replacement");
        plog("Injected");
        log = sb.ToString();
        return true;
    }

    public static bool Execute(string source, out string log) {
        if (!IsInjected()) { log = "You must inject before executing"; return false; }
        ulong root = Mem.Find(Rbx.Datamodel, "CoreGui", "_speedexecutor");
        if (root == 0) { log = "_speedexecutor missing"; return false; }
        ulong upd = Mem.FindChild(root, "UpdateIndicator");
        if (upd == 0) { log = "UpdateIndicator missing"; return false; }
        string err;
        byte[] bc = Compiler.Compile(Encoding.UTF8.GetBytes(source), out err);
        if (bc == null || bc.Length == 0) { log = "compile: " + err; return false; }
        Bridge.SetTarget(bc);
        bool cur = Mem.Bool(upd + Off.Misc_Value);
        Mem.WriteBool(upd + Off.Misc_Value, !cur);
        log = "Executed";
        return true;
    }
}
