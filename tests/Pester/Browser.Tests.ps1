# Pester 5 – Modul Browser mit erfundenen Profilen (keine echten Konten, keine echten Passwörter).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\modules\Browser.ps1')

    function New-TestProfiles {
        param($Root)
        $l = Join-Path $Root 'AppData\Local'; $a = Join-Path $Root 'AppData\Roaming'
        $edge = Join-Path $l 'Microsoft\Edge\User Data'
        foreach ($p in 'Default', 'Profile 1') {
            $d = Join-Path $edge $p
            foreach ($sub in 'Local Storage\leveldb', 'Cache', 'Sessions', 'Sync Data', 'Local Extension Settings\nngceckbapebfimnlniiiahkandclblb', 'Extensions\abc') {
                New-Item -ItemType Directory -Force -Path (Join-Path $d $sub) | Out-Null
            }
            Set-Content -Path (Join-Path $d 'Local Storage\leveldb\000003.log') -Value 'x'
            Set-Content -Path (Join-Path $d 'Login Data') -Value 'x'
            Set-Content -Path (Join-Path $d 'Cookies') -Value 'x'
            Set-Content -Path (Join-Path $d 'Bookmarks') -Value '{"roots":{}}'
            Set-Content -Path (Join-Path $d 'Extensions\abc\manifest.json') -Value '{}'
            Set-Content -Path (Join-Path $d 'Preferences') -Encoding UTF8 -Value '{"account_info":[{"email":"alice@example.com","account_id":"1"}],"google":{"services":{"last_username":"alice@example.com"}},"sync":{"x":1},"homepage":"about:blank"}'
        }
        Set-Content -Path (Join-Path $edge 'Local State') -Encoding UTF8 -Value '{"profile":{"info_cache":{"Default":{"name":"Person 1","user_name":"alice@example.com"},"Profile 1":{"name":"Profil 1","user_name":"alice@example.com","gaia_id":"1"}}}}'
        $ff = Join-Path $a 'Mozilla\Firefox\Profiles\abc123.default-release'
        New-Item -ItemType Directory -Force -Path (Join-Path $ff 'storage\default') | Out-Null
        Set-Content -Path (Join-Path $ff 'logins.json') -Value '{"logins":[{"id":1},{"id":2}]}'
        Set-Content -Path (Join-Path $ff 'key4.db') -Value 'x'
        Set-Content -Path (Join-Path $ff 'signedInUser.json') -Value '{"accountData":{"email":"bob@example.com"}}'
        Set-Content -Path (Join-Path $ff 'prefs.js') -Value ('user_pref("services.sync.username", "bob@example.com");' + [Environment]::NewLine + 'user_pref("browser.startup.homepage", "about:blank");')
        @{ UserProfile = $Root; AppData = $a; LocalAppData = $l; Hkcu = 'HKCU:\Software\DevVmCleanupTest' }
    }
}

Describe 'Browser – Modul-Beschreibung' {
    It 'bietet alle Kategorien einzeln an, Lesezeichen standardmässig aus' {
        $i = Get-ModuleInfo
        ($i.categories | ForEach-Object { $_.id }) | Should -Be @('signin', 'passwords', 'cookies', 'sitestorage', 'autofill', 'sessions', 'history', 'downloads', 'cache', 'extdata', 'bookmarks')
        ($i.categories | Where-Object { $_.id -eq 'bookmarks' }).default | Should -BeFalse
        $i.processes | Should -Contain 'msedge'
    }
}

