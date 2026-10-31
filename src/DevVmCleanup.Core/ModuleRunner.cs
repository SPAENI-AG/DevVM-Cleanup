using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevVmCleanup.Core;

public sealed class ModuleException(string message) : Exception(message);

/// <summary>
/// Findet die PowerShell-Module (modules\*.ps1, ohne "_"-Präfix), ruft sie auf und liest ihre JSON-Ausgabe.
/// Neue Module = neue Datei im Ordner, ohne Neukompilieren.
/// </summary>
public sealed class ModuleRunner
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    public string ModulesFolder { get; }

    /// <summary>"powershell.exe" (Windows PowerShell 5.1, auf jedem Windows vorhanden); für Tests auf "pwsh" umlenkbar.</summary>
    public string PowerShell { get; set; } = "powershell.exe";

    /// <summary>Optional: Kontext-Überschreibung (Pfade/Registry-Zweig) als JSON – für Tests.</summary>
    public string? ContextJson { get; set; }

    public static string DefaultModulesFolder => Path.Combine(AppContext.BaseDirectory, "modules");

    public ModuleRunner(string? modulesFolder = null) => ModulesFolder = modulesFolder ?? DefaultModulesFolder;

    /// <summary>Alle Modul-Skripte (ohne Hilfsskripte mit "_"-Präfix), alphabetisch.</summary>
    public IReadOnlyList<string> DiscoverScripts() =>
        Directory.Exists(ModulesFolder)
            ? Directory.EnumerateFiles(ModulesFolder, "*.ps1")
                .Where(f => !Path.GetFileName(f).StartsWith('_'))
                .OrderBy(f => f, StringComparer.OrdinalIgnoreCase).ToList()
            : new List<string>();

    public static string[] BuildArguments(string script, string action, IEnumerable<string>? categories, string lang, string? contextJson)
    {
        var args = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Action", action, "-Lang", lang };
        var cats = categories?.ToList();
        if (cats is { Count: > 0 }) { args.Add("-Categories"); args.Add(string.Join(",", cats)); }
        if (!string.IsNullOrEmpty(contextJson)) { args.Add("-ContextJson"); args.Add(contextJson); }
        return args.ToArray();
    }

    /// <summary>Liest die Beschreibungen aller Module. Ein defektes Modul wird mit Fehlertext gemeldet, die anderen bleiben nutzbar.</summary>
    public async Task<(List<ModuleInfo> Modules, List<string> Errors)> LoadModulesAsync(CancellationToken ct = default)
    {
        var modules = new List<ModuleInfo>();
        var errors = new List<string>();
        foreach (var script in DiscoverScripts())
        {
            try
            {
                var info = ParseJson<ModuleInfo>(await RunAsync(BuildArguments(script, "Info", null, "de", ContextJson), ct).ConfigureAwait(false));
                if (string.IsNullOrWhiteSpace(info.Id)) throw new ModuleException("Modul ohne id");
                info.ScriptPath = script;
                modules.Add(info);
            }
            catch (Exception ex) { errors.Add($"{Path.GetFileName(script)}: {ex.Message}"); }
        }
        return (modules, errors);
    }

    public async Task<ModuleAnalysis> AnalyzeAsync(ModuleInfo module, IEnumerable<string>? categories, string lang, CancellationToken ct = default) =>
        ParseJson<ModuleAnalysis>(await RunAsync(BuildArguments(module.ScriptPath, "Analyze", categories, lang, ContextJson), ct).ConfigureAwait(false));

    public async Task<ModuleCleanResult> CleanAsync(ModuleInfo module, IEnumerable<string> categories, string lang, CancellationToken ct = default)
    {
        var cats = categories.ToList();
        if (cats.Count == 0) return new ModuleCleanResult { Module = module.Id };   // nie ohne ausdrückliche Auswahl löschen
        return ParseJson<ModuleCleanResult>(await RunAsync(BuildArguments(module.ScriptPath, "Clean", cats, lang, ContextJson), ct).ConfigureAwait(false));
    }

    public async Task<PreflightData> GetPreflightAsync(CancellationToken ct = default)
    {
        var script = Path.Combine(ModulesFolder, "_Preflight.ps1");
        return ParseJson<PreflightData>(await RunAsync(new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script }, ct).ConfigureAwait(false));
    }

    public async Task<FinishResult> FinishAsync(string action, string? newName, CancellationToken ct = default)
    {
        var script = Path.Combine(ModulesFolder, "_Finish.ps1");
        var args = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Action", action };
        if (!string.IsNullOrEmpty(newName)) { args.Add("-NewName"); args.Add(newName); }
        return ParseJson<FinishResult>(await RunAsync(args, ct).ConfigureAwait(false));
    }

    /// <summary>Letzte JSON-Zeile der Ausgabe lesen (Warnungen/Meldungen davor werden ignoriert).</summary>
    public static T ParseJson<T>(string output)
    {
        var line = output.Split('\n').Select(l => l.Trim()).LastOrDefault(l => l.StartsWith('{'));
        if (line is null) throw new ModuleException(LogRedactor.Redact(output.Trim().Length > 0 ? output.Trim() : "keine Ausgabe"));
        return JsonSerializer.Deserialize<T>(line, Json) ?? throw new ModuleException("leere JSON-Antwort");
    }

    private async Task<string> RunAsync(IEnumerable<string> args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(PowerShell)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi) ?? throw new ModuleException("PowerShell konnte nicht gestartet werden");
        var stdout = p.StandardOutput.ReadToEndAsync(ct);
        var stderr = p.StandardError.ReadToEndAsync(ct);
        await p.WaitForExitAsync(ct).ConfigureAwait(false);
        var o = await stdout.ConfigureAwait(false);
        var e = await stderr.ConfigureAwait(false);
        if (p.ExitCode != 0 && !o.Contains('{'))
            throw new ModuleException(LogRedactor.Redact(string.IsNullOrWhiteSpace(e) ? $"Exitcode {p.ExitCode}" : e.Trim()));
        return o;
    }
}
