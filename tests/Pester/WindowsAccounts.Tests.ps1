# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Pester 5 – Modul Windows-Konten (erfundene Daten; Credential Manager und dsregcmd werden ersetzt, nichts Echtes berührt).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\WindowsAccounts.ps1')
    function New-TestCtx {
        param($Root)
        @{ UserProfile = $Root; AppData = (Join-Path $Root 'AppData\Roaming'); LocalAppData = (Join-Path $Root 'AppData\Local'); ProgramData = (Join-Path $Root 'ProgramData')
           ProgramFiles = (Join-Path $Root 'PF'); ProgramFilesX86 = (Join-Path $Root 'PF86'); ScanRoots = ''; Hkcu = 'HKCU:\Software\DevVmCleanupTest' }
    }
    function New-TestFile {
        param([string]$Path, [string]$Content = 'x')
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        Set-Content -Path $Path -Value $Content
    }

    $script:creds = New-Object System.Collections.ArrayList
    function Get-StoredCredentialTargets { @($script:creds | ForEach-Object { $_ }) }
    function Remove-StoredCredential { param([uint32]$Type, [string]$Target) $i = -1; for ($k = 0; $k -lt $script:creds.Count; $k++) { if ($script:creds[$k].Target -eq $Target) { $i = $k } }; if ($i -ge 0) { $script:creds.RemoveAt($i); $true } else { $false } }
    function Get-DsregStatus { @{ AzureAdJoined = $true; WorkplaceJoined = $false; DomainJoined = $false; TenantName = 'Beispiel GmbH' } }
}

Describe 'Windows-Konten – Beschreibung' {
    It 'hat drei Kategorien und den Token-Broker-Prozess' {
        $i = Get-ModuleInfo
        $i.id | Should -Be 'accounts'
        ($i.categories | ForEach-Object { $_.id }) | Should -Be @('workaccounts', 'broker', 'credentials')
        $i.processes | Should -Contain 'Microsoft.AAD.BrokerPlugin'
    }
}

Describe 'Windows-Konten – Token-Broker und Anmeldeinformationen' {
    BeforeEach {
        $script:ctx = New-TestCtx (Join-Path $TestDrive 'h')
        $b = Join-Path $script:ctx.LocalAppData 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
        New-TestFile (Join-Path $b 'AC\TokenBroker\Accounts\a.tbres')
        New-TestFile (Join-Path $b 'LocalState\x.dat')
        New-TestFile (Join-Path $script:ctx.LocalAppData 'Microsoft\TokenBroker\Cache\c.tbres')
        New-TestFile (Join-Path $script:ctx.UserProfile 'Documents\wichtig.txt')
        $script:creds.Clear()
        [void]$script:creds.Add(@{ Type = [uint32]1; Target = 'LegacyGeneric:target=example-host' })
        [void]$script:creds.Add(@{ Type = [uint32]2; Target = 'TERMSRV/example-host' })
    }
    It 'Analyse meldet Broker-Cache und Anmeldungen, nennt keine Hostnamen und löscht nichts' {
        $r = Analyze -Ctx $script:ctx
        ($r.findings | ForEach-Object { $_.category }) | Should -Contain 'broker'
        $c = $r.findings | Where-Object { $_.category -eq 'credentials' }
        $c.label | Should -BeLike '2 *'
        $c.label | Should -Not -BeLike '*example-host*'
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\TokenBroker') | Should -BeTrue
    }
    It 'Analyse weist auf die Azure-AD-Mitgliedschaft hin (Hinweis, kein Fund)' {
        $r = Analyze -Ctx $script:ctx -Categories @('workaccounts')
        ($r.notes -join ' ') | Should -BeLike '*Beispiel GmbH*'
        $r.findings.Count | Should -Be 0
    }
    It 'Clean entfernt Broker-Cache und alle Anmeldungen, Dokumente bleiben' {
        $r = Clean -Ctx $script:ctx -Categories @('broker', 'credentials')
        ($r.results | Where-Object { -not $_.ok }).Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\TokenBroker') | Should -BeFalse
        $script:creds.Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.UserProfile 'Documents\wichtig.txt') | Should -BeTrue
    }
    It 'Clean ohne Kategorien löscht nichts' {
        (Clean -Ctx $script:ctx -Categories @()).results.Count | Should -Be 0
        $script:creds.Count | Should -Be 2
    }
    It 'Kontrolllauf meldet danach sauber' {
        [void](Clean -Ctx $script:ctx -Categories @('workaccounts', 'broker', 'credentials'))
        (Analyze -Ctx $script:ctx).findings.Count | Should -Be 0
    }
}

Describe 'Windows-Konten – Registry (nur Windows)' -Skip:(-not $isWindowsHost) {
    BeforeEach {
        $script:ctx = New-TestCtx $TestDrive
        $script:creds.Clear()
        New-Item -Path "$($script:ctx.Hkcu)\Software\Microsoft\IdentityCRL\StoredIdentities\alice@example.com" -Force | Out-Null
    }
    AfterEach { Remove-Item -Path 'HKCU:\Software\DevVmCleanupTest' -Recurse -Force -ErrorAction SilentlyContinue }
    It 'zeigt das verbundene Konto und entfernt es' {
        (Analyze -Ctx $script:ctx -Categories @('workaccounts')).findings[0].label | Should -BeLike '*alice@example.com*'
        [void](Clean -Ctx $script:ctx -Categories @('workaccounts'))
        (Analyze -Ctx $script:ctx -Categories @('workaccounts')).findings.Count | Should -Be 0
    }
}
