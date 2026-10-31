# DevVM Cleanup

Windows-Tool (WPF, Administratorrechte) zum **Bereinigen von Entwicklungs-VMs** vor der Weitergabe: überall abmelden, keine Zugangsdaten, Tokens oder Spuren des Einrichters zurücklassen. Die Kopien arbeiten danach im **selben Windows-Profil** weiter.

*English: Windows tool (WPF, needs administrator rights) that cleans development VMs before they are handed over: sign out everywhere and leave no credentials, tokens or traces of the person who set the VM up. The copies continue to be used in the **same Windows profile**. German and English UI, switchable at runtime.*

**Nur bereinigen – kein Ersteinrichtungs-Modus. Das Windows-Konto selbst (Passwort, Anmeldung) wird nie verändert.**
*Cleanup only – no first-time setup. The Windows account itself (password, sign-in) is never touched.*

## Ablauf / Workflow
1. **Prüfungen:** läuft in einer VM (WMI-Hersteller Hyper-V/VMware/…; nur mit bewusster Option übersteuerbar), Administratorrechte, Profil des angemeldeten Benutzers
2. **Betroffene Programme** erkennen und nach Bestätigung schliessen (inkl. Hintergrundprozesse, z. B. Edge Startup Boost)
3. **Analyse mit Vorschau** pro Modul («gefunden: …») – gelöscht wird erst nach Bestätigung
4. **Module/Kategorien per Checkbox** wählen, bereinigen, Log (nie Passwörter/Tokens im Klartext)
5. **Geheimnis-Scan** (nur Bericht)
6. **Kontrolllauf** muss «sauber» melden
7. Optional: Computernamen ändern oder Sysprep, dann Herunterfahren

## Module
| Modul | Inhalt | Stand |
|---|---|---|
| **Office / M365** | Office-Identitäten, Lizenz-Tokens, Outlook-Profile, OneDrive trennen, Teams-Cache | ✔ |
| **Browser** | Edge, Chrome, Brave/Opera/Vivaldi, Firefox – **alle Profile**; einzeln wählbar: Sync-Anmeldung, Passwörter/Passkeys, Cookies, Website-Speicher, Autofill, Sitzungen/Tabs, Verlauf, Downloadliste, Cache, Passwortmanager-Erweiterungsdaten, (optional) Lesezeichen | ✔ |
| **Windows-Konten** | verbundene Geschäfts-/Schulkonten, Token-Broker (AAD.BrokerPlugin), Anmeldeinformationsverwaltung (Domänen-/Azure-AD-Mitgliedschaft bleibt unverändert, nur Hinweis) | ✔ |
| **Entwicklungstools** | Visual Studio, GitHub Copilot/CLI, VS Code, Git (Identität, Anmeldedaten), SSH-Schlüssel, NuGet, `.npmrc`/Yarn-Tokens | ✔ |
| **Optional** | device2cloud, Sophos Connect, eCatcher (nur wenn vorhanden); Lizenz-Hinweise (z. B. Siemens Automation License Manager) | ✔ |
| **Spuren** | Temp, Papierkorb, Zuletzt verwendet, RDP-Verlauf, PowerShell-History, Ereignisprotokolle | ✔ |
| **Geheimnis-Scan** | nur Bericht, löscht nie: Git-Remotes mit Token, `.git-credentials`, `.env`, `.pfx`, Passwörter in `appsettings.json` | ✔ |

Module sind **lesbare PowerShell-Skripte** im Ordner `modules` (ein Skript pro Modul, Funktionen `Analyze` und `Clean`, Ausgabe JSON). Sie lassen sich auch ohne Oberfläche nutzen, und ein neues Modul ist nur eine neue Datei – ohne neu zu kompilieren:

```powershell
powershell -File modules\Browser.ps1 -Action Analyze -Lang de
powershell -File modules\Browser.ps1 -Action Clean -Categories signin,passwords,cookies
```

