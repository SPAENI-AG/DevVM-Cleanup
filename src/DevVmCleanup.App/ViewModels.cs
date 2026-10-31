using System.Collections.ObjectModel;
using System.ComponentModel;
using DevVmCleanup.Core;

namespace DevVmCleanup.App;

public abstract class Notifier : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Eine wählbare Kategorie eines Moduls mit Vorschau („gefunden: …“).</summary>
public sealed class CategoryVm : Notifier
{
    private bool _checked;
    private bool _enabled = true;
    private string _preview = "";

    public CategoryVm(CategoryInfo info) { Info = info; _checked = info.Default; }

    public CategoryInfo Info { get; }
    public string Id => Info.Id;
    public string Label => Info.Label(Loc.Instance.Language);

    public bool IsChecked { get => _checked; set { if (_checked != value) { _checked = value; Raise(nameof(IsChecked)); Changed?.Invoke(); } } }
    /// <summary>Ohne Fund nicht wählbar.</summary>
    public bool IsEnabled { get => _enabled; set { if (_enabled != value) { _enabled = value; Raise(nameof(IsEnabled)); } } }
    public string Preview { get => _preview; set { _preview = value; Raise(nameof(Preview)); } }
    public List<Finding> Findings { get; set; } = new();

    public event Action? Changed;
    public void RefreshLabel() => Raise(nameof(Label));
}

/// <summary>Ein Modul (ein PowerShell-Skript) mit seinen Kategorien.</summary>
public sealed class ModuleVm : Notifier
{
    private bool? _checked = true;
    private bool _busy;

    public ModuleVm(ModuleInfo info)
    {
        Info = info;
        foreach (var c in info.Categories)
        {
            var vm = new CategoryVm(c) { Preview = Loc.T("Lbl_NotAnalyzed") };
            vm.Changed += UpdateModuleCheck;
            Categories.Add(vm);
        }
    }

    public ModuleInfo Info { get; }
    public string Name => Info.Name.Get(Loc.Instance.Language);
    public ObservableCollection<CategoryVm> Categories { get; } = new();

    /// <summary>Dreiwertig: alle / keine / teilweise gewählt. Setzen wählt alle wählbaren Kategorien.</summary>
    public bool? IsChecked
    {
        get => _checked;
        set
        {
            if (_busy) return;
            _busy = true;
            foreach (var c in Categories.Where(c => c.IsEnabled)) c.IsChecked = value == true;
            _busy = false;
            UpdateModuleCheck();
        }
    }

    private void UpdateModuleCheck()
    {
        if (_busy) return;
        var enabled = Categories.Where(c => c.IsEnabled).ToList();
        _checked = enabled.Count == 0 || enabled.All(c => !c.IsChecked) ? false
                 : enabled.All(c => c.IsChecked) ? true : null;
        Raise(nameof(IsChecked));
    }

    public IEnumerable<string> SelectedCategoryIds => Categories.Where(c => c.IsEnabled && c.IsChecked).Select(c => c.Id);

    /// <summary>Analyseergebnis eintragen: Vorschau je Kategorie; Kategorien ohne Fund werden abgewählt und gesperrt.</summary>
    public void ApplyAnalysis(ModuleAnalysis a)
    {
        _busy = true;
        foreach (var c in Categories)
        {
            c.Findings = a.Findings.Where(f => f.Category == c.Id).ToList();
            if (c.Findings.Count == 0)
            {
                c.Preview = Loc.T("Lbl_NoFindings");
                c.IsEnabled = false;
                c.IsChecked = false;
            }
            else
            {
                c.Preview = Loc.T("Lbl_Found", string.Join("; ", c.Findings.Select(f => $"{f.Scope}: {f.Label}")));
                c.IsEnabled = true;
                c.IsChecked = c.Info.Default;
            }
        }
        _busy = false;
        UpdateModuleCheck();
    }

    public void RefreshLabels()
    {
        Raise(nameof(Name));
        foreach (var c in Categories) c.RefreshLabel();
    }
}
