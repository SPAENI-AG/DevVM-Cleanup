# Optional.ps1 – Modul "Optionale Programme" (nur wenn installiert/Daten vorhanden)
# device2cloud / machinetoservice, Sophos Connect, eWON eCatcher – Benutzerdaten und gespeicherte Zugangsdaten.
# Dazu Lizenz-HINWEISE (z. B. Siemens Automation License Manager): maschinengebundene Lizenzen werden NICHT verändert,
# nur gemeldet, damit sie nach dem Verteilen der VM bewusst geprüft werden.
# Die Ordnernamen sind eine bestmögliche Zuordnung (Herstellerangaben können sich ändern) – siehe docs/NOT-TOUCHED.md.
#   powershell -File Optional.ps1 -Action Analyze -Lang de
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ModuleInfo {
    [ordered]@{
        id         = 'optional'
        name       = [ordered]@{ de = 'Optionale Programme (device2cloud, Sophos Connect, eCatcher)'; en = 'Optional programs (device2cloud, Sophos Connect, eCatcher)' }
        processes  = @('eCatcher', 'SophosConnect', 'scvpn', 'device2cloud', 'machinetoservice')
        categories = @(
            [ordered]@{ id = 'device2cloud'; de = 'device2cloud / machinetoservice (Benutzerdaten, Zugang)'; en = 'device2cloud / machinetoservice (user data, access)'; default = $true }
            [ordered]@{ id = 'sophos';       de = 'Sophos Connect (Benutzerdaten, Verbindungsprofile)';        en = 'Sophos Connect (user data, connection profiles)';   default = $true }
            [ordered]@{ id = 'ecatcher';     de = 'eWON eCatcher / Talk2M (Konto, Zugang)';                    en = 'eWON eCatcher / Talk2M (account, access)';           default = $true }
        )
    }
}

function Get-OptionalTargets {
    param($Ctx)
    $a = $Ctx.AppData; $l = $Ctx.LocalAppData; $pd = $Ctx.ProgramData; $u = $Ctx.UserProfile
    $t = [ordered]@{
        device2cloud = @(
            @{ Path = (P $a 'device2cloud') }, @{ Path = (P $l 'device2cloud') },
            @{ Path = (P $a 'machinetoservice') }, @{ Path = (P $l 'machinetoservice') }
        )
        sophos       = @(
            @{ Path = (P $a 'Sophos', 'Connect') }, @{ Path = (P $l 'Sophos', 'Connect') }
        )
        ecatcher     = @(
            @{ Path = (P $a 'eCatcher') }, @{ Path = (P $l 'eCatcher') },
            @{ Path = (P $a 'eWON') }, @{ Path = (P $l 'eWON') }, @{ Path = (P $a 'Talk2M') }
        )
    }
    if ($pd) {
        $t.sophos += @{ Path = (P $pd 'Sophos', 'Connect', 'profiles') }
        $t.sophos += @{ Path = (P $pd 'Sophos', 'Connect', 'import') }
    }
    $t
}

function Get-LicenseNotes {
    # Nur Hinweise, es wird nichts verändert.
    param($Ctx)
    $notes = @()
    $roots = @($Ctx.ProgramFiles, $Ctx.ProgramFilesX86) | Where-Object { $_ }
    $checks = @(
        @{ Rel = @('Siemens', 'Automation', 'Automation License Manager'); De = 'Siemens Automation License Manager gefunden: Lizenzen sind an den PC/die VM gebunden und wurden NICHT verändert. Nach dem Verteilen Lizenzen prüfen bzw. neu zuweisen.'; En = 'Siemens Automation License Manager found: licenses are bound to the PC/VM and were NOT changed. Check or reassign licenses after distributing the VM.' }
        @{ Rel = @('CodeMeter'); De = 'CodeMeter gefunden: Lizenzcontainer/Dongle-Lizenzen wurden NICHT verändert. Nach dem Verteilen prüfen.'; En = 'CodeMeter found: license containers/dongle licenses were NOT changed. Check after distributing.' }
        @{ Rel = @('Rockwell Software', 'FactoryTalk Activation'); De = 'FactoryTalk Activation gefunden: Aktivierungen sind maschinengebunden und wurden NICHT verändert. Nach dem Verteilen prüfen.'; En = 'FactoryTalk Activation found: activations are machine-bound and were NOT changed. Check after distributing.' }
    )
    foreach ($c in $checks) {
        foreach ($r in $roots) {
            if (Test-Path -LiteralPath (P $r $c.Rel)) { $notes += (T $c.De $c.En); break }
        }
    }
    $notes
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $t = Get-OptionalTargets $Ctx
    $names = @{ device2cloud = 'device2cloud / machinetoservice'; sophos = 'Sophos Connect'; ecatcher = 'eWON eCatcher' }
    $f = @()
    foreach ($cat in $want) {
        if (-not $t.Contains($cat)) { continue }
        $present = @($t[$cat] | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            $f += New-Finding $cat $names[$cat] ((T 'Benutzerdaten vorhanden ({0} Ordner, {1} MB)' 'user data present ({0} folders, {1} MB)') -f $present.Count, $mb) $present.Count
        }
    }
    [ordered]@{ module = 'optional'; findings = @($f); notes = @(Get-LicenseNotes $Ctx) }
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $t = Get-OptionalTargets $Ctx
    $names = @{ device2cloud = 'device2cloud / machinetoservice'; sophos = 'Sophos Connect'; ecatcher = 'eWON eCatcher' }
    $results = @()
    foreach ($cat in $Categories) {
        if (-not $t.Contains($cat)) { continue }
        $removed = 0; $errors = @()
        foreach ($x in $t[$cat]) { try { $removed += Remove-Target $x $Ctx } catch { $errors += $_.Exception.Message } }
        $results += New-Result $cat $names[$cat] ($errors.Count -eq 0) $removed ($errors -join '; ')
    }
    [ordered]@{ module = 'optional'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