Describe 'Browser – Analyse' {
    BeforeEach { $script:ctx = New-TestProfiles -Root (Join-Path $TestDrive 'h1') }
    It 'findet alle Profile mit Anzeigename und angemeldetem Konto' {
        $r = Analyze -Ctx $script:ctx
        $signin = @($r.findings | Where-Object { $_.category -eq 'signin' })
        ($signin | ForEach-Object { $_.scope }) | Should -Contain 'Edge / Profil 1'
        ($signin | ForEach-Object { $_.scope }) | Should -Contain 'Edge / Person 1'
        ($signin | ForEach-Object { $_.scope }) | Should -Contain 'Firefox / abc123.default-release'
        ($signin | Where-Object { $_.scope -eq 'Edge / Profil 1' }).label | Should -BeLike '*alice@example.com*'
    }
    It 'zählt Firefox-Passwörter' {
        $r = Analyze -Ctx $script:ctx -Categories @('passwords')
        ($r.findings | Where-Object { $_.scope -like 'Firefox*' }).label | Should -BeLike '2 *'
    }
    It 'löscht bei der Analyse nichts' {
        [void](Analyze -Ctx $script:ctx)
        Test-Path (Join-Path $script:ctx.LocalAppData 'Microsoft\Edge\User Data\Profile 1\Login Data') | Should -BeTrue
    }
}

Describe 'Browser – Bereinigung' {
    BeforeEach { $script:ctx = New-TestProfiles -Root (Join-Path $TestDrive 'h2') }
    It 'entfernt Anmeldung, behält Erweiterungen, Einstellungen und Lesezeichen' {
        $r = Clean -Ctx $script:ctx -Categories @('signin', 'cookies', 'sitestorage', 'sessions', 'cache', 'extdata')
        ($r.results | Where-Object { -not $_.ok }).Count | Should -Be 0
        $p = Join-Path $script:ctx.LocalAppData 'Microsoft\Edge\User Data\Profile 1'
        Test-Path (Join-Path $p 'Cookies') | Should -BeFalse
        Test-Path (Join-Path $p 'Local Storage') | Should -BeFalse
        Test-Path (Join-Path $p 'Extensions\abc\manifest.json') | Should -BeTrue
        Test-Path (Join-Path $p 'Bookmarks') | Should -BeTrue
        $prefs = Get-Content -Path (Join-Path $p 'Preferences') -Raw | ConvertFrom-Json
        $prefs.PSObject.Properties['account_info'] | Should -BeNullOrEmpty
        $prefs.homepage | Should -Be 'about:blank'
        $ls = Get-Content -Path (Join-Path $script:ctx.LocalAppData 'Microsoft\Edge\User Data\Local State') -Raw | ConvertFrom-Json
        $ls.profile.info_cache.'Profile 1'.PSObject.Properties['user_name'] | Should -BeNullOrEmpty
        $ls.profile.info_cache.'Profile 1'.name | Should -Be 'Profil 1'
    }
    It 'Firefox: entfernt Sync-Konto und Passwörter, lässt übrige prefs.js-Zeilen' {
        [void](Clean -Ctx $script:ctx -Categories @('signin', 'passwords'))
        $ff = Join-Path $script:ctx.AppData 'Mozilla\Firefox\Profiles\abc123.default-release'
        Test-Path (Join-Path $ff 'logins.json') | Should -BeFalse
        Test-Path (Join-Path $ff 'signedInUser.json') | Should -BeFalse
        $prefs = Get-Content -Path (Join-Path $ff 'prefs.js') -Raw
        $prefs | Should -Not -BeLike '*services.sync.username*'
        $prefs | Should -BeLike '*browser.startup.homepage*'
    }
    It 'Lesezeichen nur auf ausdrücklichen Wunsch' {
        $p = Join-Path $script:ctx.LocalAppData 'Microsoft\Edge\User Data\Default'
        [void](Clean -Ctx $script:ctx -Categories @('cookies'))
        Test-Path (Join-Path $p 'Bookmarks') | Should -BeTrue
        [void](Clean -Ctx $script:ctx -Categories @('bookmarks'))
        Test-Path (Join-Path $p 'Bookmarks') | Should -BeFalse
    }
    It 'Clean ohne Kategorien löscht nichts' {
        (Clean -Ctx $script:ctx -Categories @()).results.Count | Should -Be 0
    }
    It 'Kontrolllauf meldet danach sauber (ohne SQLite-abhängige Zähler)' {
        $cats = @('signin', 'passwords', 'cookies', 'sitestorage', 'sessions', 'cache', 'extdata')
        [void](Clean -Ctx $script:ctx -Categories $cats)
        (Analyze -Ctx $script:ctx -Categories $cats).findings.Count | Should -Be 0
    }
}
