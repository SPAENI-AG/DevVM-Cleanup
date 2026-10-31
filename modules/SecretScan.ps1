# SecretScan.ps1 – Modul "Geheimnis-Scan" (NUR BERICHT – löscht nie etwas)
# Sucht im Benutzerprofil (und optionalen Zusatzordnern, ScanRoots) nach Dateien, die Zugangsdaten enthalten können:
#   git      Git-Remotes mit Token/Passwort in der URL, .git-credentials
#   env      .env-Dateien mit Passwort-/Token-artigen Schlüsseln
#   certs    .pfx/.p12-Zertifikate und private Schlüssel (.pem/.key mit "PRIVATE KEY")
#   appsettings  Passwörter/Geheimnisse in appsettings*.json, secrets.json (.NET User Secrets)
# Der Bericht nennt Pfad und Art des Fundes, NIE den Wert des Geheimnisses.
#   powershell -File SecretScan.ps1 -Action Analyze -Lang de
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

$script:SkipDirs = @('node_modules', '.git', 'bin', 'obj', '.vs', 'packages', '.nuget', 'AppData', 'Windows', '$RECYCLE.BIN', 'System Volume Information', '.cache', '.gradle', '.m2')
$script:MaxDepth = 8
$script:MaxFiles = 300000

function Get-ModuleInfo {
    [ordered]@{
        id         = 'secretscan'
        reportOnly = $true
        name       = [ordered]@{ de = 'Geheimnis-Scan (nur Bericht)'; en = 'Secret scan (report only)' }
        processes  = @()
        categories = @(
            [ordered]@{ id = 'git';         de = 'Git-Remotes mit Token, .git-credentials'; en = 'Git remotes with token, .git-credentials'; default = $true }
            [ordered]@{ id = 'env';         de = '.env-Dateien';                            en = '.env files';                                 default = $true }
            [ordered]@{ id = 'certs';       de = 'Zertifikate und private Schlüssel';       en = 'Certificates and private keys';              default = $true }
            [ordered]@{ id = 'appsettings'; de = 'Passwörter in appsettings.json / secrets.json'; en = 'Passwords in appsettings.json / secrets.json'; default = $true }
        )
    }
}

function Get-ScanRoots {
    param($Ctx)
    $roots = @()
    if ($Ctx.UserProfile) { $roots += $Ctx.UserProfile }
    foreach ($r in ("$($Ctx.ScanRoots)" -split '\|')) { if ($r.Trim()) { $roots += $r.Trim() } }
    @($roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
}

function Find-ScanFiles {
    # Läuft per Stack durch die Ordner (tief begrenzt, ohne Verknüpfungen), liefert alle Dateipfade
    param([string]$Root)
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@($Root, 0))
    $count = 0
    while ($stack.Count -gt 0) {
        $item = $stack.Pop(); $dir = $item[0]; $depth = $item[1]
        try { $entries = [IO.Directory]::EnumerateFileSystemEntries($dir) } catch { continue }
        foreach ($e in $entries) {
            $name = [IO.Path]::GetFileName($e)
            try { $attr = [IO.File]::GetAttributes($e) } catch { continue }
            if ($attr -band [IO.FileAttributes]::Directory) {
                if ($attr -band [IO.FileAttributes]::ReparsePoint) { continue }
                # .git wird nicht durchlaufen; die config wird gezielt gelesen (Find-GitConfig)
                if ($script:SkipDirs -contains $name) {
                    if ($name -eq '.git') { $cfg = Join-Path $e 'config'; if (Test-Path -LiteralPath $cfg) { $cfg } }
                    continue
                }
                if ($depth -lt $script:MaxDepth) { $stack.Push(@($e, ($depth + 1))) }
            } else {
                $count++
                if ($count -gt $script:MaxFiles) { return }
                $e
            }
        }
    }
}

function Test-GitConfigToken {
    # Liefert Remote-Namen mit Zugangsdaten in der URL: https://user:pw@host, https://token@host
    param([string]$File)
    $remotes = @(); $name = ''
    foreach ($line in (Get-Content -LiteralPath $File -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*\[remote\s+"([^"]+)"\]') { $name = $Matches[1]; continue }
        if ($line -match '^\s*\[') { $name = ''; continue }
        if ($name -and $line -match '^\s*url\s*=\s*(\w+://)([^/\s@]+)@') {
            $cred = $Matches[2]
            # "git@host" (ssh) enthält kein Geheimnis; Benutzer:Passwort oder Token sind Funde
            if ($cred -match ':' -or $cred -match '^(gh[pousr]_|github_pat_|glpat-|xox)' -or $cred.Length -ge 30) { $remotes += $name }
        }
    }
    @($remotes | Select-Object -Unique)
}

