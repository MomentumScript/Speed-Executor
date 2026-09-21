using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;





static class Bridge {
    static TcpListener _listener;
    static byte[] _targetSource = new byte[0];
    static readonly object _lock = new object();
    static int _fpsCap = 60;
    static ulong _valueOffset;
    public static volatile bool IsRunning;
    static volatile bool _startRequested;
    static readonly object _startLock = new object();

    

    static readonly System.Net.Http.HttpClient Http = new System.Net.Http.HttpClient(
        new System.Net.Http.HttpClientHandler {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            AllowAutoRedirect = true,
        }, true) { Timeout = TimeSpan.FromSeconds(60) };

    

    static readonly Dictionary<int, System.Net.WebSockets.ClientWebSocket> _wsSockets = new Dictionary<int, System.Net.WebSockets.ClientWebSocket>();
    static readonly Dictionary<int, System.Collections.Concurrent.ConcurrentQueue<string>> _wsRecv = new Dictionary<int, System.Collections.Concurrent.ConcurrentQueue<string>>();
    static readonly object _wsLock = new object();
    static int _wsNext = 0;

    

    public static Func<string> GetClipboard;
    public static Action<string> SetClipboard;

    

    static readonly List<string> _console = new List<string>();
    public static event Action<string> ConsoleLine;

    public static void LogLine(string line) {
        if (line == null) return;
        lock (_lock) {
            if (_console.Count > 5000) _console.RemoveRange(0, 1000);
            _console.Add(line);
        }
        var handler = ConsoleLine;
        if (handler != null) { try { handler(line); } catch { } }
    }
    public static string ConsoleText() { lock (_lock) { return string.Join("\n", _console); } }
    public static event Action ConsoleCleared;
    public static void ClearConsole() {
        lock (_lock) { _console.Clear(); }
        var handler = ConsoleCleared;
        if (handler != null) { try { handler(); } catch { } }
    }

    public static void SetTarget(byte[] bc) { lock (_lock) { _targetSource = bc; } }

    public static void EnsureStarted() {
        if (_startRequested) return;
        lock (_startLock) {
            if (_startRequested) return;
            _startRequested = true;
            new Thread(Run) { IsBackground = true }.Start();
        }
    }

    public static void Run() {
        try {
            _listener = new TcpListener(IPAddress.Loopback, Off.BridgePort);
            _listener.Start(8);
        } catch { _startRequested = false; return; }
        IsRunning = true;
        for (;;) {
            try {
                var c = _listener.AcceptTcpClient();
                ThreadPool.QueueUserWorkItem(Handle, c);
            } catch { break; }
        }
    }
    public static void Stop() { IsRunning = false; try { if (_listener != null) _listener.Stop(); } catch { } }

    static void Handle(object o) {
        var c = (TcpClient)o;
        try {
            using (c) {
                var ns = c.GetStream();
                ns.ReadTimeout = 15000;
                var req = new List<byte>();
                var one = new byte[1];
                int headerEnd = -1;
                while (req.Count < 65536) {
                    int r;
                    try { r = ns.Read(one, 0, 1); } catch { break; }
                    if (r <= 0) break;
                    req.Add(one[0]);
                    int n = req.Count;
                    if (n >= 4 && req[n-4] == '\r' && req[n-3] == '\n' && req[n-2] == '\r' && req[n-1] == '\n') {
                        headerEnd = n;
                        break;
                    }
                }
                if (headerEnd < 0) return;
                string head = Encoding.ASCII.GetString(req.ToArray(), 0, headerEnd);
                bool isGet = head.StartsWith("GET ");
                int contentLen = 0;
                int cl = head.IndexOf("Content-Length:");
                if (cl >= 0) {
                    int eol = head.IndexOf("\r\n", cl);
                    int.TryParse(head.Substring(cl + 15, eol - cl - 15).Trim(), out contentLen);
                }
                if (contentLen < 0 || contentLen > 64 * 1024 * 1024) return;
                var body = new byte[contentLen];
                int got = 0;
                while (got < contentLen) {
                    int r = ns.Read(body, got, contentLen - got);
                    if (r <= 0) break;
                    got += r;
                }
                if (got < contentLen) return;
                byte[] resp = isGet ? LockedTarget() : Dispatch(body);
                string hdr = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " + resp.Length + "\r\n\r\n";
                byte[] hb = Encoding.ASCII.GetBytes(hdr);
                ns.Write(hb, 0, hb.Length);
                if (resp.Length > 0) ns.Write(resp, 0, resp.Length);
            }
        } catch { }
    }
    static byte[] LockedTarget() { lock (_lock) { return _targetSource; } }

