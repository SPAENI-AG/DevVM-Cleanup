namespace DevVmCleanup.Core;

public enum CheckState { Ok, Warning, Failed }

public sealed record CheckItem(CheckState State, string Detail);

public sealed record PreflightResult(CheckItem Vm, CheckItem Admin, CheckItem Profile)
{
    /// <summary>Alle Prüfungen bestanden (VM-Prüfung nur mit bewusster Übersteuerung ignorierbar).</summary>
    public bool CanProceed => Vm.State != CheckState.Failed && Admin.State == CheckState.Ok && Profile.State != CheckState.Failed;
}

/// <summary>Bewertet die Rohdaten der Vorab-Prüfungen. Reine Logik, ohne Windows-Aufrufe.</summary>
public static class Preflight
{
    private static readonly string[] VmMarkers =
    {
        "virtual machine", "vmware", "virtualbox", "innotek", "qemu", "kvm", "xen", "parallels", "bochs", "hyper-v", "virtual platform"
    };

    public static bool IsVirtualMachine(string manufacturer, string model)
    {
        var s = (manufacturer + " " + model).ToLowerInvariant();
        return VmMarkers.Any(s.Contains);
    }

    public static PreflightResult Evaluate(PreflightData d, bool allowNonVm)
    {
        var vmText = $"{d.Manufacturer} / {d.Model}".Trim(' ', '/');
        var vm = IsVirtualMachine(d.Manufacturer, d.Model)
            ? new CheckItem(CheckState.Ok, vmText)
            : allowNonVm
                ? new CheckItem(CheckState.Warning, vmText)
                : new CheckItem(CheckState.Failed, vmText);

        var admin = new CheckItem(d.IsAdmin ? CheckState.Ok : CheckState.Failed, d.CurrentUser);

        CheckItem profile;
        if (string.IsNullOrWhiteSpace(d.InteractiveUser))
            profile = new CheckItem(CheckState.Warning, d.CurrentUser);
        else if (string.Equals(d.InteractiveUser, d.CurrentUser, StringComparison.OrdinalIgnoreCase))
            profile = new CheckItem(CheckState.Ok, d.CurrentUser);
        else
            profile = new CheckItem(CheckState.Failed, $"{d.CurrentUser} ≠ {d.InteractiveUser}");

        return new PreflightResult(vm, admin, profile);
    }
}
