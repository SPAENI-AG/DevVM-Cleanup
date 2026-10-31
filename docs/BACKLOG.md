# Backlog / offene Punkte

## Zuerst auf Windows prüfen (nicht in der Entstehungsumgebung getestet)
- [ ] `dotnet build DevVmCleanup.slnx -c Release` (C# und XAML wurden ohne SDK geschrieben und nicht kompiliert)
- [ ] `dotnet run --project tests/DevVmCleanup.Tests -c Release` und `Invoke-Pester tests/Pester` (Pester lief nur mit einem Ersatz unter Linux; SQLite- und Registry-Tests sind Windows-only)
- [ ] Oberfläche von Hand durchklicken: Prüfungen, Analyse, Auswahl, Bereinigen, Kontrolllauf, Sprachwechsel, F1/`?`, Info-Fenster, Update-Banner
- [ ] Browser-Modul gegen echte Edge-/Chrome-/Firefox-Profile in einer Test-VM (Sync-Anmeldung entfernen: prüfen, dass kein Re-Login erfolgt; Chromium-Preferences-Schutz (MAC) beobachten)
- [ ] `powershell.exe` (5.1) und `pwsh` (7): `Remove-JsonPaths` in beiden Editionen
- [ ] Single-File-Publish mit Ordnern `modules` und `Help` neben der Exe

## Module (Reihenfolge nach Spezifikation)
- [ ] **Windows-Konten:** Geschäfts-/Schulkonten, Token-Broker (AAD.BrokerPlugin), Anmeldeinformationsverwaltung
- [ ] **Entwicklungstools:** Visual Studio (IdentityService), GitHub Copilot, VS Code Accounts, Git `user.name`/`user.email` + Credential Manager, SSH-Schlüssel, NuGet-Zugangsdaten, `.npmrc`-Tokens
- [ ] **Optional (nur wenn installiert):** device2cloud, Sophos Connect, eCatcher; Lizenz-Hinweise (z. B. Siemens Automation License Manager)
- [ ] **Spuren:** Temp, Papierkorb, zuletzt verwendet, RDP-Verlauf, PowerShell-History (PSReadLine), Ereignisprotokolle
- [ ] **Geheimnis-Scan (nur Bericht):** Git-Remotes mit Token in URL, `.git-credentials`, `.env`, `.pfx`, Passwörter in `appsettings.json` o. ä. – UI-Schritt «5. Geheimnis-Scan» ergänzen
- [ ] Passkeys (Chrome Google Password Manager / Windows Hello) prüfen

## Verbesserungen
- [ ] Preview-Texte nach Sprachwechsel neu laden (aktuell zeigt die Vorschau die Sprache der Analyse)
- [ ] Export des Logs / Berichts
- [ ] Code-Signing (Secrets `SIGN_PFX_BASE64` / `SIGN_PFX_PASSWORD` im Repository anlegen)
- [ ] Screenshots für README (nur mit Beispieldaten)
