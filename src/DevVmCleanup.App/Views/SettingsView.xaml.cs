using System.Windows;
using System.Windows.Controls;
using DevVmCleanup.Core;

namespace DevVmCleanup.App.Views;

/// <summary>Einstellungen: Sprache und Update-Prüfung. Änderungen werden sofort übernommen und gespeichert.</summary>
public partial class SettingsView : UserControl
{
    private bool _loading;

    /// <summary>Wird ausgelöst, wenn im Kombinationsfeld eine Sprache gewählt wurde ("de" | "en").</summary>
    public event EventHandler<string>? LanguageSelected;

    public SettingsView()
    {
        InitializeComponent();
        LoadFromSettings();
    }

    public void LoadFromSettings()
    {
        _loading = true;
        var s = App.Settings;
        cb_Language.SelectedIndex = s.Language == "en" ? 1 : 0;
        chk_Updates.IsChecked = s.CheckForUpdates;
        _loading = false;
    }

    private void cb_Language_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || cb_Language.SelectedItem is not ComboBoxItem it) return;
        LanguageSelected?.Invoke(this, (string)it.Tag);
    }

    private void chk_Updates_Click(object sender, RoutedEventArgs e)
    {
        App.Settings.CheckForUpdates = chk_Updates.IsChecked == true;
        MainWindow.TrySave();
    }

    private void Help_Click(object sender, RoutedEventArgs e) =>
        MainWindow.ShowHelp((sender as FrameworkElement)?.Tag as string ?? "");
}
