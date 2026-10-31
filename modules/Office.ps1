# Office.ps1 – Modul "Office / Microsoft 365"
# Meldet Office, Outlook, OneDrive und Teams ab und entfernt lokale Anmelde-/Lizenz-Spuren des aktuellen Benutzers.
# Nutzung ohne Oberfläche:
#   powershell -File Office.ps1 -Action Analyze -Lang de
#   powershell -File Office.ps1 -Action Clean -Categories identity,license,outlook,onedrive,teams
# Es werden KEINE Dokumente, Postfach-Inhalte auf dem Server oder OneDrive-Dateien gelöscht
# (OneDrive wird nur getrennt, synchronisierte Ordner bleiben als normale lokale Dateien liegen).
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ModuleInfo {
    [ordered]@{
        id         = 'office'
        name       = [ordered]@{ de = 'Office / Microsoft 365'; en = 'Office / Microsoft 365' }
        processes  = @('OUTLOOK', 'WINWORD', 'EXCEL', 'POWERPNT', 'ONENOTE', 'MSACCESS', 'olk', 'OneDrive', 'FileCoAuth', 'FileSyncHelper', 'ms-teams', 'Teams', 'lync')
        categories = @(
            [ordered]@{ id = 'identity'; de = 'Office-Identitäten (Anmeldung)'; en = 'Office identities (sign-in)'; default = $true }
            [ordered]@{ id = 'license';  de = 'Lizenz-Tokens';                   en = 'License tokens';              default = $true }
            [ordered]@{ id = 'outlook';  de = 'Outlook-Profile und -Cache';      en = 'Outlook profiles and cache';  default = $true }
            [ordered]@{ id = 'onedrive'; de = 'OneDrive trennen';                en = 'Unlink OneDrive';             default = $true }
            [ordered]@{ id = 'teams';    de = 'Teams-Cache und -Anmeldung';      en = 'Teams cache and sign-in';     default = $true }
        )
    }
}

function Get-OfficeTargets {
    param($Ctx)
    $h = $Ctx.Hkcu; $l = $Ctx.LocalAppData; $a = $Ctx.AppData
    $o = "$h\Software\Microsoft\Office\16.0"
    [ordered]@{
        identity = @(
            @{ Reg = "$o\Common\Identity" }
            @{ Reg = "$o\Common\ServicesManagerCache" }
            @{ Reg = "$o\Common\ServicesManager\Cache" }
            @{ Path = (P $l 'Microsoft', 'IdentityCache') }
            @{ Path = (P $l 'Microsoft', 'OneAuth') }
        )
        license  = @(
            @{ Reg = "$o\Common\Licensing" }
            @{ Path = (P $l 'Microsoft', 'Office', '16.0', 'Licensing') }
            @{ Path = (P $l 'Microsoft', 'Office', 'Licenses') }
        )
        outlook  = @(
            @{ Reg = "$o\Outlook\Profiles" }
            @{ Reg = "$h\Software\Microsoft\Windows NT\CurrentVersion\Windows Messaging Subsystem\Profiles" }
            @{ Path = (P $l 'Microsoft', 'Outlook') }
            @{ Path = (P $a 'Microsoft', 'Outlook') }
            @{ Path = (P $a 'Microsoft', 'Signatures') }
            @{ Path = (P $l 'Packages', 'Microsoft.OutlookForWindows_8wekyb3d8bbwe', 'LocalCache') }
        )
        onedrive = @(
            @{ Reg = "$h\Software\Microsoft\OneDrive\Accounts" }
            @{ Path = (P $l 'Microsoft', 'OneDrive', 'settings') }
            @{ Path = (P $l 'Microsoft', 'OneDrive', 'logs'); Optional = $true }   # Protokolle: nur nach Möglichkeit, nie ein Fund
        )
        teams    = @(
            @{ Path = (P $a 'Microsoft', 'Teams') }
            @{ Path = (P $l 'Packages', 'MSTeams_8wekyb3d8bbwe', 'LocalCache') }
        )
    }
}

function Get-OfficeIdentityNames {
    # Anzeigenamen der angemeldeten Office-Identitäten (nur Kontoname/E-Mail, keine Tokens)
    param($Ctx)
    $base = "$($Ctx.Hkcu)\Software\Microsoft\Office\16.0\Common\Identity\Identities"
    $names = @()
    foreach ($id in (Get-RegChildNames $base)) {
        $mail = Get-RegValue "$base\$id" 'EmailAddress'
        if (-not $mail) { $mail = Get-RegValue "$base\$id" 'FriendlyName' }
        if ($mail) { $names += [string]$mail }
    }
    @($names | Select-Object -Unique)
}