    static byte[] Dispatch(byte[] post) {
        int nl = Array.IndexOf(post, (byte)'\n');
        string method;
        var args = new List<byte[]>();
        if (nl < 0) { method = S(post); }
        else {
            method = S(post, 0, nl);
            if (method == "compile_raw") {
                args.Add(Sub(post, nl + 1, post.Length - nl - 1));
            } else {
                int start = nl + 1;
                for (int i = start; i <= post.Length; i++) {
                    if (i == post.Length || post[i] == '\n') {
                        args.Add(Sub(post, start, i - start));
                        start = i + 1;
                    }
                }
            }
        }
        return RecvMethod(method, args);
    }
    static string S(byte[] b) { return Encoding.ASCII.GetString(b); }
    static string S(byte[] b, int o, int n) { return Encoding.ASCII.GetString(b, o, n); }
    static byte[] Sub(byte[] b, int o, int n) {
        if (o < 0) o = 0;
        if (o > b.Length) o = b.Length;
        if (n < 0) n = 0;
        if (o + n > b.Length) n = b.Length - o;
        var r = new byte[n];
        Buffer.BlockCopy(b, o, r, 0, n);
        return r;
    }
    static byte[] Ret(string s) { return Encoding.ASCII.GetBytes(s); }
    static byte[] B64(byte[] b) { return Encoding.ASCII.GetBytes(Convert.ToBase64String(b)); }
    static byte[] B64d(byte[] b) {
        try { return Convert.FromBase64String(Encoding.ASCII.GetString(b)); }
        catch { return new byte[0]; }
    }
    static string JEsc(string s) {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder(s.Length + 8);
        foreach (char ch in s) {
            switch (ch) {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (ch < 0x20) sb.Append("\\u").Append(((int)ch).ToString("x4"));
                    else sb.Append(ch);
                    break;
            }
        }
        return sb.ToString();
    }

