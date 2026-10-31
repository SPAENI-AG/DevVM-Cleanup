# Traces.ps1 – Modul "Spuren"
# Temp, Papierkorb, "Zuletzt verwendet", RDP-Verlauf, PowerShell-History (PSReadLine), Ereignisprotokolle.
# Ereignisprotokolle gelten für den ganzen PC (Administratorrechte nötig), alles andere nur für das Benutzerprofil.
#   powershell -File Traces.ps1 -Action Analyze -Lang de
#   powershell -File Traces.ps1 -Action Clean -Categories temp,recent,rdp,pshistory
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ModuleInfo {
    [ordered]@{
        id         = 'traces'
        name       = [ordered]@{ de = 'Spuren'; en = 'Traces' }
        processes  = @()
        categories = @(
            [ordered]@{ id = 'temp';       de = 'Temporäre Dateien (Temp, Absturzberichte)'; en = 'Temporary files (Temp, crash reports)'; default = $true }
            [ordered]@{ id = 'recyclebin'; de = 'Papierkorb';                                en = 'Recycle bin';                              default = $true }
            [ordered]@{ id = 'recent';     de = 'Zuletzt verwendet (Dateien, Sprunglisten, Eingabeverlauf)'; en = 'Recent items (files, jump lists, input history)'; default = $true }
            [ordered]@{ id = 'rdp';        de = 'RDP-Verlauf (Remotedesktop)';               en = 'RDP history (Remote Desktop)';             default = $true }
            [ordered]@{ id = 'pshistory';  de = 'PowerShell-History (PSReadLine)';           en = 'PowerShell history (PSReadLine)';          default = $true }
            [ordered]@{ id = 'eventlogs';  de = 'Ereignisprotokolle (ganzer PC)';            en = 'Event logs (whole PC)';                    default = $true }
        )
    }
}

function Get-TraceTargets {
    param($Ctx)
    $h = $Ctx.Hkcu; $a = $Ctx.AppData; $l = $Ctx.LocalAppData; $u = $Ctx.UserProfile
    $exp = "$h\Software\Microsoft\Windows\CurrentVersion\Explorer"
    [ordered]@{
        # Inhalt dieser Ordner wird geleert (Ordner bleiben bestehen)
        tempDirs = @(
            (P $l 'Temp'), (P $l 'CrashDumps'), (P $l 'Microsoft', 'Windows', 'WER'), (P $l 'Microsoft', 'Windows', 'INetCache')
        )
        recentDirs = @(
            (P $a 'Microsoft', 'Windows', 'Recent')
        )
        recentRegs = @(
            @{ Reg = "$exp\RecentDocs" }, @{ Reg = "$exp\RunMRU" }, @{ Reg = "$exp\TypedPaths" }, @{ Reg = "$exp\WordWheelQuery" },
            @{ Reg = "$exp\ComDlg32\OpenSavePidlMRU" }, @{ Reg = "$exp\ComDlg32\LastVisitedPidlMRU" }
        )
        rdp = @(
            @{ Reg = "$h\Software\Microsoft\Terminal Server Client\Default" }
            @{ Reg = "$h\Software\Microsoft\Terminal Server Client\Servers" }
            @{ Path = (P $u 'Documents', 'Default.rdp') }
            @{ Path = (P $l 'Microsoft', 'Terminal Server Client', 'Cache') }
        )
        psHistoryDirs = @(
            (P $a 'Microsoft', 'Windows', 'PowerShell', 'PSReadLine'), (P $a 'Microsoft', 'PowerShell', 'PSReadLine')
        )
    }
}

# --- Papierkorb und Ereignisprotokolle (nur Windows; in Tests überschreibbar) ----------------------
function Get-RecycleBinCount {
    if (-not (Test-IsWindowsHost)) { return 0 }
    try { @((New-Object -ComObject Shell.Application).NameSpace(10).Items()).Count } catch { 0 }
}

function Clear-RecycleBinSafe {
    # Laufwerk für Laufwerk: Datenträger ohne Papierkorb (z. B. optisches Laufwerk) dürfen nicht den ganzen Vorgang scheitern lassen.
    if (-not (Test-IsWindowsHost)) { return }
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -and $d.DriveType -ne 'Removable') { continue }
        if (-not $d.IsReady) { continue }
        try { Clear-RecycleBin -DriveLetter $d.Name.Substring(0, 1) -Force -ErrorAction Stop } catch { }
    }
    $left = Get-RecycleBinCount
    if ($left -gt 0) { throw ((T 'Papierkorb nicht vollständig geleert ({0} Elemente übrig)' 'Recycle bin not completely emptied ({0} items left)') -f $left) }
}