function Test-EnvFile {
    param([string]$File)
    @(Get-Content -LiteralPath $File -ErrorAction SilentlyContinue | Where-Object {
            $_ -match '^\s*(export\s+)?[A-Za-z0-9_.-]*(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY|CONNECTION_?STRING)[A-Za-z0-9_.-]*\s*=\s*\S+' -and
            $_ -notmatch '=\s*(["'']?)(changeme|your[_-].*|<.*>|xxx+|\*+|)\1\s*$'
        }).Count
}

function Test-AppSettingsFile {
    param([string]$File)
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $File -ErrorAction SilentlyContinue)) {
        if ($line -match '"[A-Za-z0-9_.:-]*(Password|Pwd|Secret|ApiKey|ClientSecret|AccessKey|PrivateKey|Token)"\s*:\s*"([^"]{4,})"') {
            if ($Matches[2] -notmatch '^(changeme|your[_-]|<|\*+$|xxx|\$\{|%)') { $n++ }
        } elseif ($line -match '(?i)(password|pwd)\s*=\s*[^;"\s]{3,}') { $n++ }
    }
    $n
}

function Test-PrivateKeyFile {
    param([string]$File)
    try {
        $fi = Get-Item -LiteralPath $File -ErrorAction Stop
        if ($fi.Length -gt 1MB) { return $false }
        [bool](Select-String -LiteralPath $File -Pattern 'BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY' -Quiet -ErrorAction SilentlyContinue)
    } catch { $false }
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $f = @()
    $seen = @{}
    foreach ($root in (Get-ScanRoots $Ctx)) {
        $files = @(Find-ScanFiles $root)
        # UserSecrets liegen im (sonst übersprungenen) AppData
        if ($Ctx.AppData -and ($root -eq $Ctx.UserProfile) -and ($want -contains 'appsettings')) {
            $us = (P $Ctx.AppData 'Microsoft', 'UserSecrets')
            if (Test-Path -LiteralPath $us) { $files += @(Get-ChildItem -LiteralPath $us -Recurse -Filter 'secrets.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
        }
        foreach ($file in $files) {
            if ($seen.ContainsKey($file)) { continue }
            $seen[$file] = $true
            $name = [IO.Path]::GetFileName($file); $lname = $name.ToLowerInvariant()
            $disp = $file   # vollständiger Pfad (bei mehreren Scan-Ordnern eindeutig)

            if ($want -contains 'git') {
                if ($lname -eq 'config' -and (Split-Path -Leaf (Split-Path -Parent $file)) -eq '.git') {
                    $r = @(Test-GitConfigToken $file)
                    if ($r.Count -gt 0) { $f += New-Finding 'git' $disp ((T 'Zugangsdaten in der Remote-URL ({0})' 'credentials in remote URL ({0})') -f ($r -join ', ')) 1 }
                } elseif ($lname -eq '.git-credentials') {
                    $f += New-Finding 'git' $disp (T '.git-credentials-Datei (Klartext-Anmeldedaten)' '.git-credentials file (clear-text credentials)') 1
                }
            }
            if ($want -contains 'env' -and ($lname -eq '.env' -or ($lname -like '.env.*' -and $lname -notmatch '\.(example|sample|template|dist)$'))) {
                $n = Test-EnvFile $file
                if ($n -gt 0) { $f += New-Finding 'env' $disp ((T '.env-Datei mit {0} Geheimnis-Einträgen' '.env file with {0} secret entries') -f $n) $n }
            }
            if ($want -contains 'certs') {
                if ($lname -like '*.pfx' -or $lname -like '*.p12') { $f += New-Finding 'certs' $disp (T 'Zertifikat mit privatem Schlüssel (PFX/P12)' 'certificate with private key (PFX/P12)') 1 }
                elseif (($lname -like '*.pem' -or $lname -like '*.key') -and (Test-PrivateKeyFile $file)) { $f += New-Finding 'certs' $disp (T 'privater Schlüssel (PEM/KEY)' 'private key (PEM/KEY)') 1 }
            }
            if ($want -contains 'appsettings' -and ($lname -like 'appsettings*.json' -or $lname -eq 'secrets.json')) {
                $n = Test-AppSettingsFile $file
                if ($n -gt 0) { $f += New-Finding 'appsettings' $disp ((T '{0} Einträge mit Passwort/Geheimnis' '{0} entries with password/secret') -f $n) $n }
            }
        }
    }
    [ordered]@{ module = 'secretscan'; findings = @($f); notes = @() }
}

function Clean {
    # Bewusst leer: der Geheimnis-Scan ist nur ein Bericht und löscht nie etwas.
    param($Ctx, [string[]]$Categories = @())
    [ordered]@{ module = 'secretscan'; results = @() }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
