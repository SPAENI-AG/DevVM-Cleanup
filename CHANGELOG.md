# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Der Release-Workflow übernimmt den Abschnitt der jeweiligen Version als Release-Notiz.

## [Unveröffentlicht]

## [0.1.0] - 2026-10-31

### Neu
- Grundgerüst im SPÄNI-Hausstil: WPF (.NET 10), UI-freie Bibliothek `DevVmCleanup.Core`, DE/EN live umschaltbar, Hilfe im Browser (F1), Einstellungen, Info-Fenster, Update-Hinweis über GitHub Releases.
- Ablauf: Prüfungen (VM / Administrator / Profil), Programme erkennen und schliessen, Analyse mit Vorschau, Auswahl per Checkbox, Bereinigen, Kontrolllauf, optional Computername / Sysprep / Herunterfahren.
- Module als lesbare PowerShell-Skripte (`Analyze`, `Clean`, JSON-Ausgabe), auch ohne Oberfläche nutzbar; neue Module = neue Datei.
- Modul **Office / M365**: Identitäten, Lizenz-Tokens, Outlook-Profile, OneDrive trennen, Teams-Cache.
- Modul **Browser**: Edge, Chrome, Brave, Vivaldi, Opera, Firefox, alle Profile, zehn Kategorien einzeln wählbar (plus optional Lesezeichen).
- Log ohne Passwörter/Tokens (Filter), Logdatei unter `%APPDATA%\DevVM-Cleanup\logs`.
- Pester-Tests mit erfundenen Testdaten und Konsolen-Testlauf für die C#-Logik.
