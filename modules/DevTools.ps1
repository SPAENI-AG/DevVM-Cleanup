# DevTools.ps1 – Modul "Entwicklungstools"
# Visual Studio (IdentityService), GitHub Copilot/CLI, VS Code-Konten, Git (user.name/user.email, Anmeldedaten),
# SSH-Schlüssel, NuGet-Zugangsdaten, .npmrc/Yarn-Tokens.
# Es werden Anmeldungen und Zugangsdaten entfernt – NICHT Quellcode, Repositories, Erweiterungen oder allgemeine Einstellungen.
#   powershell -File DevTools.ps1 -Action Analyze -Lang de
#   powershell -File DevTools.ps1 -Action Clean -Categories git,ssh,npmrc
param(
    [ValidateSet('', 'Info', 'Analyze', 'Clean')][string]$Action = '',
    [string]$Categories = '',
    [string]$ContextJson = '',
    [string]$Lang = 'de'
)

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ModuleInfo {
    [ordered]@{
        id         = 'devtools'
        name       = [ordered]@{ de = 'Entwicklungstools'; en = 'Development tools' }
        processes  = @('devenv', 'Code', 'Code - Insiders', 'VSCodium', 'git-credential-manager', 'gh', 'ssh-agent', 'ServiceHub.Host.Dotnet.x64', 'ServiceHub.IdentityHost')
        categories = @(
            [ordered]@{ id = 'vs';      de = 'Visual Studio (Konto, IdentityService)'; en = 'Visual Studio (account, IdentityService)'; default = $true }
            [ordered]@{ id = 'copilot'; de = 'GitHub Copilot / GitHub CLI';            en = 'GitHub Copilot / GitHub CLI';              default = $true }
            [ordered]@{ id = 'vscode';  de = 'VS Code (Konten, Anmeldungen)';          en = 'VS Code (accounts, sign-ins)';             default = $true }
            [ordered]@{ id = 'git';     de = 'Git (user.name/user.email, Anmeldedaten)'; en = 'Git (user.name/user.email, credentials)'; default = $true }
            [ordered]@{ id = 'ssh';     de = 'SSH-Schlüssel (und known_hosts)';        en = 'SSH keys (and known_hosts)';               default = $true }
            [ordered]@{ id = 'nuget';   de = 'NuGet-Zugangsdaten und API-Schlüssel';   en = 'NuGet credentials and API keys';          default = $true }
            [ordered]@{ id = 'npmrc';   de = '.npmrc / Yarn-Tokens';                   en = '.npmrc / Yarn tokens';                     default = $true }
        )
    }
}

# Zeilen, die Zugangsdaten enthalten
$script:NpmSecretRx = '^\s*(//[^=\s]+:)?(_authToken|_auth|_password|username|email|always-auth)\s*='
$script:YarnSecretRx = '(?i)^\s*(npmAuthToken|npmAuthIdent|_authToken|_auth|_password)\b'
$script:VsCodeSecretWhere = "key LIKE 'secret://%' OR key LIKE 'github.auth%' OR key LIKE 'microsoft.auth%' OR key LIKE '%authenticationsessions%' OR key LIKE '%accountPreference%' OR key LIKE 'github.copilot%'"

function Get-VsCodeDirs {
    param($Ctx)
    foreach ($n in 'Code', 'Code - Insiders', 'VSCodium', 'Cursor') {
        $d = (P $Ctx.AppData $n)
        if (Test-Path -LiteralPath $d) { $d }
    }
}

function Get-SshFiles {
    param($Ctx)
    $dir = (P $Ctx.UserProfile '.ssh')
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like 'id_*' -or $_.Name -like '*.pem' -or $_.Name -like '*.ppk' -or $_.Name -like 'known_hosts*'
        } | ForEach-Object { $_.FullName })
}

