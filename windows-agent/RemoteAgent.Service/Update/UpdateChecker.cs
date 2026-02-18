using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace RemoteAgent.Service.Update;

/// <summary>
/// Kontroluje dostupnost nových verzí z manifest.json.
/// </summary>
public class UpdateChecker
{
    private readonly ILogger _logger;
    private readonly string _manifestUrl;
    private readonly string _currentVersion;
    private readonly HttpClient _http = new();

    public UpdateChecker(ILogger logger, string manifestUrl, string currentVersion)
    {
        _logger = logger;
        _manifestUrl = manifestUrl;
        _currentVersion = currentVersion;
        _http.Timeout = TimeSpan.FromSeconds(15);
    }

    public async Task<UpdateManifest?> CheckForUpdateAsync()
    {
        try
        {
            var response = await _http.GetStringAsync(_manifestUrl);
            var manifest = JsonSerializer.Deserialize<UpdateManifest>(response);

            if (manifest == null) return null;

            if (IsNewerVersion(manifest.Version, _currentVersion))
            {
                _logger.LogInformation("Update available: {New} (current: {Current})", manifest.Version, _currentVersion);
                return manifest;
            }

            _logger.LogDebug("No update available (current: {Current}, latest: {Latest})", _currentVersion, manifest.Version);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Update check failed: {Error}", ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Kontrola s rozlišením výsledku: aktualizace / aktuální / chyba.
    /// </summary>
    public async Task<UpdateCheckResult> CheckForUpdateDetailedAsync()
    {
        try
        {
            var response = await _http.GetStringAsync(_manifestUrl);
            var manifest = JsonSerializer.Deserialize<UpdateManifest>(response);

            if (manifest == null)
                return new UpdateCheckResult { Status = UpdateStatus.Error, ErrorMessage = "Neplatná odpověď serveru." };

            if (IsNewerVersion(manifest.Version, _currentVersion))
            {
                _logger.LogInformation("Update available: {New} (current: {Current})", manifest.Version, _currentVersion);
                return new UpdateCheckResult { Status = UpdateStatus.UpdateAvailable, Manifest = manifest };
            }

            _logger.LogDebug("No update available (current: {Current}, latest: {Latest})", _currentVersion, manifest.Version);
            return new UpdateCheckResult { Status = UpdateStatus.UpToDate };
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Update check failed: {Error}", ex.Message);
            return new UpdateCheckResult { Status = UpdateStatus.Error, ErrorMessage = ex.Message };
        }
    }

    /// <summary>
    /// Porovnání verzí (semver: major.minor.patch)
    /// </summary>
    private static bool IsNewerVersion(string newVersion, string currentVersion)
    {
        if (!Version.TryParse(newVersion, out var nv)) return false;
        if (!Version.TryParse(currentVersion, out var cv)) return true;
        return nv > cv;
    }
}

public enum UpdateStatus { UpToDate, UpdateAvailable, Error }

public class UpdateCheckResult
{
    public UpdateStatus Status { get; set; }
    public UpdateManifest? Manifest { get; set; }
    public string? ErrorMessage { get; set; }
}

public class UpdateManifest
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = "";

    [JsonPropertyName("download_url")]
    public string DownloadUrl { get; set; } = "";

    [JsonPropertyName("sha256")]
    public string Sha256 { get; set; } = "";

    [JsonPropertyName("release_notes")]
    public string? ReleaseNotes { get; set; }

    [JsonPropertyName("required")]
    public bool Required { get; set; }

    [JsonPropertyName("signature")]
    public string Signature { get; set; } = "";
}
