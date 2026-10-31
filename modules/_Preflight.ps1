# _Preflight.ps1 – Prüfdaten für die Vorab-Prüfungen (nur lesen). Ausgabe: JSON.
#   * Hersteller/Modell laut WMI (Erkennung virtueller Maschinen: Hyper-V, VMware, VirtualBox, KVM/QEMU, Xen, Parallels)
#   * Administratorrechte
#   * Läuft das Programm im Profil des angemeldeten Benutzers? (Besitzer von explorer.exe = Prozessbenutzer)
# Der Windows-Account wird nicht verändert.
param()

$cs = $null
try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$interactive = $null
try {
    $owner = (Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1 |
        Invoke-CimMethod -MethodName GetOwner)
    if ($owner.User) { $interactive = "$($owner.Domain)\$($owner.User)" }
} catch { }

$result = [ordered]@{
    manufacturer    = if ($cs) { [string]$cs.Manufacturer } else { '' }
    model           = if ($cs) { [string]$cs.Model } else { '' }
    isAdmin         = [bool]$isAdmin
    currentUser     = $identity.Name
    interactiveUser = $interactive
    computerName    = $env:COMPUTERNAME
    profilePath     = $env:USERPROFILE
}
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
[Console]::Out.WriteLine((ConvertTo-Json -InputObject $result -Compress))
