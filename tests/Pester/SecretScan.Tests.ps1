# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Pester 5 – Geheimnis-Scan: nur Bericht, mit erfundenen Beispiel-"Geheimnissen" (kein echtes Konto, kein echter Schlüssel).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\SecretScan.ps1')
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

}

Describe 'Geheimnis-Scan' {
    BeforeEach {
        $script:ctx = New-TestCtx (Join-Path $TestDrive 'h')
        $u = $script:ctx.UserProfile
        New-TestFile (Join-Path $u 'src\app\.git\config') "[remote `"origin`"]`n  url = https://alice:geheim-beispiel@example.com/team/app.git`n[remote `"ok`"]`n  url = git@example.com:team/app.git"
        New-TestFile (Join-Path $u 'src\sauber\.git\config') "[remote `"origin`"]`n  url = https://example.com/team/sauber.git"
        New-TestFile (Join-Path $u 'src\app\.env') "API_TOKEN=geheim-beispiel`nDEBUG=true"
        New-TestFile (Join-Path $u 'src\app\.env.example') "API_TOKEN=geheim-beispiel"
        New-TestFile (Join-Path $u 'src\app\cert.pfx') 'x'
        New-TestFile (Join-Path $u 'src\app\key.pem') "-----BEGIN PRIVATE KEY-----`nAAAA`n-----END PRIVATE KEY-----"
        New-TestFile (Join-Path $u 'src\app\public.pem') "-----BEGIN CERTIFICATE-----`nAAAA`n-----END CERTIFICATE-----"
        New-TestFile (Join-Path $u 'src\app\appsettings.json') "{`n  `"Db`": {`n    `"Password`": `"geheim-beispiel`",`n    `"Name`": `"x`"`n  }`n}"
        New-TestFile (Join-Path $u 'src\app\appsettings.Development.json') "{ `"Logging`": { `"Level`": `"Debug`" } }"
        New-TestFile (Join-Path $u 'node_modules\pkg\.env') "API_TOKEN=geheim-beispiel"
        New-TestFile (Join-Path $u '.git-credentials') 'https://alice:geheim-beispiel@example.com'
        New-TestFile (Join-Path $script:ctx.AppData 'Microsoft\UserSecrets\abc\secrets.json') "{ `"Api:ClientSecret`": `"geheim-beispiel`" }"
    }
    It 'ist als reiner Bericht gekennzeichnet' {
        (Get-ModuleInfo).reportOnly | Should -BeTrue
    }
    It 'findet die Beispiel-Funde, überspringt node_modules und Vorlagen' {
        $r = Analyze -Ctx $script:ctx
        $by = @{}; foreach ($f in $r.findings) { $by[$f.category] += @($f) }
        $by['git'].Count | Should -Be 2
        $by['env'].Count | Should -Be 1
        $by['certs'].Count | Should -Be 2
        $by['appsettings'].Count | Should -Be 2
        ($r.findings | ForEach-Object { $_.scope }) | Should -Not -BeLike '*node_modules*'
    }
    It 'nennt nie den Wert des Geheimnisses' {
        ((Analyze -Ctx $script:ctx) | ConvertTo-Json -Depth 6) | Should -Not -BeLike '*geheim-beispiel*'
    }
    It 'löscht nichts – auch nicht mit Clean' {
        [void](Analyze -Ctx $script:ctx)
        (Clean -Ctx $script:ctx -Categories @('git', 'env', 'certs', 'appsettings')).results.Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.UserProfile '.git-credentials') | Should -BeTrue
        Test-Path (Join-Path $script:ctx.UserProfile 'src\app\.env') | Should -BeTrue
    }
    It 'durchsucht zusätzliche Ordner (ScanRoots)' {
        $extra = Join-Path $TestDrive 'extra'
        New-TestFile (Join-Path $extra 'proj\.env') 'DB_PASSWORD=geheim-beispiel'
        $script:ctx.ScanRoots = $extra
        (Analyze -Ctx $script:ctx -Categories @('env')).findings.Count | Should -Be 2
    }
}