    static byte[] RecvMethod(string method, List<byte[]> args) {
        Fapi.EnsureWorkspace();
        if (method == "identifyexecutor")
            return new byte[] { (byte)'a', (byte)'r', (byte)'e', (byte)'s', 0, (byte)'1', (byte)'.', (byte)'0', (byte)'.', (byte)'0' };

        if (method == "setclipboard") {
            if (args.Count < 1) return Ret("bad content");
            try {
                var data = B64d(args[0]);
                if (SetClipboard != null) { SetClipboard(Encoding.UTF8.GetString(data)); return Ret("ok"); }
            } catch { }
            return Ret("fail");
        }
        if (method == "getclipboard") {
            try {
                if (GetClipboard != null) return Encoding.UTF8.GetBytes(GetClipboard());
            } catch { }
            return Ret("");
        }
        if (method == "compile") {
            if (args.Count < 1) return Ret("fail");
            var src = B64d(args[0]);
            string err;
            var bc = Compiler.Compile(src, out err);
            if (bc == null || bc.Length == 0) return Ret("fail\n" + (err ?? "compile error"));
            return B64(bc);
        }
        if (method == "compile_raw") {
            if (args.Count < 1) return new byte[0];
            string err;
            var bc = Compiler.Compile(args[0], out err);
            if (bc == null || bc.Length == 0) return Ret("fail\n" + (err ?? "compile error"));
            return bc;
        }
        if (method == "iswindowactive") {
            try {
                IntPtr fg = Native.GetForegroundWindow();
                uint pid;
                Native.GetWindowThreadProcessId(fg, out pid);
                string exe = "";
                try { using (var p = Process.GetProcessById((int)pid)) exe = Path.GetFileName(p.MainModule.FileName); } catch { }
                return Ret(string.Equals(exe, "RobloxPlayerBeta.exe", StringComparison.OrdinalIgnoreCase) ? "true" : "false");
            } catch { return Ret("false"); }
        }
        if (method == "getinit" || method == "getinitraw") {
            var src = Fapi.InitLuau();
            if (src == null || src.Length == 0) return Ret("fail");
#pragma warning disable 162
            if (Off.BridgePort != 9475) {
                string s = Encoding.UTF8.GetString(src);
                s = s.Replace("localhost:9475", "localhost:" + Off.BridgePort);
                src = Encoding.UTF8.GetBytes(s);
            }
#pragma warning restore 162
            string err;
            var bc = Compiler.Compile(src, out err);
            if (bc == null || bc.Length == 0) return Ret("fail\n" + (err ?? "compile error"));
            if (method == "getinitraw") return bc;
            return B64(bc);
        }

        if (method == "getcommit" || method == "getclientversion") {
            string commit = null;
            try {
                foreach (uint pid in Multi.AllRoblox()) {
                    string exe = Multi.ExePath(pid);
                    if (exe == null) continue;
                    string dir = Path.GetFileName(Path.GetDirectoryName(exe));
                    if (!string.IsNullOrEmpty(dir) && dir.StartsWith("version-", StringComparison.OrdinalIgnoreCase)) {
                        commit = dir.Substring("version-".Length);
                        break;
                    }
                }
            } catch { }
            if (commit == null) {
                try {
                    string versions = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Roblox", "Versions");
                    if (Directory.Exists(versions)) {
                        var dirs = Directory.GetDirectories(versions, "version-*");
                        if (dirs.Length > 0) {
                            string dir = Path.GetFileName(dirs[dirs.Length - 1]);
                            commit = dir.Substring("version-".Length);
                        }
                    }
                } catch { }
            }
            return Ret(commit ?? "unknown");
        }

        if (method == "hash") {
            if (args.Count < 2) return Ret("fail");
            string algo = S(args[0]).ToLowerInvariant();
            var data = B64d(args[1]);
            try {
                HashAlgorithm h = null;
                if (algo == "sha256") h = new SHA256Managed();
                else if (algo == "sha384") h = new SHA384Managed();
                else if (algo == "sha512") h = new SHA512Managed();
                else if (algo == "sha1") h = new SHA1Managed();
                else if (algo == "md5") h = new MD5CryptoServiceProvider();
                else return Ret("fail");
                using (h) {
                    var sb = new StringBuilder();
                    foreach (byte x in h.ComputeHash(data)) sb.Append(x.ToString("x2"));
                    return Ret(sb.ToString());
                }
            } catch { return Ret("fail"); }
        }
        if (method == "setfpscap" || method == "getfpscap") {
            if (method == "setfpscap") {
                if (args.Count < 1) return Ret("fail");
                int v;
                if (!int.TryParse(S(args[0]), out v)) return Ret("fail");
                _fpsCap = v;
                return Ret("ok");
            }
            return Ret(_fpsCap.ToString());
        }
        if (method == "messagebox") {
            if (args.Count < 3) return Ret("fail");
            string text = Encoding.UTF8.GetString(B64d(args[0]));
            string title = Encoding.UTF8.GetString(B64d(args[1]));
            uint flags;
            if (!uint.TryParse(S(args[2]), out flags)) return Ret("fail");
            int btn = Native.MessageBoxA(IntPtr.Zero, text, title, flags);
            return Ret(btn.ToString());
        }
        if (method == "getcustomasset") {
            

            

            if (args.Count < 1) return Ret("fail");
            try {
                string src = S(args[0]);
                if (!File.Exists(src)) {
                    

                    

                    try {
                        string ws = Fapi.WorkspacePath(src);
                        if (ws != null && File.Exists(ws)) src = ws;
                    } catch { }
                }
                if (!File.Exists(src)) return Ret("fail");
                string contentDir = null;
                try {
                    foreach (uint pid in Multi.AllRoblox()) {
                        string exe = Multi.ExePath(pid);
                        if (exe == null) continue;
                        string dir = Path.GetDirectoryName(exe);
                        if (dir == null) continue;
                        string candidate = Path.Combine(dir, "content");
                        if (Directory.Exists(candidate)) { contentDir = candidate; break; }
                    }
                } catch { }
                if (contentDir == null) return Ret("fail");
                byte[] bytes = File.ReadAllBytes(src);
                string hash;
                using (var sha = SHA1.Create()) {
                    hash = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
                }
                string ext = Path.GetExtension(src);
                if (string.IsNullOrEmpty(ext)) ext = ".png";
                string rel = "speedassets/" + hash + ext;
                string dest = Path.Combine(contentDir, "speedassets", hash + ext);
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                File.WriteAllBytes(dest, bytes);
                return Ret(rel);
            } catch { return Ret("fail"); }
        }
        if (method == "httpget") {
            if (args.Count < 1) return Ret("fail");
            try {
                string url = S(args[0]);
                return Http.GetByteArrayAsync(url).GetAwaiter().GetResult();
            } catch { return Ret("fail"); }
        }
        if (method == "httppost") {
            if (args.Count < 1) return Ret("fail");
            try {
                string url = S(args[0]);
                string body = args.Count > 1 ? S(args[1]) : "";
                string ctype = args.Count > 2 ? S(args[2]) : "application/json";
                var content = new System.Net.Http.StringContent(body, Encoding.UTF8, ctype);
                var resp = Http.PostAsync(url, content).GetAwaiter().GetResult();
                return resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
            } catch { return Ret("fail"); }
        }
        if (method == "request") {
            

            

            if (args.Count < 1) return Ret("fail");
            try {
                string json = Encoding.UTF8.GetString(B64d(args[0]));
                using (var doc = System.Text.Json.JsonDocument.Parse(json)) {
                    var root = doc.RootElement;
                    string url = root.TryGetProperty("Url", out var uEl) ? uEl.GetString() : null;
                    if (string.IsNullOrEmpty(url)) return Ret("fail");
                    string verb = root.TryGetProperty("Method", out var mEl) ? (mEl.GetString() ?? "GET") : "GET";
                    string body = null;
                    if (root.TryGetProperty("Body", out var bEl) &&
                        bEl.ValueKind != System.Text.Json.JsonValueKind.Null &&
                        bEl.ValueKind != System.Text.Json.JsonValueKind.Undefined) {
                        body = bEl.ValueKind == System.Text.Json.JsonValueKind.String ? bEl.GetString() : bEl.GetRawText();
                    }

                    using (var req = new System.Net.Http.HttpRequestMessage(new System.Net.Http.HttpMethod(verb.ToUpperInvariant()), url)) {
                        if (body != null) req.Content = new System.Net.Http.StringContent(body, Encoding.UTF8);
                        if (root.TryGetProperty("Headers", out var hEl) && hEl.ValueKind == System.Text.Json.JsonValueKind.Object) {
                            foreach (var p in hEl.EnumerateObject()) {
                                string v = p.Value.ValueKind == System.Text.Json.JsonValueKind.String ? p.Value.GetString() : p.Value.GetRawText();
                                if (p.Name.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)) {
                                    if (req.Content == null) req.Content = new System.Net.Http.StringContent("");
                                    req.Content.Headers.Remove("Content-Type");
                                    req.Content.Headers.TryAddWithoutValidation("Content-Type", v);
                                } else {
                                    req.Headers.TryAddWithoutValidation(p.Name, v);
                                }
                            }
                        }
                        if (root.TryGetProperty("Cookies", out var cEl) && cEl.ValueKind == System.Text.Json.JsonValueKind.Object) {
                            var cb = new StringBuilder();
                            foreach (var p in cEl.EnumerateObject()) {
                                if (cb.Length > 0) cb.Append("; ");
                                cb.Append(p.Name).Append('=').Append(p.Value.GetString() ?? "");
                            }
                            if (cb.Length > 0) req.Headers.TryAddWithoutValidation("Cookie", cb.ToString());
                        }

                        using (var resp = Http.SendAsync(req).GetAwaiter().GetResult()) {
                            byte[] bodyBytes = resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                            var sb = new StringBuilder();
                            sb.Append("{\"Success\":true,\"StatusCode\":").Append((int)resp.StatusCode);
                            sb.Append(",\"StatusMessage\":\"").Append(JEsc(resp.ReasonPhrase ?? "")).Append("\"");
                            sb.Append(",\"Headers\":{");
                            bool first = true;
                            foreach (var h in resp.Headers) {
                                if (!first) sb.Append(',');
                                first = false;
                                sb.Append('"').Append(JEsc(h.Key)).Append("\":\"").Append(JEsc(string.Join(", ", h.Value))).Append('"');
                            }
                            foreach (var h in resp.Content.Headers) {
                                if (!first) sb.Append(',');
                                first = false;
                                sb.Append('"').Append(JEsc(h.Key)).Append("\":\"").Append(JEsc(string.Join(", ", h.Value))).Append('"');
                            }
                            sb.Append("},\"Body\":\"").Append(Convert.ToBase64String(bodyBytes)).Append("\"}");
                            return Ret(sb.ToString());
                        }
                    }
                }
            } catch { return Ret("fail"); }
        }
        if (method == "websocket_connect") {
            if (args.Count < 1) return Ret("fail");
            try {
                string url = S(args[0]);
                var ws = new System.Net.WebSockets.ClientWebSocket();
                ws.ConnectAsync(new Uri(url), CancellationToken.None).GetAwaiter().GetResult();
                var queue = new System.Collections.Concurrent.ConcurrentQueue<string>();
                int id;
                lock (_wsLock) {
                    id = ++_wsNext;
                    _wsSockets[id] = ws;
                    _wsRecv[id] = queue;
                }
                int cap = id;
                System.Threading.Tasks.Task.Run(async () => {
                    var buf = new byte[32768];
                    try {
                        while (ws.State == System.Net.WebSockets.WebSocketState.Open) {
                            var res = await ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None);
                            if (res.MessageType == System.Net.WebSockets.WebSocketMessageType.Close) break;
                            if (res.Count > 0) queue.Enqueue(Encoding.UTF8.GetString(buf, 0, res.Count));
                        }
                    } catch { }
                    lock (_wsLock) {
                        _wsSockets.Remove(cap);
                        _wsRecv.Remove(cap);
                    }
                });
                return Ret(id.ToString());
            } catch { return Ret("fail"); }
        }
        if (method == "websocket_send") {
            if (args.Count < 2) return Ret("fail");
            try {
                int id = int.Parse(S(args[0]));
                System.Net.WebSockets.ClientWebSocket ws;
                lock (_wsLock) { if (!_wsSockets.TryGetValue(id, out ws)) return Ret("fail"); }
                var bytes = Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(args[1]));
                ws.SendAsync(new ArraySegment<byte>(bytes), System.Net.WebSockets.WebSocketMessageType.Text, true, CancellationToken.None).GetAwaiter().GetResult();
                return Ret("ok");
            } catch { return Ret("fail"); }
        }
        if (method == "websocket_close") {
            if (args.Count < 1) return Ret("fail");
            try {
                int id = int.Parse(S(args[0]));
                System.Net.WebSockets.ClientWebSocket ws;
                lock (_wsLock) {
                    if (!_wsSockets.TryGetValue(id, out ws)) return Ret("ok");
                    _wsSockets.Remove(id);
                    _wsRecv.Remove(id);
                }
                try { ws.CloseAsync(System.Net.WebSockets.WebSocketCloseStatus.NormalClosure, "", CancellationToken.None).GetAwaiter().GetResult(); } catch { }
                return Ret("ok");
            } catch { return Ret("fail"); }
        }
        if (method == "websocket_poll") {
            if (args.Count < 1) return Ret("");
            try {
                int id = int.Parse(S(args[0]));
                System.Collections.Concurrent.ConcurrentQueue<string> q;
                lock (_wsLock) { if (!_wsRecv.TryGetValue(id, out q)) return Ret(""); }
                string msg;
                if (q.TryDequeue(out msg)) return Encoding.UTF8.GetBytes(msg);
                return Ret("");
            } catch { return Ret(""); }
        }
        if (method == "getmousepos") {
            Native.POINT p;
            if (!Native.GetCursorPos(out p)) return Ret("fail");
            return Ret(p.X + "," + p.Y);
        }
        {
            

            bool handled = true;
            if (method == "mouse1click") { MouseBtn(0x2, 0); MouseBtn(0x4, 0); }
            else if (method == "mouse2click") { MouseBtn(0x8, 0); MouseBtn(0x10, 0); }
            else if (method == "middleclick") { MouseBtn(0x20, 0); MouseBtn(0x40, 0); }
            else if (method == "mouse1down") MouseBtn(0x2, 0);
            else if (method == "mouse1up") MouseBtn(0x4, 0);
            else if (method == "mouse2down") MouseBtn(0x8, 0);
            else if (method == "mouse2up") MouseBtn(0x10, 0);
            else if (method == "middledown") MouseBtn(0x20, 0);
            else if (method == "middleup") MouseBtn(0x40, 0);
            else if (method == "mousescroll") {
                if (args.Count < 1) return Ret("fail");
                int delta;
                if (!int.TryParse(S(args[0]), out delta)) return Ret("fail");
                

                MouseBtn(0x800, delta * 120);
            }
            else if (method == "movemouse" || method == "mousemoveabs") {
                if (args.Count < 2) return Ret("fail");
                int x, y;
                if (!int.TryParse(S(args[0]), out x) || !int.TryParse(S(args[1]), out y)) return Ret("fail");
                int sw = Screen.PrimaryScreen.Bounds.Width, sh = Screen.PrimaryScreen.Bounds.Height;
                var inp = new Native.INPUT[1];
                inp[0].type = 0;
                inp[0].u.mi.dwFlags = 0x1 | 0x8000;
                inp[0].u.mi.dx = sw > 1 ? x * 65535 / (sw - 1) : 0;
                inp[0].u.mi.dy = sh > 1 ? y * 65535 / (sh - 1) : 0;
                Native.SendInput(1, inp, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
            }
            else if (method == "movemouserel") {
                if (args.Count < 2) return Ret("fail");
                int x, y;
                if (!int.TryParse(S(args[0]), out x) || !int.TryParse(S(args[1]), out y)) return Ret("fail");
                try {
                    if (Mem.Pid != 0) {
                        IntPtr rbx = Win.GetHwnd(Mem.Pid);
                        if (rbx != IntPtr.Zero && Native.GetForegroundWindow() != rbx) {
                            Win.ForceForeground(rbx);
                        }
                    }
                } catch { }
                var inp = new Native.INPUT[1];
                inp[0].type = 0;
                inp[0].u.mi.dwFlags = 0x1;
                inp[0].u.mi.dx = x;
                inp[0].u.mi.dy = y;
                Native.SendInput(1, inp, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
            }
            else if (method == "keyclick" || method == "keypress" || method == "keyrelease") {
                if (args.Count < 1) return Ret("fail");
                uint vk;
                if (!uint.TryParse(S(args[0]), out vk)) return Ret("fail");
                bool up = method == "keyrelease";
                KeyEvt(vk, up);
                if (method == "keyclick") KeyEvt(vk, true);
            }
            else handled = false;
            if (handled) return Ret("ok");
        }
        if (method == "log") {
            if (args.Count >= 1) {
                string text;
                try { text = Encoding.UTF8.GetString(B64d(args[0])); }
                catch { text = S(args[0]); }
                foreach (var ln in text.Replace("\r\n", "\n").Split('\n')) LogLine(ln);
            }
            return Ret("ok");
        }
        if (method == "clearlog") { ClearConsole(); return Ret("ok"); }
        if (method == "calibrate_value") {
            if (args.Count < 2) return Ret("fail:args");
            string holderName = S(args[0]), targetName = S(args[1]);
            ulong root = Mem.Find(Executor.Rbx.Datamodel, "CoreGui", "_speedexecutor");
            if (root == 0) return Ret("fail:root");
            ulong holder = Mem.FindChild(root, holderName);
            ulong target = Mem.FindChild(root, targetName);
            if (holder == 0) return Ret("fail:holder");
            if (target == 0) return Ret("fail:target");
            for (ulong off = 0x40; off <= 0x300; off += 8) {
                if (Mem.U64(holder + off) == target) {
                    _valueOffset = off;
                    return Ret(off.ToString());
                }
            }
            return Ret("fail:scan");
        }
        if (method == "getscriptbytecode" || method == "getscripthash") {
            if (args.Count < 1) return Ret("fail:args");
            string holderName = S(args[0]);
            ulong root = Mem.Find(Executor.Rbx.Datamodel, "CoreGui", "_speedexecutor");
            if (root == 0) return Ret("fail:root");
            ulong holder = Mem.FindChild(root, holderName);
            if (holder == 0) return Ret("fail:holder");
            ulong target = Mem.U64(holder + (_valueOffset != 0 ? _valueOffset : Off.Misc_Value));
            if (!Mem.Valid(target)) return Ret("fail:value");
            string cls = Mem.ClassName(target);
            ulong bcOff = 0;
            if (cls == "ModuleScript") bcOff = Off.Module_BC;
            else if (cls == "LocalScript") bcOff = Off.Local_BC;
            else return Ret("fail:class:" + cls);
            ulong bcStruct = Mem.U64(target + bcOff);
            if (!Mem.Valid(bcStruct)) return Ret("fail:bc");
            ulong ptr = Mem.U64(bcStruct + Off.BC_Ptr);
            ulong sz = Mem.U64(bcStruct + Off.BC_Size);
            if (!Mem.Valid(ptr) || sz == 0 || sz > 20 * 1024 * 1024) return Ret("fail:mem");
            var bc = Mem.Read(ptr, (int)sz);
            if (bc == null) return Ret("fail:read");
            if (method == "getscripthash") {
                try {
                    using (var h = new SHA384Managed()) {
                        var sb = new StringBuilder();
                        foreach (byte x in h.ComputeHash(bc)) sb.Append(x.ToString("x2"));
                        return Ret(sb.ToString());
                    }
                } catch { return Ret("fail:hash"); }
            }
            return B64(bc);
        }

        

        if (args.Count == 0 && method != "listfiles") return Ret("bad request");
        string arg0 = args.Count == 0 ? "" : S(args[0]);
        string path;
        if (method == "listfiles" && arg0 == "") path = Fapi.WorkspaceDir();
        else path = Fapi.WorkspacePath(arg0);
        if (path == null) return Ret("bad request");
        if (method == "writefile") {
            if (args.Count < 2) return Ret("bad content");
            try { File.WriteAllBytes(path, B64d(args[1])); return Ret("ok"); }
            catch { return Ret("fail"); }
        }
        if (method == "appendfile") {
            if (args.Count < 2) return Ret("bad content");
            try {
                using (var f = new FileStream(path, FileMode.Append, FileAccess.Write))
                    { var d = B64d(args[1]); f.Write(d, 0, d.Length); }
                return Ret("ok");
            } catch { return Ret("fail"); }
        }
        if (method == "readfile") {
            try {
                if (!File.Exists(path)) return Ret("fail");
                return B64(File.ReadAllBytes(path));
            } catch { return Ret("fail"); }
        }
        if (method == "isfile") {
            try { return Ret(File.Exists(path) ? "true" : "false"); }
            catch { return Ret("false"); }
        }
        if (method == "isfolder") {
            try { return Ret(Directory.Exists(path) ? "true" : "false"); }
            catch { return Ret("false"); }
        }
        if (method == "delfile") {
            try { File.Delete(path); return Ret("ok"); } catch { return Ret("fail"); }
        }
        if (method == "makefolder") {
            try { Directory.CreateDirectory(path); return Ret("ok"); } catch { return Ret("fail"); }
        }
        if (method == "delfolder") {
            try { Directory.Delete(path); return Ret("ok"); } catch { return Ret("fail"); }
        }
        if (method == "listfiles") {
            try {
                var names = new List<string>();
                foreach (var e in Directory.EnumerateFileSystemEntries(path)) {
                    string n = Path.GetFileName(e);
                    if (n.StartsWith(".")) continue;
                    names.Add(n);
                }
                return Ret(string.Join("\n", names));
            } catch { return Ret(""); }
        }
        if (method == "loadfile") {
            try {
                if (!File.Exists(path)) return Ret("fail");
                string err;
                var bc = Compiler.Compile(File.ReadAllBytes(path), out err);
                if (bc == null || bc.Length == 0) return Ret("fail\n" + (err ?? "compile error"));
                return B64(bc);
            } catch { return Ret("fail"); }
        }
        if (method == "getcustomasset") return Ret(path);

        

        if (method == "getthreadidentity") return Ret("8");
        if (method == "setthreadidentity") return Ret("ok");
        if (method == "getgc" || method == "getreg" || method == "getrawmetatable" ||
            method == "debug_getconstants" || method == "debug_getupvalues") return Ret("{}");
        if (method == "cache_invalidate" || method == "cache_replace" ||
            method == "setrawmetatable" || method == "setreadonly" ||
            method == "sethiddenproperty" || method == "cleardrawcache" ||
            method == "getrenderproperty" || method == "setrenderproperty" ||
            method == "firesignal" || method == "replicatesignal" ||
            method == "debug_setconstant" || method == "debug_setstack" ||
            method == "debug_setupvalue") return Ret("ok");
        if (method == "cache_iscached" || method == "isscriptable") return Ret("true");
        if (method == "isreadonly" || method == "setscriptable" ||
            method == "sethiddenproperty" || method == "isrenderobj") return Ret("false");
        if (method == "gethiddenproperty") return Encoding.ASCII.GetBytes("nil\0false");
        if (method == "getconnections") return Ret("0");
        if (method == "getnamecallmethod" || method == "debug_getconstant" ||
            method == "debug_getproto" || method == "debug_getstack" ||
            method == "debug_getupvalue") return Ret("nil");
        if (method == "debug_getprotos" || method == "getnilinstances") return Ret("0");
        return Ret("bad request");
    }

    static void MouseBtn(int flags, int data) {
        var inp = new Native.INPUT[1];
        inp[0].type = 0;
        inp[0].u.mi.dwFlags = flags;
        inp[0].u.mi.mouseData = data;
        Native.SendInput(1, inp, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
    }
    static void KeyEvt(uint vk, bool up) {
        var inp = new Native.INPUT[1];
        inp[0].type = 1;
        ushort scan = (ushort)Native.MapVirtualKeyA(vk, 0);
        if (scan != 0) {
            inp[0].u.ki.wScan = (short)scan;
            inp[0].u.ki.dwFlags = 0x0008;
        } else {
            inp[0].u.ki.wVk = (short)vk;
            inp[0].u.ki.dwFlags = 0;
        }
        if (up) inp[0].u.ki.dwFlags |= 0x0002;
        Native.SendInput(1, inp, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.INPUT)));
    }
}
