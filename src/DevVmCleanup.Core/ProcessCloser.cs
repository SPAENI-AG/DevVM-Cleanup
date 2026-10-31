using System.Diagnostics;

namespace DevVmCleanup.Core;

public sealed record RunningProcess(string Name, int Id);

/// <summary>Erkennt laufende Programme (auch Hintergrundprozesse) und schliesst sie nach Bestätigung durch den Aufrufer.</summary>
public static class ProcessCloser
{
    /// <summary>Prozessnamen ohne ".exe", Gross-/Kleinschreibung egal. Der eigene Prozess wird nie aufgeführt.</summary>
    public static List<RunningProcess> FindRunning(IEnumerable<string> names)
    {
        var wanted = new HashSet<string>(names.Select(NormalizeName), StringComparer.OrdinalIgnoreCase);
        var self = Environment.ProcessId;
        var list = new List<RunningProcess>();
        foreach (var p in Process.GetProcesses())
        {
            try
            {
                if (p.Id != self && wanted.Contains(p.ProcessName)) list.Add(new RunningProcess(p.ProcessName, p.Id));
            }
            catch (Exception) { /* Prozess beendet */ }
            finally { p.Dispose(); }
        }
        return list.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    public static string NormalizeName(string name) =>
        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;

    /// <summary>Erst höflich schliessen (Fenster), nach Wartezeit beenden. Gibt die noch laufenden Prozesse zurück.</summary>
    public static async Task<List<RunningProcess>> CloseAsync(IEnumerable<string> names, TimeSpan grace, CancellationToken ct = default)
    {
        var names2 = names.ToList();
        foreach (var rp in FindRunning(names2))
        {
            try { using var p = Process.GetProcessById(rp.Id); p.CloseMainWindow(); }
            catch (Exception) { }
        }
        var deadline = DateTime.UtcNow + grace;
        while (DateTime.UtcNow < deadline && FindRunning(names2).Count > 0)
            await Task.Delay(250, ct).ConfigureAwait(false);

        foreach (var rp in FindRunning(names2))
        {
            try { using var p = Process.GetProcessById(rp.Id); p.Kill(entireProcessTree: true); p.WaitForExit(3000); }
            catch (Exception) { }
        }
        await Task.Delay(300, ct).ConfigureAwait(false);
        return FindRunning(names2);
    }
}
