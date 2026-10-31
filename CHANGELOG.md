# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Der Release-Workflow übernimmt den Abschnitt der jeweiligen Version als Release-Notiz.

## [Unveröffentlicht]

## [0.2.0] - 2026-10-31

### Neu
- Modul **Windows-Konten**: verbundene Geschäfts-/Schulkonten, Token-Broker (AAD.BrokerPlugin), Anmeldeinformationsverwaltung. Die Domänen-/Azure-AD-Mitgliedschaft und das lokale Windows-Konto bleiben unverändert (nur Hinweis).
- Modul **Entwicklungstools**: Visual Studio, GitHub Copilot/CLI, VS-Code-Konten, Git (Identität, Anmeldedaten), SSH-Schlüssel, NuGet-Zugangsdaten, `.npmrc`/Yarn-Tokens.
- Modul **Optionale Programme**: device2cloud, Sophos Connect, eCatcher (nur wenn vorhanden) plus Lizenz-Hinweise (z. B. Siemens Automation License Manager, nichts verändert).
- Modul **Spuren**: Temp, Papierkorb, Zuletzt verwendet, RDP-Verlauf, PowerShell-History, Ereignisprotokolle.
- Modul **Geheimnis-Scan** (nur Bericht, löscht nie): Git-Remotes mit Token, `.git-credentials`, `.env`, Zertifikate/private Schlüssel, Passwörter in `appsettings.json`/`secrets.json`; zusätzliche Scan-Ordner in den Einstellungen.
- Module können Hinweise (`notes`) und das Kennzeichen `reportOnly` liefern; die Oberfläche zeigt Hinweise unter dem Modul und kennt den neuen Schritt «5. Geheimnis-Scan».
- Löschschutz: `ProgramData` als erlaubte Wurzel, geschützte Standardordner, Verknüpfungen werden nie verfolgt.

## [0.1.0] - 2026-10-31

### Neu
- Grundgerüst im SPÄNI-Hausstil: WPF (.NET 10), UI-freie Bibliothek `DevVmCleanup.Core`, DE/EN live umschaltbar, Hilfe im Browser (F1), Einstellungen, Info-Fenster, Update-Hinweis über GitHub Releases.
- Ablauf: Prüfungen (VM / Administrator / Profil), Programme erkennen und schliessen, Analyse mit Vorschau, Auswahl per Checkbox, Bereinigen, Kontrolllauf, optional Computername / Sysprep / Herunterfahren.
- Module als lesbare PowerShell-Skripte (`Analyze`, `Clean`, JSON-Ausgabe), auch ohne Oberfläche nutzbar; neue Module = neue Datei.
- Modul **Office / M365**: Identitäten, Lizenz-Tokens, Outlook-Profile, OneDrive trennen, Teams-Cache.
- Modul **Browser**: Edge, Chrome, Brave, Vivaldi, Opera, Firefox, alle Profile, zehn Kategorien einzeln wählbar (plus optional Lesezeichen).
- Log ohne Passwörter/Tokens (Filter), Logdatei unter `%APPDATA%\DevVM-Cleanup\logs`.
- Pester-Tests mit erfundenen Testdaten und Konsolen-Testlauf für die C#-Logik.
