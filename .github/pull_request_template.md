## Änderung

<!-- Was und warum? -->

## Checkliste
- [ ] `dotnet build DevVmCleanup.slnx -c Release`, `dotnet run --project tests/DevVmCleanup.Tests -c Release` und `Invoke-Pester tests/Pester` laufen grün
- [ ] Neue sichtbare Texte in `Strings.cs` (DE und EN), neue Hilfe-Anker in beiden Hilfeseiten
- [ ] Modul-Änderung: Test in `tests/Pester`, `docs/NOT-TOUCHED.md` und `CHANGELOG.md` ergänzt
- [ ] Keine Zugangsdaten, Tokens, Kundendaten, internen Pfade/Hostnamen oder echten Konten enthalten (Testdaten sind erfunden)
