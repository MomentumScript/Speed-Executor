using System;
using System.Diagnostics;
using System.IO;



static class Compiler {
    public static byte[] Compile(byte[] src, out string err) {
        err = null;
        string tmp = Path.Combine(Path.GetTempPath(),
            "ares_src_" + Process.GetCurrentProcess().Id + "_" + Environment.TickCount + ".luau");
        try { File.WriteAllBytes(tmp, src); }
        catch { err = "temp write failed"; return null; }

        string compiler = Fapi.CompilerPath();
        if (compiler == null) { err = "compiler missing"; return null; }

        byte[] result = null;
        try {
            var psi = new ProcessStartInfo {
                FileName = compiler,
                Arguments = "\"" + tmp + "\" --binary",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using (var p = Process.Start(psi)) {
                

                

                var stderrTask = p.StandardError.ReadToEndAsync();
                var ms = new MemoryStream();
                p.StandardOutput.BaseStream.CopyTo(ms);
                string stderrText = null;
                try { stderrText = stderrTask.GetAwaiter().GetResult(); } catch { }
                if (!p.WaitForExit(30000)) { try { p.Kill(); } catch { } err = "compile timeout"; }
                else if (p.ExitCode != 0) err = FirstCompilerError(stderrText);
                else result = ms.ToArray();
                if (result != null && result.Length == 0) {
                    err = FirstCompilerError(stderrText);
                    result = null;
                }
            }
        } catch { err = "CreateProcess failed"; }
        try { File.Delete(tmp); } catch { }
        return result;
    }

    

    

    

    static string FirstCompilerError(string stderrText) {
        if (!string.IsNullOrWhiteSpace(stderrText)) {
            foreach (string raw in stderrText.Split('\n')) {
                string line = raw.Trim();
                if (line.Length == 0) continue;
                if (line.IndexOf("Error:", StringComparison.OrdinalIgnoreCase) >= 0)
                    return "compile " + line;
            }
            string trimmed = stderrText.Trim();
            return "compile " + (trimmed.Length > 300 ? trimmed.Substring(0, 300) : trimmed);
        }
        return "compile failed (compiler reported nothing)";
    }
}
