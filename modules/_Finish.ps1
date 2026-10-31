# _Finish.ps1 – optionaler Abschluss: Computername ändern, Sysprep, Herunterfahren.
# Das Windows-Konto (Passwort, Anmeldung) wird NICHT verändert.
#   -Action Rename   -NewName <Name>      Computername ändern (wirkt nach Neustart)
#   -Action Sysprep                       Sysprep /generalize /oobe /shutdown  (bewusste Option, entfernt u. a. die Computer-SID)
#   -Action Shutdown                      Herunterfahren in 10 Sekunden
param(
    [Parameter(Mandatory)][ValidateSet('Rename', 'Sysprep', 'Shutdown')][string]$Action,
    [string]$NewName = ''
)
$ErrorActionPreference = 'Stop'
$ok = $true; $message = ''
try {
    switch ($Action) {
        'Rename' {
            if ($NewName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') { throw 'Ungültiger Computername (1-15 Zeichen: Buchstaben, Ziffern, Bindestrich).' }
            Rename-Computer -NewName $NewName -Force
        }
        'Sysprep' {
            $exe = Join-Path $env:SystemRoot 'System32\Sysprep\sysprep.exe'
            if (-not (Test-Path -LiteralPath $exe)) { throw 'sysprep.exe nicht gefunden.' }
            Start-Process -FilePath $exe -ArgumentList '/generalize', '/oobe', '/shutdown', '/quiet'
        }
        'Shutdown' { & shutdown.exe /s /t 10 /c 'DevVM Cleanup' }
    }
} catch { $ok = $false; $message = $_.Exception.Message }
[Console]::Out.WriteLine((ConvertTo-Json -InputObject ([ordered]@{ action = $Action; ok = $ok; message = $message }) -Compress))
