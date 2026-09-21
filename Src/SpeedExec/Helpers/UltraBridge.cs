using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace SpeedExecutor
{
    public class UltraBridge : IDisposable
    {
        private Process _process;
        private readonly object _writeLock = new object();
        private bool _disposed;

        public event Action<string> OnReply;
        public event Action<string> OnError;
        public event Action OnReady;
        public event Action OnExited;

        public bool IsRunning => _process != null && !_process.HasExited;
        public bool IsReady { get; private set; }

        public void Start(string pythonPath, string serverScript)
        {
            if (IsRunning)
                return;

            var psi = new ProcessStartInfo
            {
                FileName = pythonPath,
                Arguments = "\"" + serverScript + "\"",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            _process = new Process { StartInfo = psi, EnableRaisingEvents = true };
            _process.OutputDataReceived += OnOutputData;
            _process.ErrorDataReceived += OnErrorData;
            _process.Exited += OnProcessExited;

            _process.Start();
            _process.BeginOutputReadLine();
            _process.BeginErrorReadLine();
        }

        private void OnOutputData(object sender, DataReceivedEventArgs e)
        {
            if (string.IsNullOrEmpty(e.Data))
                return;

            try
            {
                var kv = ParseJson(e.Data);

                if (kv.ContainsKey("status") && kv["status"] == "ready")
                {
                    IsReady = true;
                    OnReady?.Invoke();
                }
                else if (kv.ContainsKey("reply"))
                {
                    OnReply?.Invoke(kv["reply"]);
                }
                else if (kv.ContainsKey("error"))
                {
                    OnError?.Invoke(kv["error"]);
                }
            }
            catch
            {
            }
        }

        private void OnErrorData(object sender, DataReceivedEventArgs e)
        {
            if (!string.IsNullOrEmpty(e.Data))
                Debug.WriteLine("[ultra_server] " + e.Data);
        }

        private void OnProcessExited(object sender, EventArgs e)
        {
            IsReady = false;
            OnExited?.Invoke();
        }

        public void SendReply(string text)
        {
            if (!IsRunning || !IsReady)
            {
                OnError?.Invoke("Ultra is not running");
                return;
            }
            SendCommand("{\"type\":\"reply\",\"text\":" + JsonEscape(text) + "}");
        }

        public void SendRegen(string text)
        {
            if (!IsRunning || !IsReady) return;
            SendCommand("{\"type\":\"regen\",\"text\":" + JsonEscape(text) + "}");
        }

        public void SetTemperature(double temp)
        {
            SendCommand("{\"type\":\"set_temp\",\"value\":" + temp.ToString("F1") + "}");
        }

        public void Quit()
        {
            try { SendCommand("{\"type\":\"quit\"}"); } catch { }
        }

        private void SendCommand(string json)
        {
            if (!IsRunning) return;
            try
            {
                lock (_writeLock)
                {
                    _process.StandardInput.WriteLine(json);
                    _process.StandardInput.Flush();
                }
            }
            catch (Exception ex)
            {
                OnError?.Invoke(ex.Message);
            }
        }

        private static string JsonEscape(string s)
        {
            if (s == null) return "\"\"";
            s = s.Replace("\\", "\\\\");
            s = s.Replace("\"", "\\\"");
            s = s.Replace("\n", "\\n");
            s = s.Replace("\r", "\\r");
            s = s.Replace("\t", "\\t");
            return "\"" + s + "\"";
        }

        private static Dictionary<string, string> ParseJson(string json)
        {
            var result = new Dictionary<string, string>();
            json = json.Trim();
            if (json.StartsWith("{")) json = json.Substring(1);
            if (json.EndsWith("}")) json = json.Substring(0, json.Length - 1);

            int i = 0;
            while (i < json.Length)
            {
                while (i < json.Length && (json[i] == ' ' || json[i] == ',')) i++;
                if (i >= json.Length) break;

                string key = ReadJsonString(json, ref i);
                if (key == null) break;

                while (i < json.Length && json[i] != ':') i++;
                if (i < json.Length) i++;

                while (i < json.Length && json[i] == ' ') i++;
                if (i >= json.Length) break;

                string val;
                if (json[i] == '"')
                {
                    val = ReadJsonString(json, ref i);
                }
                else
                {
                    int start = i;
                    while (i < json.Length && json[i] != ',' && json[i] != '}') i++;
                    val = json.Substring(start, i - start).Trim();
                }

                if (key != null && val != null)
                    result[key] = val;
            }
            return result;
        }

        private static string ReadJsonString(string json, ref int i)
        {
            if (i >= json.Length || json[i] != '"') return null;
            i++;
            var sb = new StringBuilder();
            while (i < json.Length)
            {
                if (json[i] == '\\' && i + 1 < json.Length)
                {
                    char next = json[i + 1];
                    if (next == '"') sb.Append('"');
                    else if (next == '\\') sb.Append('\\');
                    else if (next == 'n') sb.Append('\n');
                    else if (next == 'r') sb.Append('\r');
                    else if (next == 't') sb.Append('\t');
                    else { sb.Append('\\'); sb.Append(next); }
                    i += 2;
                }
                else if (json[i] == '"')
                {
                    i++;
                    return sb.ToString();
                }
                else
                {
                    sb.Append(json[i]);
                    i++;
                }
            }
            return sb.ToString();
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            try
            {
                if (IsRunning)
                {
                    Quit();
                    if (!_process.WaitForExit(2000))
                        _process.Kill();
                }
            }
            catch { }

            _process?.Dispose();
        }
    }
}