function Get-OneDriveAccountNames {
    param($Ctx)
    $base = "$($Ctx.Hkcu)\Software\Microsoft\OneDrive\Accounts"
    $names = @()
    foreach ($id in (Get-RegChildNames $base)) {
        if ($id -notmatch '^(Business\d+|Personal)$') { continue }   # z. B. "FileCoAuth" ist kein Konto
        $mail = Get-RegValue "$base\$id" 'UserEmail'
        $names += $(if ($mail) { [string]$mail } else { $id })
    }
    @($names)
}

function Get-OutlookProfileNames {
    param($Ctx)
    $n = @()
    $n += Get-RegChildNames "$($Ctx.Hkcu)\Software\Microsoft\Office\16.0\Outlook\Profiles"
    $n += Get-RegChildNames "$($Ctx.Hkcu)\Software\Microsoft\Windows NT\CurrentVersion\Windows Messaging Subsystem\Profiles"
    @($n | Select-Object -Unique)
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $targets = Get-OfficeTargets $Ctx
    $scope = 'Office'
    $findings = @()

    if ($want -contains 'identity') {
        $names = Get-OfficeIdentityNames $Ctx
        $present = @($targets.identity | Where-Object { Test-TargetExists $_ }).Count
        if ($names.Count -gt 0) {
            $findings += New-Finding 'identity' $scope ((T 'angemeldet als {0}' 'signed in as {0}') -f ($names -join ', ')) $names.Count
        } elseif ($present -gt 0) {
            $findings += New-Finding 'identity' $scope (T 'Anmelde-Zwischenspeicher vorhanden' 'sign-in cache present') $present
        }
    }
    if ($want -contains 'license') {
        $present = @($targets.license | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { $findings += New-Finding 'license' $scope (T 'Lizenz-Tokens vorhanden' 'license tokens present') $present }
    }
    if ($want -contains 'outlook') {
        $profiles = Get-OutlookProfileNames $Ctx
        $ost = 0
        $dir = (P $Ctx.LocalAppData 'Microsoft', 'Outlook')
        if (Test-Path -LiteralPath $dir) {
            $ost = @(Get-ChildItem -LiteralPath $dir -Filter '*.ost' -File -ErrorAction SilentlyContinue).Count
        }
        $present = @($targets.outlook | Where-Object { Test-TargetExists $_ }).Count
        if ($profiles.Count -gt 0 -or $ost -gt 0 -or $present -gt 0) {
            $label = (T '{0} Profile, {1} Offline-Postfächer (OST)' '{0} profiles, {1} offline mailboxes (OST)') -f $profiles.Count, $ost
            $findings += New-Finding 'outlook' $scope $label ([math]::Max(1, $profiles.Count + $ost))
        }
    }
    if ($want -contains 'onedrive') {
        $names = Get-OneDriveAccountNames $Ctx
        $present = @($targets.onedrive | Where-Object { -not $_.Optional -and (Test-TargetExists $_) }).Count
        if ($names.Count -gt 0) {
            $findings += New-Finding 'onedrive' $scope ((T 'verbunden mit {0}' 'linked to {0}') -f ($names -join ', ')) $names.Count
        } elseif ($present -gt 0) {
            $findings += New-Finding 'onedrive' $scope (T 'OneDrive-Einstellungen vorhanden' 'OneDrive settings present') $present
        }
    }
    if ($want -contains 'teams') {
        $present = @($targets.teams | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0
            foreach ($t in $present) { $mb += (Get-PathSizeMB $t.Path) }
            $findings += New-Finding 'teams' $scope ((T 'Teams-Daten ({0} MB)' 'Teams data ({0} MB)') -f $mb) $present.Count
        }
    }
    [ordered]@{ module = 'office'; findings = @($findings) }
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $targets = Get-OfficeTargets $Ctx
    $results = @()
    foreach ($cat in $Categories) {
        if (-not $targets.Contains($cat)) { continue }
        $removed = 0; $errors = @()
        foreach ($t in $targets[$cat]) {
            try { $removed += Remove-Target $t $Ctx }
            catch { if (-not $t.Optional) { $errors += $_.Exception.Message } }   # optionale Ziele (Protokolle) dürfen gesperrt sein
        }
        $results += New-Result $cat 'Office' ($errors.Count -eq 0) $removed ($errors -join '; ')
    }
    [ordered]@{ module = 'office'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
