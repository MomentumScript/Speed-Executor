using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using SpeedExecutor;

[System.Runtime.InteropServices.ClassInterface(System.Runtime.InteropServices.ClassInterfaceType.AutoDual)]
[System.Runtime.InteropServices.ComVisible(true)]
public class FileInterop
{
    private string ScriptsFolder => Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts");

    public FileInterop()
    {
        

        if (!Directory.Exists(ScriptsFolder))
            Directory.CreateDirectory(ScriptsFolder);
    }

    public string[] GetFiles()
    {
        try
        {
            return Directory.GetFiles(ScriptsFolder, "*.*")
                .Where(f => f.EndsWith(".txt", StringComparison.OrdinalIgnoreCase) ||
                           f.EndsWith(".lua", StringComparison.OrdinalIgnoreCase) ||
                           f.EndsWith(".luau", StringComparison.OrdinalIgnoreCase))
                .Select(Path.GetFileName)
                .ToArray();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("explorer error");
            return new string[0];
        }
    }

    public string ReadFile(string filename)
    {
        try
        {
            string path = Path.Combine(ScriptsFolder, filename);
            return File.Exists(path) ? File.ReadAllText(path) : "";
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("explorer error");
            return "";
        }
    }

    public void OpenFile(string filename)
    {
        try
        {
            string text = ReadFile(filename);
            if (!string.IsNullOrEmpty(text))
            {
                

                Application.Current.Dispatcher.Invoke(async () =>
                {
                    if (Application.Current.MainWindow is MainWindow main)
                    {
                        

                        string escapedText = JsonSerializer.Serialize(text);
                        await main.Editor.CoreWebView2.ExecuteScriptAsync(
                            $"setValue({escapedText})");
                    }
                });
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("explorer error");
        }
    }
}