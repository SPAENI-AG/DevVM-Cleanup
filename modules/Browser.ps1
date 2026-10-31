# Browser.ps1 – Modul "Browser" (Edge, Chrome, weitere Chromium-Browser, Firefox; ALLE Profile)
# Nutzung ohne Oberfläche:
#   powershell -File Browser.ps1 -Action Analyze -Lang de
#   powershell -File Browser.ps1 -Action Clean -Categories signin,passwords,cookies
# Alle Browser müssen vor "Clean" geschlossen sein (auch Hintergrundprozesse, z. B. Edge Startup Boost).
#
# Wird bewusst NICHT angefasst: Erweiterungen selbst, allgemeine Einstellungen, Lesezeichen (nur optional "bookmarks",
# standardmässig aus; für Firefox nicht angeboten, weil Lesezeichen dort in places.sqlite mit dem Verlauf liegen).
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

# Bekannte Passwortmanager-Erweiterungen (Chrome-Web-Store- und Edge-Add-ons-IDs). Liste bei Bedarf ergänzen.
$script:PasswordManagerExtensionIds = @(
    'nngceckbapebfimnlniiiahkandclblb' # Bitwarden (Chrome)
    'jbkfoedolllekgbhcbcoahefnbanhhlh' # Bitwarden (Edge)
    'aeblfdkhhhdcdjpifhhbdiojplfjncoa' # 1Password (Chrome)
    'dppgmdbiimibapkepcbdbmkaabgiofem' # 1Password (Edge)
    'hdokiejnpimakedhajhdlcegeplioahd' # LastPass (Chrome)
    'bbcinlkgjjkejfdpemiealijmmooekmp' # LastPass (Edge)
    'fdjamakpfbbddfjaooikfcpapjohcfmg' # Dashlane (Chrome)
    'gehmmocbbkpblljhkekmfhjpfbkclbph' # Dashlane (Edge)
    'oboonakemofpalcgghocfoadofidjkkk' # KeePassXC-Browser
    'bfogiafebfohielmmehodmfbbebbbpei' # Keeper
    'fooolghllnmhmmndgjiamiiodkpenpbb' # NordPass
    'ghmbeldphafepmbegfdlkpapadhbakde' # Proton Pass
)

function Get-ModuleInfo {
    [ordered]@{
        id         = 'browser'
        name       = [ordered]@{ de = 'Browser'; en = 'Browsers' }
        processes  = @('msedge', 'chrome', 'brave', 'vivaldi', 'opera', 'firefox')
        categories = @(
            [ordered]@{ id = 'signin';      de = 'Sync-Anmeldung (Konto)';                    en = 'Sync sign-in (account)';              default = $true }
            [ordered]@{ id = 'passwords';   de = 'Gespeicherte Passwörter / Passkeys';        en = 'Saved passwords / passkeys';          default = $true }
            [ordered]@{ id = 'cookies';     de = 'Cookies / Sitzungen (angemeldete Websites)'; en = 'Cookies / sessions (signed-in sites)'; default = $true }
            [ordered]@{ id = 'sitestorage'; de = 'Website-Speicher (Local Storage, IndexedDB)'; en = 'Site storage (Local Storage, IndexedDB)'; default = $true }
            [ordered]@{ id = 'autofill';    de = 'Autofill (Adressen, Karten, Formulare)';    en = 'Autofill (addresses, cards, forms)';  default = $true }
            [ordered]@{ id = 'sessions';    de = 'Sitzungen / geöffnete Tabs';                en = 'Sessions / open tabs';                default = $true }
            [ordered]@{ id = 'history';     de = 'Verlauf';                                   en = 'History';                             default = $true }
            [ordered]@{ id = 'downloads';   de = 'Downloadliste';                             en = 'Download list';                       default = $true }
            [ordered]@{ id = 'cache';       de = 'Cache';                                     en = 'Cache';                               default = $true }
            [ordered]@{ id = 'extdata';     de = 'Daten von Passwortmanager-Erweiterungen';   en = 'Password-manager extension data';     default = $true }
            [ordered]@{ id = 'bookmarks';   de = 'Lesezeichen (Chromium)';                    en = 'Bookmarks (Chromium)';                default = $false }
        )
    }
}

