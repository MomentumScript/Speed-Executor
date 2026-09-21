using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;







static class AiServer {
    

    static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromHours(2) };
    static readonly HttpClient Probe = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };

    static readonly string ModelUrl =
        "https://huggingface.co/zzkkdinx/Qwen2.5-1.5B-Instruct-Q4_K_M-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf";

    static Process _proc;

    static string Dir() => Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AiServer");
    static string ServerExe() => Path.Combine(Dir(), "llama-server.exe");
    static string ModelFile() => Path.Combine(Dir(), "model.gguf");

    

    public static async Task<bool> IsHealthyAsync(string baseUrl) {
        string url = baseUrl.Trim().TrimEnd('/') + "/health";
        try {
            using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2)))
            using (var resp = await Probe.GetAsync(url, cts.Token).ConfigureAwait(false))
                return resp.IsSuccessStatusCode;
        } catch {
            return false;
        }
    }

    

    

    public static async Task EnsureRunningAsync(string baseUrl, Func<string, Task> status) {
        if (await IsHealthyAsync(baseUrl).ConfigureAwait(false)) return;
        if (_proc != null && !_proc.HasExited) return;

        int port = PortOf(baseUrl);
        bool loopback;
        try {
            var u = new Uri(baseUrl);
            loopback = string.Equals(u.Host, "localhost", StringComparison.OrdinalIgnoreCase) ||
                       u.Host == "127.0.0.1" || u.Host == "::1" || u.Host == "[::1]";
        } catch { loopback = false; }

        if (!loopback) {
            throw new Exception("The AI server at \"" + baseUrl + "\" is not reachable. Start it manually or point the Server box at a local address (127.0.0.1).");
        }

        Directory.CreateDirectory(Dir());

        if (!File.Exists(ServerExe())) {
            await status("AI server engine not found - downloading...").ConfigureAwait(false);
            await DownloadServerAsync(status).ConfigureAwait(false);
        }

        if (!File.Exists(ModelFile())) {
            await status("AI model not found - downloading model (~1 GB, one time)...").ConfigureAwait(false);
            await DownloadFileAsync(ModelUrl, ModelFile(), status).ConfigureAwait(false);
        }

        await status("Starting local AI server on port " + port + "...").ConfigureAwait(false);
        StartServer(port);

        int waited = 0;
        string healthBase = "http://127.0.0.1:" + port;
        while (waited < 1200) {
            if (await IsHealthyAsync(healthBase).ConfigureAwait(false)) {
                await status("Local AI server ready.").ConfigureAwait(false);
                return;
            }
            if (_proc != null && _proc.HasExited) {
                throw new Exception("The AI server closed unexpectedly. Try again or run it yourself on port " + port + ".");
            }
            await Task.Delay(500).ConfigureAwait(false);
            waited++;
        }
        throw new Exception("The AI server did not become ready in time.");
    }

    public static void Shutdown() {
        try {
            if (_proc != null && !_proc.HasExited) _proc.Kill();
            _proc = null;
        } catch { }
    }

    static int PortOf(string baseUrl) {
        try { return new Uri(baseUrl).Port; } catch { return 8080; }
    }

    static void StartServer(int port) {
        var psi = new ProcessStartInfo {
            FileName = ServerExe(),
            Arguments = "-m \"" + ModelFile() + "\" --host 127.0.0.1 --port " + port +
                        " --ctx-size 8192 --parallel 1 --no-warmup",
            WorkingDirectory = Dir(),
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        _proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        _proc.OutputDataReceived += (s, e) => Log(e.Data);
        _proc.ErrorDataReceived += (s, e) => Log(e.Data);
        _proc.Start();
        _proc.BeginOutputReadLine();
        _proc.BeginErrorReadLine();
    }

    static void Log(string line) {
        if (!string.IsNullOrEmpty(line)) System.Diagnostics.Debug.WriteLine("[AiServer] " + line);
    }

    static async Task DownloadServerAsync(Func<string, Task> status) {
        const string apiUrl = "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest";
        var req = new HttpRequestMessage(HttpMethod.Get, apiUrl);
        req.Headers.Add("User-Agent", "SpeedExecutor");
        using (var resp = await Http.SendAsync(req).ConfigureAwait(false)) {
            string json = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
                throw new Exception("Could not fetch the latest server build: HTTP " + resp.StatusCode);
            string assetUrl = null, assetName = null;
            using (var doc = JsonDocument.Parse(json)) {
                foreach (var a in doc.RootElement.GetProperty("assets").EnumerateArray()) {
                    string name = a.TryGetProperty("name", out var n) ? n.GetString() : null;
                    if (name != null &&
                        name.Contains("-bin-win-cpu-x64", StringComparison.OrdinalIgnoreCase) &&
                        name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) {
                        assetName = name;
                        assetUrl = a.GetProperty("browser_download_url").GetString();
                        break;
                    }
                }
            }
            if (assetUrl == null)
                throw new Exception("Could not find a Windows CPU build for the AI server.");
            string zip = Path.Combine(Dir(), assetName);
            await DownloadFileAsync(assetUrl, zip, status).ConfigureAwait(false);
            await Task.Run(() =>
            {
                string tmp = Path.Combine(Dir(), "_extract");
                if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
                Directory.CreateDirectory(tmp);
                System.IO.Compression.ZipFile.ExtractToDirectory(zip, tmp);
                string src = Path.Combine(tmp, "llama-server.exe");
                if (!File.Exists(src)) src = Path.Combine(tmp, "build", "bin", "llama-server.exe");
                if (!File.Exists(src)) throw new IOException("llama-server.exe not found in archive");
                File.Copy(src, ServerExe(), true);
                try { Directory.Delete(tmp, true); } catch { }
            }).ConfigureAwait(false);
            try { File.Delete(zip); } catch { }
        }
        if (!File.Exists(ServerExe()))
            throw new Exception("Server download finished but the executable was not found.");
    }

    static async Task DownloadFileAsync(string url, string dest, Func<string, Task> status) {
        string tmp = dest + ".tmp";
        if (File.Exists(tmp)) { try { File.Delete(tmp); } catch { } }
        Directory.CreateDirectory(Path.GetDirectoryName(dest));
        using (var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
            string body = null;
            if (!resp.IsSuccessStatusCode) {
                using (var c = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                using (var sr = new StreamReader(c))
                    body = sr.ReadToEnd();
                throw new Exception("Download failed: HTTP " + resp.StatusCode + (body == null ? "" : " " + body.Substring(0, Math.Min(120, body.Length))));
            }
            long total = resp.Content.Headers.ContentLength ?? 0;
            using (var src = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
            using (var dst = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true)) {
                var buf = new byte[81920];
                long done = 0;
                long lastReport = 0;
                int r;
                while ((r = await src.ReadAsync(buf, 0, buf.Length).ConfigureAwait(false)) > 0) {
                    await dst.WriteAsync(buf, 0, r).ConfigureAwait(false);
                    done += r;
                    if (total > 0 && done - lastReport >= 16 * 1024 * 1024) {
                        lastReport = done;
                        await status("Downloading... " + (done / (1024 * 1024)) + " MB / " + (total / (1024 * 1024)) + " MB").ConfigureAwait(false);
                    }
                }
            }
        }
        if (File.Exists(dest)) { try { File.Delete(dest); } catch { } }
        File.Move(tmp, dest);
    }
}