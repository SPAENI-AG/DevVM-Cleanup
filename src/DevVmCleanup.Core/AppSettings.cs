using System.Text.Json;
using System.Text.Json.Serialization;

namespace DevVmCleanup.Core;

/// <summary>Persistente Einstellungen als JSON unter %APPDATA%\DevVM-Cleanup\settings.json (keine Passwörter).</summary>
public sealed class AppSettings
{
    public const string AppFolderName = "DevVM-Cleanup";

    public string Language { get; set; } = "de";

    /// <summary>Zusätzliche Ordner für den Geheimnis-Scan (neben dem Benutzerprofil).</summary>
    public List<string> ScanRoots { get; set; } = new();

    // --- Updates (GitHub Releases) ---
    public bool CheckForUpdates { get; set; } = true;
    public DateTime? LastUpdateCheckUtc { get; set; }
    /// <summary>"Diese Version überspringen" – kein Hinweis mehr für genau diese Version.</summary>
    public string SkippedVersion { get; set; } = "";
    /// <summary>Zuletzt gestartete Version – für den Hinweis nach einem Update.</summary>
    public string LastRunVersion { get; set; } = "";

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    /// <summary>Kann für Tests umgelenkt werden.</summary>
    public static string? FolderOverride { get; set; }

    public static string Folder
    {
        get
        {
            var d = FolderOverride ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppFolderName);
            Directory.CreateDirectory(d);
            return d;
        }
    }

    public static string FilePath => Path.Combine(Folder, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOpts) ?? new();
        }
        catch (Exception)
        {
            // defekte Datei -> Standardwerte
        }
        return new AppSettings();
    }

    public void Save()
    {
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(this, JsonOpts));
        File.Move(tmp, FilePath, overwrite: true);
    }
}
