# CLAUDE.md – DevVM Cleanup

Kontext für Claude Code. Sprache im Projekt: **Deutsch** (UI-Texte, Logs, Doku; UI zusätzlich Englisch, README DE+EN). Code-Bezeichner Englisch.
Aufbau, Design und Technik **wie `d2c-VPN-Switch`** (WPF / .NET 10, SPÄNI-Hausstil, Skill `spaeni-wpf-app-layout`).

> **ACHTUNG: Dieses Repository ist (später) ÖFFENTLICH auf GitHub.** Immer beachten:
> keine internen Pfade, Hostnamen, Server-/UNC-Namen, Kundendaten, Zugangsdaten, Tokens, echten Konten oder
> Mail-Adressen (ausser den fixen Firmen-/Supportangaben unten) in Code, Tests, Testdaten, Doku, Screenshots,
> Commit-Messages. Testdaten sind frei erfunden (`alice@example.com`). Vor dem ersten Push und vor jedem Release:
> Repo nach internen Daten, Hostnamen und Passwörtern durchsuchen (siehe „Veröffentlichungs-Check“).

## Zweck

Entwicklungs-VMs werden einmal eingerichtet und als Kopien an Programmierer verteilt. Diese arbeiten im
**selben Windows-Profil** weiter. Vor dem Verteilen muss die VM bereinigt werden: überall abmelden, keine
Zugangsdaten/Tokens/Spuren des Einrichters zurücklassen.

- **Nur bereinigen** – kein Ersteinrichtungs-Modus.
- Das **Windows-Konto selbst wird NICHT angefasst** (kein Passwortwechsel, keine Änderung an der Anmeldung).
- Generisch für öffentliche Nutzer: keine internen Pfade/Hostnamen/Kundendaten.

## Eckdaten

| Was | Wert |
|---|---|
| Name | DevVM Cleanup |
| Firma | SPÄNI Elektro-Mechanik AG (genau so; nie „Späni“/„SPAENI“ ausser in URLs/Mail) |
| Entwickler (**nur** im Info-Fenster) | Ralph Kessler, ralph.kessler@outlook.com |
| Support | support@elektro-spaeni.ch / https://support.elektro-spaeni.ch |
| Lizenz | MIT, © SPÄNI Elektro-Mechanik AG |
| Sprachen | DE/EN (live umschaltbar) |
| GitHub | `SPAENI-AG/DevVM-Cleanup` |

## Architektur

- **WPF**, `net10.0-windows`, SPÄNI-Stil (Styles/Footer/Menü/Info/Hilfe/Settings/Update-Banner aus dem Skill).
- **UI-freie Logik** in `net10.0`-Klassenbibliothek `DevVmCleanup.Core` (läuft auch unter Linux-CI).
- **Module = lesbare PowerShell-Skripte** in `modules/` (ein Skript pro Modul) mit den Funktionen
  `Analyze` und `Clean` (plus `Get-ModuleInfo`), **Ausgabe JSON** auf stdout. Die UI ruft sie auf; die Module sind
  auch ohne UI nutzbar. **Neue Module = neue Datei in `modules/`, ohne neu zu kompilieren** (UI baut Auswahl aus
  `Get-ModuleInfo`). Dateien mit `_`-Präfix (`_Common.ps1`, `_Preflight.ps1`, `_Finish.ps1`) sind Hilfsskripte, keine Module.
- **Pester-Tests** (`tests/Pester`) mit erfundenen Testdaten (keine echten Konten). Dazu ein Konsolen-Testlauf
  `tests/DevVmCleanup.Tests` für die C#-Logik (Übersetzungen, Hilfe-Anker, Parser, Redaktion).
- Verteilung über **GitHub Releases** (self-contained Einzeldatei, ZIP + SHA-256), Update-Hinweis in der App.
  **Keine Telemetrie, keine anderen Verbindungen** als die optionale Update-Prüfung.

```
Directory.Build.props           Version (einzige Stelle), GitHubRepository, Firma, Lizenz
DevVmCleanup.slnx
src/DevVmCleanup.Core/          UI-frei (net10.0)
  ModuleRunner.cs               findet/startet Modul-Skripte (powershell.exe), parst JSON
  Models.cs                     ModuleInfo, Finding, CleanResult, Preflight-Ergebnis
  Preflight.cs                  Bewertung VM / Admin / Profil (Daten kommen aus modules/_Preflight.ps1)
  ProcessCloser.cs              laufende Programme erkennen und schliessen
  LogRedactor.cs                entfernt Passwörter/Tokens aus Logzeilen
  Loc.cs, Strings.cs            DE/EN
  AppSettings.cs, UpdateChecker.cs, HelpServer.cs
src/DevVmCleanup.App/           WPF (App.xaml Styles, MainWindow, Views/SettingsView, AboutWindow, Help/)
modules/                        PowerShell-Module (Office, Browser …) + _Common.ps1, _Preflight.ps1, _Finish.ps1
tests/Pester/                   Pester 5 Tests
tests/DevVmCleanup.Tests/       Konsolen-Testlauf (C#)
docs/                           Notgrenzen, Backlog
```

## Modul-Vertrag (PowerShell)

Aufruf: `powershell -File modules\Office.ps1 -Action Info|Analyze|Clean [-Categories a,b] [-Lang de|en] [-ContextJson '{...}']`
Ohne `-Action` (Dot-Sourcing, z. B. Pester) passiert nichts ausser dem Laden der Funktionen.

