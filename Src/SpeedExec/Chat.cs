using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;







static class Chat {
    public static string BaseUrl = "http://127.0.0.1:8080";
    public static string Model = "";

    static readonly System.Net.Http.HttpClient Http = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromMinutes(10) };
    static readonly List<JsonObject> Messages = new List<JsonObject> { SystemMessage() };

    public class ToolCall {
        public string Id;
        public string Name;
        public string Args;
    }

    public static void Reset() {
        Messages.Clear();
        Messages.Add(SystemMessage());
    }

    static JsonObject SystemMessage() {
        string flyRecipe =
@"local plr = game:GetService(""Players"").LocalPlayer
local uis = game:GetService(""UserInputService"")
local rs = game:GetService(""RunService"")
local chr = plr.Character or plr.CharacterAdded:Wait()
local hrp = chr:WaitForChild(""HumanoidRootPart"")
local flying = false
uis.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.Space then flying = true end
end)
uis.InputEnded:Connect(function(inp)
    if inp.KeyCode == Enum.KeyCode.Space then flying = false end
end)
rs.Heartbeat:Connect(function()
    if not flying then return end
    local cam = workspace.CurrentCamera
    local dir = (cam.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
    hrp.CFrame = hrp.CFrame:ToWorldSpace(CFrame.new(dir * 0.25 + Vector3.new(0, -0.35, 0)))
end)";
        string content =
                "You are \"Speed Chat\", the assistant built into Speed Executor, a Roblox Luau script executor " +
                "with a built-in Monaco editor, a scripts folder, and inject-and-run capabilities.\n\n" +
                "Environment facts:\n" +
                "- Saved scripts live in the executor's \"Scripts\" folder beside the exe.\n" +
                "- The executor can attach to a running Roblox game, inject, and execute code in game.\n" +
                "- You can write code, save it, load it into the editor, inspect the editor, and run code in game.\n\n" +
                "Available tools:\n" +
                "1. run_lua(code) - Execute Luau code directly in the running Roblox game. Attaches and injects automatically. Use whenever the user asks to run, execute, or test a script.\n" +
                "2. create_script(name, code) - Write a complete Lua/Luau script into the Scripts folder so it appears in the file list. Use when the user asks to make, create, or save a script.\n" +
                "3. set_editor(code) - Replace the code currently shown in the built-in editor.\n" +
                "4. get_editor() - Return the code currently in the editor.\n" +
                "5. list_scripts() - Return the file names saved in the Scripts folder.\n" +
                "6. read_script(name) - Return the code of a saved script.\n" +
                "7. attach() - Attach to Roblox and inject so scripts can run (run_lua does this automatically).\n\n" +
                "Behavior rules:\n" +
                "- When asked to make a script, call create_script AND set_editor so the code is saved and visible. Always give a complete, working script.\n" +
                "- When asked to run/execute something, call run_lua with the full code. If the user mentions their editor script, read get_editor() first if needed.\n" +
                "- Report the result of each tool call to the user.\n" +
                "- Keep normal conversation short and friendly. Only use tools when the request needs them.\n" +
                "- For scripts, write idiomatic, modern Roblox Luau and avoid syntax errors.\n\n" +
                "Roblox script recipes (use these patterns when the user asks for them):\n" +
                "- \"Fly script\" (fly while holding Space, CFrame movement every frame):\n" + flyRecipe + "\n" +
                "- \"Teleport\": set the HumanoidRootPart CFrame, e.g. player.Character:WaitForChild(\"HumanoidRootPart\").CFrame = CFrame.new(0, 50, 0)\n" +
                "- \"Infinite jump\": on Humanoid Jump value change, reset the Humanoid state to Jumping.\n" +
                "- \"Speed\": raise the Humanoid.WalkSpeed.\n" +
                "- \"ESP / wallhack\": not a normal script feature; if asked, explain it needs a client-side highlight approach or decline.\n" +
                "If a request doesn't clearly match a known recipe, ask the user what the script should actually do in game.";
        return new JsonObject { ["role"] = "system", ["content"] = content };
    }

    

    

    

    public static async Task<string> Ask(string userText, Func<string, Task> onEvent, Func<ToolCall, Task<string>> runTool) {
        Messages.Add(new JsonObject { ["role"] = "user", ["content"] = userText });
        int guard = 0;
        while (guard++ < 10) {
            string json = await Post(Messages).ConfigureAwait(false);
            string content = "";
            var toolCalls = new List<ToolCall>();
            using (var doc = JsonDocument.Parse(json)) {
                var msg = doc.RootElement.GetProperty("choices")[0].GetProperty("message");
                if (msg.TryGetProperty("content", out var c) && c.ValueKind == JsonValueKind.String)
                    content = c.GetString() ?? "";

                JsonElement tcs;
                bool hasTools = msg.TryGetProperty("tool_calls", out tcs) &&
                                tcs.ValueKind == JsonValueKind.Array &&
                                tcs.GetArrayLength() > 0;
                if (hasTools) {
                    var asst = new JsonObject {
                        ["role"] = "assistant",
                        ["content"] = string.IsNullOrEmpty(content) ? "" : content,
                        ["tool_calls"] = new JsonArray()
                    };
                    foreach (var tc in tcs.EnumerateArray()) {
                        string id = tc.TryGetProperty("id", out var ip) ? (ip.GetString() ?? ("call_" + toolCalls.Count)) : ("call_" + toolCalls.Count);
                        string name = "";
                        var fn = tc.GetProperty("function");
                        if (fn.TryGetProperty("name", out var np)) name = np.GetString() ?? "";
                        string args = "";
                        var a = fn.GetProperty("arguments");
                        if (a.ValueKind == JsonValueKind.String) args = a.GetString() ?? "";
                        else if (a.ValueKind == JsonValueKind.Object || a.ValueKind == JsonValueKind.Array) args = a.GetRawText();
                        args = FixToolArgs(args);
                        toolCalls.Add(new ToolCall { Id = id, Name = name, Args = args });
                        asst["tool_calls"].AsArray().Add(new JsonObject {
                            ["id"] = id,
                            ["type"] = "function",
                            ["function"] = new JsonObject { ["name"] = name, ["arguments"] = args }
                        });
                    }
                    Messages.Add(asst);

                    foreach (var call in toolCalls) {
                        string result;
                        try {
                            result = runTool != null ? await runTool(call).ConfigureAwait(false) : "unhandled tool";
                        } catch (Exception ex) {
                            result = "error: " + ex.Message;
                        }
                        if (result.Length > 12000) result = result.Substring(0, 12000) + "\n...[truncated]";
                        if (onEvent != null) await onEvent("Tool: " + call.Name + "\n" + result).ConfigureAwait(false);
                        Messages.Add(new JsonObject { ["role"] = "tool", ["tool_call_id"] = call.Id, ["content"] = result });
                    }
                    continue;
                }
            }
            return content;
        }
        return "Stopped after too many tool calls.";
    }

    public static string Arg(string argsJson, string key) {
        if (string.IsNullOrWhiteSpace(argsJson)) return "";
        try {
            using (var doc = JsonDocument.Parse(argsJson)) {
                var root = doc.RootElement;
                if (root.TryGetProperty(key, out var v)) {
                    switch (v.ValueKind) {
                        case JsonValueKind.String: return v.GetString() ?? "";
                        case JsonValueKind.True: return "true";
                        case JsonValueKind.False: return "false";
                        case JsonValueKind.Number: return v.GetRawText();
                        case JsonValueKind.Object:
                        case JsonValueKind.Array: return v.GetRawText();
                    }
                }
            }
        } catch { }
        return "";
    }

    

    

    

    

    static string FixToolArgs(string raw) {
        if (string.IsNullOrWhiteSpace(raw)) return "{}";
        raw = raw.Trim();
        try { using (var d = JsonDocument.Parse(raw)) return d.RootElement.GetRawText(); } catch { }

        string softened = Soften(raw);
        if (softened != raw) {
            foreach (var tail in new[] { "", "\"}", "}" }) {
                try { using (var d = JsonDocument.Parse(softened + tail)) return d.RootElement.GetRawText(); } catch { }
            }
        }
        return ManualArgs(raw);
    }

    static string Soften(string s) {
        var sb = new StringBuilder(s.Length + 16);
        for (int i = 0; i < s.Length; i++) {
            char c = s[i];
            if (c == '\r') continue;
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\t') sb.Append("\\t");
            else if (c == '\b') sb.Append("\\b");
            else if (c == '\f') sb.Append("\\f");
            else sb.Append(c);
        }
        return sb.ToString();
    }

    

    

    

    static string ManualArgs(string raw) {
        var o = new JsonObject();
        int ni = raw.IndexOf("\"name\"", StringComparison.OrdinalIgnoreCase);
        if (ni >= 0) {
            int endQ;
            int q = IndexOfStringValue(raw, ni + 6, out endQ);
            if (q >= 0 && endQ > q) o["name"] = Unescape(raw.Substring(q + 1, endQ - q - 1));
        }
        int ci = raw.IndexOf("\"code\"", StringComparison.OrdinalIgnoreCase);
        if (ci >= 0) {
            int endQ;
            int q = IndexOfStringValue(raw, ci + 6, out endQ);
            if (q >= 0) {
                string code = raw.Substring(q + 1);
                code = code.TrimEnd();
                if (code.EndsWith("\"") && !code.EndsWith("\\\"")) code = code.Substring(0, code.Length - 1);
                code = code.TrimEnd();
                if (code.EndsWith("}")) code = code.Substring(0, code.Length - 1);
                o["code"] = Unescape(code);
            }
        }
        return o.ToJsonString();
    }

    static int IndexOfStringValue(string s, int start, out int closingQuote) {
        closingQuote = -1;
        int colon = s.IndexOf(':', start);
        if (colon < 0) return -1;
        int q = s.IndexOf('"', colon + 1);
        if (q < 0) return -1;
        int end = s.IndexOf('"', q + 1);
        while (end > 0 && CountEscapes(s, end) % 2 == 1) end = s.IndexOf('"', end + 1);
        closingQuote = end;
        return q;
    }

    static int CountEscapes(string s, int idx) {
        int n = 0;
        for (int i = idx - 1; i >= 0 && s[i] == '\\'; i--) n++;
        return n;
    }

    static string Unescape(string s) {
        var sb = new StringBuilder(s.Length);
        for (int i = 0; i < s.Length; i++) {
            char c = s[i];
            if (c == '\\' && i + 1 < s.Length) {
                char n = s[++i];
                if (n == 'n') sb.Append('\n');
                else if (n == 'r') sb.Append('\r');
                else if (n == 't') sb.Append('\t');
                else if (n == '"') sb.Append('"');
                else if (n == '\\') sb.Append('\\');
                else { sb.Append('\\'); sb.Append(n); }
            } else sb.Append(c);
        }
        return sb.ToString();
    }

    static async Task<string> Post(List<JsonObject> messages) {
        string baseUrl = BaseUrl.Trim().TrimEnd('/');
        if (baseUrl.EndsWith("/v1", StringComparison.OrdinalIgnoreCase))
            baseUrl = baseUrl.Substring(0, baseUrl.Length - 3).TrimEnd('/');

        var body = new JsonObject();
        if (!string.IsNullOrWhiteSpace(Model)) body["model"] = Model;
        var arr = new JsonArray();
        foreach (var m in messages) arr.Add(JsonNode.Parse(m.ToJsonString()));
        body["messages"] = arr;
        body["tools"] = ToolsSchema();
        body["tool_choice"] = "auto";
        body["max_tokens"] = 4096;
        body["temperature"] = 0.7;
        body["stream"] = false;

        using (var content = new System.Net.Http.StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"))
        using (var resp = await Http.PostAsync(baseUrl + "/v1/chat/completions", content).ConfigureAwait(false)) {
            string text = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
                throw new Exception(resp.StatusCode + " " + text.Substring(0, Math.Min(300, text.Length)));
            return text;
        }
    }

    static JsonArray ToolsSchema() {
        var arr = new JsonArray();
        arr.Add(Function("run_lua",
            "Execute Luau code in the running Roblox game through the executor. Attaches/injects automatically. Returns execution status.",
            Props("code", "The full Lua/Luau code to run."), new[] { "code" }));
        arr.Add(Function("create_script",
            "Create and save a Lua/Luau script into the executor's Scripts folder so it appears in the file list.",
            Props("name", "File name for the script (no path).", "code", "The full Lua/Luau code to save."), new[] { "name", "code" }));
        arr.Add(Function("set_editor",
            "Replace the code currently shown in the built-in editor.",
            Props("code", "The Lua/Luau code to load into the editor."), new[] { "code" }));
        arr.Add(Function("get_editor",
            "Return the code currently in the built-in editor.", new JsonObject(), null));
        arr.Add(Function("list_scripts",
            "Return the file names of scripts saved in the Scripts folder.", new JsonObject(), null));
        arr.Add(Function("read_script",
            "Return the contents of a saved script by file name.",
            Props("name", "File name of the saved script."), new[] { "name" }));
        arr.Add(Function("attach",
            "Attach to Roblox and inject the executor so scripts can run. Returns status.", new JsonObject(), null));
        return arr;
    }

    static JsonObject Props(params string[] kv) {
        var props = new JsonObject();
        for (int i = 0; i + 1 < kv.Length; i += 2) {
            props[kv[i]] = new JsonObject {
                ["type"] = "string",
                ["description"] = kv[i + 1]
            };
        }
        return props;
    }

    static JsonObject Function(string name, string desc, JsonObject props, string[] required) {
        var fn = new JsonObject {
            ["type"] = "function",
            ["function"] = new JsonObject {
                ["name"] = name,
                ["description"] = desc,
                ["parameters"] = new JsonObject { ["type"] = "object", ["properties"] = props }
            }
        };
        if (required != null && required.Length > 0) {
            var r = new JsonArray();
            foreach (var s in required) r.Add(s);
            ((JsonObject)fn["function"]["parameters"])["required"] = r;
        }
        return fn;
    }
}