// Einfacher Testlauf ohne Framework: dotnet run --project tests/DevVmCleanup.Tests -c Release
// Prüft Übersetzungen, Hilfe-Anker, Prüfungs-Bewertung, Log-Filter, Modul-Schnittstelle und Update-Parser. Exitcode 1 bei Fehlern.
// Testdaten sind frei erfunden (example.com), keine echten Konten.
using System.Text.Json;
using System.Text.RegularExpressions;
using DevVmCleanup.Core;

var failures = new List<string>();
void Check(bool ok, string msg) { if (!ok) failures.Add(msg); }

// Repository-Wurzel finden
var root = AppContext.BaseDirectory;
while (root != null && !File.Exists(Path.Combine(root, "Directory.Build.props"))) root = Path.GetDirectoryName(root);
if (root == null) { Console.Error.WriteLine("Repository-Wurzel nicht gefunden"); return 1; }

// 1. Übersetzungen: Platzhalter in DE und EN identisch, keine leeren Texte
static string[] Placeholders(string s) => Regex.Matches(s, @"\{\d+\}").Select(m => m.Value).Distinct().OrderBy(x => x).ToArray();
foreach (var (key, t) in Strings.Table)
{
    Check(t.De.Length > 0 && t.En.Length > 0, $"Leerer Text: {key}");
    Check(Placeholders(t.De).SequenceEqual(Placeholders(t.En)), $"Platzhalter DE/EN verschieden: {key}");
}

