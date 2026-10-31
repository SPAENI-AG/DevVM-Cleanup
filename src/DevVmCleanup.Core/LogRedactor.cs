using System.Text.RegularExpressions;

namespace DevVmCleanup.Core;

/// <summary>Entfernt Passwörter und Tokens aus Texten, bevor sie ins Log geschrieben werden.</summary>
public static class LogRedactor
{
    private const string Mask = "***";

    private static readonly (Regex Rx, string Replacement)[] Rules =
    {
        // Anmeldedaten in URLs: https://user:pass@host
        (new Regex(@"(?<=://)[^/\s:@]+:[^/\s@]+@", RegexOptions.Compiled), Mask + "@"),
        // JWT
        (new Regex(@"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*", RegexOptions.Compiled), Mask),
        // GitHub-Tokens
        (new Regex(@"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b", RegexOptions.Compiled), Mask),
        // Schlüssel = Wert (password, token, secret, api key, authorization, bearer …)
        (new Regex(@"(?i)\b(password|passwd|pwd|passphrase|token|secret|api[_-]?key|authorization|bearer|_authToken|_auth)\b(\s*[:=]\s*|\s+)(""[^""]*""|'[^']*'|\S+)", RegexOptions.Compiled), "$1$2" + Mask),
        // lange Base64-/Hex-artige Zeichenketten
        (new Regex(@"(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/_-]{40,}={0,2}(?![A-Za-z0-9+/_-])", RegexOptions.Compiled), Mask),
    };

    public static string Redact(string? text)
    {
        if (string.IsNullOrEmpty(text)) return text ?? "";
        var s = text;
        foreach (var (rx, rep) in Rules) s = rx.Replace(s, rep);
        return s;
    }
}