function Get-VsTargets {
    param($Ctx)
    $h = $Ctx.Hkcu; $l = $Ctx.LocalAppData
    $t = @(
        @{ Path = (P $l '.IdentityService') }
        @{ Path = (P $l 'GitCredentialManager') }
        @{ Path = (P $l 'MicrosoftCredentialProvider') }
        @{ Reg = "$h\Software\Microsoft\VSCommon\ConnectedUser" }
    )
    foreach ($v in (Get-RegChildNames "$h\Software\Microsoft\VSCommon")) {
        if ($v -match '^\d+\.\d+$') {
            $t += @{ Reg = "$h\Software\Microsoft\VSCommon\$v\ClientServices\TokenStorage" }
            $t += @{ Reg = "$h\Software\Microsoft\VSCommon\$v\ConnectedUser" }
        }
    }
    $t
}

function Get-CopilotTargets {
    param($Ctx)
    @(
        @{ Path = (P $Ctx.LocalAppData 'github-copilot') }
        @{ Path = (P $Ctx.AppData 'github-copilot') }
        @{ Path = (P $Ctx.AppData 'GitHub CLI') }
    )
}

# --- Git: .gitconfig ---------------------------------------------------------------------------
function Get-GitConfigCleaned {
    # Rückgabe: @{ Lines = bereinigte Zeilen; Removed = Anzahl entfernter Zeilen }
    param([string[]]$Lines)
    $out = New-Object System.Collections.Generic.List[string]
    $section = ''; $removed = 0
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[\s*([^\s\]"]+)') { $section = $Matches[1].ToLowerInvariant() }
        $drop = $false
        if ($section -eq 'user' -and $line -match '^\s*(name|email|signingkey)\s*=') { $drop = $true }
        elseif ($section -eq 'credential' -and $line -match '^\s*username\s*=') { $drop = $true }
        if ($drop) { $removed++ } else { $out.Add($line) }
    }
    @{ Lines = $out.ToArray(); Removed = $removed }
}

function Get-GitUserLines {
    param($Ctx)
    $f = (P $Ctx.UserProfile '.gitconfig')
    if (-not (Test-Path -LiteralPath $f)) { return 0 }
    (Get-GitConfigCleaned @(Get-Content -LiteralPath $f -Encoding UTF8)).Removed
}

function Get-GitCredentialEntries {
    @(Get-StoredCredentialTargets | Where-Object { $_.Target -like 'git:*' -or $_.Target -like 'GitHub*' -or $_.Target -like 'gcm:*' -or $_.Target -like 'VSCredentials_*' })
}

# --- NuGet -------------------------------------------------------------------------------------
function Get-NuGetConfigFiles {
    param($Ctx)
    $dir = (P $Ctx.AppData 'NuGet')
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $files = @()
    $main = Join-Path $dir 'NuGet.Config'
    if (Test-Path -LiteralPath $main) { $files += $main }
    $cfg = Join-Path $dir 'config'
    if (Test-Path -LiteralPath $cfg) { $files += @(Get-ChildItem -LiteralPath $cfg -Filter '*.config' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    $files
}

function Get-NuGetSecretNodeCount {
    param([string]$File)
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($File)
        @($doc.SelectNodes('//packageSourceCredentials | //apikeys')).Count
    } catch { 0 }
}

function Remove-NuGetSecretNodes {
    param([string]$File)
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($File)
    $nodes = @($doc.SelectNodes('//packageSourceCredentials | //apikeys'))
    foreach ($n in $nodes) { [void]$n.ParentNode.RemoveChild($n) }
    if ($nodes.Count -gt 0) { $doc.Save($File) }
    $nodes.Count
}

# --- Zeilenbasierte Token-Dateien (.npmrc, .yarnrc) -----------------------------------------------
function Get-TokenFiles {
    param($Ctx)
    $u = $Ctx.UserProfile
    @(
        @{ Path = (P $u '.npmrc');      Rx = $script:NpmSecretRx }
        @{ Path = (P $u '.yarnrc');     Rx = $script:YarnSecretRx }
        @{ Path = (P $u '.yarnrc.yml'); Rx = $script:YarnSecretRx }
    ) | Where-Object { Test-Path -LiteralPath $_.Path }
}

function Get-MatchingLineCount {
    param([string]$File, [string]$Rx)
    @(Get-Content -LiteralPath $File -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match $Rx }).Count
}

# --- VS Code -----------------------------------------------------------------------------------
function Get-VsCodeFindingCount {
    param($Ctx)
    $n = 0
    foreach ($d in (Get-VsCodeDirs $Ctx)) {
        $db = (P $d 'User', 'globalStorage', 'state.vscdb')
        if (Test-Path -LiteralPath $db) { $n += [math]::Max(0, (Get-SqlCount $db "SELECT count(*) FROM ItemTable WHERE $($script:VsCodeSecretWhere)")) }
        foreach ($rel in @(@('Cookies'), @('Network', 'Cookies'))) { if (Test-Path -LiteralPath (P $d $rel)) { $n++ } }
    }
    $n
}

function Analyze {
    param($Ctx, [string[]]$Categories = @())
    $all = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $want = if ($Categories.Count -gt 0) { $Categories } else { $all }
    $scope = T 'Entwicklungstools' 'Development tools'
    $f = @()

    if ($want -contains 'vs') {
        $present = @((Get-VsTargets $Ctx) | Where-Object { Test-TargetExists $_ }).Count
        $cred = @(Get-StoredCredentialTargets | Where-Object { $_.Target -like 'VSCredentials_*' }).Count
        if (($present + $cred) -gt 0) { $f += New-Finding 'vs' $scope ((T 'Visual-Studio-/Git-Credential-Manager-Anmeldung vorhanden ({0} Ablagen)' 'Visual Studio / Git Credential Manager sign-in present ({0} locations)') -f ($present + $cred)) ($present + $cred) }
    }
    if ($want -contains 'copilot') {
        $present = @((Get-CopilotTargets $Ctx) | Where-Object { Test-TargetExists $_ }).Count
        if ($present -gt 0) { $f += New-Finding 'copilot' $scope (T 'GitHub-Copilot-/GitHub-CLI-Anmeldung vorhanden' 'GitHub Copilot / GitHub CLI sign-in present') $present }
    }
    if ($want -contains 'vscode') {
        $n = Get-VsCodeFindingCount $Ctx
        if ($n -gt 0) { $f += New-Finding 'vscode' $scope ((T 'VS-Code-Anmeldungen/Sitzungen: {0} Einträge' 'VS Code sign-ins/sessions: {0} entries') -f $n) $n }
    }
    if ($want -contains 'git') {
        $lines = Get-GitUserLines $Ctx
        $gc = Test-Path -LiteralPath (P $Ctx.UserProfile '.git-credentials')
        $cm = @(Get-GitCredentialEntries).Count
        if ($lines -gt 0) { $f += New-Finding 'git' $scope ((T 'Git-Identität in .gitconfig ({0} Zeilen: Name/E-Mail)' 'Git identity in .gitconfig ({0} lines: name/e-mail)') -f $lines) $lines }
        if ($gc) { $f += New-Finding 'git' $scope (T '.git-credentials vorhanden' '.git-credentials present') 1 }
        if ($cm -gt 0) { $f += New-Finding 'git' $scope ((T '{0} Git-Anmeldungen im Credential Manager' '{0} Git credentials in Credential Manager') -f $cm) $cm }
    }
    if ($want -contains 'ssh') {
        $files = @(Get-SshFiles $Ctx)
        if ($files.Count -gt 0) { $f += New-Finding 'ssh' $scope ((T '{0} SSH-Dateien (Schlüssel/known_hosts)' '{0} SSH files (keys/known_hosts)') -f $files.Count) $files.Count }
    }
    if ($want -contains 'nuget') {
        $n = 0; foreach ($file in (Get-NuGetConfigFiles $Ctx)) { $n += Get-NuGetSecretNodeCount $file }
        if ($n -gt 0) { $f += New-Finding 'nuget' $scope ((T 'NuGet: {0} Abschnitte mit Zugangsdaten/API-Schlüsseln' 'NuGet: {0} sections with credentials/API keys') -f $n) $n }
    }
    if ($want -contains 'npmrc') {
        $n = 0; foreach ($tf in (Get-TokenFiles $Ctx)) { $n += Get-MatchingLineCount $tf.Path $tf.Rx }
        if ($n -gt 0) { $f += New-Finding 'npmrc' $scope ((T '{0} Zeilen mit Token/Zugangsdaten (.npmrc/Yarn)' '{0} lines with tokens/credentials (.npmrc/Yarn)') -f $n) $n }
    }
    [ordered]@{ module = 'devtools'; findings = @($f); notes = @() }
}

function Clean-Category {
    param($Ctx, [string]$Cat)
    $removed = 0
    switch ($Cat) {
        'vs' {
            foreach ($x in (Get-VsTargets $Ctx)) { $removed += Remove-Target $x $Ctx }
            foreach ($c in @(Get-StoredCredentialTargets | Where-Object { $_.Target -like 'VSCredentials_*' })) { if (Remove-StoredCredential -Type $c.Type -Target $c.Target) { $removed++ } }
        }
        'copilot' { foreach ($x in (Get-CopilotTargets $Ctx)) { $removed += Remove-Target $x $Ctx } }
        'vscode' {
            foreach ($d in (Get-VsCodeDirs $Ctx)) {
                $db = (P $d 'User', 'globalStorage', 'state.vscdb')
                if (Test-Path -LiteralPath $db) {
                    Invoke-SqlExec $db "DELETE FROM ItemTable WHERE $($script:VsCodeSecretWhere); VACUUM;"
                    $removed++
                }
                foreach ($rel in @(@('Cookies'), @('Cookies-journal'), @('Network', 'Cookies'), @('Network', 'Cookies-journal'), @('Local Storage'), @('Session Storage'))) {
                    $removed += Remove-PathSafe -Path (P $d $rel) -Ctx $Ctx
                }
            }
        }
        'git' {
            $cfg = (P $Ctx.UserProfile '.gitconfig')
            if (Test-Path -LiteralPath $cfg) {
                $r = Get-GitConfigCleaned @(Get-Content -LiteralPath $cfg -Encoding UTF8)
                if ($r.Removed -gt 0) { Set-Content -LiteralPath $cfg -Value $r.Lines -Encoding UTF8; $removed += $r.Removed }
            }
            $removed += Remove-PathSafe -Path (P $Ctx.UserProfile '.git-credentials') -Ctx $Ctx
            foreach ($c in @(Get-GitCredentialEntries)) { if (Remove-StoredCredential -Type $c.Type -Target $c.Target) { $removed++ } }
        }
        'ssh' { foreach ($file in (Get-SshFiles $Ctx)) { $removed += Remove-PathSafe -Path $file -Ctx $Ctx } }
        'nuget' { foreach ($file in (Get-NuGetConfigFiles $Ctx)) { $removed += Remove-NuGetSecretNodes $file } }
        'npmrc' {
            foreach ($tf in (Get-TokenFiles $Ctx)) {
                $lines = @(Get-Content -LiteralPath $tf.Path -Encoding UTF8)
                $keep = @($lines | Where-Object { $_ -notmatch $tf.Rx })
                if ($keep.Count -ne $lines.Count) { Set-Content -LiteralPath $tf.Path -Value $keep -Encoding UTF8; $removed += ($lines.Count - $keep.Count) }
            }
        }
    }
    $removed
}

function Clean {
    param($Ctx, [string[]]$Categories = @())
    $valid = (Get-ModuleInfo).categories | ForEach-Object { $_.id }
    $scope = T 'Entwicklungstools' 'Development tools'
    $results = @()
    foreach ($cat in $Categories) {
        if ($cat -notin $valid) { continue }
        try { $results += New-Result $cat $scope $true ([int](Clean-Category $Ctx $cat)) '' }
        catch { $results += New-Result $cat $scope $false 0 $_.Exception.Message }
    }
    [ordered]@{ module = 'devtools'; results = @($results) }
}

if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }
