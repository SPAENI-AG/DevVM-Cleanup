using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DevVmCleanup.Core;

namespace DevVmCleanup.App;

public partial class MainWindow : Window
{
    private readonly ModuleRunner _runner = new();
    private readonly RunLog _log = new();
    private readonly List<ModuleVm> _modules = new();               // Module mit Bereinigung
    private readonly List<ModuleInfo> _scanModules = new();         // Berichtsmodule (Geheimnis-Scan), löschen nie
    private PreflightData? _preflightData;
    private PreflightResult? _preflight;
    private bool _analyzed;

    public MainWindow()
    {
        InitializeComponent();

        Title = $"{AppInfo.Title}  v{AppInfo.Version.ToString(3)}";
        tb_FooterCompany.Text = AppInfo.Company;
        tb_FooterVersion.Text = AppInfo.VersionText;
        tb_Verify.Text = Loc.T("Lbl_VerifyNone");
        tb_Verify.Foreground = (Brush)FindResource("MutedBrush");

        SettingsPage.LanguageSelected += (_, lang) => SetLanguage(lang);
        UpdateLanguageChecks();
        Loc.Instance.LanguageChanged += (_, _) =>
        {
            RefreshUpdateBanner();
            foreach (var m in _modules) m.RefreshLabels();
            ShowPreflight();
            UpdateProgramsText();
            if (!_verified) tb_Verify.Text = Loc.T("Lbl_VerifyNone");
        };
    }

    private bool _verified;

    // --- Start -------------------------------------------------------------
    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        var s = App.Settings;
        var current = UpdateChecker.Normalize(AppInfo.Version);

        var last = UpdateChecker.ParseTag(s.LastRunVersion);
        if (last is not null && UpdateChecker.IsNewer(current, last)) _updatedTo = current;
        s.LastRunVersion = UpdateChecker.Format(current);
        TrySave();
        RefreshUpdateBanner();

        Log(Loc.T("Log_Start", AppInfo.Version.ToString(3), _log.FilePath));
        await LoadModules();
        await RunPreflight();
        UpdateProgramsText();

