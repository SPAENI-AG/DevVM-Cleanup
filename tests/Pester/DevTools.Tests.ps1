# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Pester 5 – Modul Entwicklungstools (erfundene Zugangsdaten, nur Temp-Ordner).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\DevTools.ps1')
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
}

Describe 'Entwicklungstools – Beschreibung' {
    It 'bietet alle sieben Kategorien an' {
        ((Get-ModuleInfo).categories | ForEach-Object { $_.id }) | Should -Be @('vs', 'copilot', 'vscode', 'git', 'ssh', 'nuget', 'npmrc')
    }
}

Describe 'Entwicklungstools – Git-Konfiguration' {
    It 'entfernt nur Name/E-Mail/Signing-Key und Benutzernamen, lässt den Rest' {
        $lines = @('[user]', '  name = Alice Beispiel', '  email = alice@example.com', '  signingkey = ABC', '[core]', '  autocrlf = true', '[credential "https://example.com"]', '  username = alice', '  helper = manager', '[alias]', '  name = x')
        $r = Get-GitConfigCleaned $lines
        $r.Removed | Should -Be 4
        ($r.Lines -join '|') | Should -BeLike '*autocrlf = true*'
        ($r.Lines -join '|') | Should -BeLike '*helper = manager*'
        ($r.Lines -join '|') | Should -BeLike '*name = x*'
        ($r.Lines -join '|') | Should -Not -BeLike '*alice@example.com*'
    }
}

Describe 'Entwicklungstools – Dateien' {
    BeforeEach {
        $script:ctx = New-TestCtx (Join-Path $TestDrive 'h')
        $u = $script:ctx.UserProfile; $a = $script:ctx.AppData; $l = $script:ctx.LocalAppData
        New-TestFile (Join-Path $u '.gitconfig') "[user]`n  name = Alice Beispiel`n  email = alice@example.com`n[core]`n  autocrlf = true"
        New-TestFile (Join-Path $u '.git-credentials') 'https://alice:geheim-beispiel@example.com'
        New-TestFile (Join-Path $u '.ssh\id_ed25519') 'PRIVATE'
        New-TestFile (Join-Path $u '.ssh\id_ed25519.pub') 'PUBLIC'
        New-TestFile (Join-Path $u '.ssh\known_hosts') 'host'
        New-TestFile (Join-Path $u '.ssh\config') 'Host beispiel'
        New-TestFile (Join-Path $u '.npmrc') "registry=https://registry.example.com/`n//registry.example.com/:_authToken=geheim-beispiel`nemail=alice@example.com"
        New-TestFile (Join-Path $l '.IdentityService\cache.bin')
        New-TestFile (Join-Path $a 'GitHub CLI\hosts.yml') 'oauth_token: geheim-beispiel'
        New-TestFile (Join-Path $a 'NuGet\NuGet.Config') '<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><add key="intern" value="https://nuget.example.com/index.json" /></packageSources><packageSourceCredentials><intern><add key="Username" value="alice" /><add key="ClearTextPassword" value="geheim-beispiel" /></intern></packageSourceCredentials></configuration>'
        New-TestFile (Join-Path $u 'src\projekt\code.cs') 'class A {}'
        $script:creds.Clear()
        [void]$script:creds.Add(@{ Type = [uint32]1; Target = 'git:https://example.com' })
        [void]$script:creds.Add(@{ Type = [uint32]1; Target = 'LegacyGeneric:target=other' })
    }
    It 'Analyse findet alle Kategorien und gibt keine Geheimnisse aus' {
        $r = Analyze -Ctx $script:ctx
        foreach ($c in 'vs', 'copilot', 'git', 'ssh', 'nuget', 'npmrc') { ($r.findings | ForEach-Object { $_.category }) | Should -Contain $c }
        ($r | ConvertTo-Json -Depth 6) | Should -Not -BeLike '*geheim-beispiel*'
    }
    It 'Clean entfernt Zugangsdaten und lässt Code, Konfigurationsrest und SSH-config stehen' {
        $r = Clean -Ctx $script:ctx -Categories @('vs', 'copilot', 'git', 'ssh', 'nuget', 'npmrc')
        ($r.results | Where-Object { -not $_.ok }).Count | Should -Be 0
        $u = $script:ctx.UserProfile
        Test-Path (Join-Path $u '.git-credentials') | Should -BeFalse
        Test-Path (Join-Path $u '.ssh\id_ed25519') | Should -BeFalse
        Test-Path (Join-Path $u '.ssh\id_ed25519.pub') | Should -BeFalse
        Test-Path (Join-Path $u '.ssh\known_hosts') | Should -BeFalse
        Test-Path (Join-Path $u '.ssh\config') | Should -BeTrue
        Test-Path (Join-Path $u 'src\projekt\code.cs') | Should -BeTrue
        (Get-Content -Path (Join-Path $u '.gitconfig') -Raw) | Should -BeLike '*autocrlf*'
        (Get-Content -Path (Join-Path $u '.gitconfig') -Raw) | Should -Not -BeLike '*alice@example.com*'
        (Get-Content -Path (Join-Path $u '.npmrc') -Raw) | Should -BeLike '*registry=https://registry.example.com*'
        (Get-Content -Path (Join-Path $u '.npmrc') -Raw) | Should -Not -BeLike '*_authToken*'
        $nu = Get-Content -Path (Join-Path $script:ctx.AppData 'NuGet\NuGet.Config') -Raw
        $nu | Should -BeLike '*packageSources*'
        $nu | Should -Not -BeLike '*ClearTextPassword*'
        Test-Path (Join-Path $script:ctx.AppData 'GitHub CLI') | Should -BeFalse
        $script:creds.Count | Should -Be 1   # nur der Git-Eintrag wurde entfernt
    }
    It 'Clean ohne Kategorien löscht nichts' {
        (Clean -Ctx $script:ctx -Categories @()).results.Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.UserProfile '.git-credentials') | Should -BeTrue
    }
    It 'Kontrolllauf meldet danach sauber' {
        [void](Clean -Ctx $script:ctx -Categories @('vs', 'copilot', 'git', 'ssh', 'nuget', 'npmrc'))
        (Analyze -Ctx $script:ctx -Categories @('vs', 'copilot', 'git', 'ssh', 'nuget', 'npmrc')).findings.Count | Should -Be 0
    }
}