# ---------------------------------------------------------------------------------------------
# Browser und Profile finden
# ---------------------------------------------------------------------------------------------
function Get-ChromiumBrowsers {
    param($Ctx)
    $l = $Ctx.LocalAppData; $a = $Ctx.AppData
    @(
        @{ Id = 'edge';    Name = 'Edge';    Root = (P $l 'Microsoft', 'Edge', 'User Data');           Flat = $false }
        @{ Id = 'chrome';  Name = 'Chrome';  Root = (P $l 'Google', 'Chrome', 'User Data');            Flat = $false }
        @{ Id = 'brave';   Name = 'Brave';   Root = (P $l 'BraveSoftware', 'Brave-Browser', 'User Data'); Flat = $false }
        @{ Id = 'vivaldi'; Name = 'Vivaldi'; Root = (P $l 'Vivaldi', 'User Data');                     Flat = $false }
        @{ Id = 'opera';   Name = 'Opera';   Root = (P $a 'Opera Software', 'Opera Stable');           Flat = $true }
        @{ Id = 'operagx'; Name = 'Opera GX'; Root = (P $a 'Opera Software', 'Opera GX Stable');       Flat = $true }
    ) | Where-Object { Test-Path -LiteralPath $_.Root }
}

function Get-ChromiumProfiles {
    param($Browser)
    $localState = Read-JsonFile (Join-Path $Browser.Root 'Local State')
    $dirs = @()
    if ($Browser.Flat) {
        if (Test-Path -LiteralPath (Join-Path $Browser.Root 'Preferences')) { $dirs += , @{ Dir = $Browser.Root; Key = '' } }
    } else {
        foreach ($d in (Get-ChildItem -LiteralPath $Browser.Root -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -in 'System Profile', 'Guest Profile') { continue }
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'Preferences')) { $dirs += , @{ Dir = $d.FullName; Key = $d.Name } }
        }
    }
    foreach ($p in $dirs) {
        $name = if ($p.Key) { $p.Key } else { 'Default' }
        $cache = $null
        if ($localState -and $p.Key) {
            $info = $localState.PSObject.Properties['profile']
            if ($info -and $info.Value.PSObject.Properties['info_cache']) {
                $entry = $info.Value.info_cache.PSObject.Properties[$p.Key]
                if ($entry -and $entry.Value.name) { $name = [string]$entry.Value.name }
            }
        }
        @{ Dir = $p.Dir; Key = $p.Key; Name = $name }
    }
}

function Get-FirefoxProfiles {
    param($Ctx)
    $root = (P $Ctx.AppData 'Mozilla', 'Firefox', 'Profiles')
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        @{ Dir = $d.FullName; Name = $d.Name; CacheDir = (P $Ctx.LocalAppData 'Mozilla', 'Firefox', 'Profiles', $d.Name, 'cache2') }
    }
}