// 2. Alle im Code/XAML verwendeten Schlüssel existieren
var srcFiles = Directory.EnumerateFiles(Path.Combine(root, "src"), "*.*", SearchOption.AllDirectories)
    .Where(f => (f.EndsWith(".cs") || f.EndsWith(".xaml")) && !f.EndsWith("Loc.cs") && !f.EndsWith("TrExtension.cs")
                && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")).ToList();
var used = new HashSet<string>();
foreach (var f in srcFiles)
{
    var text = File.ReadAllText(f);
    foreach (Match m in Regex.Matches(text, @"Loc\.T\(\s*""([A-Za-z_]+)""\s*[,)]")) used.Add(m.Groups[1].Value);
    foreach (Match m in Regex.Matches(text, @"\{l:Tr\s+([A-Za-z_]+)\}")) used.Add(m.Groups[1].Value);
}
used.UnionWith(new[] { "Chk_AdminOk", "Chk_AdminFail" });   // bedingt gewählte Schlüssel
foreach (var k in used) Check(Strings.Table.ContainsKey(k), $"Schlüssel fehlt in Strings: {k}");
var unused = Strings.Table.Keys.Except(used).ToList();   // nur Hinweis, kein Fehler
if (unused.Count > 0) Console.WriteLine("Hinweis: ungenutzte Schlüssel: " + string.Join(", ", unused));

// 3. Hilfe-Anker
var help = Path.Combine(root, "src", "DevVmCleanup.App", "Help");
var ids = new Dictionary<string, HashSet<string>>();
foreach (var lang in new[] { "de", "en" })
{
    var html = File.ReadAllText(Path.Combine(help, lang + ".html"));
    ids[lang] = Regex.Matches(html, @"<section id=""([^""]+)""").Select(m => m.Groups[1].Value).ToHashSet();
    foreach (Match m in Regex.Matches(html, @"href=""#([^""]+)"""))
        Check(ids[lang].Contains(m.Groups[1].Value), $"{lang}.html: Link auf fehlenden Anker #{m.Groups[1].Value}");
}
Check(ids["de"].SetEquals(ids["en"]), "Hilfe-Anker in de.html und en.html verschieden");
var tags = new HashSet<string>();
foreach (var f in srcFiles.Where(f => f.EndsWith(".xaml")))
    foreach (Match m in Regex.Matches(File.ReadAllText(f), @"Tag=""([a-z\-]+)"""))
        if (m.Groups[1].Value is not ("de" or "en")) tags.Add(m.Groups[1].Value);
foreach (var t in tags) Check(ids["de"].Contains(t), $"Hilfe-Anker fehlt: {t}");

// 4. Prüfungen (VM / Admin / Profil)
Check(Preflight.IsVirtualMachine("Microsoft Corporation", "Virtual Machine"), "Hyper-V erkannt");
Check(Preflight.IsVirtualMachine("VMware, Inc.", "VMware7,1"), "VMware erkannt");
Check(Preflight.IsVirtualMachine("innotek GmbH", "VirtualBox"), "VirtualBox erkannt");
Check(Preflight.IsVirtualMachine("QEMU", "Standard PC (Q35 + ICH9, 2009)"), "QEMU erkannt");
Check(!Preflight.IsVirtualMachine("Dell Inc.", "Latitude 7440"), "Echter PC nicht als VM");
var vmData = new PreflightData { Manufacturer = "VMware, Inc.", Model = "VMware7,1", IsAdmin = true, CurrentUser = @"PC\dev", InteractiveUser = @"pc\DEV" };
Check(Preflight.Evaluate(vmData, false).CanProceed, "VM + Admin + gleiches Profil: weiter");
var pcData = new PreflightData { Manufacturer = "Dell Inc.", Model = "Latitude", IsAdmin = true, CurrentUser = @"PC\dev", InteractiveUser = @"PC\dev" };
Check(!Preflight.Evaluate(pcData, false).CanProceed, "Echter PC ohne Übersteuerung gesperrt");
Check(Preflight.Evaluate(pcData, true).CanProceed, "Echter PC mit bewusster Übersteuerung erlaubt");
Check(!Preflight.Evaluate(new PreflightData { Manufacturer = "VMware", Model = "x", IsAdmin = false, CurrentUser = "a", InteractiveUser = "a" }, false).CanProceed, "Ohne Admin gesperrt");
Check(!Preflight.Evaluate(new PreflightData { Manufacturer = "VMware", Model = "x", IsAdmin = true, CurrentUser = @"PC\admin2", InteractiveUser = @"PC\dev" }, false).CanProceed, "Falsches Profil gesperrt");
Check(Preflight.Evaluate(new PreflightData { Manufacturer = "VMware", Model = "x", IsAdmin = true, CurrentUser = "a", InteractiveUser = null }, false).CanProceed, "Unbekannter Benutzer nur Warnung");

// 5. Log-Filter: nie Passwörter/Tokens im Klartext
foreach (var secret in new[] { "hunter2-example", "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl", "s3cr3tvalue" })
{
    foreach (var line in new[] { $"password={secret}", $"Token: {secret}", $"url https://user:{secret}@example.com/x", $"//registry/:_authToken={secret}" })
        Check(!LogRedactor.Redact(line).Contains(secret), $"Log-Filter lässt Geheimnis durch: {line}");
}
foreach (var bare in new[] { "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl" })
    Check(!LogRedactor.Redact("Wert " + bare).Contains(bare), "Log-Filter: Token ohne Schlüsselwort");
Check(LogRedactor.Redact("Edge / Profil 1: 37 Passwörter") == "Edge / Profil 1: 37 Passwörter", "Log-Filter verändert harmlosen Text");

// 6. Modul-Schnittstelle (ohne PowerShell)
var tmp = Path.Combine(Path.GetTempPath(), "dvc_test_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tmp);
try
{
    File.WriteAllText(Path.Combine(tmp, "B.ps1"), "");
    File.WriteAllText(Path.Combine(tmp, "A.ps1"), "");
    File.WriteAllText(Path.Combine(tmp, "_Common.ps1"), "");
    File.WriteAllText(Path.Combine(tmp, "readme.txt"), "");
    var found = new ModuleRunner(tmp).DiscoverScripts().Select(Path.GetFileName).ToArray();
    Check(found.SequenceEqual(new[] { "A.ps1", "B.ps1" }), "Module: nur Skripte ohne _-Präfix, alphabetisch");
}
finally { Directory.Delete(tmp, true); }

var cleanArgs = ModuleRunner.BuildArguments(@"C:\m\Office.ps1", "Clean", new[] { "identity", "license" }, "en", null);
Check(cleanArgs.SequenceEqual(new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", @"C:\m\Office.ps1", "-Action", "Clean", "-Lang", "en", "-Categories", "identity,license" }), "Argumente Clean");
Check(!ModuleRunner.BuildArguments("x.ps1", "Analyze", null, "de", null).Contains("-Categories"), "Analyse ohne Kategorien = alle");

var json = "Warnung\n{\"module\":\"office\",\"findings\":[{\"category\":\"identity\",\"scope\":\"Office\",\"label\":\"angemeldet als alice@example.com\",\"count\":1}]}\n";
var a = ModuleRunner.ParseJson<ModuleAnalysis>(json);
Check(a.Module == "office" && a.Findings.Count == 1 && a.Findings[0].Label.Contains("alice@example.com"), "Analyse-JSON");
var info = ModuleRunner.ParseJson<ModuleInfo>("{\"id\":\"browser\",\"name\":{\"de\":\"Browser\",\"en\":\"Browsers\"},\"processes\":[\"msedge\"],\"categories\":[{\"id\":\"signin\",\"de\":\"Sync\",\"en\":\"Sync\",\"default\":false}]}");
Check(info.Id == "browser" && info.Name.Get("en") == "Browsers" && info.Categories[0].Default == false && info.Processes[0] == "msedge", "Info-JSON");
var threw = false;
try { ModuleRunner.ParseJson<ModuleAnalysis>("kein json"); } catch (ModuleException) { threw = true; }
Check(threw, "Ungültige Ausgabe wirft ModuleException");
Check(ModuleRunner.ParseJson<ModuleCleanResult>("{\"module\":\"x\",\"results\":[{\"category\":\"c\",\"scope\":\"s\",\"ok\":true,\"removed\":3,\"message\":\"\"}]}").Results[0].Removed == 3, "Clean-JSON");
Check(ProcessCloser.NormalizeName("msedge.exe") == "msedge" && ProcessCloser.NormalizeName("Chrome") == "Chrome", "Prozessname normalisiert");

// 6b. Berichtsmodule, Hinweise, Kontext
var rep = ModuleRunner.ParseJson<ModuleInfo>("{\"id\":\"secretscan\",\"reportOnly\":true,\"name\":{\"de\":\"x\",\"en\":\"x\"},\"processes\":[],\"categories\":[]}");
Check(rep.ReportOnly, "reportOnly gelesen");
var cleanRep = new ModuleRunner("nicht-vorhanden").CleanAsync(rep, new[] { "git" }, "de").GetAwaiter().GetResult();
Check(cleanRep.Results.Count == 0, "Berichtsmodul wird nie bereinigt (ohne PowerShell-Aufruf)");
var withNotes = ModuleRunner.ParseJson<ModuleAnalysis>("{\"module\":\"optional\",\"findings\":[],\"notes\":[\"Hinweis eins\"]}");
Check(withNotes.Notes.Count == 1 && withNotes.Notes[0] == "Hinweis eins", "Notes gelesen");
Check(ModuleRunner.BuildContextJson(null) is null && ModuleRunner.BuildContextJson(new[] { " " }) is null, "Kontext ohne Scan-Ordner");
var ctxText = ModuleRunner.BuildContextJson(new[] { @"D:\src", @"E:\work" });
Check(ctxText is not null && ctxText.StartsWith("b64:"), "Kontext als Base64");
using (var ctxDoc = JsonDocument.Parse(System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(ctxText![4..]))))
    Check(ctxDoc.RootElement.GetProperty("ScanRoots").GetString() == @"D:\src|E:\work", "Kontext mit Scan-Ordnern");
Check(ModuleRunner.BuildContextJson(new[] { "a|b" }) is null, "Ordner mit Trennzeichen abgelehnt");

// 6c. mitgelieferte Module: gültige Info-Struktur (Textprüfung der Skripte)
var modulesDir = Path.Combine(root, "modules");
var expected = new[] { "Office", "Browser", "WindowsAccounts", "DevTools", "Optional", "Traces", "SecretScan" };
foreach (var n in expected) Check(File.Exists(Path.Combine(modulesDir, n + ".ps1")), $"Modul fehlt: {n}.ps1");
foreach (var f in new ModuleRunner(modulesDir).DiscoverScripts())
{
    var text = File.ReadAllText(f);
    Check(text.Contains("function Get-ModuleInfo") && text.Contains("function Analyze") && text.Contains("function Clean"), $"Modul-Vertrag (Info/Analyze/Clean): {Path.GetFileName(f)}");
    Check(text.Contains("Invoke-ModuleMain"), $"Modul ruft Invoke-ModuleMain: {Path.GetFileName(f)}");
    Check(File.ReadAllBytes(f).Take(3).SequenceEqual(new byte[] { 0xEF, 0xBB, 0xBF }), $"Modul ohne UTF-8-BOM (Windows PowerShell 5.1 zeigt Umlaute falsch): {Path.GetFileName(f)}");
}
Check(new ModuleRunner(modulesDir).DiscoverScripts().Count == expected.Length, "Anzahl Module entspricht der Erwartung");

// 7. Log-Datei schreibt gefiltert
var logDir = Path.Combine(Path.GetTempPath(), "dvc_log_" + Guid.NewGuid().ToString("N"));
try
{
    var log = new RunLog(logDir);
    log.Write("password=geheim-example");
    Check(!File.ReadAllText(log.FilePath).Contains("geheim-example"), "Logdatei ohne Passwort");
}
finally { if (Directory.Exists(logDir)) Directory.Delete(logDir, true); }

// 8. Update-Prüfung
Check(UpdateChecker.ParseTag("v1.3") == new Version(1, 3, 0, 0), "ParseTag v1.3");
Check(UpdateChecker.ParseTag("v1.3.0-beta") is null, "ParseTag Vorabversion");
Check(UpdateChecker.IsNewer(new Version(2, 0, 1), new Version(2, 0)), "IsNewer");
using (var doc = JsonDocument.Parse("{\"tag_name\":\"v0.2.0\",\"html_url\":\"https://example.com/r\",\"assets\":[{\"name\":\"DevVM-Cleanup_0.2.0_win-x64.zip\",\"browser_download_url\":\"https://example.com/z.zip\"},{\"name\":\"x.sha256\",\"browser_download_url\":\"https://example.com/s\"}]}"))
{
    var rel = UpdateChecker.Parse(doc.RootElement);
    Check(rel is not null && rel.DownloadUrl == "https://example.com/z.zip", "Release-Parser: ZIP-Asset");
}

// 9. Hausstil: Firmenname und Entwickler nur wie vorgesehen
var company = "SPÄNI Elektro-Mechanik AG";
foreach (var f in srcFiles.Where(f => f.EndsWith(".xaml") || f.EndsWith(".cs")))
{
    var text = File.ReadAllText(f);
    Check(!Regex.IsMatch(text, @"Späni|SPAENI|Spaeni AG"), $"Firmenname falsch geschrieben in {Path.GetFileName(f)}");
}
Check(File.ReadAllText(Path.Combine(root, "src", "DevVmCleanup.App", "AppInfo.cs")).Contains(company), "AppInfo enthält Firmenname");
foreach (var f in srcFiles.Where(f => !f.EndsWith("AppInfo.cs")))
    Check(!File.ReadAllText(f).Contains("Ralph Kessler"), $"Entwicklername ausserhalb des Info-Fensters: {Path.GetFileName(f)}");

if (failures.Count == 0) { Console.WriteLine("Alle Tests bestanden."); return 0; }
foreach (var f in failures) Console.Error.WriteLine("FEHLER: " + f);
return 1;
