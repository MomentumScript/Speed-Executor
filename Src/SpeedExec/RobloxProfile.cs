using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;

















static class RobloxProfile
{
    public class Info
    {
        public long UserId;
        public string Name = "";
        public string DisplayName = "";
        public DateTime Created;
        public bool Verified;

        public string Initial
        {
            get
            {
                string s = string.IsNullOrEmpty(Name) ? "?" : Name;
                return s.Substring(0, 1).ToUpperInvariant();
            }
        }
    }

    static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };

    static RobloxProfile()
    {
        try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }
        try { Http.DefaultRequestHeaders.UserAgent.ParseAdd("SpeedExecutor/1.0"); } catch { }
    }

    static string LogsDirectory
    {
        get
        {
            try
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Roblox", "logs");
            }
            catch { return null; }
        }
    }

    

    public static long FindUserId()
    {
        try
        {
            string dir = LogsDirectory;
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return 0;

            var candidates = Directory.GetFiles(dir, "*_Player_*.log")
                .Select(p => new FileInfo(p))
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .ToList();

            int scanned = 0;
            foreach (var file in candidates)
            {
                if (scanned++ >= 8) break; 


                string[] lines;
                try { lines = File.ReadAllLines(file.FullName); }
                catch { continue; }

                foreach (string line in lines)
                {
                    long id = ParseUserId(line);
                    if (id != 0) return id;
                }
            }
        }
        catch { }
        return 0;
    }

    static long ParseUserId(string line)
    {
        const string marker = "rbxuid=";
        int at = line.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (at < 0) return 0;

        int start = at + marker.Length;
        int end = start;
        while (end < line.Length && char.IsDigit(line[end])) end++;
        if (end == start) return 0;

        if (long.TryParse(line.Substring(start, end - start), out long id) && id > 0)
            return id;

        return 0;
    }

    

    public static async Task<Info> FetchAsync(long userId)
    {
        string json = await Http.GetStringAsync("https://users.roblox.com/v1/users/" +
                                                userId.ToString(CultureInfo.InvariantCulture));

        var info = new Info { UserId = userId };
        using (var doc = JsonDocument.Parse(json))
        {
            var root = doc.RootElement;

            if (root.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String)
                info.Name = name.GetString() ?? "";

            if (root.TryGetProperty("displayName", out var display) && display.ValueKind == JsonValueKind.String)
                info.DisplayName = display.GetString() ?? "";

            if (root.TryGetProperty("created", out var created) && created.ValueKind == JsonValueKind.String)
                DateTime.TryParse(created.GetString(), CultureInfo.InvariantCulture,
                                  DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal,
                                  out info.Created);

            if (root.TryGetProperty("hasVerifiedBadge", out var verified) &&
                (verified.ValueKind == JsonValueKind.True || verified.ValueKind == JsonValueKind.False))
                info.Verified = verified.GetBoolean();
        }

        if (string.IsNullOrEmpty(info.DisplayName)) info.DisplayName = info.Name;
        return info;
    }

    

    public static async Task<BitmapImage> FetchAvatarAsync(long userId)
    {
        string url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" +
                     userId.ToString(CultureInfo.InvariantCulture) + "&size=150x150&format=Png&isCircular=true";

        

        for (int attempt = 0; attempt < 4; attempt++)
        {
            string json = await Http.GetStringAsync(url);
            string imageUrl = null;

            using (var doc = JsonDocument.Parse(json))
            {
                if (doc.RootElement.TryGetProperty("data", out var data) &&
                    data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0)
                {
                    var first = data[0];
                    if (first.TryGetProperty("state", out var state) &&
                        state.GetString() == "Completed" &&
                        first.TryGetProperty("imageUrl", out var img) &&
                        img.ValueKind == JsonValueKind.String)
                    {
                        imageUrl = img.GetString();
                    }
                }
            }

            if (!string.IsNullOrEmpty(imageUrl))
            {
                byte[] bytes = await Http.GetByteArrayAsync(imageUrl);
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.StreamSource = new MemoryStream(bytes);
                bitmap.EndInit();
                bitmap.Freeze();
                return bitmap;
            }

            await Task.Delay(700);
        }

        return null;
    }
}



static class AppInfo
{
    public const string Version = "1.2.0";

    public class Change
    {
        public string Version;
        public string Date;
        public string[] Notes;

        public Change(string version, string date, string[] notes)
        {
            Version = version;
            Date = date;
            Notes = notes;
        }
    }

    public static readonly Change[] Changelog =
    {
        new Change("1.2.0", "16 Sep 2026", new[]
        {
            "New Dashboard tab, now the default view.",
            "Sidebar status dot is replaced by your Roblox avatar, with a status ring that lights up once attached.",
            "Account name, display name, join date and avatar are resolved from the client log plus Roblox's public APIs.",
            "Changelog tracked in-app.",
        }),
        new Change("1.1.0", "16 Sep 2026", new[]
        {
            "Full UI pass: consistent hover, pressed and disabled states on every button.",
            "Accent buttons no longer lose their colour after being hovered.",
            "Window can be resized; editor, file list, settings and chat now stretch with it.",
            "Minimize and Close use distinct icons; dragging is limited to the title bar.",
            "Script list refresh no longer flickers or drops your selection.",
            "Editor read/write is JSON-safe, so tabs and backslashes survive open/save/run.",
        }),
        new Change("1.0.0", "15 Sep 2026", new[]
        {
            "Editor, Script Hub, Settings and Speed Chat tabs.",
            "Local AI server setup with tool calling: run Lua, attach, read and write scripts.",
        }),
    };
}
