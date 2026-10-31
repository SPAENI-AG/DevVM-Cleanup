# Pester 5 – Modul Office. Registry-Tests laufen gegen einen Test-Zweig (HKCU:\Software\DevVmCleanupTest), nie gegen echte Daten.
# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\Office.ps1')
}

Describe 'Office – Modul-Beschreibung' {
    It 'hat id, Kategorien und Prozesse' {
        $i = Get-ModuleInfo
        $i.id | Should -Be 'office'
        ($i.categories | ForEach-Object { $_.id }) | Should -Be @('identity', 'license', 'outlook', 'onedrive', 'teams')
        $i.processes | Should -Contain 'OUTLOOK'
    }
}

Describe 'Office – Dateien' {
    BeforeEach {
        $h = Join-Path $TestDrive 'home'
        $script:ctx = @{ UserProfile = $h; AppData = (Join-Path $h 'AppData\Roaming'); LocalAppData = (Join-Path $h 'AppData\Local'); Hkcu = 'HKCU:\Software\DevVmCleanupTest' }
        $l = $script:ctx.LocalAppData
        foreach ($d in 'Microsoft\Outlook', 'Microsoft\IdentityCache', 'Microsoft\Office\16.0\Licensing', 'Microsoft\OneDrive\settings') {
            New-Item -ItemType Directory -Force -Path (Join-Path $l $d) | Out-Null
        }
        Set-Content -Path (Join-Path $l 'Microsoft\Outlook\alice@example.com.ost') -Value 'x'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:ctx.AppData 'Microsoft\Teams') | Out-Null
        Set-Content -Path (Join-Path $script:ctx.AppData 'Microsoft\Teams\cache.bin') -Value 'x'
        $script:keep = Join-Path $h 'Documents\wichtig.docx'
        New-Item -ItemType Directory -Force -Path (Split-Path $script:keep) | Out-Null
        Set-Content -Path $script:keep -Value 'x'
    }
    It 'Analyse findet Spuren, löscht aber nichts' {
        $r = Analyze -Ctx $script:ctx
        ($r.findings | ForEach-Object { $_.category }) | Should -Contain 'outlook'
        ($r.findings | ForEach-Object { $_.category }) | Should -Contain 'teams'
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\Outlook') | Should -BeTrue
    }
    It 'Clean löscht nur gewählte Kategorien, Dokumente bleiben' {
        $r = Clean -Ctx $script:ctx -Categories @('outlook', 'teams')
        ($r.results | Where-Object { -not $_.ok }).Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\Outlook') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.AppData 'Microsoft\Teams') | Should -BeFalse
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\IdentityCache') | Should -BeTrue   # nicht gewählt
        Test-Path $script:keep | Should -BeTrue
    }
    It 'Clean ohne Kategorien löscht nichts' {
        (Clean -Ctx $script:ctx -Categories @()).results.Count | Should -Be 0
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\Outlook') | Should -BeTrue
    }
    It 'Kontrolllauf meldet danach sauber' {
        [void](Clean -Ctx $script:ctx -Categories @('identity', 'license', 'outlook', 'onedrive', 'teams'))
        (Analyze -Ctx $script:ctx).findings.Count | Should -Be 0
    }
}

Describe 'Office – Registry (nur Windows)' -Skip:(-not $isWindowsHost) {
    BeforeEach {
        $script:ctx = @{ UserProfile = $TestDrive; AppData = $TestDrive; LocalAppData = $TestDrive; Hkcu = 'HKCU:\Software\DevVmCleanupTest' }
        $id = "$($script:ctx.Hkcu)\Software\Microsoft\Office\16.0\Common\Identity\Identities\ABC_Test"
        New-Item -Path $id -Force | Out-Null
        New-ItemProperty -Path $id -Name 'EmailAddress' -Value 'alice@example.com' -Force | Out-Null
        New-Item -Path "$($script:ctx.Hkcu)\Software\Microsoft\OneDrive\Accounts\Business1" -Force | Out-Null
        New-ItemProperty -Path "$($script:ctx.Hkcu)\Software\Microsoft\OneDrive\Accounts\Business1" -Name 'UserEmail' -Value 'alice@example.com' -Force | Out-Null
    }
    AfterEach { Remove-Item -Path 'HKCU:\Software\DevVmCleanupTest' -Recurse -Force -ErrorAction SilentlyContinue }
    It 'zeigt „angemeldet als“ und entfernt die Identität' {
        (Analyze -Ctx $script:ctx -Categories @('identity')).findings[0].label | Should -BeLike '*alice@example.com*'
        [void](Clean -Ctx $script:ctx -Categories @('identity', 'onedrive'))
        (Analyze -Ctx $script:ctx -Categories @('identity', 'onedrive')).findings.Count | Should -Be 0
    }
}
