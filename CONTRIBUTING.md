# Mitarbeit / Contributing

- Issues und Pull Requests sind willkommen. **Keine Zugangsdaten, Tokens, Kundendaten, Hostnamen oder Profildateien** in Issues, Logs, Testdaten oder Screenshots. Testdaten sind frei erfunden (`alice@example.com`).
- Sicherheitslücken: siehe `SECURITY.md`.
- Sprache: UI-Texte, Doku und Logs Deutsch, UI zusätzlich Englisch über `Strings.cs`; Code-Bezeichner Englisch.
- Jeder sichtbare Text läuft über `Loc` (`Strings.cs`, DE und EN). Neue Hilfe-Anker in `de.html` **und** `en.html`.
- Vor dem Pull Request:
  ```
  dotnet build DevVmCleanup.slnx -c Release
  dotnet run --project tests/DevVmCleanup.Tests -c Release
  Invoke-Pester tests/Pester -Output Detailed
  ```
- Firmenname immer **SPÄNI Elektro-Mechanik AG**.

## Neues Modul
Ein Modul ist **eine Datei** `modules/<Name>.ps1` – ohne neu zu kompilieren. Vorlage: `modules/Office.ps1`.

1. Kopf: `param([string]$Action, [string]$Categories, [string]$ContextJson, [string]$Lang)` und `. (Join-Path $PSScriptRoot '_Common.ps1')`.
2. `Get-ModuleInfo` → `id`, `name` (de/en), `processes` (Prozessnamen, die die Daten sperren), `categories` (`id`, `de`, `en`, `default`).
3. `Analyze -Ctx -Categories` → `{ module, findings:[{category, scope, label, count}] }`. **Nur lesen.** Leere Kategorienliste = alle.
4. `Clean -Ctx -Categories` → `{ module, results:[{category, scope, ok, removed, message}] }`. Nur gewählte Kategorien; leere Liste = nichts löschen.
5. Löschen ausschliesslich über `Remove-PathSafe` / `Remove-RegKeySafe` (bleibt im Kontext, schützt Wurzeln und Standardordner).
6. Letzte Zeile: `if ($Action) { Invoke-ModuleMain -Action $Action -Categories $Categories -ContextJson $ContextJson -Lang $Lang }`.
7. **Nie Passwörter oder Tokens ausgeben** – nur Kategorien, Zähler und Anzeigenamen. Texte zweisprachig über `T 'deutsch' 'english'`.
8. Pester-Test in `tests/Pester` mit erfundenen Testdaten (Temp-Ordner via `$TestDrive`, Registry nur unter `HKCU:\Software\DevVmCleanupTest`).
9. `CHANGELOG.md`, README-Tabelle und `docs/NOT-TOUCHED.md` aktualisieren.

Nicht ins Repo gehören: echte Konten, Tokens, interne Pfade/Hostnamen/UNC-Namen, Kundendaten.
