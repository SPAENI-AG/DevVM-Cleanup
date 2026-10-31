# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Pester 5 – Modul Spuren. Papierkorb und Ereignisprotokolle werden ersetzt; es wird nichts Echtes gelöscht.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\Traces.ps1')
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

    $script:recycle = 3
    $script:logs = @('Application', 'System')
    function Get-RecycleBinCount { $script:recycle }
    function Clear-RecycleBinSafe { $script:recycle = 0 }
    function Get-EventLogsWithRecords { @($script:logs) }
    function Clear-EventLogSafe { param([string]$LogName) $script:logs = @($script:logs | Where-Object { $_ -ne $LogName }) }
    function Old { param([string]$Path) (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddHours(-2) }
}

Describe 'Spuren – Beschreibung' {
    It 'hat sechs Kategorien' {
        ((Get-ModuleInfo).categories | ForEach-Object { $_.id }) | Should -Be @('temp', 'recyclebin', 'recent', 'rdp', 'pshistory', 'eventlogs')
    }
}

Describe 'Spuren – Bereinigung' {
    BeforeEach {
        $script:recycle = 3; $script:logs = @('Application', 'System')
        $script:ctx = New-TestCtx (Join-Path $TestDrive 'h')
        $l = $script:ctx.LocalAppData; $a = $script:ctx.AppData; $u = $script:ctx.UserProfile
        New-TestFile (Join-Path $l 'Temp\a.tmp'); Old (Join-Path $l 'Temp\a.tmp')
        New-TestFile (Join-Path $l 'Temp\sub\b.tmp')
        New-TestFile (Join-Path $a 'Microsoft\Windows\Recent\doc.lnk'); Old (Join-Path $a 'Microsoft\Windows\Recent\doc.lnk')
        New-TestFile (Join-Path $a 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt') 'Get-Secret'
        New-TestFile (Join-Path $u 'Documents\Default.rdp') 'full address:s:beispiel'
        New-TestFile (Join-Path $u 'Documents\wichtig.txt')
    }
    It 'Analyse findet Spuren und löscht nichts' {
        $r = Analyze -Ctx $script:ctx
        ($r.findings | ForEach-Object { $_.category }) | Should -Be @('temp', 'recyclebin', 'recent', 'rdp', 'pshistory', 'eventlogs')
        Test-Path (Join-Path $script:ctx.LocalAppData 'Temp\a.tmp') | Should -BeTrue
    }
    It 'Clean leert Temp (Ordner bleibt), Verlauf, RDP, Papierkorb und Ereignisprotokolle' {
        $r = Clean -Ctx $script:ctx -Categories @('temp', 'recyclebin', 'recent', 'rdp', 'pshistory', 'eventlogs')
        ($r.results | Where-Object { -not $_.ok }).Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.LocalAppData 'Temp') | Should -BeTrue
        Get-ChildCount (Join-Path $script:ctx.LocalAppData 'Temp') | Should -Be 0
        Test-Path (Join-Path $script:ctx.AppData 'Microsoft\Windows\Recent\doc.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.AppData 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.UserProfile 'Documents\Default.rdp') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.UserProfile 'Documents\wichtig.txt') | Should -BeTrue
        $script:recycle | Should -Be 0
        $script:logs.Count | Should -Be 0
    }
    It 'Clean ohne Kategorien löscht nichts' {
        (Clean -Ctx $script:ctx -Categories @()).results.Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.LocalAppData 'Temp\a.tmp') | Should -BeTrue
    }
    It 'Kontrolllauf meldet danach sauber' {
        [void](Clean -Ctx $script:ctx -Categories @('temp', 'recyclebin', 'recent', 'rdp', 'pshistory', 'eventlogs'))
        (Analyze -Ctx $script:ctx).findings.Count | Should -Be 0
    }
}
