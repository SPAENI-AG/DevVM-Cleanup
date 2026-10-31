using System.Text;

namespace DevVmCleanup.Core;

/// <summary>Protokolldatei unter %APPDATA%\DevVM-Cleanup\logs. Jede Zeile läuft durch <see cref="LogRedactor"/>.</summary>
public sealed class RunLog
{
    private readonly object _sync = new();
    public string FilePath { get; }

    public static string Folder => Path.Combine(AppSettings.Folder, "logs");

    public RunLog(string? folder = null, DateTime? now = null)
    {
        var dir = folder ?? Folder;
        Directory.CreateDirectory(dir);
        FilePath = Path.Combine(dir, $"cleanup_{(now ?? DateTime.Now):yyyyMMdd_HHmmss}.log");
    }

    /// <summary>Schreibt eine Zeile (ohne Passwörter/Tokens) und gibt den geschriebenen Text zurück.</summary>
    public string Write(string message)
    {
        var line = $"{DateTime.Now:HH:mm:ss}  {LogRedactor.Redact(message)}";
        try { lock (_sync) File.AppendAllText(FilePath, line + Environment.NewLine, Encoding.UTF8); }
        catch (Exception) { /* Logdatei nicht schreibbar: Anzeige im Fenster genügt */ }
        return line;
    }
}
