using System;
using System.IO;
using System.Reflection;





static class Fapi {
    public static string ExeDir() {
        string p = Assembly.GetExecutingAssembly().Location;
        return Path.GetDirectoryName(p) + Path.DirectorySeparatorChar;
    }
    static string DiskLuauDir() { return Path.Combine(ExeDir(), "FAPI", "luau") + Path.DirectorySeparatorChar; }

    static byte[] FromDisk(string name) {
        try {
            

            string a = Path.Combine(DiskLuauDir(), name);
            if (File.Exists(a)) return File.ReadAllBytes(a);
            string b = Path.Combine(ExeDir(), "..", "FAPI", "luau", name);
            if (File.Exists(b)) return File.ReadAllBytes(b);
        } catch { }
        return null;
    }
    static byte[] FromBundle(string res) {
        try {
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(res)) {
                if (s == null) return null;
                var ms = new MemoryStream();
                s.CopyTo(ms);
                return ms.ToArray();
            }
        } catch { return null; }
    }
    static byte[] Get(string res, string diskName) {
        return FromDisk(diskName) ?? FromBundle(res);
    }

    public static byte[] InitBin() { return Get("FAPI.luau.init.bin", "init.bin"); }
    public static byte[] InitLuau() { return Get("FAPI.luau.init.luau", "init.luau"); }

    

    static string _compilerPath;
    public static string CompilerPath() {
        if (_compilerPath != null) return _compilerPath;
        string disk = Path.Combine(DiskLuauDir(), "compile.exe");
        if (File.Exists(disk)) { _compilerPath = disk; return disk; }
        string parent = Path.Combine(ExeDir(), "..", "FAPI", "luau", "compile.exe");
        if (File.Exists(parent)) { _compilerPath = parent; return parent; }
        var data = FromBundle("FAPI.luau.compile.exe");
        if (data == null) return null;
        string dir = Path.Combine(Path.GetTempPath(), "ares_bundle", "r11");
        try { Directory.CreateDirectory(dir); } catch { }
        string target = Path.Combine(dir, "compile.exe");
        bool write = true;
        try {
            var fi = new FileInfo(target);
            if (fi.Exists && fi.Length == data.Length) write = false;
        } catch { }
        if (write) { try { File.WriteAllBytes(target, data); } catch { return null; } }
        _compilerPath = target;
        return target;
    }

    public static string AppData() {
        return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
    }
    public static string AresDir() { return Path.Combine(AppData(), "ares"); }
    static string _workspace;
    public static string WorkspaceDir() {
        if (_workspace != null) return _workspace;
        string localWs = Path.Combine(ExeDir(), "workspace");
        string legacy = Path.Combine(AresDir(), "workspace");
        bool legacyHasFiles = false;
        try {
            if (Directory.Exists(legacy))
                foreach (var e in Directory.EnumerateFileSystemEntries(legacy)) {
                    var n = Path.GetFileName(e);
                    if (!n.StartsWith(".")) { legacyHasFiles = true; break; }
                }
        } catch { }
        bool localOk = false;
        try {
            Directory.CreateDirectory(localWs);
            string probe = Path.Combine(localWs, ".writetest");
            File.WriteAllBytes(probe, new byte[1]);
            File.Delete(probe);
            localOk = true;
        } catch { }
        _workspace = (!legacyHasFiles && localOk) ? localWs : legacy;
        return _workspace;
    }
    public static void EnsureWorkspace() {
        try { Directory.CreateDirectory(AresDir()); } catch { }
        try { Directory.CreateDirectory(WorkspaceDir()); } catch { }
        try { Directory.CreateDirectory(Path.Combine(WorkspaceDir(), "scripts")); } catch { }
    }
    public static string WorkspacePath(string rel) {
        if (rel.Contains("..\\") || rel.Contains("../")) return null;
        return Path.Combine(WorkspaceDir(), rel);
    }
}
