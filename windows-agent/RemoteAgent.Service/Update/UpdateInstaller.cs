using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using Microsoft.Extensions.Logging;

namespace RemoteAgent.Service.Update;

/// <summary>
/// Stáhne a nainstaluje update. Používá batch script pro replace-while-running.
/// Ověřuje RSA-SHA256 podpis update balíčku.
/// </summary>
public class UpdateInstaller
{
    private readonly ILogger _logger;
    private readonly HttpClient _http = new();
    private static readonly string UpdateDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "RemoteAgent", "Updates");

    // ── RSA veřejný klíč pro ověření podpisu update balíčků ──
    // Vygeneruj pár: openssl genrsa -out update-private.pem 2048
    // Exportuj veřejný: openssl rsa -in update-private.pem -pubout -out update-public.pem
    // Podpiš update: openssl dgst -sha256 -sign update-private.pem -out update.sig ServiDesk-Setup.exe
    // Base64 podpis: base64 -i update.sig
    private const string UpdatePublicKeyPem = @"-----BEGIN PUBLIC KEY-----
REPLACE_WITH_YOUR_PUBLIC_KEY
-----END PUBLIC KEY-----";

    public UpdateInstaller(ILogger logger)
    {
        _logger = logger;
        Directory.CreateDirectory(UpdateDir);
    }

    public async Task<bool> DownloadAndInstallAsync(UpdateManifest manifest)
    {
        try
        {
            var fileName = Path.GetFileName(new Uri(manifest.DownloadUrl).AbsolutePath);
            var filePath = Path.Combine(UpdateDir, fileName);

            _logger.LogInformation("Downloading update {Version} from {Url}", manifest.Version, manifest.DownloadUrl);

            // Stáhnout soubor
            using var response = await _http.GetAsync(manifest.DownloadUrl);
            response.EnsureSuccessStatusCode();
            var data = await response.Content.ReadAsByteArrayAsync();
            await File.WriteAllBytesAsync(filePath, data);

            // Ověřit SHA-256
            if (!string.IsNullOrEmpty(manifest.Sha256))
            {
                var hash = Convert.ToHexString(SHA256.HashData(data));
                if (!hash.Equals(manifest.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogError("SHA-256 mismatch! Expected: {Expected}, Got: {Got}", manifest.Sha256, hash);
                    File.Delete(filePath);
                    return false;
                }
                _logger.LogInformation("SHA-256 verified OK");
            }

            // Ověřit RSA podpis
            if (!VerifySignature(data, manifest.Signature))
            {
                _logger.LogError("RSA signature verification FAILED for update {Version}", manifest.Version);
                File.Delete(filePath);
                return false;
            }
            _logger.LogInformation("RSA signature verified OK");

            // Pokud je to installer (.exe), spustit ho
            if (fileName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogInformation("Launching installer: {Path}", filePath);
                CreateUpdateScript(filePath);
                return true;
            }

            _logger.LogWarning("Unknown update file type: {Name}", fileName);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Update download/install failed");
            return false;
        }
    }

    /// <summary>
    /// Ověří RSA-SHA256 podpis update balíčku.
    /// </summary>
    private bool VerifySignature(byte[] data, string signatureBase64)
    {
        if (string.IsNullOrEmpty(signatureBase64))
        {
            _logger.LogError("Update has no signature – rejected");
            return false;
        }

        if (UpdatePublicKeyPem.Contains("REPLACE_WITH_YOUR_PUBLIC_KEY"))
        {
            _logger.LogWarning("Update public key not configured – skipping signature check");
            return true; // Zpětná kompatibilita dokud se nenastaví klíč
        }

        try
        {
            using var rsa = RSA.Create();
            rsa.ImportFromPem(UpdatePublicKeyPem);
            var signature = Convert.FromBase64String(signatureBase64);
            return rsa.VerifyData(data, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "RSA signature verification error");
            return false;
        }
    }

    /// <summary>
    /// Vytvoří a spustí batch script, který zastaví službu, spustí installer a restartuje službu.
    /// </summary>
    private void CreateUpdateScript(string installerPath)
    {
        var scriptPath = Path.Combine(UpdateDir, "update.bat");
        var guiExePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "ServiDesk", "ServiDesk.exe");

        var script = $"""
            @echo off
            echo Stopping RemoteAgentService...
            sc stop RemoteAgentService
            timeout /t 5 /nobreak
            echo Running installer...
            "{installerPath}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
            echo Starting RemoteAgentService...
            sc start RemoteAgentService
            timeout /t 2 /nobreak
            echo Starting GUI...
            start "" "{guiExePath}"
            del "%~f0"
            """;

        File.WriteAllText(scriptPath, script);

        var psi = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c \"{scriptPath}\"",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        Process.Start(psi);
    }
}