# ---------------------------------------------------------------------------------------------
# Ziele pro Kategorie
# ---------------------------------------------------------------------------------------------
function Get-ChromiumProfileTargets {
    # Dateien/Ordner je Kategorie; SQL-/JSON-Eingriffe stehen in Clean-ChromiumProfile
    param([string]$Dir)
    function D { param([string[]]$Names) @($Names | ForEach-Object { @{ Path = (Join-Path $Dir $_) } }) }
    [ordered]@{
        signin      = @(D @('Sync Data', 'Sync App Settings', 'Account Web Data', 'Account Web Data-journal'))
        passwords   = @(D @('Login Data', 'Login Data-journal', 'Login Data For Account', 'Login Data For Account-journal', 'Affiliation Database', 'Affiliation Database-journal'))
        cookies     = @(
            @{ Path = (Join-Path $Dir 'Cookies') }, @{ Path = (Join-Path $Dir 'Cookies-journal') },
            @{ Path = (P $Dir 'Network', 'Cookies') }, @{ Path = (P $Dir 'Network', 'Cookies-journal') }
        )
        sitestorage = @(D @('Local Storage', 'IndexedDB', 'Session Storage', 'Service Worker', 'File System', 'WebStorage'))
        autofill    = @()   # per SQL in Web Data (siehe Clean-ChromiumProfile)
        sessions    = @(D @('Sessions', 'Current Session', 'Current Tabs', 'Last Session', 'Last Tabs'))
        history     = @(D @('History', 'History-journal', 'Top Sites', 'Top Sites-journal', 'Visited Links', 'Favicons', 'Favicons-journal', 'Shortcuts', 'Shortcuts-journal', 'Network Action Predictor', 'Media History'))
        downloads   = @()   # per SQL in History
        cache       = @(D @('Cache', 'Code Cache', 'GPUCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache', 'ShaderCache'))
        extdata     = @(
            foreach ($id in $script:PasswordManagerExtensionIds) {
                @{ Path = (P $Dir 'Local Extension Settings', $id) }
                @{ Path = (P $Dir 'Sync Extension Settings', $id) }
                @{ Path = (P $Dir 'IndexedDB', "chrome-extension_$($id)_0.indexeddb.leveldb") }
            }
        )
        bookmarks   = @(D @('Bookmarks', 'Bookmarks.bak', 'Bookmarks.msbak'))
    }
}

function Get-FirefoxProfileTargets {
    param($Profile)
    $d = $Profile.Dir
    function F { param([string[]]$Names) @($Names | ForEach-Object { @{ Path = (Join-Path $d $_) } }) }
    [ordered]@{
        signin      = @(F @('signedInUser.json', 'storage-sync-v2.sqlite', 'storage-sync-v2.sqlite-wal', 'storage-sync-v2.sqlite-shm', 'weave'))
        passwords   = @(F @('logins.json', 'logins-backup.json', 'key4.db', 'key3.db', 'signons.sqlite'))
        cookies     = @(F @('cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm'))
        sitestorage = @(F @('storage', 'webappsstore.sqlite', 'chromeappsstore.sqlite', 'storage.sqlite'))
        autofill    = @(F @('formhistory.sqlite', 'formhistory.sqlite-wal', 'autofill-profiles.json', 'credit-cards.json'))
        sessions    = @(F @('sessionstore.jsonlz4', 'sessionstore-backups', 'sessionCheckpoints.json'))
        history     = @()   # per SQL in places.sqlite (Lesezeichen bleiben)
        downloads   = @(F @('downloads.json'))
        cache       = @(@{ Path = $Profile.CacheDir }, @{ Path = (Join-Path $d 'startupCache') })
        extdata     = @(F @('browser-extension-data'))
        bookmarks   = @()
    }
}

# ---------------------------------------------------------------------------------------------
# Analyse
# ---------------------------------------------------------------------------------------------
function Add-IfAny {
    param([ref]$List, [string]$Cat, [string]$Scope, [string]$Label, [int]$Count)
    $List.Value += , (New-Finding $Cat $Scope $Label $Count)
}

function Get-ChromiumSignedInNames {
    param($Browser, $Profile)
    $names = @()
    $prefs = Read-JsonFile (Join-Path $Profile.Dir 'Preferences')
    if ($prefs -and $prefs.PSObject.Properties['account_info']) {
        foreach ($acc in @($prefs.account_info)) {
            if ($acc.email) { $names += [string]$acc.email }
            elseif ($acc.account_id) { $names += '(Konto)' }
        }
    }
    if ($prefs -and $prefs.PSObject.Properties['google'] -and $prefs.google.PSObject.Properties['services']) {
        $u = $prefs.google.services.PSObject.Properties['last_username']
        if ($u -and $u.Value) { $names += [string]$u.Value }
    }
    $ls = Read-JsonFile (Join-Path $Browser.Root 'Local State')
    if ($ls -and $Profile.Key -and $ls.PSObject.Properties['profile'] -and $ls.profile.PSObject.Properties['info_cache']) {
        $e = $ls.profile.info_cache.PSObject.Properties[$Profile.Key]
        if ($e -and $e.Value.PSObject.Properties['user_name'] -and $e.Value.user_name) { $names += [string]$e.Value.user_name }
    }
    @($names | Select-Object -Unique)
}