function Get-EventLogsWithRecords {
    # Namen der Ereignisprotokolle mit ALTEN Einträgen (älter als 10 Minuten). Protokolle füllen sich laufend neu und das Löschen
    # selbst schreibt einen Eintrag – ein Protokoll mit nur frischen Einträgen zählt daher nicht, sonst wäre der Kontrolllauf nie "sauber".
    if (-not (Test-IsWindowsHost)) { return @() }
    $limit = (Get-Date).AddMinutes(-10)
    $names = @()
    try {
        foreach ($log in (Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 })) {
            $oldest = Get-WinEvent -LogName $log.LogName -Oldest -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($oldest -and $oldest.TimeCreated -lt $limit) { $names += $log.LogName }
        }
    } catch { }
    $names
}

function Clear-EventLogSafe {
    param([string]$LogName)
    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($LogName)
}

function Get-SettledChildCount {
    # Elemente, die älter als 60 Sekunden sind – ganz frische Dateien stammen meist von laufenden Programmen
    # (auch von PowerShell selbst) und würden den Kontrolllauf grundlos stören.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $limit = (Get-Date).AddSeconds(-60)
    @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit }).Count
}

function Get-HistoryFiles {
    param($Dirs)
    foreach ($d in $Dirs) {
        if (Test-Path -LiteralPath $d) {
            Get-ChildItem -LiteralPath $d -File -Force -Filter '*_history.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }
    }
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $t = Get-TraceTargets $Ctx
    $scope = T 'Spuren' 'Traces'
    $f = @()

    if ($want -contains 'temp') {
        $n = 0; $mb = 0
        foreach ($d in $t.tempDirs) { $n += Get-SettledChildCount $d; $mb += Get-PathSizeMB $d }
        if ($n -gt 0) { $f += New-Finding 'temp' $scope ((T '{0} Elemente in Temp-Ordnern ({1} MB)' '{0} items in temp folders ({1} MB)') -f $n, $mb) $n }
    }
    if ($want -contains 'recyclebin') {
        $n = Get-RecycleBinCount
        if ($n -gt 0) { $f += New-Finding 'recyclebin' $scope ((T '{0} Elemente im Papierkorb' '{0} items in the recycle bin') -f $n) $n }
    }
    if ($want -contains 'recent') {
        $n = 0; foreach ($d in $t.recentDirs) { $n += Get-ChildCount $d }
        $r = @($t.recentRegs | Where-Object { Test-TargetExists $_ }).Count
        if (($n + $r) -gt 0) { $f += New-Finding 'recent' $scope ((T '{0} zuletzt verwendete Elemente, {1} Verlaufsschlüssel' '{0} recent items, {1} history keys') -f $n, $r) ($n + $r) }
    }
    if ($want -contains 'rdp') {
        $n = @($t.rdp | Where-Object { Test-TargetExists $_ }).Count
        if ($n -gt 0) { $f += New-Finding 'rdp' $scope (T 'RDP-Verlauf vorhanden' 'RDP history present') $n }
    }
    if ($want -contains 'pshistory') {
        $files = @(Get-HistoryFiles $t.psHistoryDirs)
        if ($files.Count -gt 0) { $f += New-Finding 'pshistory' $scope ((T '{0} PowerShell-Verlaufsdateien' '{0} PowerShell history files') -f $files.Count) $files.Count }
    }
    if ($want -contains 'eventlogs') {
        $logs = @(Get-EventLogsWithRecords)
        if ($logs.Count -gt 0) { $f += New-Finding 'eventlogs' $scope ((T '{0} Ereignisprotokolle mit Einträgen (älter als 10 Minuten)' '{0} event logs with entries (older than 10 minutes)') -f $logs.Count) $logs.Count }
    }
    [ordered]@{ module = 'traces'; findings = @($f); notes = @() }
}

function Clean-Category {
    param($Ctx, [string]$Cat)
    $t = Get-TraceTargets $Ctx
    $removed = 0
    switch ($Cat) {
        'temp' { foreach ($d in $t.tempDirs) { $removed += (Remove-ChildrenSafe $d $Ctx).Removed } }
        'recyclebin' { $n = Get-RecycleBinCount; Clear-RecycleBinSafe; $removed += $n }
        'recent' {
            foreach ($d in $t.recentDirs) { $removed += (Remove-ChildrenSafe $d $Ctx).Removed }
            foreach ($x in $t.recentRegs) { $removed += Remove-Target $x $Ctx }
        }
        'rdp' { foreach ($x in $t.rdp) { $removed += Remove-Target $x $Ctx } }
        'pshistory' { foreach ($file in (Get-HistoryFiles $t.psHistoryDirs)) { $removed += Remove-PathSafe -Path $file -Ctx $Ctx } }
        'eventlogs' {
            foreach ($name in (Get-EventLogsWithRecords)) {
                try { Clear-EventLogSafe $name; $removed++ } catch { }   # einzelne geschützte Protokolle dürfen fehlschlagen
            }
        }
    }
    $removed
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $valid = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $scope = T 'Spuren' 'Traces'
    $results = @()
    foreach ($cat in $Categories) {
        if ($cat -notin $valid) { continue }
        try { $results += New-Result $cat $scope $true ([int](Clean-Category $Ctx $cat)) '' }
        catch { $results += New-Result $cat $scope $false 0 $_.Exception.Message }
    }
    [ordered]@{ module = 'traces'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