- `Get-ModuleInfo` → `{ id, name:{de,en}, processes:[…], categories:[{id, de, en, default}] }`
- `Analyze -Ctx -Categories -Lang` → `{ module, findings:[{category, label, count, detail}] }` (nur lesen, löscht nichts)
- `Clean -Ctx -Categories -Lang` → `{ module, results:[{category, ok, removed, message}] }`
- `-Ctx`/`-ContextJson` übersteuert Pfade (`UserProfile`, `AppData`, `LocalAppData`, `Hkcu`) – so testen Pester-Tests
  gegen Temp-Ordner und einen Test-Registry-Zweig statt gegen das echte Profil.
- **Ausgaben und Logs enthalten nie Passwörter/Tokens im Klartext.** Analyse darf Konto-Anzeigenamen (E-Mail) zeigen, damit
  der Anwender sieht, „angemeldet als …“; der Log (`Clean`) nennt nur Kategorien und Anzahlen.
- Löschen nur innerhalb der Ctx-Wurzeln (`Remove-PathSafe`); nie ganze Wurzeln, nie das Windows-Konto.

## Ablauf der App

1. Prüfungen: läuft in VM (WMI-Hersteller Hyper-V/VMware/…; nur mit bewusster Option übersteuerbar), Adminrechte,
   läuft im Profil des aktuellen Benutzers (Interaktiv angemeldeter Benutzer = Prozessbenutzer).
2. Betroffene Programme erkennen und nach Bestätigung schliessen (inkl. Hintergrundprozesse, z. B. Edge Startup Boost).
3. Analyse mit Vorschau pro Modul („gefunden: …“) – Standard; gelöscht wird erst nach Bestätigung.
4. Module/Kategorien per Checkbox wählen, bereinigen, Log (nie Passwörter/Tokens).
5. Geheimnis-Scan: nur Bericht, löscht nichts (Modul offen, siehe Backlog).
6. Kontrolllauf muss „sauber“ melden (erneute Analyse der gewählten Kategorien ohne Funde).
7. Optional: Computernamen ändern oder Sysprep; dann Herunterfahren (`modules/_Finish.ps1`).

## Stand der Module

| Modul | Stand |
|---|---|
| Office/M365 (`Office.ps1`) | umgesetzt: Identitäten, Lizenz-Tokens, Outlook-Profile, OneDrive trennen, Teams-Cache |
| Browser (`Browser.ps1`) | umgesetzt: Edge, Chrome, Brave/Opera/Vivaldi (Chromium), Firefox; alle Profile; 10 Kategorien einzeln wählbar |
| Windows-Konten | offen (Geschäfts-/Schulkonten, AAD.BrokerPlugin, Anmeldeinformationsverwaltung) |
| Entwicklungstools | offen (VS IdentityService, Copilot, VS Code, Git, SSH, NuGet, .npmrc) |
| Optional (device2cloud, Sophos Connect, eCatcher, Lizenz-Hinweise) | offen |
| Spuren | offen (Temp, Papierkorb, zuletzt verwendet, RDP, PSReadLine, Ereignisprotokolle) |
| Geheimnis-Scan | offen (nur Bericht) |

## Build und Test

```
dotnet build DevVmCleanup.slnx -c Release
dotnet run --project tests/DevVmCleanup.Tests -c Release
pwsh -Command "Invoke-Pester tests/Pester -Output Detailed"        # Pester 5
```
Ohne UAC zum Ausprobieren: PowerShell `$env:__COMPAT_LAYER='RunAsInvoker'; & .\src\DevVmCleanup.App\bin\Release\net10.0-windows\DevVM-Cleanup.exe`
(Admin-Funktionen/Prüfung schlagen dann fehl.)

Release: `<Version>` in `Directory.Build.props` erhöhen, Abschnitt in `CHANGELOG.md`, Tag `vX.Y.Z` → Workflow `release.yml`.

## Konventionen

- Code-Behind, Steuerelementnamen mit Typpräfix (`tb_`, `bt_`, `cb_`, `chk_`, `mi_`, `tc_`, `ti_`).
- **Jeder sichtbare Text über `Loc`** (`{l:Tr Key}` / `Loc.T("Key", args)`), DE und EN in `Strings.cs`. Modul-Texte kommen
  zweisprachig aus den Skripten (`-Lang`).
- Firmenname immer **SPÄNI Elektro-Mechanik AG**; Entwicklername nur im Info-Fenster.
- Langlaufende Aktionen in `Task.Run`; nach Bereinigung immer Kontrolllauf anbieten.
- Version nur in `Directory.Build.props`.
- Neues Modul: neue Datei `modules/<Name>.ps1`, Pester-Test in `tests/Pester`, Eintrag in `CHANGELOG.md`/README-Tabelle,
  Eintrag in `docs/NOT-TOUCHED.md` falls es bewusst etwas ausspart.

## Veröffentlichungs-Check (vor erstem Push / jedem Release)

```
grep -rniE "elektro-spaeni|späni|\\\\\\\\[a-z0-9_-]+\\\\|password\s*[:=]|token|secret" --exclude-dir=.git .
```
Treffer prüfen: erlaubt sind nur die Firmen-/Supportangaben aus der Tabelle oben und erfundene Testwerte.
`gitleaks`/`git secrets` zusätzlich, falls verfügbar.

## Teststatus / Offene Punkte

- Siehe `docs/BACKLOG.md`. In der Entstehungsumgebung stand kein .NET-SDK/Windows zur Verfügung: C# und WPF sind **nicht
  kompiliert**, die Skripte wurden nur per PowerShell-Parser und Datei-Smoketests (Linux) geprüft. Zuerst auf Windows
  `dotnet build`, Pester und die Checkliste aus `docs/BACKLOG.md` durchlaufen.
