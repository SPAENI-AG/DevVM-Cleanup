using System.Windows;
using DevVmCleanup.Core;

namespace DevVmCleanup.App;

public partial class App : Application
{
    public static AppSettings Settings { get; private set; } = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        Settings = AppSettings.Load();
        Loc.Instance.Language = Settings.Language;   // vor dem Hauptfenster
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        HelpServer.Shutdown();
        base.OnExit(e);
    }
}
