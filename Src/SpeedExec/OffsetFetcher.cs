using System;
using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;









static class OffsetFetcher {
    static readonly HttpClient Http = MakeClient();
    const string Base = "https://offsets.imtheo.lol";
    public static string LastLog = "";

    static HttpClient MakeClient() {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("SpeedExecutor/1.0");
        return c;
    }

    public static async Task<bool> FetchAsync(string version) {
        LastLog = "";
        if (string.IsNullOrEmpty(version)) { LastLog = "no version"; return false; }
        bool any = false;
        var offTask = TryGet($"{Base}/{version}/OffsetsHex.json");
        var ffTask = TryGet($"{Base}/{version}/FFlagsHex.json");
        await Task.WhenAll(offTask, ffTask);

        if (!string.IsNullOrEmpty(offTask.Result)) {
            int applied = ApplyOffsets(offTask.Result);
            LastLog += "offsets:" + applied + " ";
            if (applied > 0) any = true;
        } else LastLog += "offsets:http-fail ";

        if (!string.IsNullOrEmpty(ffTask.Result)) {
            int applied = ApplyFFlags(ffTask.Result);
            LastLog += "fflags:" + applied;
            if (applied > 0) any = true;
        } else LastLog += "fflags:http-fail";

        if (any) Off.ClientVersion = version;
        return any;
    }

    static async Task<string> TryGet(string url) {
        try { return await Http.GetStringAsync(url); }
        catch { return null; }
    }

    static int ApplyOffsets(string json) {
        int n = 0;
        try {
            using (var doc = JsonDocument.Parse(json)) {
                JsonElement offsets;
                if (!doc.RootElement.TryGetProperty("Offsets", out offsets)) return 0;

                n += ApplyPath(offsets, ref Off.FDM_Pointer,           "FakeDataModel", "Pointer");
                n += ApplyPath(offsets, ref Off.FDM_RealDataModel,     "FakeDataModel", "RealDataModel");
                n += ApplyPath(offsets, ref Off.Instance_Name,         "Instance", "Name");
                n += ApplyPath(offsets, ref Off.Instance_NameContainer,"Instance", "NameContainer");
                n += ApplyPath(offsets, ref Off.Instance_ClassDesc,    "Instance", "ClassDescriptor");
                n += ApplyPath(offsets, ref Off.Instance_ClassName,    "Instance", "ClassName");
                n += ApplyPath(offsets, ref Off.Instance_Parent,       "Instance", "Parent");
                n += ApplyPath(offsets, ref Off.Instance_ChildrenStart,"Instance", "ChildrenStart");
                n += ApplyPath(offsets, ref Off.Instance_ChildrenEnd,  "Instance", "ChildrenEnd");
                n += ApplyPath(offsets, ref Off.Module_BC,             "ModuleScript", "ByteCode");
                n += ApplyPath(offsets, ref Off.Local_BC,              "LocalScript", "ByteCode");
                n += ApplyPath(offsets, ref Off.Misc_Value,            "Misc", "Value");
                

                

                n += ApplyPath(offsets, ref Off.TaskSchedulerTargetFps,"TaskScheduler", "MaxFPS");
            }
        } catch { }
        return n;
    }

    static int ApplyFFlags(string json) {
        int n = 0;
        try {
            using (var doc = JsonDocument.Parse(json)) {
                JsonElement fflags;
                if (!doc.RootElement.TryGetProperty("FFlagOffsets", out fflags)) return 0;
                if (!fflags.TryGetProperty("FFlags", out fflags)) return 0;

                n += ApplyPath(fflags, ref Off.FFlag_EnableLoadModule, "EnableLoadModule");
                n += ApplyPath(fflags, ref Off.FFlagDebugSkyGray,      "DebugSkyGray");
            }
        } catch { }
        return n;
    }

    static int ApplyPath(JsonElement root, ref ulong field, params string[] path) {
        JsonElement cur = root;
        foreach (var p in path) {
            if (cur.ValueKind != JsonValueKind.Object) return 0;
            if (!cur.TryGetProperty(p, out cur)) return 0;
        }
        ulong v;
        if (TryParseNum(cur, out v)) { field = v; return 1; }
        return 0;
    }

    static bool TryParseNum(JsonElement e, out ulong v) {
        v = 0;
        if (e.ValueKind == JsonValueKind.Number) return e.TryGetUInt64(out v);
        if (e.ValueKind == JsonValueKind.String) {
            string s = e.GetString();
            if (string.IsNullOrEmpty(s)) return false;
            s = s.Trim();
            if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                return ulong.TryParse(s.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out v);
            return ulong.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v);
        }
        return false;
    }
}
