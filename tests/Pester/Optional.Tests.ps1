# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Pester 5 – Modul Optionale Programme (nur wenn Daten vorhanden) und Lizenz-Hinweise.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\Optional.ps1')
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

Describe 'Optional – nur wenn vorhanden' {
    BeforeEach { $script:ctx = New-TestCtx (Join-Path $TestDrive 'h') }
    It 'meldet nichts, wenn nichts installiert ist' {
        $r = Analyze -Ctx $script:ctx
        $r.findings.Count | Should -Be 0
        $r.notes.Count | Should -Be 0
    }
    It 'findet und bereinigt Sophos Connect und eCatcher, nicht device2cloud' {
        New-TestFile (Join-Path $script:ctx.AppData 'Sophos\Connect\settings.json')
        New-TestFile (Join-Path $script:ctx.ProgramData 'Sophos\Connect\profiles\p.pro')
        New-TestFile (Join-Path $script:ctx.AppData 'eCatcher\account.cfg')
        $r = Analyze -Ctx $script:ctx
        ($r.findings | ForEach-Object { $_.category }) | Should -Be @('sophos', 'ecatcher')
        [void](Clean -Ctx $script:ctx -Categories @('sophos', 'ecatcher'))
        Test-Path (Join-Path $script:ctx.ProgramData 'Sophos\Connect\profiles') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.AppData 'eCatcher') | Should -BeFalse
        (Analyze -Ctx $script:ctx).findings.Count | Should -Be 0
    }
    It 'Lizenz-Hinweis für Siemens ALM, ohne etwas zu verändern' {
        New-TestFile (Join-Path $script:ctx.ProgramFilesX86 'Siemens\Automation\Automation License Manager\alm.exe')
        $r = Analyze -Ctx $script:ctx
        ($r.notes -join ' ') | Should -BeLike '*Automation License Manager*'
        Test-Path (Join-Path $script:ctx.ProgramFilesX86 'Siemens\Automation\Automation License Manager\alm.exe') | Should -BeTrue
    }
}
