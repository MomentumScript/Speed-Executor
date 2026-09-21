using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;





static class Config
{
    public sealed class SettingsData
    {
        public bool TopMost { get; set; }
        public string Accent { get; set; }
        public int EditorFont { get; set; }
        public bool TutorialDone { get; set; }
        public string LastTab { get; set; }
        public string ChatServer { get; set; }
        public string ChatModel { get; set; }
    }

    public sealed class OpenTab
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public string Content { get; set; }
        public int Cursor { get; set; }
        public int Scroll { get; set; }
    }

    public sealed class TabsData
    {
        public int Active { get; set; }
        public List<OpenTab> Tabs { get; set; }
    }

    public sealed class ChatMessage
    {
        public bool User { get; set; }
        public string Text { get; set; }
    }

    public sealed class ChatData
    {
        public List<ChatMessage> Messages { get; set; }
    }

    public sealed class AccountRecord
    {
        public long UserId { get; set; }
        public string Name { get; set; }
        public string DisplayName { get; set; }
        public string Initial { get; set; }
        public bool Verified { get; set; }
        public int Uses { get; set; }
        public string FirstSeen { get; set; }
        public string LastSeen { get; set; }
    }

    public sealed class AccountsData
    {
        public List<AccountRecord> Accounts { get; set; }
    }

    static readonly object _gate = new object();
    static readonly JsonSerializerOptions _json = new JsonSerializerOptions
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static SettingsData Settings = new SettingsData();
    public static TabsData Tabs = new TabsData();
    public static ChatData Chat = new ChatData();
    public static AccountsData Accounts = new AccountsData();

    static string DirPath() { return Installer.ConfigDir(); }
    static string StatePath() { return Path.Combine(DirPath(), "state.txt"); }
    static string SettingsPath() { return Path.Combine(DirPath(), "settings.json"); }
    static string TabsPath() { return Path.Combine(DirPath(), "tabs.txt"); }
    static string OldTabsPath() { return Path.Combine(DirPath(), "tabs.json"); }
    static string ChatPath() { return Path.Combine(DirPath(), "chat.json"); }
    static string AccountsPath() { return Path.Combine(DirPath(), "accounts.json"); }

    public static void Load()
    {
        try
        {
            lock (_gate)
            {
                Settings = Read<SettingsData>(StatePath()) ?? Read<SettingsData>(SettingsPath()) ?? new SettingsData();
                Tabs = Read<TabsData>(TabsPath()) ?? Read<TabsData>(OldTabsPath()) ?? new TabsData();
                Chat = Read<ChatData>(ChatPath()) ?? new ChatData();
                Accounts = Read<AccountsData>(AccountsPath()) ?? new AccountsData();
            }
        }
        catch { }

        if (Settings == null) Settings = new SettingsData();
        if (Tabs == null) Tabs = new TabsData();
        if (Chat == null) Chat = new ChatData();
        if (Accounts == null) Accounts = new AccountsData();

        if (Settings.Accent == null) Settings.Accent = "#FFE8A800";
        if (Settings.EditorFont <= 0) Settings.EditorFont = 14;
        if (Settings.LastTab == null) Settings.LastTab = "dashboard";
        if (Settings.ChatServer == null) Settings.ChatServer = "http://127.0.0.1:8080";
        if (Settings.ChatModel == null) Settings.ChatModel = "";
        if (Tabs.Tabs == null) Tabs.Tabs = new List<OpenTab>();
        if (Chat.Messages == null) Chat.Messages = new List<ChatMessage>();
        if (Accounts.Accounts == null) Accounts.Accounts = new List<AccountRecord>();
    }

    static T Read<T>(string path) where T : class
    {
        try
        {
            if (!File.Exists(path)) return null;
            string text = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(text)) return null;
            return JsonSerializer.Deserialize<T>(text, _json);
        }
        catch { return null; }
    }

    static void Write<T>(string path, T value)
    {
        try
        {
            Directory.CreateDirectory(DirPath());
            File.WriteAllText(path, JsonSerializer.Serialize(value, _json));
        }
        catch { }
    }

    public static void SaveSettings() { lock (_gate) Write(StatePath(), Settings); }
    public static void SaveTabs() { lock (_gate) Write(TabsPath(), Tabs); }
    public static void SaveChat() { lock (_gate) Write(ChatPath(), Chat); }
    public static void SaveAccounts() { lock (_gate) Write(AccountsPath(), Accounts); }

    public static void SaveAll()
    {
        SaveSettings();
        SaveTabs();
        SaveChat();
        SaveAccounts();
    }

    


    public static void RememberAccount(RobloxProfile.Info info)
    {
        if (info == null || info.UserId == 0) return;
        try
        {
            lock (_gate)
            {
                if (Accounts.Accounts == null) Accounts.Accounts = new List<AccountRecord>();

                var rec = Accounts.Accounts.Find(a => a.UserId == info.UserId);
                string now = DateTime.Now.ToString("yyyy-MM-dd HH:mm");

                if (rec == null)
                {
                    rec = new AccountRecord
                    {
                        UserId = info.UserId,
                        FirstSeen = now,
                        Initial = string.IsNullOrEmpty(info.Initial) ? "?" : info.Initial,
                    };
                    Accounts.Accounts.Add(rec);
                }

                rec.Name = info.Name;
                rec.DisplayName = info.DisplayName;
                rec.Verified = info.Verified;
                rec.Initial = string.IsNullOrEmpty(info.Initial) ? "?" : info.Initial;
                rec.Uses = rec.Uses + 1;
                rec.LastSeen = now;

                Write(AccountsPath(), Accounts);
            }
        }
        catch { }
    }

    public static void ClearAccounts()
    {
        try
        {
            lock (_gate)
            {
                Accounts.Accounts = new List<AccountRecord>();
                Write(AccountsPath(), Accounts);
            }
        }
        catch { }
    }
}
