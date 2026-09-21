using System;
using System.IO;





static class Installer {
    public static string ConfigDir() {
        string root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "SpeedExecutor");
        try { Directory.CreateDirectory(root); } catch { }
        return root;
    }
}
