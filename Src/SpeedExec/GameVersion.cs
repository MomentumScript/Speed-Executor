using System;
using System.Diagnostics;
using System.Text.RegularExpressions;





static class GameVersion {
    static readonly Regex Rx = new Regex(@"version-[a-f0-9]{8,32}",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static string Detect(uint pid) {
        try {
            using (var p = Process.GetProcessById((int)pid)) {
                string path = null;
                try { path = p.MainModule != null ? p.MainModule.FileName : null; } catch { }
                if (!string.IsNullOrEmpty(path)) {
                    var m = Rx.Match(path);
                    if (m.Success) return m.Value;
                }
            }
        } catch { }
        return null;
    }
}
