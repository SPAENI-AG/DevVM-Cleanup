# Sicherheit

Sicherheitslücken bitte **nicht** als öffentliches Issue melden, sondern per E-Mail an **support@elektro-spaeni.ch**
(Betreff «DevVM Cleanup – Sicherheit»). Bitte keine Zugangsdaten, Tokens, Kundendaten oder Profildateien mitsenden.

Hinweise zum Programm:
- Es läuft mit Administratorrechten (Anwendungsmanifest), weil es Registry und Profildaten bereinigt.
- Es **löscht Daten dauerhaft** – nur in Kopien/VMs verwenden. Das Windows-Konto wird nie verändert.
- Löschen ist auf das Profil des angemeldeten Benutzers begrenzt (Wurzel- und Standardordner sind geschützt, Verknüpfungen werden nicht verfolgt).
- Es speichert keine Passwörter. Logs und Fehlermeldungen werden gefiltert (keine Passwörter/Tokens im Klartext).
- Der Geheimnis-Scan (geplant) ist reiner Bericht und löscht nichts.
- Einziger Netzwerkzugriff: optionale Update-Prüfung bei `api.github.com` (höchstens alle 20 Stunden, ohne Nutzungsdaten). Keine Telemetrie.
- Release-Dateien haben eine SHA-256-Prüfsumme; die Exe ist ohne Code-Signing-Zertifikat unsigniert.

---

# Security (English)

Please do **not** report vulnerabilities as public issues. Send an e-mail to **support@elektro-spaeni.ch**
(subject “DevVM Cleanup – Security”) without credentials, tokens, customer data or profile files.

The program runs with administrator rights, **deletes data permanently** (use on copies/VMs only), never changes the Windows account,
filters logs and error messages, does not use telemetry, and only contacts `api.github.com` for the optional update check.