        // automatische Prüfung (höchstens alle 20 h, still bei Fehlern)
        if (UpdateChecker.IsDue(s, DateTime.UtcNow))
        {
            try
            {
                var latest = await UpdateChecker.GetLatestAsync(current);
                s.LastUpdateCheckUtc = DateTime.UtcNow;
                TrySave();
                if (latest is not null && UpdateChecker.IsNewer(latest.Version, current)
                    && UpdateChecker.Format(latest.Version) != s.SkippedVersion)
                {
                    _available = latest;
                    RefreshUpdateBanner();
                }
            }
            catch (Exception)
            {
                // offline / Proxy / GitHub nicht erreichbar: beim nächsten Start erneut
            }
        }
    }

    // --- Updates (GitHub Releases) -------------------------------------------
    private ReleaseInfo? _available;
    private Version? _updatedTo;

    private async void mi_CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        if (!UpdateChecker.IsConfigured)
        {
            MessageBox.Show(Loc.T("Upd_NotConfigured"), AppInfo.Title, MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var current = UpdateChecker.Normalize(AppInfo.Version);
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            var latest = await UpdateChecker.GetLatestAsync(current);
            App.Settings.LastUpdateCheckUtc = DateTime.UtcNow;
            TrySave();
            if (latest is not null && UpdateChecker.IsNewer(latest.Version, current))
            {
                _available = latest;
                RefreshUpdateBanner();
            }
            else
            {
                MessageBox.Show(Loc.T("Upd_UpToDate", UpdateChecker.Format(current)), AppInfo.Title, MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(Loc.T("Upd_Failed", ex.Message), AppInfo.Title, MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            Mouse.OverrideCursor = null;
        }
    }

    private void RefreshUpdateBanner()
    {
        if (_available is not null)
        {
            tb_UpdateText.Text = Loc.T("Upd_Available", UpdateChecker.Format(_available.Version), UpdateChecker.Format(AppInfo.Version));
            bt_UpdateDownload.Visibility = Visibility.Visible;
            bt_UpdateSkip.Visibility = Visibility.Visible;
            bt_UpdateNotes.Visibility = Visibility.Visible;
            bd_Update.Visibility = Visibility.Visible;
        }
        else if (_updatedTo is not null)
        {
            tb_UpdateText.Text = Loc.T("Upd_Updated", UpdateChecker.Format(_updatedTo));
            bt_UpdateDownload.Visibility = Visibility.Collapsed;
            bt_UpdateSkip.Visibility = Visibility.Collapsed;
            bt_UpdateNotes.Visibility = UpdateChecker.IsConfigured ? Visibility.Visible : Visibility.Collapsed;
            bd_Update.Visibility = Visibility.Visible;
        }
        else
        {
            bd_Update.Visibility = Visibility.Collapsed;
        }
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { MessageBox.Show(ex.Message, AppInfo.Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void bt_UpdateDownload_Click(object sender, RoutedEventArgs e)
    {
        if (_available is not null) OpenUrl(_available.DownloadUrl ?? _available.PageUrl);
    }

    private void bt_UpdateNotes_Click(object sender, RoutedEventArgs e)
    {
        if (_available is not null) OpenUrl(_available.PageUrl);
        else if (_updatedTo is not null) OpenUrl(UpdateChecker.ReleasePage(_updatedTo));
    }

    private void bt_UpdateSkip_Click(object sender, RoutedEventArgs e)
    {
        if (_available is null) return;
        App.Settings.SkippedVersion = UpdateChecker.Format(_available.Version);
        TrySave();
        _available = null;
        RefreshUpdateBanner();
    }

    private void bt_UpdateClose_Click(object sender, RoutedEventArgs e)
    {
        if (_available is not null) _available = null;
        else _updatedTo = null;
        RefreshUpdateBanner();
    }

    // --- Sprache -------------------------------------------------------------
    private void SetLanguage(string lang)
    {
        if (lang == Loc.Instance.Language) { UpdateLanguageChecks(); return; }
        Loc.Instance.Language = lang;
        App.Settings.Language = lang;
        TrySave();
        UpdateLanguageChecks();
        SettingsPage.LoadFromSettings();
    }

    private void UpdateLanguageChecks()
    {
        mi_LangDe.IsChecked = Loc.Instance.Language == "de";
        mi_LangEn.IsChecked = Loc.Instance.Language == "en";
    }

    private void mi_LangDe_Click(object sender, RoutedEventArgs e) => SetLanguage("de");
    private void mi_LangEn_Click(object sender, RoutedEventArgs e) => SetLanguage("en");

    // --- Menü / Hilfe --------------------------------------------------------
    private void mi_Exit_Click(object sender, RoutedEventArgs e) => Close();
    private void mi_Settings_Click(object sender, RoutedEventArgs e) => tc_Main.SelectedItem = ti_Settings;
    private void mi_Help_Click(object sender, RoutedEventArgs e) => ShowHelp("");
    private void mi_HelpTopic_Click(object sender, RoutedEventArgs e) => ShowHelp((sender as FrameworkElement)?.Tag as string ?? "");
    private void Help_Click(object sender, RoutedEventArgs e) => ShowHelp((sender as FrameworkElement)?.Tag as string ?? "");

    public static void ShowHelp(string anchor)
    {
        var error = HelpServer.Open(anchor);
        if (error is not null) MessageBox.Show(error, AppInfo.Title, MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private void mi_SettingsFolder_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo(AppSettings.Folder) { UseShellExecute = true });

    private void mi_LogFolder_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo(RunLog.Folder) { UseShellExecute = true });

    private void mi_About_Click(object sender, RoutedEventArgs e) => new AboutWindow { Owner = this }.ShowDialog();

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e) => TrySave();

    public static void TrySave()
    {
        try { App.Settings.Save(); }
        catch (Exception) { /* nicht kritisch */ }
    }

    // --- Log / Busy ----------------------------------------------------------
    /// <summary>Zeile ins Fenster und in die Logdatei – beides ohne Passwörter/Tokens (LogRedactor).</summary>
    private void Log(string msg)
    {
        var line = _log.Write(msg);
        tb_Log.AppendText(line + Environment.NewLine);
        tb_Log.ScrollToEnd();
    }

    private void Busy(bool b)
    {
        Mouse.OverrideCursor = b ? Cursors.Wait : null;
        pb_Busy.Visibility = b ? Visibility.Visible : Visibility.Collapsed;
        foreach (var c in new Control[] { bt_Recheck, bt_CloseApps, bt_Analyze, bt_Clean, bt_Verify, bt_Scan, bt_Rename, bt_Sysprep, bt_Shutdown, ic_Modules })
            c.IsEnabled = !b;
    }

    // --- 1. Prüfungen ----------------------------------------------------------
    private async Task RunPreflight()
    {
        tb_CheckVm.Text = Loc.T("Chk_Running");
        tb_CheckAdmin.Text = tb_CheckProfile.Text = "";
        try
        {
            _preflightData = await _runner.GetPreflightAsync();
            ShowPreflight();
            Log(Loc.T("Log_Preflight", _preflight!.Vm.State, _preflight.Admin.State, _preflight.Profile.State));
        }
        catch (Exception ex)
        {
            _preflightData = null;
            _preflight = null;
            tb_CheckVm.Text = Loc.T("Chk_Error", LogRedactor.Redact(ex.Message));
            tb_CheckVm.Foreground = Brushes.Firebrick;
            Log(Loc.T("Log_Fail", ex.Message));
        }
    }

    private void ShowPreflight()
    {
        if (_preflightData is null) return;
        _preflight = Preflight.Evaluate(_preflightData, chk_AllowNonVm.IsChecked == true);
        var p = _preflight;

        tb_CheckVm.Text = p.Vm.State switch
        {
            CheckState.Ok => Loc.T("Chk_VmOk", p.Vm.Detail),
            CheckState.Warning => Loc.T("Chk_VmWarn", p.Vm.Detail),
            _ => Loc.T("Chk_VmFail", p.Vm.Detail),
        };
        tb_CheckAdmin.Text = Loc.T(p.Admin.State == CheckState.Ok ? "Chk_AdminOk" : "Chk_AdminFail");
        tb_CheckProfile.Text = p.Profile.State switch
        {
            CheckState.Ok => Loc.T("Chk_ProfileOk", p.Profile.Detail),
            CheckState.Warning => Loc.T("Chk_ProfileWarn", p.Profile.Detail),
            _ => Loc.T("Chk_ProfileFail", p.Profile.Detail),
        };
        SetColor(tb_CheckVm, p.Vm.State);
        SetColor(tb_CheckAdmin, p.Admin.State);
        SetColor(tb_CheckProfile, p.Profile.State);

        // Übersteuern nur anbieten, wenn keine VM erkannt wurde
        var isVm = Preflight.IsVirtualMachine(_preflightData.Manufacturer, _preflightData.Model);
        chk_AllowNonVm.Visibility = isVm ? Visibility.Collapsed : Visibility.Visible;
    }

    private static void SetColor(TextBlock tb, CheckState s) =>
        tb.Foreground = s switch { CheckState.Ok => Brushes.DarkGreen, CheckState.Warning => Brushes.DarkOrange, _ => Brushes.Firebrick };

    private async void bt_Recheck_Click(object sender, RoutedEventArgs e)
    {
        Busy(true);
        await RunPreflight();
        Busy(false);
    }

    private void chk_AllowNonVm_Click(object sender, RoutedEventArgs e) => ShowPreflight();

    // --- Module laden --------------------------------------------------------
    private async Task LoadModules()
    {
        Busy(true);
        var (mods, errors) = await _runner.LoadModulesAsync();
        _modules.Clear();
        _scanModules.Clear();
        foreach (var m in mods)
        {
            if (m.ReportOnly) _scanModules.Add(m);
            else _modules.Add(new ModuleVm(m));
        }
        ic_Modules.ItemsSource = _modules;
        tb_ModulesNone.Visibility = _modules.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var err in errors) Log(Loc.T("Log_ModuleError", err.Split(':')[0], LogRedactor.Redact(err)));
        tb_ModuleErrors.Visibility = errors.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        tb_ModuleErrors.Text = string.Join(Environment.NewLine, errors.Select(x => Loc.T("Lbl_ModuleError", LogRedactor.Redact(x))));
        Log(Loc.T("Log_ModulesLoaded", _modules.Count + _scanModules.Count));
        bt_Scan.IsEnabled = _scanModules.Count > 0;
        Busy(false);
    }

    // --- 2. Programme ----------------------------------------------------------
    private IEnumerable<string> ProcessNames(IEnumerable<ModuleVm> modules) =>
        modules.SelectMany(m => m.Info.Processes).Distinct(StringComparer.OrdinalIgnoreCase);

    private List<RunningProcess> RunningNow() => ProcessCloser.FindRunning(ProcessNames(_modules));

    private void UpdateProgramsText()
    {
        var running = RunningNow();
        tb_Programs.Text = running.Count == 0
            ? Loc.T("Lbl_ProgramsNone")
            : Loc.T("Lbl_ProgramsRunning", string.Join(", ", running.Select(r => r.Name).Distinct(StringComparer.OrdinalIgnoreCase)));
    }

    private async void bt_CloseApps_Click(object sender, RoutedEventArgs e) => await CloseApps();

    /// <summary>Erkennt laufende Programme, fragt nach und schliesst sie. true = danach läuft nichts mehr.</summary>
    private async Task<bool> CloseApps()
    {
        var running = RunningNow();
        if (running.Count == 0) { UpdateProgramsText(); return true; }
        var names = string.Join(Environment.NewLine, running.Select(r => r.Name).Distinct(StringComparer.OrdinalIgnoreCase).Select(n => "• " + n));
        if (MessageBox.Show(this, Loc.T("Msg_CloseConfirm", names), Loc.T("Msg_CloseTitle"), MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK)
            return false;

        Busy(true);
        Log(Loc.T("Log_Closing", string.Join(", ", running.Select(r => r.Name).Distinct(StringComparer.OrdinalIgnoreCase))));
        var left = await ProcessCloser.CloseAsync(ProcessNames(_modules), TimeSpan.FromSeconds(8));
        Busy(false);
        UpdateProgramsText();
        if (left.Count > 0)
        {
            MessageBox.Show(this, Loc.T("Msg_CloseStill", string.Join(", ", left.Select(r => r.Name).Distinct())), Loc.T("Msg_CloseTitle"),
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }
        Log(Loc.T("Log_Closed"));
        return true;
    }

    // --- 3. Analyse ------------------------------------------------------------
    private async void bt_Analyze_Click(object sender, RoutedEventArgs e) => await DoAnalyze();

    private async Task DoAnalyze()
    {
        Busy(true);
        Log(Loc.T("Log_Analyzing"));
        var total = 0;
        foreach (var m in _modules)
        {
            try
            {
                var a = await _runner.AnalyzeAsync(m.Info, null, Loc.Instance.Language);
                m.ApplyAnalysis(a);
                total += a.Findings.Count;
                foreach (var f in a.Findings) Log($"  {m.Info.Id} · {f.Scope}: {f.Label}");
                foreach (var n in a.Notes) Log($"  {m.Info.Id} · ℹ {n}");
            }
            catch (Exception ex)
            {
                Log(Loc.T("Log_AnalyzeFail", m.Info.Id, LogRedactor.Redact(ex.Message)));
            }
        }
        _analyzed = true;
        _verified = false;
        Log(Loc.T("Log_AnalyzeDone", total));
        UpdateProgramsText();
        Busy(false);
    }

    // --- 4. Bereinigen und Kontrolllauf ------------------------------------------
    private async void bt_Clean_Click(object sender, RoutedEventArgs e)
    {
        if (_preflight is null || !_preflight.CanProceed)
        {
            MessageBox.Show(this, Loc.T("Msg_PreflightFail"), Loc.T("Msg_CleanTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!_analyzed)
        {
            MessageBox.Show(this, Loc.T("Msg_NeedAnalyze"), Loc.T("Msg_CleanTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var selected = _modules.Select(m => (Module: m, Cats: m.SelectedCategoryIds.ToList())).Where(x => x.Cats.Count > 0).ToList();
        if (selected.Count == 0)
        {
            MessageBox.Show(this, Loc.T("Msg_NothingSelected"), Loc.T("Msg_CleanTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var summary = string.Join(Environment.NewLine, selected.Select(x =>
            $"{x.Module.Name}:" + Environment.NewLine +
            string.Join(Environment.NewLine, x.Module.Categories.Where(c => c.IsEnabled && c.IsChecked).Select(c => "   • " + c.Label)))) + Environment.NewLine;
        if (MessageBox.Show(this, Loc.T("Msg_CleanConfirm", summary), Loc.T("Msg_CleanTitle"), MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK)
            return;

        // betroffene Programme müssen geschlossen sein
        if (!await CloseApps()) return;
        var stillRunning = ProcessCloser.FindRunning(ProcessNames(selected.Select(x => x.Module)));
        if (stillRunning.Count > 0)
        {
            MessageBox.Show(this, Loc.T("Msg_AppsRunning", string.Join(", ", stillRunning.Select(r => r.Name).Distinct())), Loc.T("Msg_CleanTitle"),
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Busy(true);
        foreach (var (module, cats) in selected)
        {
            Log(Loc.T("Log_Cleaning", module.Info.Id));
            try
            {
                var r = await _runner.CleanAsync(module.Info, cats, Loc.Instance.Language);
                foreach (var item in r.Results)
                    Log(item.Ok
                        ? Loc.T("Log_CleanItem", item.Scope, item.Category, item.Removed)
                        : Loc.T("Log_CleanItemFail", item.Scope, item.Category, item.Message));
            }
            catch (Exception ex)
            {
                Log(Loc.T("Log_CleanFail", module.Info.Id, LogRedactor.Redact(ex.Message)));
            }
        }
        Log(Loc.T("Log_CleanDone"));
        Busy(false);
        await DoVerify(selected.ToDictionary(x => x.Module, x => x.Cats));
    }

    private async void bt_Verify_Click(object sender, RoutedEventArgs e)
    {
        // Kontrolllauf über die aktuell gewählten Kategorien (ohne Analyse: alle Standard-Kategorien)
        var scope = new Dictionary<ModuleVm, List<string>>();
        foreach (var m in _modules)
        {
            var cats = _analyzed ? m.SelectedCategoryIds.ToList() : m.Info.Categories.Where(c => c.Default).Select(c => c.Id).ToList();
            if (cats.Count > 0) scope[m] = cats;
        }
        await DoVerify(scope);
    }

    /// <summary>Kontrolllauf: gewählte Kategorien erneut analysieren – muss „sauber“ melden.</summary>
    private async Task DoVerify(Dictionary<ModuleVm, List<string>> scope)
    {
        Busy(true);
        Log(Loc.T("Log_Verify"));
        var remaining = new List<string>();
        foreach (var (module, cats) in scope)
        {
            try
            {
                var a = await _runner.AnalyzeAsync(module.Info, cats, Loc.Instance.Language);
                remaining.AddRange(a.Findings.Select(f => $"{module.Name} · {f.Scope}: {f.Label}"));
            }
            catch (Exception ex)
            {
                remaining.Add($"{module.Name}: {LogRedactor.Redact(ex.Message)}");
            }
        }
        _verified = true;
        if (remaining.Count == 0)
        {
            tb_Verify.Text = Loc.T("Lbl_VerifyClean");
            tb_Verify.Foreground = Brushes.DarkGreen;
            Log(Loc.T("Log_VerifyClean"));
        }
        else
        {
            tb_Verify.Text = Loc.T("Lbl_VerifyDirty") + Environment.NewLine + string.Join(Environment.NewLine, remaining.Select(x => "• " + x));
            tb_Verify.Foreground = Brushes.Firebrick;
            Log(Loc.T("Log_VerifyDirty", remaining.Count));
            foreach (var r in remaining) Log("  " + r);
        }
        Busy(false);
    }

    // --- 5. Geheimnis-Scan (nur Bericht) ---------------------------------------------
    private async void bt_Scan_Click(object sender, RoutedEventArgs e)
    {
        Busy(true);
        Log(Loc.T("Log_Scanning"));
        _runner.ContextJson = ModuleRunner.BuildContextJson(App.Settings.ScanRoots);
        var lines = new List<string>();
        try
        {
            foreach (var m in _scanModules)
            {
                try
                {
                    var a = await _runner.AnalyzeAsync(m, null, Loc.Instance.Language);
                    lines.AddRange(a.Findings.Select(f => $"{f.Scope}  –  {f.Label}"));
                }
                catch (Exception ex)
                {
                    Log(Loc.T("Log_AnalyzeFail", m.Id, LogRedactor.Redact(ex.Message)));
                }
            }
        }
        finally { _runner.ContextJson = null; }

        tb_ScanResult.Visibility = Visibility.Visible;
        tb_ScanResult.Text = lines.Count == 0 ? Loc.T("Lbl_ScanNone") : string.Join(Environment.NewLine, lines);
        Log(Loc.T("Log_ScanDone", lines.Count));
        foreach (var l in lines) Log("  " + l);
        Busy(false);
    }

    // --- 6. Abschluss (optional) -------------------------------------------------
    private async Task Finish(string action, string? name = null)
    {
        Busy(true);
        try
        {
            var r = await _runner.FinishAsync(action, name);
            Log(Loc.T("Log_Finish", action, r.Ok ? Loc.T("Log_Ok") : Loc.T("Log_Fail", LogRedactor.Redact(r.Message))));
        }
        catch (Exception ex)
        {
            Log(Loc.T("Log_Finish", action, Loc.T("Log_Fail", LogRedactor.Redact(ex.Message))));
        }
        Busy(false);
    }

    private bool FinishAllowed()
    {
        if (_preflight is not null && _preflight.CanProceed) return true;
        MessageBox.Show(this, Loc.T("Msg_PreflightFail"), Loc.T("Msg_FinishTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        return false;
    }

    private async void bt_Rename_Click(object sender, RoutedEventArgs e)
    {
        var name = tb_NewName.Text.Trim();
        if (!Regex.IsMatch(name, "^[A-Za-z0-9][A-Za-z0-9-]{0,14}$"))
        {
            MessageBox.Show(this, Loc.T("Msg_RenameInvalid"), Loc.T("Msg_FinishTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!FinishAllowed()) return;
        if (MessageBox.Show(this, Loc.T("Msg_RenameConfirm", name), Loc.T("Msg_FinishTitle"), MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        await Finish("Rename", name);
    }

    private async void bt_Sysprep_Click(object sender, RoutedEventArgs e)
    {
        if (!FinishAllowed()) return;
        if (MessageBox.Show(this, Loc.T("Msg_SysprepConfirm"), Loc.T("Msg_FinishTitle"), MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        await Finish("Sysprep");
    }

    private async void bt_Shutdown_Click(object sender, RoutedEventArgs e)
    {
        if (!FinishAllowed()) return;
        if (MessageBox.Show(this, Loc.T("Msg_ShutdownConfirm"), Loc.T("Msg_FinishTitle"), MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        await Finish("Shutdown");
    }
}
