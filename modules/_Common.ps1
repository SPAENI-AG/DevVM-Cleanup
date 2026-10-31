# _Common.ps1 – gemeinsame Hilfsfunktionen der DevVM-Cleanup-Module.
# Wird von den Modulen per Dot-Sourcing geladen. Kein Modul selbst (Präfix "_").
# Regeln:
#  * Analyse liest nur, Clean löscht nur innerhalb der Wurzeln des Kontexts ($Ctx).
#  * Ausgaben/Logs enthalten nie Passwörter oder Tokens. Es werden nur Kategorien, Zähler und Anzeigenamen gemeldet.
#  * Windows PowerShell 5.1 und PowerShell 7 werden unterstützt.

$script:DvcLang = 'de'

function T {
    # T 'deutsch' 'english' -> Text in der gewählten Sprache
    param([string]$De, [string]$En)
    if ($script:DvcLang -eq 'en') { $En } else { $De }
}

function Test-IsWindowsHost {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function New-Ctx {
    # Kontext = Wurzeln, in denen gearbeitet werden darf. Tests übersteuern sie (Temp-Ordner, Test-Registry-Zweig).
    param([string]$Json)
    $ctx = @{
        UserProfile  = $env:USERPROFILE
        AppData      = $env:APPDATA
        LocalAppData = $env:LOCALAPPDATA
        Hkcu         = 'HKCU:'
    }
    if ($Json) {
        $o = $Json | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $ctx[$p.Name] = [string]$p.Value }
    }
    $ctx
}

function P {
    # Pfad aus Teilen bauen (plattformneutral): P $base 'a','b'
    param([string]$Base, [string[]]$Rest)
    $p = $Base
    foreach ($r in $Rest) { $p = Join-Path $p $r }
    $p
}

function Split-List {
    param($Value)
    @($Value | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function New-Finding {
    param([string]$Category, [string]$Scope, [string]$Label, [int]$Count = 1)
    [ordered]@{ category = $Category; scope = $Scope; label = $Label; count = $Count }
}

function New-Result {
    param([string]$Category, [string]$Scope, [bool]$Ok, [int]$Removed, [string]$Message = '')
    [ordered]@{ category = $Category; scope = $Scope; ok = $Ok; removed = $Removed; message = $Message }
}

function Write-ModuleJson {
    param($Object)
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $Object -Depth 8 -Compress))
}

# ---------------------------------------------------------------------------------------------
# Sicheres Löschen
# ---------------------------------------------------------------------------------------------
function Get-ProtectedPaths {
    # Diese Ordner (und die Wurzeln selbst) werden nie gelöscht – auch nicht, wenn ein Modul es versehentlich verlangt.
    param($Ctx)
    $list = @()
    foreach ($k in 'UserProfile', 'AppData', 'LocalAppData') { if ($Ctx[$k]) { $list += $Ctx[$k] } }
    if ($Ctx.UserProfile) {
        foreach ($n in 'AppData', 'Documents', 'Desktop', 'Downloads', 'Pictures', 'Videos', 'Music', 'Favorites', 'Links', 'Contacts', 'Saved Games', 'Searches', '3D Objects', 'OneDrive') {
            $list += (Join-Path $Ctx.UserProfile $n)
        }
    }
    foreach ($k in 'AppData', 'LocalAppData') { if ($Ctx[$k]) { $list += (Join-Path $Ctx[$k] 'Microsoft') } }
    $list
}