function Get-CountLabel {
    # Zahl -> Text; -1 = vorhanden, aber nicht zählbar
    param([int]$N, [string]$De, [string]$En)
    if ($N -lt 0) { return (T "$De (Anzahl unbekannt)" "$En (count unknown)") }
    (T "$N $De" "$N $En")
}

function Analyze-ChromiumProfile {
    param($Browser, $Profile, [string[]]$Want)
    $scope = "$($Browser.Name) / $($Profile.Name)"
    $dir = $Profile.Dir
    $t = Get-ChromiumProfileTargets $dir
    $f = @()

    if ($Want -contains 'signin') {
        $names = Get-ChromiumSignedInNames $Browser $Profile
        $files = @($t.signin | Where-Object { Test-TargetExists $_ }).Count
        if ($names.Count -gt 0) { Add-IfAny ([ref]$f) 'signin' $scope ((T 'angemeldet als {0}' 'signed in as {0}') -f ($names -join ', ')) $names.Count }
        elseif ($files -gt 0) { Add-IfAny ([ref]$f) 'signin' $scope (T 'Sync-Daten vorhanden' 'sync data present') $files }
    }
    if ($Want -contains 'passwords') {
        $n = 0; $any = $false
        foreach ($file in 'Login Data', 'Login Data For Account') {
            $path = Join-Path $dir $file
            if (Test-Path -LiteralPath $path) {
                $any = $true
                $c = Get-SqlCount $path 'SELECT count(*) FROM logins'
                if ($c -lt 0) { $n = -1 } elseif ($n -ge 0) { $n += $c }
            }
        }
        if ($any -and $n -ne 0) { Add-IfAny ([ref]$f) 'passwords' $scope (Get-CountLabel $n 'Passwörter' 'passwords') ([math]::Max(1, $n)) }
    }
    if ($Want -contains 'cookies') {
        $path = if (Test-Path -LiteralPath (P $dir 'Network', 'Cookies')) { P $dir 'Network', 'Cookies' } else { Join-Path $dir 'Cookies' }
        if (Test-Path -LiteralPath $path) {
            $n = Get-SqlCount $path 'SELECT count(DISTINCT host_key) FROM cookies'
            if ($n -ne 0) { Add-IfAny ([ref]$f) 'cookies' $scope ((T 'Cookies von {0} Websites' 'cookies from {0} sites') -f $(if ($n -lt 0) { '?' } else { $n })) ([math]::Max(1, $n)) }
        }
    }
    if ($Want -contains 'sitestorage') {
        $present = @($t.sitestorage | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            Add-IfAny ([ref]$f) 'sitestorage' $scope ((T 'Website-Speicher ({0} MB)' 'site storage ({0} MB)') -f $mb) $present.Count
        }
    }
    if ($Want -contains 'autofill') {
        $wd = Join-Path $dir 'Web Data'
        if (Test-Path -LiteralPath $wd) {
            $addr = [math]::Max(0, (Get-SqlCount $wd 'SELECT count(*) FROM autofill_profiles'))
            $cards = [math]::Max(0, (Get-SqlCount $wd 'SELECT count(*) FROM credit_cards'))
            $forms = [math]::Max(0, (Get-SqlCount $wd 'SELECT count(*) FROM autofill'))
            if (($addr + $cards + $forms) -gt 0) {
                Add-IfAny ([ref]$f) 'autofill' $scope ((T '{0} Adressen, {1} Karten, {2} Formulareinträge' '{0} addresses, {1} cards, {2} form entries') -f $addr, $cards, $forms) ($addr + $cards + $forms)
            }
        }
    }
    if ($Want -contains 'sessions') {
        $present = @($t.sessions | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'sessions' $scope (T 'Sitzungsdateien (geöffnete Tabs) vorhanden' 'session files (open tabs) present') $present }
    }
    if ($Want -contains 'history') {
        $h = Join-Path $dir 'History'
        if (Test-Path -LiteralPath $h) {
            $n = Get-SqlCount $h 'SELECT count(*) FROM urls'
            if ($n -ne 0) { Add-IfAny ([ref]$f) 'history' $scope (Get-CountLabel $n 'besuchte Seiten im Verlauf' 'pages in history') ([math]::Max(1, $n)) }
        }
    }
    if ($Want -contains 'downloads') {
        $h = Join-Path $dir 'History'
        if (Test-Path -LiteralPath $h) {
            $n = Get-SqlCount $h 'SELECT count(*) FROM downloads'
            if ($n -ne 0) { Add-IfAny ([ref]$f) 'downloads' $scope (Get-CountLabel $n 'Einträge in der Downloadliste' 'entries in download list') ([math]::Max(1, $n)) }
        }
    }
    if ($Want -contains 'cache') {
        $present = @($t.cache | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            Add-IfAny ([ref]$f) 'cache' $scope ((T 'Cache ({0} MB)' 'cache ({0} MB)') -f $mb) $present.Count
        }
    }
    if ($Want -contains 'extdata') {
        $present = @($t.extdata | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'extdata' $scope (T 'Daten von Passwortmanager-Erweiterungen vorhanden' 'password-manager extension data present') $present }
    }
    if ($Want -contains 'bookmarks') {
        $present = @($t.bookmarks | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'bookmarks' $scope (T 'Lesezeichen vorhanden' 'bookmarks present') $present }
    }
    $f
}

