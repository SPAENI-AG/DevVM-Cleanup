# Backlog / offene Punkte

## Zuerst auf Windows prüfen (nicht in der Entstehungsumgebung getestet)
- [ ] `dotnet build DevVmCleanup.slnx -c Release` (C# und XAML wurden ohne SDK geschrieben und nicht kompiliert)
- [ ] `dotnet run --project tests/DevVmCleanup.Tests -c Release` und `Invoke-Pester tests/Pester` (Pester lief nur mit einem Ersatz unter Linux; SQLite- und Registry-Tests sind Windows-only)
- [ ] Oberfläche von Hand durchklicken: Prüfungen, Analyse, Auswahl, Bereinigen, Kontrolllauf, Sprachwechsel, F1/`?`, Info-Fenster, Update-Banner
- [ ] Browser-Modul gegen echte Edge-/Chrome-/Firefox-Profile in einer Test-VM (Sync-Anmeldung entfernen: prüfen, dass kein Re-Login erfolgt; Chromium-Preferences-Schutz (MAC) beobachten)
- [ ] `powershell.exe` (5.1) und `pwsh` (7): `Remove-JsonPaths` in beiden Editionen
- [ ] Single-File-Publish mit Ordnern `modules` und `Help` neben der Exe

## Module – umgesetzt, auf echten Systemen zu prüfen
- [ ] **Windows-Konten:** Registry-Pfade (IdentityCRL, WorkplaceJoin, `Windows\CurrentVersion\AAD`) und Broker-Ordner gegen echte Windows-10/11-Profile prüfen; Verhalten nach dem Entfernen (Office/Edge/Teams fragen neu an?)
- [ ] **Entwicklungstools:** VS-Code-`state.vscdb`-Schlüssel (`secret://…`, `*.auth*`) und VS-`VSCommon`-Pfade je Version prüfen; Git Credential Manager (`gcm:`-Ziele)
- [ ] **Optional:** echte Ordner von device2cloud, Sophos Connect, eCatcher ermitteln (heute bestmögliche Namen) und Prozessnamen ergänzen
- [ ] **Spuren:** Ereignisprotokolle (Berechtigungen einzelner Protokolle), Temp-Ordner mit gesperrten Dateien, Papierkorb über alle Laufwerke
- [ ] **Geheimnis-Scan:** Laufzeit auf grossen Laufwerken, zusätzliche Muster (AWS/Azure-Schlüssel, `.npmrc` in Repos, `*.publishsettings`)

## Weitere Ideen
- [ ] Docker-/Cloud-CLI-Anmeldungen (`~/.docker`, `~/.aws`, `~/.azure`, `~/.kube`), KeePass-/Passwortmanager-Desktopdaten, `~/.config/gh`
- [ ] SSH-`config` optional bereinigen
- [ ] Passkeys (Chrome Google Password Manager) prüfen

## Verbesserungen
- [ ] Preview-Texte nach Sprachwechsel neu laden (aktuell zeigt die Vorschau die Sprache der Analyse)
- [ ] Export des Logs / Berichts
- [ ] Code-Signing (Secrets `SIGN_PFX_BASE64` / `SIGN_PFX_PASSWORD` im Repository anlegen)
- [ ] Screenshots für README (nur mit Beispieldaten)
