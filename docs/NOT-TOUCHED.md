# Was DevVM Cleanup bewusst nicht anfasst / What the tool deliberately does not touch

**Das Windows-Konto**
- Passwort, Anmeldung, Kontotyp, Gruppen, Anmeldeoptionen (PIN/Windows Hello). Das Tool ändert **nie** die Anmeldung am PC.

**Programme und Einstellungen**
- Installierte Programme und Browser-Erweiterungen selbst (nur deren *Anmelde- und Passwortdaten* auf Wunsch).
- Allgemeine Browser-Einstellungen (Startseite, Design, Suchmaschinen usw.).
- Lesezeichen – nur wenn die Kategorie «Lesezeichen» ausdrücklich gewählt wird (Standard: aus; bei Firefox nicht angeboten, weil sie dort mit dem Verlauf in `places.sqlite` liegen und beim Verlauf erhalten bleiben).
- Office-Programme, Lizenzen auf Maschinenebene (nur die Benutzer-Tokens im Profil).

**Daten**
- Dokumente, Quellcode, Repositories, Projektdateien.
- Postfach-Inhalte auf dem Server und PST-Dateien in Dokumenten. (Lokale Offline-Kopien OST und Outlook-Profile werden auf Wunsch entfernt.)
- OneDrive-Dateien: nur die Verbindung wird getrennt; bereits synchronisierte Dateien bleiben als normale lokale Dateien.
- Alles ausserhalb des Profils des angemeldeten Benutzers; Geräte-/Maschinenkonfiguration.

**Technische Schutzmassnahmen**
- Löschen nur unterhalb des Benutzerprofils; Profilwurzel, `AppData`, `Documents`, `Desktop`, `Downloads` usw. sind geschützt.
- Verknüpfungen (Junctions/Symlinks) werden nur selbst entfernt, ihr Ziel nie.
- Analyse und Geheimnis-Scan verändern nichts. «Clean» ohne ausdrückliche Kategorienwahl löscht nichts.

**Bekannte Grenzen**
- Passkeys, die in Windows Hello / im Windows-Konto gespeichert sind, liegen ausserhalb der Browser-Profile (Modul «Windows-Konten», geplant).
- Edge kann sich mit einem noch vorhandenen Windows-Geschäfts-/Schulkonto beim nächsten Start wieder anmelden (Modul «Windows-Konten», geplant).
- Chromium-«Web Data»/«Login Data» und Firefox-Dateien werden mit SQLite bereinigt (VACUUM); auf SSD/Snapshots können Reste in Dateisystem-Schattenkopien bleiben.
- Die Liste bekannter Passwortmanager-Erweiterungen ist in `modules/Browser.ps1` und lässt sich ergänzen.