function Analyze-FirefoxProfile {
    param($Profile, [string[]]$Want)
    $scope = "Firefox / $($Profile.Name)"
    $dir = $Profile.Dir
    $t = Get-FirefoxProfileTargets $Profile
    $f = @()

    if ($Want -contains 'signin') {
        $user = $null
        $s = Read-JsonFile (Join-Path $dir 'signedInUser.json')
        if ($s -and $s.PSObject.Properties['accountData'] -and $s.accountData.email) { $user = [string]$s.accountData.email }
        $prefs = Join-Path $dir 'prefs.js'
        $hasPrefs = $false
        if (Test-Path -LiteralPath $prefs) { $hasPrefs = [bool](Select-String -LiteralPath $prefs -Pattern 'user_pref\("(services\.sync\.username|identity\.fxaccounts\.)' -Quiet) }
        if ($user) { Add-IfAny ([ref]$f) 'signin' $scope ((T 'angemeldet als {0}' 'signed in as {0}') -f $user) 1 }
        elseif ($hasPrefs -or (Test-TargetExists $t.signin[0])) { Add-IfAny ([ref]$f) 'signin' $scope (T 'Sync-Anmeldung vorhanden' 'sync sign-in present') 1 }
    }
    if ($Want -contains 'passwords') {
        $lj = Read-JsonFile (Join-Path $dir 'logins.json')
        $n = 0
        if ($lj -and $lj.PSObject.Properties['logins']) { $n = @($lj.logins).Count }
        $keyOnly = (Test-Path -LiteralPath (Join-Path $dir 'key4.db'))
        if ($n -gt 0) { Add-IfAny ([ref]$f) 'passwords' $scope ((T '{0} Passwörter' '{0} passwords') -f $n) $n }
        elseif ($keyOnly -and (Test-Path -LiteralPath (Join-Path $dir 'logins.json'))) { Add-IfAny ([ref]$f) 'passwords' $scope (T 'Passwortspeicher vorhanden (leer)' 'password store present (empty)') 1 }
    }
    if ($Want -contains 'cookies') {
        $c = Join-Path $dir 'cookies.sqlite'
        if (Test-Path -LiteralPath $c) {
            $n = Get-SqlCount $c 'SELECT count(DISTINCT host) FROM moz_cookies'
            if ($n -ne 0) { Add-IfAny ([ref]$f) 'cookies' $scope ((T 'Cookies von {0} Websites' 'cookies from {0} sites') -f $(if ($n -lt 0) { '?' } else { $n })) ([math]::Max(1, $n)) }
        }
    }
    if ($Want -contains 'sitestorage') {
        $present = @($t.sitestorage | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            Add-IfAny ([ref]$f) 'sitestorage' $scope ((T 'Website-Speicher ({0} MB)' 'site storage ({0} MB)') -f $mb) $present.Count
        }
    }
    if ($Want -contains 'autofill') {
        $fh = Join-Path $dir 'formhistory.sqlite'
        $n = 0
        if (Test-Path -LiteralPath $fh) { $n = [math]::Max(0, (Get-SqlCount $fh 'SELECT count(*) FROM moz_formhistory')) }
        $extra = @($t.autofill | Where-Object { $_.Path -notlike '*formhistory*' -and (Test-TargetExists $_) }).Count
        if (($n + $extra) -gt 0) { Add-IfAny ([ref]$f) 'autofill' $scope ((T '{0} Formulareinträge, {1} Autofill-Dateien' '{0} form entries, {1} autofill files') -f $n, $extra) ($n + $extra) }
    }
    if ($Want -contains 'sessions') {
        $present = @($t.sessions | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'sessions' $scope (T 'Sitzungsdateien (geöffnete Tabs) vorhanden' 'session files (open tabs) present') $present }
    }
    if ($Want -contains 'history') {
        $pl = Join-Path $dir 'places.sqlite'
        if (Test-Path -LiteralPath $pl) {
            $n = Get-SqlCount $pl 'SELECT count(*) FROM moz_historyvisits'
            if ($n -ne 0) { Add-IfAny ([ref]$f) 'history' $scope (Get-CountLabel $n 'Besuche im Verlauf' 'visits in history') ([math]::Max(1, $n)) }
        }
    }
    if ($Want -contains 'downloads') {
        $present = @($t.downloads | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'downloads' $scope (T 'Downloadliste vorhanden' 'download list present') $present }
    }
    if ($Want -contains 'cache') {
        $present = @($t.cache | Where-Object { Test-TargetExists $_ })
        if ($present.Count -gt 0) {
            $mb = 0; foreach ($x in $present) { $mb += (Get-PathSizeMB $x.Path) }
            Add-IfAny ([ref]$f) 'cache' $scope ((T 'Cache ({0} MB)' 'cache ({0} MB)') -f $mb) $present.Count
        }
    }
    if ($Want -contains 'extdata') {
        $present = @($t.extdata | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { Add-IfAny ([ref]$f) 'extdata' $scope (T 'Erweiterungsdaten vorhanden (alle Erweiterungen)' 'extension data present (all extensions)') $present }
    }
    $f
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { @($all | Where-Object { $_ -ne 'bookmarks' }) }
    $findings = @()
    foreach ($b in (Get-ChromiumBrowsers $Ctx)) {
        foreach ($p in (Get-ChromiumProfiles $b)) { $findings += Analyze-ChromiumProfile $b $p $want }
    }
    foreach ($p in (Get-FirefoxProfiles $Ctx)) { $findings += Analyze-FirefoxProfile $p $want }
    [ordered]@{ module = 'browser'; findings = @($findings) }
}

# ---------------------------------------------------------------------------------------------
# Bereinigung
# ---------------------------------------------------------------------------------------------
function Clean-ChromiumProfile {
    param($Browser, $Profile, [string]$Cat, $Ctx)
    $dir = $Profile.Dir
    $t = Get-ChromiumProfileTargets $dir
    $removed = 0
    foreach ($x in $t[$Cat]) { $removed += Remove-Target $x $Ctx }
    switch ($Cat) {
        'signin' {
            # Konto aus Preferences / Local State entfernen, Token-Tabelle leeren
            $removed += [math]::Max(0, (Remove-JsonPaths (Join-Path $dir 'Preferences') @(
                        'account_info', 'account_tracker_service_last_update', 'google.services', 'sync', 'signin', 'edge.services')))
            if ($Profile.Key) {
                $pre = "profile.info_cache.$($Profile.Key)"
                $removed += [math]::Max(0, (Remove-JsonPaths (Join-Path $Browser.Root 'Local State') @(
                            "$pre.user_name", "$pre.gaia_name", "$pre.gaia_given_name", "$pre.gaia_id", "$pre.gaia_picture_file_name",
                            "$pre.hosted_domain", "$pre.is_consented_primary_account", "$pre.account_categories")))
            }
            $removed += Invoke-SqlDeleteAll (Join-Path $dir 'Web Data') @('token_service')
        }
        'autofill' {
            $removed += Invoke-SqlDeleteAll (Join-Path $dir 'Web Data') @(
                'autofill', 'autofill_profiles', 'autofill_profile_names', 'autofill_profile_emails', 'autofill_profile_phones',
                'autofill_profile_addresses', 'credit_cards', 'masked_credit_cards', 'unmasked_credit_cards', 'local_ibans',
                'masked_ibans', 'server_addresses', 'server_address_metadata', 'autofill_sync_metadata', 'autofill_model_type_state')
        }
        'downloads' {
            $removed += Invoke-SqlDeleteAll (Join-Path $dir 'History') @('downloads', 'downloads_url_chains', 'downloads_slices')
        }
        'sitestorage' { }
    }
    $removed
}

function Clean-FirefoxProfile {
    param($Profile, [string]$Cat, $Ctx)
    $dir = $Profile.Dir
    $t = Get-FirefoxProfileTargets $Profile
    $removed = 0
    foreach ($x in $t[$Cat]) { $removed += Remove-Target $x $Ctx }
    switch ($Cat) {
        'signin' {
            $prefs = Join-Path $dir 'prefs.js'
            if (Test-Path -LiteralPath $prefs) {
                $lines = @(Get-Content -LiteralPath $prefs -Encoding UTF8)
                $keep = @($lines | Where-Object { $_ -notmatch '^user_pref\("(services\.sync\.|identity\.fxaccounts\.)' })
                if ($keep.Count -ne $lines.Count) {
                    Set-Content -LiteralPath $prefs -Value $keep -Encoding UTF8
                    $removed += ($lines.Count - $keep.Count)
                }
            }
        }
        'autofill' {
            $removed += Invoke-SqlDeleteAll (Join-Path $dir 'formhistory.sqlite') @('moz_formhistory')
        }
        'history' {
            $pl = Join-Path $dir 'places.sqlite'
            if (Test-Path -LiteralPath $pl) {
                # Besuche und nicht mit Lesezeichen verknüpfte Seiten entfernen; Lesezeichen bleiben erhalten
                Invoke-SqlExec $pl 'DELETE FROM moz_historyvisits;'
                Invoke-SqlExec $pl 'DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL);'
                Invoke-SqlExec $pl "DELETE FROM moz_annos WHERE anno_attribute_id IN (SELECT id FROM moz_anno_attributes WHERE name LIKE 'downloads/%');"
                Invoke-SqlExec $pl 'VACUUM;'
                $removed++
            }
        }
    }
    $removed
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $valid = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $results = @()
    $units = @()
    foreach ($b in (Get-ChromiumBrowsers $Ctx)) {
        foreach ($p in (Get-ChromiumProfiles $b)) { $units += , @{ Kind = 'c'; B = $b; P = $p; Scope = "$($b.Name) / $($p.Name)" } }
    }
    foreach ($p in (Get-FirefoxProfiles $Ctx)) { $units += , @{ Kind = 'f'; B = $null; P = $p; Scope = "Firefox / $($p.Name)" } }

    foreach ($cat in $Categories) {
        if ($cat -notin $valid) { continue }
        foreach ($u in $units) {
            if ($u.Kind -eq 'f' -and $cat -eq 'bookmarks') { continue }
            try {
                $n = if ($u.Kind -eq 'c') { Clean-ChromiumProfile $u.B $u.P $cat $Ctx } else { Clean-FirefoxProfile $u.P $cat $Ctx }
                $results += New-Result $cat $u.Scope $true ([int]$n) ''
            } catch {
                $results += New-Result $cat $u.Scope $false 0 $_.Exception.Message
            }
        }
    }
    [ordered]@{ module = 'browser'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
