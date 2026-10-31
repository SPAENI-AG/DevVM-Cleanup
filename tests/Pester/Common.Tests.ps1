# Pester 5 – gemeinsame Hilfsfunktionen. Alle Testdaten sind erfunden.
# Skip-Bedingungen werden in der Discovery-Phase ausgewertet – daher ausserhalb von BeforeAll.
$isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\_Common.ps1')
}

Describe 'Remove-PathSafe' {
    BeforeEach {
        $script:ctx = @{ UserProfile = (Join-Path $TestDrive 'home'); AppData = (Join-Path $TestDrive 'home\AppData\Roaming'); LocalAppData = (Join-Path $TestDrive 'home\AppData\Local'); Hkcu = 'HKCU:\Software\DevVmCleanupTest' }
        New-Item -ItemType Directory -Force -Path $script:ctx.LocalAppData | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $TestDrive 'outside') | Out-Null
        Set-Content -Path (Join-Path $TestDrive 'outside\keep.txt') -Value 'x'
    }
    It 'löscht Ordner innerhalb der Wurzeln' {
        $d = Join-Path $script:ctx.LocalAppData 'App\Cache'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Set-Content -Path (Join-Path $d 'a.bin') -Value 'x'
        Remove-PathSafe -Path $d -Ctx $script:ctx | Should -Be 1
        Test-Path $d | Should -BeFalse
    }
    It 'liefert 0, wenn nichts da ist' {
        Remove-PathSafe -Path (Join-Path $script:ctx.LocalAppData 'gibtsnicht') -Ctx $script:ctx | Should -Be 0
    }
    It 'verweigert Pfade ausserhalb der Wurzeln' {
        { Remove-PathSafe -Path (Join-Path $TestDrive 'outside\keep.txt') -Ctx $script:ctx } | Should -Throw
        Test-Path (Join-Path $TestDrive 'outside\keep.txt') | Should -BeTrue
    }
    It 'verweigert die Wurzel selbst' {
        { Remove-PathSafe -Path $script:ctx.LocalAppData -Ctx $script:ctx } | Should -Throw
    }
}

Describe 'Get-CredentialKind' {
    It 'nennt nur bekannte Typen, nie Host- oder Benutzernamen' {
        Get-CredentialKind 'git:https://example.com' | Should -Be 'git'
        Get-CredentialKind 'TERMSRV/beispiel-host' | Should -Be 'TERMSRV'
        Get-CredentialKind 'VSCredentials_beispiel' | Should -Be 'VSCredentials'
        Get-CredentialKind 'Nextcloud_alice@example.com:https://x' | Should -Be 'Sonstige'
        Get-CredentialKind 'nuget.example.com' | Should -Be 'Sonstige'
        Get-CredentialKind 'LegacyGeneric:target=x' | Should -Be 'LegacyGeneric'
    }
}

Describe 'Split-List' {
    It 'trennt Kommalisten (powershell -File liefert sie als einen String)' {
        (Split-List 'a, b,c') -join '|' | Should -Be 'a|b|c'
        (Split-List '').Count | Should -Be 0
    }
}

Describe 'Remove-JsonPaths' {
    It 'entfernt gezielt Schlüssel und lässt den Rest unverändert' {
        $f = Join-Path $TestDrive 'Preferences'
        Set-Content -Path $f -Encoding UTF8 -Value '{"account_info":[{"email":"alice@example.com"}],"google":{"services":{"last_username":"alice@example.com"}},"keep":{"v":"ä"}}'
        Remove-JsonPaths -File $f -Paths @('account_info', 'google.services', 'gibt.es.nicht') | Should -Be 2
        $o = Get-Content -Path $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $o.PSObject.Properties['account_info'] | Should -BeNullOrEmpty
        $o.keep.v | Should -Be 'ä'
    }
}

Describe 'SQLite (nur Windows)' -Skip:(-not $isWindowsHost) {
    It 'zählt und leert Tabellen' {
        Initialize-Sqlite | Should -BeTrue
        $db = Join-Path $TestDrive 'test.db'
        # leere Datei = gültige leere SQLite-Datenbank (Exec öffnet nur vorhandene Dateien)
        New-Item -ItemType File -Path $db -Force | Out-Null
        [DvcSqlite]::Exec($db, 'CREATE TABLE logins(id INTEGER); INSERT INTO logins VALUES (1),(2),(3);') | Should -Be 0
        Get-SqlCount -File $db -Sql 'SELECT count(*) FROM logins' | Should -Be 3
        Invoke-SqlDeleteAll -File $db -Tables @('logins', 'gibtsnicht') | Should -Be 1
        Get-SqlCount -File $db -Sql 'SELECT count(*) FROM logins' | Should -Be 0
    }
}
