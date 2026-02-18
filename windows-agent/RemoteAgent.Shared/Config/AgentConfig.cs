using System.Text.Json;
using System.Text.Json.Serialization;

namespace RemoteAgent.Shared.Config;

public class AgentConfig
{
    [JsonPropertyName("relayServerUrl")]
    public string RelayServerUrl { get; set; } = "wss://your-relay-domain.example.com/ws";

    [JsonPropertyName("agentId")]
    public string AgentId { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("reconnectIntervalMs")]
    public int ReconnectIntervalMs { get; set; } = 5000;

    [JsonPropertyName("heartbeatIntervalMs")]
    public int HeartbeatIntervalMs { get; set; } = 10000;

    [JsonPropertyName("captureSettings")]
    public CaptureSettings CaptureSettings { get; set; } = new();

    [JsonIgnore]
    public string AgentVersion => System.Reflection.Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "1.3.0";

    [JsonPropertyName("updateManifestUrl")]
    public string UpdateManifestUrl { get; set; } = "https://your-relay-domain.example.com/update/manifest.json";

    [JsonPropertyName("autoUpdateEnabled")]
    public bool AutoUpdateEnabled { get; set; } = true;

    [JsonPropertyName("updateCheckIntervalHours")]
    public int UpdateCheckIntervalHours { get; set; } = 6;

    [JsonPropertyName("unattendedAccessEnabled")]
    public bool UnattendedAccessEnabled { get; set; } = false;

    [JsonPropertyName("unattendedAccessPasswordHash")]
    public string UnattendedAccessPasswordHash { get; set; } = "";

    /// <summary>
    /// Nastaví heslo pro unattended přístup (SHA-256 hash).
    /// </summary>
    public void SetUnattendedPassword(string password)
    {
        using var sha256 = System.Security.Cryptography.SHA256.Create();
        var bytes = System.Text.Encoding.UTF8.GetBytes(password);
        var hash = sha256.ComputeHash(bytes);
        UnattendedAccessPasswordHash = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        UnattendedAccessEnabled = true;
        Save();
    }

    private static readonly string ConfigDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "RemoteAgent");

    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.json");

    public static AgentConfig Load()
    {
        if (!File.Exists(ConfigPath))
        {
            var config = new AgentConfig();
            config.Save();
            return config;
        }

        var json = File.ReadAllText(ConfigPath);
        return JsonSerializer.Deserialize<AgentConfig>(json) ?? new AgentConfig();
    }

    public void Save()
    {
        Directory.CreateDirectory(ConfigDir);
        var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(ConfigPath, json);
    }
}

public class CaptureSettings
{
    [JsonPropertyName("maxFps")]
    public int MaxFps { get; set; } = 30;

    [JsonPropertyName("defaultQuality")]
    public string DefaultQuality { get; set; } = "medium";

    [JsonPropertyName("codec")]
    public string Codec { get; set; } = "h264";

    [JsonPropertyName("monitorIndex")]
    public int MonitorIndex { get; set; } = 0;
}
