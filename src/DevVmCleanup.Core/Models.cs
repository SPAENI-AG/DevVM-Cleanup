using System.Text.Json.Serialization;

namespace DevVmCleanup.Core;

/// <summary>Zweisprachiger Text aus einem Modul-Skript.</summary>
public sealed class LocalizedText
{
    [JsonPropertyName("de")] public string De { get; set; } = "";
    [JsonPropertyName("en")] public string En { get; set; } = "";
    public string Get(string lang) => lang == "en" && En.Length > 0 ? En : De;
}

public sealed class CategoryInfo
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("de")] public string De { get; set; } = "";
    [JsonPropertyName("en")] public string En { get; set; } = "";
    [JsonPropertyName("default")] public bool Default { get; set; } = true;
    public string Label(string lang) => lang == "en" && En.Length > 0 ? En : De;
}

/// <summary>Beschreibung eines Moduls (Ausgabe von <c>-Action Info</c>).</summary>
public sealed class ModuleInfo
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public LocalizedText Name { get; set; } = new();
    [JsonPropertyName("processes")] public List<string> Processes { get; set; } = new();
    [JsonPropertyName("categories")] public List<CategoryInfo> Categories { get; set; } = new();
    /// <summary>Pfad des Skripts (wird vom ModuleRunner gesetzt).</summary>
    [JsonIgnore] public string ScriptPath { get; set; } = "";
}

/// <summary>Ein Fund der Analyse („gefunden: …“).</summary>
public sealed class Finding
{
    [JsonPropertyName("category")] public string Category { get; set; } = "";
    /// <summary>Wo gefunden, z. B. „Edge / Profil 1“.</summary>
    [JsonPropertyName("scope")] public string Scope { get; set; } = "";
    /// <summary>Lesbarer Befund, z. B. „37 Passwörter“. Enthält nie Passwörter/Tokens.</summary>
    [JsonPropertyName("label")] public string Label { get; set; } = "";
    [JsonPropertyName("count")] public int Count { get; set; }
}

public sealed class ModuleAnalysis
{
    [JsonPropertyName("module")] public string Module { get; set; } = "";
    [JsonPropertyName("findings")] public List<Finding> Findings { get; set; } = new();
}

public sealed class CleanResult
{
    [JsonPropertyName("category")] public string Category { get; set; } = "";
    [JsonPropertyName("scope")] public string Scope { get; set; } = "";
    [JsonPropertyName("ok")] public bool Ok { get; set; }
    [JsonPropertyName("removed")] public int Removed { get; set; }
    [JsonPropertyName("message")] public string Message { get; set; } = "";
}

public sealed class ModuleCleanResult
{
    [JsonPropertyName("module")] public string Module { get; set; } = "";
    [JsonPropertyName("results")] public List<CleanResult> Results { get; set; } = new();
}

/// <summary>Rohdaten aus modules/_Preflight.ps1.</summary>
public sealed class PreflightData
{
    [JsonPropertyName("manufacturer")] public string Manufacturer { get; set; } = "";
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("isAdmin")] public bool IsAdmin { get; set; }
    [JsonPropertyName("currentUser")] public string CurrentUser { get; set; } = "";
    [JsonPropertyName("interactiveUser")] public string? InteractiveUser { get; set; }
    [JsonPropertyName("computerName")] public string ComputerName { get; set; } = "";
}

public sealed class FinishResult
{
    [JsonPropertyName("action")] public string Action { get; set; } = "";
    [JsonPropertyName("ok")] public bool Ok { get; set; }
    [JsonPropertyName("message")] public string Message { get; set; } = "";
}