Was das Tool bewusst **nicht** anfasst: siehe [`docs/NOT-TOUCHED.md`](docs/NOT-TOUCHED.md).

## Download und Nutzung
Neueste Version unter **Releases**, zwei Varianten (je mit `.sha256`-Prüfsumme, .NET ist enthalten):

- **Installer** `DevVM-Cleanup_<version>_Setup.exe`: installiert nach `Program Files` (Startmenü-Eintrag, Deinstallation über «Apps & Features»). Ein neueres Setup ersetzt die installierte Version (Update). Einstellungen und Logs unter `%APPDATA%\DevVM-Cleanup` bleiben erhalten.
- **Portabel** `DevVM-Cleanup_<version>_win-x64.zip`: entpacken (die Ordner `modules` und `Help` bleiben neben der `.exe`), `DevVM-Cleanup.exe` starten. Nichts bleibt auf dem System zurück.

Beide Varianten fragen beim Start nach Administratorrechten. Der Update-Hinweis in der App bietet bei einer installierten Version das Setup an, bei der portablen das ZIP; die App aktualisiert sich nie von selbst.
Unsignierte Exe: SmartScreen → «Weitere Informationen» → «Trotzdem ausführen». Prüfsumme prüfen (Setup oder ZIP):

```powershell
(Get-FileHash .\DevVM-Cleanup_<version>_Setup.exe -Algorithm SHA256).Hash.ToLower()
```

**Vorsicht:** Das Tool löscht Daten dauerhaft. Nur in einer Kopie/VM verwenden, nicht auf einem produktiven Arbeitsplatz.
Das Programm greift nur für die optionale Update-Prüfung auf das Netzwerk zu (GitHub, höchstens alle 20 Stunden, keine Nutzungsdaten). Keine Telemetrie.

## Build
Voraussetzung: .NET 10 SDK, Windows (die Logikbibliothek und ihre Tests laufen auch unter Linux), Pester 5 für die Modul-Tests.
```
dotnet build DevVmCleanup.slnx -c Release
dotnet run --project tests/DevVmCleanup.Tests -c Release
Invoke-Pester tests/Pester -Output Detailed
```
Aufbau: `src/DevVmCleanup.Core` (UI-freie Logik), `src/DevVmCleanup.App` (WPF), `modules/` (PowerShell-Module), `tests/`.

## Doku
- [`CLAUDE.md`](CLAUDE.md) – Projektkontext, Architektur, Modul-Vertrag, Konventionen
- [`docs/NOT-TOUCHED.md`](docs/NOT-TOUCHED.md) – was das Tool bewusst nicht anfasst
- [`docs/BACKLOG.md`](docs/BACKLOG.md) – offene Punkte
- [`CHANGELOG.md`](CHANGELOG.md), [`SECURITY.md`](SECURITY.md), [`CONTRIBUTING.md`](CONTRIBUTING.md)

## English summary
- **Checks:** runs inside a VM (WMI manufacturer; override only by deliberate option), administrator rights, profile of the signed-in user.
- **Analysis first:** each module previews “found: …”; nothing is deleted until you confirm. Modules/categories are chosen by checkbox; the log never contains passwords/tokens.
- **Verification run** must report “clean”. Optional: rename computer or Sysprep, then shut down.
- **Modules** are readable PowerShell scripts in `modules\` (`Analyze`, `Clean`, JSON output) and can be used without the UI. A new module is a new file – no recompilation.
- **Download:** see *Releases* (self-contained single file, ZIP + SHA-256). No telemetry; the only network access is the optional update check against GitHub.
- **Warning:** the tool deletes data permanently – use it on a copy/VM only.

## Support
SPÄNI Elektro-Mechanik AG · [support.elektro-spaeni.ch](https://support.elektro-spaeni.ch) · support@elektro-spaeni.ch

Lizenz: MIT (siehe `LICENSE`) · © SPÄNI Elektro-Mechanik AG