function Test-PathInCtx {
    # true = Pfad liegt UNTERHALB der Kontext-Wurzeln und ist keine geschützte Wurzel/Standardordner
    param([string]$Path, $Ctx)
    $sep = [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    foreach ($prot in (Get-ProtectedPaths $Ctx)) {
        if ([string]::Equals([IO.Path]::GetFullPath($prot).TrimEnd('\', '/'), $full, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    foreach ($k in 'UserProfile', 'AppData', 'LocalAppData') {
        $root = $Ctx[$k]
        if (-not $root) { continue }
        $r = [IO.Path]::GetFullPath($root).TrimEnd('\', '/')
        if ($full.Length -gt $r.Length -and $full.StartsWith($r + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Remove-PathSafe {
    # Löscht Datei/Ordner nur unterhalb der Kontext-Wurzeln (nie Wurzeln/Standardordner). Rückgabe: 1 = gelöscht, 0 = nichts da.
    # Verknüpfungen (Junctions/Symlinks) werden nur selbst entfernt, nie ihr Ziel.
    param([string]$Path, $Ctx)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    if (-not (Test-PathInCtx -Path $Path -Ctx $Ctx)) { throw "Pfad ausserhalb des erlaubten Bereichs oder geschützt: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName) } else { [IO.File]::Delete($item.FullName) }
        return 1
    }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    1
}

function Test-RegKey {
    param([string]$Path)
    try { Test-Path -LiteralPath $Path -ErrorAction Stop } catch { $false }
}

function Remove-RegKeySafe {
    param([string]$Path, $Ctx)
    if (-not (Test-RegKey $Path)) { return 0 }
    if (-not $Path.StartsWith($Ctx.Hkcu + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Registry-Pfad ausserhalb HKCU: $Path" }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    1
}

function Get-RegChildNames {
    param([string]$Path)
    if (-not (Test-RegKey $Path)) { return @() }
    @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName })
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function Get-PathSizeMB {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { return 0 }
    [math]::Round($sum / 1MB, 1)
}

# Ziele ("Targets") sind Hashtables @{ Path = '...' } (Datei/Ordner) oder @{ Reg = 'HKCU:\...' }.
function Test-TargetExists {
    param($Target)
    if ($Target.Path) { return (Test-Path -LiteralPath $Target.Path) }
    if ($Target.Reg) { return (Test-RegKey $Target.Reg) }
    $false
}

function Remove-Target {
    param($Target, $Ctx)
    if ($Target.Path) { return (Remove-PathSafe -Path $Target.Path -Ctx $Ctx) }
    if ($Target.Reg) { return (Remove-RegKeySafe -Path $Target.Reg -Ctx $Ctx) }
    0
}

# ---------------------------------------------------------------------------------------------
# SQLite über winsqlite3.dll (in Windows 10/11 enthalten, keine Installation nötig)
# ---------------------------------------------------------------------------------------------
$script:DvcSqliteSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DvcSqlite
{
    const string Dll = "winsqlite3.dll";
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] file, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int n, out IntPtr stmt, IntPtr tail);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr stmt, int col);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr err);
    static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

    /// <summary>Erste Spalte der ersten Zeile als Zahl; -1 bei Fehler. Datei wird schreibgeschützt geöffnet.</summary>
    public static long Scalar(string file, string sql)
    {
        IntPtr db;
        if (sqlite3_open_v2(Z(file), out db, 1, IntPtr.Zero) != 0) { if (db != IntPtr.Zero) sqlite3_close(db); return -1; }
        try
        {
            IntPtr st;
            if (sqlite3_prepare_v2(db, Z(sql), -1, out st, IntPtr.Zero) != 0) return -1;
            try { return sqlite3_step(st) == 100 ? sqlite3_column_int64(st, 0) : -1; }
            finally { sqlite3_finalize(st); }
        }
        finally { sqlite3_close(db); }
    }

    /// <summary>SQL ausführen (lesen/schreiben). 0 = ok.</summary>
    public static int Exec(string file, string sql)
    {
        IntPtr db;
        int rc = sqlite3_open_v2(Z(file), out db, 2, IntPtr.Zero);
        if (rc != 0) { if (db != IntPtr.Zero) sqlite3_close(db); return rc; }
        try { IntPtr err; return sqlite3_exec(db, Z(sql), IntPtr.Zero, IntPtr.Zero, out err); }
        finally { sqlite3_close(db); }
    }
}
'@

$script:SqliteReady = $null
function Initialize-Sqlite {
    if ($null -ne $script:SqliteReady) { return $script:SqliteReady }
    $script:SqliteReady = $false
    if (-not (Test-IsWindowsHost)) { return $false }
    try {
        if (-not ('DvcSqlite' -as [type])) { Add-Type -TypeDefinition $script:DvcSqliteSource -ErrorAction Stop }
        $script:SqliteReady = $true
    } catch { $script:SqliteReady = $false }
    $script:SqliteReady
}

function Get-SqlCount {
    # Zahl aus einer SQLite-Datei lesen (auf einer Kopie, falls gesperrt). -1 = nicht ermittelbar.
    param([string]$File, [string]$Sql)
    if (-not (Test-Path -LiteralPath $File)) { return 0 }
    if (-not (Initialize-Sqlite)) { return -1 }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvc_' + [guid]::NewGuid().ToString('N') + '.db')
    try {
        Copy-Item -LiteralPath $File -Destination $tmp -Force -ErrorAction Stop
        [DvcSqlite]::Scalar($tmp, $Sql)
    } catch { -1 } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Test-SqlTable {
    param([string]$File, [string]$Table)
    (Get-SqlCount -File $File -Sql "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$Table'") -gt 0
}

function Invoke-SqlDeleteAll {
    # Leert vorhandene Tabellen und verdichtet die Datei (VACUUM), damit keine Reste in freien Seiten bleiben.
    # Rückgabe: Anzahl geleerter Tabellen; wirft bei Fehler (z. B. Datei gesperrt).
    param([string]$File, [string[]]$Tables, [string]$Where = '')
    if (-not (Test-Path -LiteralPath $File)) { return 0 }
    if (-not (Initialize-Sqlite)) { throw 'SQLite nicht verfügbar' }
    $done = 0
    foreach ($t in $Tables) {
        if (-not (Test-SqlTable -File $File -Table $t)) { continue }
        $rc = [DvcSqlite]::Exec($File, "DELETE FROM [$t];")
        if ($rc -ne 0) { throw "SQLite-Fehler $rc beim Leeren von $t" }
        $done++
    }
    if ($done -gt 0) { [void][DvcSqlite]::Exec($File, 'VACUUM;') }
    $done
}

function Invoke-SqlExec {
    param([string]$File, [string]$Sql)
    if (-not (Test-Path -LiteralPath $File)) { return }
    if (-not (Initialize-Sqlite)) { throw 'SQLite nicht verfügbar' }
    $rc = [DvcSqlite]::Exec($File, $Sql)
    if ($rc -ne 0) { throw "SQLite-Fehler $rc" }
}

# ---------------------------------------------------------------------------------------------
# JSON-Dateien gezielt bearbeiten (Schlüssel entfernen, Rest unverändert lassen)
# ---------------------------------------------------------------------------------------------
$script:DvcJsonSourceCore = @'
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
public static class DvcJson
{
    public static int RemovePaths(string file, string[] paths)
    {
        var root = JsonNode.Parse(File.ReadAllText(file)) as JsonObject;
        if (root == null) return -1;
        int n = 0;
        foreach (var p in paths)
        {
            var parts = p.Split('.');
            JsonObject cur = root;
            for (int i = 0; i < parts.Length - 1 && cur != null; i++) cur = cur[parts[i]] as JsonObject;
            if (cur != null && cur.Remove(parts[parts.Length - 1])) n++;
        }
        var opts = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
        File.WriteAllText(file, root.ToJsonString(opts));
        return n;
    }
}
'@
$script:DvcJsonSourceFramework = @'
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
public static class DvcJson
{
    public static int RemovePaths(string file, string[] paths)
    {
        var ser = new JavaScriptSerializer(); ser.MaxJsonLength = int.MaxValue; ser.RecursionLimit = 1000;
        var root = ser.DeserializeObject(File.ReadAllText(file)) as Dictionary<string, object>;
        if (root == null) return -1;
        int n = 0;
        foreach (var p in paths)
        {
            var parts = p.Split('.');
            var cur = root;
            for (int i = 0; i < parts.Length - 1 && cur != null; i++)
            {
                object o;
                cur = cur.TryGetValue(parts[i], out o) ? o as Dictionary<string, object> : null;
            }
            if (cur != null && cur.Remove(parts[parts.Length - 1])) n++;
        }
        File.WriteAllText(file, ser.Serialize(root));
        return n;
    }
}
'@

function Remove-JsonPaths {
    # Entfernt Schlüssel (Punkt-Pfade, z. B. 'google.services') aus einer JSON-Datei. Rückgabe: Anzahl entfernter Schlüssel.
    param([string]$File, [string[]]$Paths)
    if (-not (Test-Path -LiteralPath $File)) { return 0 }
    if (-not ('DvcJson' -as [type])) {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            Add-Type -TypeDefinition $script:DvcJsonSourceFramework -ReferencedAssemblies 'System.Web.Extensions' -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $script:DvcJsonSourceCore -ErrorAction Stop
        }
    }
    [DvcJson]::RemovePaths($File, $Paths)
}

function Read-JsonFile {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    try { Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

function Test-JsonPath {
    # Prüft, ob ein Punkt-Pfad (z. B. 'google.services') in einem geparsten JSON-Objekt existiert.
    param($Object, [string]$Path)
    $cur = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $false }
        $prop = $cur.PSObject.Properties[$part]
        if ($null -eq $prop) { return $false }
        $cur = $prop.Value
    }
    $true
}

# ---------------------------------------------------------------------------------------------
# Modul-Hauptprogramm (wird am Ende jedes Moduls aufgerufen)
# ---------------------------------------------------------------------------------------------
function Invoke-ModuleMain {
    param([string]$Action, [string]$Categories, [string]$ContextJson, [string]$Lang)
    $script:DvcLang = if ($Lang -eq 'en') { 'en' } else { 'de' }
    $ctx = New-Ctx $ContextJson
    $cats = Split-List $Categories
    switch ($Action) {
        'Info'    { Write-ModuleJson (Get-ModuleInfo) }
        'Analyze' { Write-ModuleJson (Analyze -Ctx $ctx -Categories $cats) }
        'Clean'   { Write-ModuleJson (Clean -Ctx $ctx -Categories $cats) }
        default   { throw "Unbekannte Aktion: $Action" }
    }
}
