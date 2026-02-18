using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using RemoteAgent.Service.Crypto;
using RemoteAgent.Shared.Config;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service.Network;

public class RelayClient : IDisposable
{
    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);
    private const int SM_CXSCREEN = 0;
    private const int SM_CYSCREEN = 1;

    private ClientWebSocket? _ws;
    private readonly AgentConfig _config;
    private CancellationTokenSource? _cts;
    private bool _disposed;
    private readonly E2ECrypto _e2eCrypto = new();

    /// <summary>
    /// E2E crypto instance pro key exchange a šifrování.
    /// </summary>
    public E2ECrypto Crypto => _e2eCrypto;

    public event Action<string, JsonElement>? OnJsonMessage;
    public event Action<byte[]>? OnBinaryMessage;
    public event Action? OnConnected;
    public event Action<string>? OnDisconnected;
    public event Action<long>? OnHeartbeatRtt;

    public bool IsConnected => _ws?.State == WebSocketState.Open;

    public RelayClient(AgentConfig config)
    {
        _config = config;
    }

    public string CustomerName { get; set; } = "";

    public async Task ConnectAsync(CancellationToken ct = default)
    {
        // Auto-provisioning: pokud nemáme agent token, získat ho
        if (string.IsNullOrEmpty(_config.AgentToken) && !string.IsNullOrEmpty(_config.ProvisionToken))
        {
            await ProvisionAsync(ct);
        }

        // Vynutit šifrované spojení
        if (!_config.RelayServerUrl.StartsWith("wss://", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Only secure WebSocket connections (wss://) are allowed");
        }

        // Vyčistit předchozí spojení pokud existuje
        if (_ws != null)
        {
            _cts?.Cancel();
            if (_ws.State == WebSocketState.Open)
                try { await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Reconnecting", CancellationToken.None); } catch { }
            _ws.Dispose();
            _ws = null;
        }

        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _ws = new ClientWebSocket();

        await _ws.ConnectAsync(new Uri(_config.RelayServerUrl), _cts.Token);
        OnConnected?.Invoke();

        // Registrace na relay serveru
        await SendJsonAsync(new
        {
            type = "agent_register",
            payload = new AgentRegisterPayload
            {
                AgentId = _config.AgentId,
                CustomerName = CustomerName,
                Hostname = Environment.MachineName,
                OsVersion = Environment.OSVersion.ToString(),
                AgentVersion = _config.AgentVersion,
                UnattendedEnabled = _config.UnattendedAccessEnabled,
                UnattendedPasswordHash = _config.UnattendedAccessPasswordHash,
                HwInfo = HardwareInfoCollector.Collect(),
                AgentToken = _config.AgentToken
            }
        });

        // Spustit receive loop a heartbeat
        _ = Task.Run(() => ReceiveLoopAsync(_cts.Token), _cts.Token);
        _ = Task.Run(() => HeartbeatLoopAsync(_cts.Token), _cts.Token);
    }

    /// <summary>
    /// Automatický provisioning – zavolá /api/provision na relay serveru
    /// a získá unikátní agent_token. Volá se jednou při prvním startu.
    /// </summary>
    private async Task ProvisionAsync(CancellationToken ct)
    {
        // Sestavit HTTP URL z WebSocket URL
        var httpUrl = _config.RelayServerUrl
            .Replace("wss://", "https://")
            .Replace("ws://", "http://")
            .Replace("/ws", "/api/provision");

        using var http = new System.Net.Http.HttpClient();
        http.Timeout = TimeSpan.FromSeconds(15);

        var payload = JsonSerializer.Serialize(new
        {
            provision_token = _config.ProvisionToken,
            agent_id = _config.AgentId,
            hostname = Environment.MachineName
        });

        var content = new System.Net.Http.StringContent(payload, Encoding.UTF8, "application/json");
        var response = await http.PostAsync(httpUrl, content, ct);
        var body = await response.Content.ReadAsStringAsync(ct);

        if (response.IsSuccessStatusCode)
        {
            var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("agent_token", out var tokenProp))
            {
                _config.AgentToken = tokenProp.GetString() ?? "";
                _config.Save();
            }
        }
    }

    public async Task ConnectWithRetryAsync(CancellationToken ct = default)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await ConnectAsync(ct);
                return;
            }
            catch (Exception)
            {
                await Task.Delay(_config.ReconnectIntervalMs, ct);
            }
        }
    }

    public async Task SendJsonAsync(object message)
    {
        if (_ws?.State != WebSocketState.Open) return;

        var json = JsonSerializer.Serialize(message);
        var bytes = Encoding.UTF8.GetBytes(json);
        await _ws.SendAsync(bytes, WebSocketMessageType.Text, true, _cts?.Token ?? CancellationToken.None);
    }

    public async Task SendBinaryAsync(byte[] data)
    {
        if (_ws?.State != WebSocketState.Open) return;

        var toSend = _e2eCrypto.IsReady ? _e2eCrypto.Encrypt(data) : data;
        await _ws.SendAsync(toSend, WebSocketMessageType.Binary, true, _cts?.Token ?? CancellationToken.None);
    }

    /// <summary>
    /// Odešle video frame s binárním headerem: [0x01][4B délka][data]
    /// Sestavuje packet in-place – header se zapíše přímo před JPEG data.
    /// </summary>
    public async Task SendVideoFrameAsync(byte[] frameData)
    {
        // Sestavit packet: [type 1B][length 4B][jpeg data]
        // Použít jeden buffer místo kopírování celého JPEG
        const int headerSize = 5;
        var packet = new byte[headerSize + frameData.Length];
        packet[0] = BinaryMessageType.VideoFrame;
        BitConverter.GetBytes(frameData.Length).CopyTo(packet, 1);
        Buffer.BlockCopy(frameData, 0, packet, headerSize, frameData.Length);

        await SendBinaryAsync(packet);
    }

    /// <summary>
    /// Odešle regionální update s hlavičkou [0x05].
    /// Packet je už sestavený v AgentService.
    /// </summary>
    public async Task SendRegionalUpdateAsync(byte[] packet)
    {
        await SendBinaryAsync(packet);
    }

    public async Task RequestSupportAsync(string customerName, string? message = null)
    {
        await SendJsonAsync(new
        {
            type = "request_support",
            payload = new RequestSupportPayload
            {
                CustomerName = customerName,
                Message = message,
                ScreenWidth = GetSystemMetrics(SM_CXSCREEN),
                ScreenHeight = GetSystemMetrics(SM_CYSCREEN)
            }
        });
    }

    public async Task EndSessionAsync(string sessionId, string reason = "completed")
    {
        await SendJsonAsync(new
        {
            type = "session_end",
            payload = new SessionEndPayload
            {
                SessionId = sessionId,
                Reason = reason
            }
        });
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[_config.CaptureSettings.MaxFps > 0 ? 1024 * 1024 * 2 : 65536];

        try
        {
            while (!ct.IsCancellationRequested && _ws?.State == WebSocketState.Open)
            {
                var result = await _ws.ReceiveAsync(buffer, ct);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    OnDisconnected?.Invoke("Server closed connection");
                    break;
                }

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    try
                    {
                        var doc = JsonDocument.Parse(json);
                        var type = doc.RootElement.GetProperty("type").GetString() ?? "";
                        var payload = doc.RootElement.TryGetProperty("payload", out var p) ? p : default;
                        OnJsonMessage?.Invoke(type, payload);
                    }
                    catch { /* invalid JSON */ }
                }
                else if (result.MessageType == WebSocketMessageType.Binary)
                {
                    var raw = new byte[result.Count];
                    Array.Copy(buffer, raw, result.Count);
                    var data = _e2eCrypto.IsReady ? _e2eCrypto.Decrypt(raw) : raw;
                    OnBinaryMessage?.Invoke(data);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (WebSocketException ex)
        {
            OnDisconnected?.Invoke(ex.Message);
        }
    }

    private async Task HeartbeatLoopAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested && _ws?.State == WebSocketState.Open)
            {
                await Task.Delay(_config.HeartbeatIntervalMs, ct);
                await SendJsonAsync(new
                {
                    type = "heartbeat",
                    payload = new { timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() }
                });
            }
        }
        catch (OperationCanceledException) { }
    }

    public async Task DisconnectAsync()
    {
        _cts?.Cancel();
        if (_ws?.State == WebSocketState.Open)
        {
            await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Disconnecting", CancellationToken.None);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _cts?.Cancel();
        _ws?.Dispose();
        _cts?.Dispose();
        _e2eCrypto.Dispose();
    }
}
