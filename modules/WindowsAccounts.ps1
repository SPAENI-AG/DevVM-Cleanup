# WindowsAccounts.ps1 – Modul "Windows-Konten" (Geschäfts-/Schulkonten, Token-Broker, Anmeldeinformationsverwaltung)
# Entfernt, womit sich der Einrichter ÜBER Windows bei Diensten angemeldet hat. Das lokale Windows-Konto selbst
# (Passwort, Anmeldung, PIN/Windows Hello) und die Domänen-/Azure-AD-Mitgliedschaft des PCs werden NICHT verändert.
#   powershell -File WindowsAccounts.ps1 -Action Analyze -Lang de
#   powershell -File WindowsAccounts.ps1 -Action Clean -Categories workaccounts,broker,credentials
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ModuleInfo {
    [ordered]@{
        id         = 'accounts'
        name       = [ordered]@{ de = 'Windows-Konten'; en = 'Windows accounts' }
        processes  = @('Microsoft.AAD.BrokerPlugin')
        categories = @(
            [ordered]@{ id = 'workaccounts'; de = 'Geschäfts-/Schulkonten (verbundene Konten)'; en = 'Work/school accounts (connected accounts)'; default = $true }
            [ordered]@{ id = 'broker';       de = 'Token-Broker (AAD.BrokerPlugin, Web Account Manager)'; en = 'Token broker (AAD.BrokerPlugin, Web Account Manager)'; default = $true }
            [ordered]@{ id = 'credentials';  de = 'Anmeldeinformationsverwaltung (gespeicherte Anmeldungen)'; en = 'Credential Manager (saved credentials)'; default = $true }
        )
    }
}

function Get-AccountTargets {
    param($Ctx)
    $h = $Ctx.Hkcu; $l = $Ctx.LocalAppData
    $broker = (P $l 'Packages', 'Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy')
    [ordered]@{
        workaccounts = @(
            @{ Reg = "$h\Software\Microsoft\IdentityCRL" }
            @{ Reg = "$h\Software\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" }
            @{ Reg = "$h\Software\Microsoft\Windows\CurrentVersion\AAD" }
        )
        broker       = @(
            @{ Path = (P $broker 'AC', 'TokenBroker') }
            @{ Path = (P $broker 'LocalState') }
            @{ Path = (P $broker 'Settings') }
            @{ Path = (P $l 'Microsoft', 'TokenBroker') }
        )
    }
}

function Get-DsregStatus {
    # Gerätestatus (Azure AD joined / Workplace joined). In Tests überschreibbar. Die Schlüsselnamen von dsregcmd sind nicht lokalisiert.
    $r = @{ AzureAdJoined = $false; WorkplaceJoined = $false; DomainJoined = $false; TenantName = '' }
    if (-not (Test-IsWindowsHost)) { return $r }
    try {
        foreach ($line in (& dsregcmd.exe /status 2>$null)) {
            if ($line -match '^\s*AzureAdJoined\s*:\s*YES') { $r.AzureAdJoined = $true }
            elseif ($line -match '^\s*WorkplaceJoined\s*:\s*YES') { $r.WorkplaceJoined = $true }
            elseif ($line -match '^\s*DomainJoined\s*:\s*YES') { $r.DomainJoined = $true }
            elseif ($line -match '^\s*TenantName\s*:\s*(.+)$') { $r.TenantName = $Matches[1].Trim() }
        }
    } catch { }
    $r
}

function Get-WorkAccountNames {
    # Angezeigte Konten (E-Mail) der verbundenen Konten – nur Namen, keine Tokens
    param($Ctx)
    $names = @()
    foreach ($n in (Get-RegChildNames "$($Ctx.Hkcu)\Software\Microsoft\IdentityCRL\StoredIdentities")) { $names += $n }
    $ji = "$($Ctx.Hkcu)\Software\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo"
    foreach ($t in (Get-RegChildNames $ji)) {
        $m = Get-RegValue "$ji\$t" 'UserEmail'
        if ($m) { $names += [string]$m }
    }
    @($names | Select-Object -Unique)
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $t = Get-AccountTargets $Ctx
    $scope = T 'Windows-Konten' 'Windows accounts'
    $findings = @(); $notes = @()

    if ($want -contains 'workaccounts') {
        $names = Get-WorkAccountNames $Ctx
        $present = @($t.workaccounts | Where-Object { Test-TargetExists $_ }).Count
        if ($names.Count -gt 0) { $findings += New-Finding 'workaccounts' $scope ((T 'verbunden mit {0}' 'connected to {0}') -f ($names -join ', ')) $names.Count }
        elseif ($present -gt 0) { $findings += New-Finding 'workaccounts' $scope (T 'Kontoverbindungen vorhanden' 'account connections present') $present }
        $ds = Get-DsregStatus
        if ($ds.AzureAdJoined) {
            $notes += ((T 'Dieser PC ist mit Azure AD verbunden ({0}). Die Geräte-Mitgliedschaft wird von diesem Tool bewusst nicht verändert.' 'This PC is joined to Azure AD ({0}). This tool deliberately does not change the device membership.') -f $ds.TenantName)
        }
        if ($ds.WorkplaceJoined) { $notes += (T 'Dieser PC ist als Arbeitsplatz registriert (Workplace Join).' 'This PC is registered as a workplace (workplace join).') }
        if ($ds.DomainJoined) { $notes += (T 'Dieser PC ist Mitglied einer Domäne; die Domänen-Mitgliedschaft wird nicht verändert.' 'This PC is domain-joined; domain membership is not changed.') }
    }
    if ($want -contains 'broker') {
        $present = @($t.broker | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            $findings += New-Finding 'broker' $scope ((T 'Token-Zwischenspeicher ({0} MB)' 'token cache ({0} MB)') -f $mb) $present.Count
        }
    }
    if ($want -contains 'credentials') {
        $creds = @(Get-StoredCredentialTargets)
        if ($creds.Count -gt 0) {
            $kinds = @($creds | ForEach-Object { Get-CredentialKind $_.Target } | Group-Object | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) ($($_.Count))" })
            $findings += New-Finding 'credentials' $scope ((T '{0} gespeicherte Anmeldungen: {1}' '{0} saved credentials: {1}') -f $creds.Count, ($kinds -join ', ')) $creds.Count
        }
    }
    [ordered]@{ module = 'accounts'; findings = @($findings); notes = @($notes) }
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $t = Get-AccountTargets $Ctx
    $results = @()
    foreach ($cat in $Categories) {
        if ($cat -notin 'workaccounts', 'broker', 'credentials') { continue }
        $removed = 0; $errors = @()
        switch ($cat) {
            { $_ -in 'workaccounts', 'broker' } {
                foreach ($x in $t[$cat]) { try { $removed += Remove-Target $x $Ctx } catch { $errors += $_.Exception.Message } }
            }
            'credentials' {
                foreach ($c in @(Get-StoredCredentialTargets)) {
                    try { if (Remove-StoredCredential -Type $c.Type -Target $c.Target) { $removed++ } else { $errors += ((T 'Eintrag ({0}) nicht löschbar' 'entry ({0}) could not be deleted') -f (Get-CredentialKind $c.Target)) } }
                    catch { $errors += $_.Exception.Message }
                }
            }
        }
        $results += New-Result $cat (T 'Windows-Konten' 'Windows accounts') ($errors.Count -eq 0) $removed ($errors -join '; ')
    }
    [ordered]@{ module = 'accounts'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
