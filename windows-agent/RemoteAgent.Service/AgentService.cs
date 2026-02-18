using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RemoteAgent.Service.Clipboard;
using RemoteAgent.Service.Crypto;
using RemoteAgent.Service.FileTransfer;
using RemoteAgent.Service.IPC;
using RemoteAgent.Service.InputInjection;
using RemoteAgent.Service.Network;
using RemoteAgent.Service.ScreenCapture;
using RemoteAgent.Service.Streaming;
using RemoteAgent.Service.Update;
using RemoteAgent.Shared.Config;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service;

/// <summary>
/// Hlavní logika Windows služby – propojuje všechny komponenty.
/// </summary>
public class AgentService : BackgroundService
{
    private readonly ILogger<AgentService> _logger;
    private readonly AgentConfig _config;
    private readonly AgentSessionManager _sessionManager;
    private readonly RelayClient _relayClient;
    private readonly MessageHandler _messageHandler;
    private readonly PipeServer _pipeServer;
    private readonly MouseInjector _mouseInjector;
    private readonly KeyboardInjector _keyboardInjector;
    private readonly AdaptiveQualityController _adaptiveQuality = new();

    private bool _adaptiveMode = true; // Výchozí: auto (adaptivní kvalita)
    private DxgiCapture? _capture;
    private ScreenEncoder? _encoder;
    private DesktopSwitcher? _desktopSwitcher;
    private ClipboardMonitor? _clipboardMonitor;
    private FileTransferManager? _fileTransfer;
    private CancellationTokenSource? _streamingCts;
    private CancellationTokenSource? _e2eFallbackCts;

    public AgentService(ILogger<AgentService> logger)
    {
        _logger = logger;
        _config = AgentConfig.Load();
        _sessionManager = new AgentSessionManager();
        _relayClient = new RelayClient(_config);
        _messageHandler = new MessageHandler();
        _pipeServer = new PipeServer();
        _mouseInjector = new MouseInjector();
        _keyboardInjector = new KeyboardInjector();

        WireEvents();
    }

    private void WireEvents()
    {
        // Relay zprávy → MessageHandler
        _relayClient.OnJsonMessage += _messageHandler.HandleJsonMessage;
        _relayClient.OnBinaryMessage += _messageHandler.HandleBinaryMessage;

        // MessageHandler eventy
        _messageHandler.OnRegistered += OnAgentRegistered;
        _messageHandler.OnSessionAccepted += OnSessionAccepted;
        _messageHandler.OnSessionEnded += OnSessionEnded;
        _messageHandler.OnError += OnRelayError;
        _messageHandler.OnQualityChange += OnQualityChange;
        _messageHandler.OnInputData += OnInputData;
        _messageHandler.OnChatMessage += OnChatReceived;
        _messageHandler.OnClipboardData += OnClipboardReceived;
        _messageHandler.OnFileTransferData += OnFileTransferData;
        _messageHandler.OnFileTransferControl += OnFileTransferControl;
        _messageHandler.OnE2EKeyExchange += OnE2EKeyExchange;
        _messageHandler.OnEncryptedChatMessage += OnEncryptedChatReceived;
        _messageHandler.OnHeartbeatRtt += OnHeartbeatRtt;

        // IPC příkazy z GUI
        _pipeServer.OnCommand += OnIpcCommand;

        // Session state changes
        _sessionManager.OnStateChanged += OnStateChanged;

        // Relay connection events
        _relayClient.OnDisconnected += async (reason) =>
        {
            _logger.LogWarning("Relay disconnected: {Reason}", reason);
            _relayClient.Crypto.Reset();
            _sessionManager.Reset();
            await _pipeServer.SendStatusAsync("disconnected", reason);

            // Auto-reconnect pokud je unattended přístup povolený a neběží embedded
            var isEmbedded = Environment.GetEnvironmentVariable("SERVIDESK_EMBEDDED") == "1";
            if (_config.UnattendedAccessEnabled && !isEmbedded)
            {
                _logger.LogInformation("Unattended mode active, auto-reconnecting in 5s...");
                await Task.Delay(5000);
                await ConnectToRelayAsync();
            }
        };
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("AgentService starting...");

        // Spustit Named Pipe server pro komunikaci s GUI
        _ = Task.Run(() => _pipeServer.StartAsync(stoppingToken), stoppingToken);

        // Spustit periodickou kontrolu aktualizací
        if (_config.AutoUpdateEnabled)
        {
            _ = Task.Run(() => UpdateCheckLoopAsync(stoppingToken), stoppingToken);
        }

        // Auto-connect k relay pokud je unattended přístup povolený
        // (ne když běží embedded v GUI – uživatel musí kliknout "Povolit připojení")
        var isEmbedded = Environment.GetEnvironmentVariable("SERVIDESK_EMBEDDED") == "1";
        if (_config.UnattendedAccessEnabled && !isEmbedded)
        {
            _logger.LogInformation("Unattended access enabled, auto-connecting to relay...");
            _ = Task.Run(async () =>
            {
                await Task.Delay(2000, stoppingToken); // Počkat na inicializaci
                await ConnectToRelayAsync();
            }, stoppingToken);
        }

        _logger.LogInformation("AgentService started, waiting for GUI commands via Named Pipe");

        // Čekat na ukončení
        await Task.Delay(Timeout.Infinite, stoppingToken);
    }

    /// <summary>
    /// Připojí se k relay serveru. Používá hostname jako customer name pro unattended režim.
    /// </summary>
    private async Task ConnectToRelayAsync()
    {
        if (_relayClient.IsConnected) return;

        try
        {
            _relayClient.CustomerName = string.IsNullOrEmpty(_relayClient.CustomerName)
                ? Environment.MachineName
                : _relayClient.CustomerName;
            await _relayClient.ConnectWithRetryAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to connect to relay");
        }
    }

    private async Task UpdateCheckLoopAsync(CancellationToken ct)
    {
        var checker = new UpdateChecker(_logger, _config.UpdateManifestUrl, _config.AgentVersion);
        var installer = new UpdateInstaller(_logger);
        var interval = TimeSpan.FromHours(_config.UpdateCheckIntervalHours);

        // Počkat 10 sekund po startu (dostatečné pro inicializaci)
        await Task.Delay(TimeSpan.FromSeconds(10), ct);

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var manifest = await checker.CheckForUpdateAsync();
                if (manifest != null)
                {
                    // Notify GUI
                    await _pipeServer.SendNotificationAsync(IpcNotification.UpdateAvailable,
                        new UpdateAvailablePayload
                        {
                            Version = manifest.Version,
                            ReleaseNotes = manifest.ReleaseNotes
                        });

                    // Auto-install if required
                    if (manifest.Required)
                    {
                        _logger.LogInformation("Required update {Version}, installing...", manifest.Version);
                        await installer.DownloadAndInstallAsync(manifest);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Update check error: {Error}", ex.Message);
            }

            await Task.Delay(interval, ct);
        }
    }

    // ── IPC příkazy z GUI ──

    private async void OnIpcCommand(string type, JsonElement? payload)
    {
        switch (type)
        {
            case IpcCommand.ConnectRelay:
            {
                if (payload.HasValue)
                {
                    var data = JsonSerializer.Deserialize<ConnectRelayPayload>(payload.Value.GetRawText());
                    if (data != null)
                        _relayClient.CustomerName = data.CustomerName;
                }
                _logger.LogInformation("GUI requested relay connection for: {Name}", _relayClient.CustomerName);

                if (_relayClient.IsConnected)
                {
                    // Už jsme připojeni k relay (např. z unattended auto-connect) → jen oznámit GUI
                    _logger.LogInformation("Already connected to relay, notifying GUI");
                    await _pipeServer.SendStatusAsync("connected");
                }
                else
                {
                    try
                    {
                        await _relayClient.ConnectAsync();
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to connect to relay");
                        await _pipeServer.SendErrorAsync("CONNECTION_FAILED", ex.Message);
                    }
                }
                break;
            }

            case IpcCommand.RequestSupport:
            {
                if (payload.HasValue)
                {
                    var data = JsonSerializer.Deserialize<RequestSupportIpcPayload>(payload.Value.GetRawText());
                    if (data != null)
                    {
                        _logger.LogInformation("Customer requested support: {Name}", data.CustomerName);
                        await _relayClient.RequestSupportAsync(data.CustomerName, data.Message);
                        _sessionManager.TransitionTo(SessionState.Waiting);
                    }
                }
                break;
            }

            case IpcCommand.CancelSupport:
            {
                if (_sessionManager.SessionId != null)
                {
                    await _relayClient.EndSessionAsync(_sessionManager.SessionId, "cancelled");
                }
                _sessionManager.Reset();
                break;
            }

            case IpcCommand.SendChat:
            {
                if (payload.HasValue)
                {
                    var chatData = JsonSerializer.Deserialize<ChatMessagePayload>(payload.Value.GetRawText());
                    if (chatData != null)
                    {
                        if (_relayClient.Crypto.IsReady)
                        {
                            // E2E: šifrovat payload jako base64
                            var plainPayload = JsonSerializer.Serialize(new { message = chatData.Message, sender = "customer", timestamp = DateTime.UtcNow.ToString("o") });
                            var encrypted = _relayClient.Crypto.EncryptToBase64(plainPayload);
                            await _relayClient.SendJsonAsync(new
                            {
                                type = "chat_message",
                                payload = new { encrypted }
                            });
                        }
                        else
                        {
                            await _relayClient.SendJsonAsync(new
                            {
                                type = "chat_message",
                                payload = new { message = chatData.Message, sender = "customer", timestamp = DateTime.UtcNow.ToString("o") }
                            });
                        }
                    }
                }
                break;
            }

            case IpcCommand.FileSavePath:
            {
                if (payload.HasValue)
                {
                    var data = JsonSerializer.Deserialize<FileSavePathPayload>(payload.Value.GetRawText());
                    if (data != null)
                    {
                        _fileTransfer?.SetSavePath(data.TransferId, data.SavePath);
                    }
                }
                break;
            }

            case IpcCommand.SetUnattendedPassword:
            {
                if (payload.HasValue)
                {
                    var data = JsonSerializer.Deserialize<SetUnattendedPasswordPayload>(payload.Value.GetRawText());
                    if (data != null && !string.IsNullOrEmpty(data.Password))
                    {
                        _config.SetUnattendedPassword(data.Password);
                        _logger.LogInformation("Unattended access password set, enabled={Enabled}", _config.UnattendedAccessEnabled);

                        if (_relayClient.IsConnected)
                        {
                            // Už jsme připojeni – poslat update
                            await _relayClient.SendJsonAsync(new
                            {
                                type = "update_agent_info",
                                payload = new
                                {
                                    unattended_enabled = _config.UnattendedAccessEnabled,
                                    unattended_password_hash = _config.UnattendedAccessPasswordHash
                                }
                            });
                            _logger.LogInformation("Sent unattended status update to relay");
                        }
                        else
                        {
                            // Nejsme připojeni – připojit se (registrace pošle unattended info)
                            _logger.LogInformation("Not connected to relay, connecting for unattended mode...");
                            _ = Task.Run(ConnectToRelayAsync);
                        }

                        // Potvrdit GUI
                        await _pipeServer.SendStatusAsync("unattended_password_set", "Heslo nastaveno, vzdálený přístup aktivní.");
                    }
                }
                break;
            }

            case IpcCommand.DisableUnattendedAccess:
            {
                _config.UnattendedAccessEnabled = false;
                _config.UnattendedAccessPasswordHash = "";
                _config.Save();
                _logger.LogInformation("Unattended access disabled");

                // Odpojit od relay pokud není aktivní session
                if (_relayClient.IsConnected && _sessionManager.SessionId == null)
                {
                    await _relayClient.DisconnectAsync();
                }

                await _pipeServer.SendStatusAsync("unattended_disabled", "Vzdálený přístup byl zrušen.");
                break;
            }

            case IpcCommand.CheckUpdate:
            {
                var checker = new UpdateChecker(_logger, _config.UpdateManifestUrl, _config.AgentVersion);
                var result = await checker.CheckForUpdateDetailedAsync();
                switch (result.Status)
                {
                    case UpdateStatus.UpdateAvailable:
                        await _pipeServer.SendNotificationAsync(IpcNotification.UpdateAvailable,
                            new UpdateAvailablePayload
                            {
                                Version = result.Manifest!.Version,
                                ReleaseNotes = result.Manifest.ReleaseNotes
                            });
                        break;
                    case UpdateStatus.UpToDate:
                        await _pipeServer.SendNotificationAsync(IpcNotification.UpdateCheckResult,
                            new UpdateCheckResultPayload
                            {
                                UpToDate = true,
                                Message = $"Máte nejnovější verzi ({_config.AgentVersion})."
                            });
                        break;
                    case UpdateStatus.Error:
                        await _pipeServer.SendNotificationAsync(IpcNotification.UpdateCheckResult,
                            new UpdateCheckResultPayload
                            {
                                UpToDate = false,
                                Message = $"Nepodařilo se zkontrolovat: {result.ErrorMessage}"
                            });
                        break;
                }
                break;
            }

            case IpcCommand.EndSession:
            {
                // Ukončit session ale nechat relay spojení aktivní (pro unattended režim)
                _e2eFallbackCts?.Cancel();
                _e2eFallbackCts = null;
                await StopStreamingAsync();
                if (_sessionManager.SessionId != null)
                {
                    await _relayClient.EndSessionAsync(_sessionManager.SessionId, "completed");
                }
                _relayClient.Crypto.Reset();
                _sessionManager.Reset();
                break;
            }

            case IpcCommand.Disconnect:
            {
                _e2eFallbackCts?.Cancel();
                _e2eFallbackCts = null;
                await StopStreamingAsync();
                if (_sessionManager.SessionId != null)
                {
                    await _relayClient.EndSessionAsync(_sessionManager.SessionId, "completed");
                }
                await _relayClient.DisconnectAsync();
                _relayClient.Crypto.Reset();
                _sessionManager.Reset();
                break;
            }
        }
    }

    // ── Relay eventy ──

    private async void OnAgentRegistered(string sessionId)
    {
        _sessionManager.SetSessionId(sessionId);
        _sessionManager.TransitionTo(SessionState.Registered);
        _logger.LogInformation("Registered with session: {SessionId}", sessionId);
        await _pipeServer.SendStatusAsync("connected");
    }

    private async void OnSessionAccepted(string adminName, string message)
    {
        _sessionManager.SetAdminName(adminName);
        _logger.LogInformation("Session accepted by: {Admin}. Waiting for E2E key exchange...", adminName);

        await _pipeServer.SendNotificationAsync(IpcNotification.SessionAccepted,
            new SessionAcceptedIpcPayload { AdminName = adminName });

        // Čekáme na E2E key exchange od vieweru.
        // Fallback: pokud E2E nepřijde do 5s, spustit nešifrovaný streaming (starší viewer).
        _e2eFallbackCts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(5000, _e2eFallbackCts.Token);
                // Timeout – viewer neposlal E2E key exchange
                if (!_relayClient.Crypto.IsReady)
                {
                    _logger.LogWarning("E2E: Timeout, starting unencrypted streaming (legacy viewer)");
                    _sessionManager.TransitionTo(SessionState.Streaming);
                    SendMonitorInfo();
                    StartStreaming();
                }
            }
            catch (OperationCanceledException) { /* E2E přišlo včas */ }
        });
    }

    private async void OnSessionEnded(string reason, string endedBy)
    {
        _logger.LogInformation("Session ended: {Reason} by {EndedBy}", reason, endedBy);
        _e2eFallbackCts?.Cancel();
        _e2eFallbackCts = null;
        await StopStreamingAsync();
        _relayClient.Crypto.Reset();
        _sessionManager.Reset();

        await _pipeServer.SendNotificationAsync(IpcNotification.SessionEnded,
            new SessionEndedIpcPayload { Reason = reason, EndedBy = endedBy });
    }

    private async void OnRelayError(string code, string message)
    {
        _logger.LogWarning("Relay error: {Code} – {Message}", code, message);
        await _pipeServer.SendErrorAsync(code, message);
    }

    private async void SendMonitorInfo()
    {
        try
        {
            var monitors = MonitorEnumerator.GetMonitors();
            _logger.LogInformation("Monitors found: {Count}", monitors.Count);
            await _relayClient.SendJsonAsync(new
            {
                type = "monitor_info",
                payload = new
                {
                    monitors = monitors.Select(m => new
                    {
                        index = m.Index,
                        name = m.Name,
                        width = m.Width,
                        height = m.Height,
                        is_primary = m.IsPrimary
                    }).ToArray(),
                    active_index = _config.CaptureSettings.MonitorIndex
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Failed to enumerate monitors: {Error}", ex.Message);
        }
    }

    private async void SwitchMonitor(int monitorIndex)
    {
        _logger.LogInformation("Switching to monitor {Index}", monitorIndex);

        // Stop current streaming
        _streamingCts?.Cancel();
        await Task.Delay(100);

        _clipboardMonitor?.StopMonitoring();
        _capture?.Dispose();
        _encoder?.Dispose();

        // Reinitialize with new monitor
        _config.CaptureSettings.MonitorIndex = monitorIndex;
        _streamingCts = new CancellationTokenSource();

        _capture = new DxgiCapture();
        _capture.Initialize(monitorIndex);

        _encoder = new ScreenEncoder();
        _encoder.Initialize(_capture.ScreenWidth, _capture.ScreenHeight);

        _clipboardMonitor?.StartMonitoring(_streamingCts.Token);

        // Notify viewer of the switch
        await _relayClient.SendJsonAsync(new
        {
            type = "monitor_switched",
            payload = new
            {
                monitor_index = monitorIndex,
                width = _capture.ScreenWidth,
                height = _capture.ScreenHeight
            }
        });

        _ = Task.Run(() => StreamingLoopAsync(_streamingCts.Token));
    }

    private void OnQualityChange(QualityChangePayload qc)
    {
        if (qc.Quality == "auto")
        {
            _adaptiveMode = true;
            _adaptiveQuality.IsEnabled = true;
            _logger.LogInformation("Adaptive quality mode enabled");
            return;
        }

        _adaptiveMode = false;
        _adaptiveQuality.IsEnabled = false;
        _logger.LogInformation("Quality change: {Quality}, FPS: {Fps}", qc.Quality, qc.Fps);
        _encoder?.ChangeQuality(qc.Quality, qc.Fps > 0 ? qc.Fps : null);
    }

    private void OnHeartbeatRtt(long rttMs)
    {
        _adaptiveQuality.UpdateRtt(rttMs);

        if (_adaptiveMode && _encoder != null)
        {
            var (quality, fps) = _adaptiveQuality.GetRecommendedSettings();
            if (quality != _encoder.Quality || fps != _encoder.Fps)
            {
                _logger.LogInformation("Adaptive: RTT={Rtt}ms -> quality={Quality}, fps={Fps}",
                    _adaptiveQuality.AverageRtt, quality, fps);
                _encoder.ChangeQuality(quality, fps);
            }
        }
    }

    private async void OnChatReceived(ChatMessagePayload chat)
    {
        _logger.LogInformation("Chat from {Sender}: {Message}", chat.Sender, chat.Message);
        await _pipeServer.SendNotificationAsync(IpcNotification.ChatMessage, chat);
    }

    private async void OnE2EKeyExchange(string peerPublicKey)
    {
        // Zrušit fallback timer — E2E přišlo včas
        _e2eFallbackCts?.Cancel();
        _e2eFallbackCts = null;

        try
        {
            // Vygenerovat vlastní key pair
            var myPublicKey = _relayClient.Crypto.GenerateKeyPair();

            // Odeslat náš public key vieweru
            await _relayClient.SendJsonAsync(new
            {
                type = "e2e_key_exchange",
                payload = new { public_key = myPublicKey }
            });

            // Odvodit sdílený klíč
            _relayClient.Crypto.DeriveSharedKey(peerPublicKey);

            _logger.LogInformation("E2E: Encryption established!");

            // Nyní spustit streaming (čekali jsme na E2E)
            _sessionManager.TransitionTo(SessionState.Streaming);
            SendMonitorInfo();
            StartStreaming();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "E2E key exchange failed, starting unencrypted streaming");
            _sessionManager.TransitionTo(SessionState.Streaming);
            SendMonitorInfo();
            StartStreaming();
        }
    }

    private async void OnEncryptedChatReceived(string encryptedBase64)
    {
        try
        {
            var json = _relayClient.Crypto.DecryptFromBase64(encryptedBase64);
            var chat = JsonSerializer.Deserialize<ChatMessagePayload>(json);
            if (chat != null)
            {
                _logger.LogInformation("E2E Chat from {Sender}: {Message}", chat.Sender, chat.Message);
                await _pipeServer.SendNotificationAsync(IpcNotification.ChatMessage, chat);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Failed to decrypt chat message: {Error}", ex.Message);
        }
    }

    private void OnClipboardReceived(string text)
    {
        _logger.LogInformation("Clipboard received from viewer: {Length} chars", text.Length);
        _clipboardMonitor?.SetClipboardText(text);
    }

    private void OnFileTransferData(byte[] data)
    {
        _fileTransfer?.HandleBinaryChunk(data);
    }

    private void OnFileTransferControl(string type, System.Text.Json.JsonElement payload)
    {
        _fileTransfer?.HandleControlMessage(type, payload);
    }

    private async void OnClipboardChanged(string text)
    {
        _logger.LogInformation("Clipboard changed locally: {Length} chars", text.Length);
        var payload = Encoding.UTF8.GetBytes(text);
        var packet = new byte[1 + 4 + payload.Length];
        packet[0] = BinaryMessageType.ClipboardData;
        BitConverter.GetBytes(payload.Length).CopyTo(packet, 1);
        payload.CopyTo(packet, 5);
        await _relayClient.SendBinaryAsync(packet);
    }

    private void OnInputData(byte[] data)
    {
        // Parsovat input event z binární zprávy
        if (data.Length < 5) return;

        var payloadLength = BitConverter.ToInt32(data, 1);
        if (data.Length < 5 + payloadLength) return;

        var json = Encoding.UTF8.GetString(data, 5, payloadLength);

        try
        {
            var doc = JsonDocument.Parse(json);
            var type = doc.RootElement.GetProperty("type").GetString();

            // Log non-mouse_move events (mouse_move je příliš chatty)
            if (type != "mouse_move")
            {
                _logger.LogInformation("Input event received: {Type}", type);
            }

            switch (type)
            {
                case "mouse_move":
                    var mx = doc.RootElement.GetProperty("x").GetDouble();
                    var my = doc.RootElement.GetProperty("y").GetDouble();
                    _mouseInjector.MoveTo(mx, my);
                    break;

                case "mouse_click":
                    var btn = doc.RootElement.GetProperty("button").GetString() ?? "left";
                    var act = doc.RootElement.GetProperty("action").GetString() ?? "down";
                    var cx = doc.RootElement.GetProperty("x").GetDouble();
                    var cy = doc.RootElement.GetProperty("y").GetDouble();
                    _mouseInjector.Click(btn, act, cx, cy);
                    break;

                case "mouse_scroll":
                    var dx = doc.RootElement.GetProperty("delta_x").GetInt32();
                    var dy = doc.RootElement.GetProperty("delta_y").GetInt32();
                    _mouseInjector.Scroll(dx, dy);
                    break;

                case "key":
                    var keyAction = doc.RootElement.GetProperty("action").GetString();
                    var keyCode = (ushort)doc.RootElement.GetProperty("key_code").GetInt32();

                    // Unicode char injection pro české/speciální znaky
                    string? charStr = null;
                    if (doc.RootElement.TryGetProperty("char", out var charEl))
                        charStr = charEl.GetString();

                    // Modifikátory — pokud Ctrl je stisknutý, je to shortcut → VK code
                    bool ctrlHeld = false;
                    if (doc.RootElement.TryGetProperty("modifiers", out var modEl))
                        ctrlHeld = modEl.TryGetProperty("ctrl", out var ctrlEl) && ctrlEl.GetBoolean();

                    // Použít Unicode injection pokud:
                    // - máme char field
                    // - není Ctrl held (Ctrl+C = shortcut, ne znak)
                    // - char je tisknutelný (délka 1)
                    bool useUnicode = !string.IsNullOrEmpty(charStr) && !ctrlHeld && charStr.Length == 1;

                    if (useUnicode)
                    {
                        if (keyAction == "down") _keyboardInjector.UnicodeKeyDown(charStr![0]);
                        else if (keyAction == "up") _keyboardInjector.UnicodeKeyUp(charStr![0]);
                    }
                    else
                    {
                        if (keyAction == "down") _keyboardInjector.KeyDown(keyCode);
                        else if (keyAction == "up") _keyboardInjector.KeyUp(keyCode);
                    }
                    break;

                case "special_key":
                    var combo = doc.RootElement.GetProperty("combination").GetString();
                    if (combo != null) _keyboardInjector.SendSpecialKey(combo);
                    break;

                case "quality_change":
                    var qFps = doc.RootElement.TryGetProperty("fps", out var fpsEl) ? fpsEl.GetInt32() : 0;
                    var qQuality = doc.RootElement.TryGetProperty("quality", out var qEl) ? qEl.GetString() ?? "medium" : "medium";
                    _logger.LogInformation("Quality change: {Quality}, FPS: {Fps}", qQuality, qFps);
                    _encoder?.ChangeQuality(qQuality, qFps > 0 ? qFps : null);
                    break;

                case "switch_monitor":
                    var monIdx = doc.RootElement.GetProperty("monitor_index").GetInt32();
                    SwitchMonitor(monIdx);
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Failed to parse input event: {Error}", ex.Message);
        }
    }

    private void OnStateChanged(SessionState oldState, SessionState newState)
    {
        _logger.LogInformation("State: {Old} → {New}", oldState, newState);
    }

    // ── Streaming ──

    private void StartStreaming()
    {
        _streamingCts = new CancellationTokenSource();
        _desktopSwitcher = new DesktopSwitcher();

        _capture = new DxgiCapture();
        _capture.Initialize(_config.CaptureSettings.MonitorIndex);

        _encoder = new ScreenEncoder();
        _encoder.Initialize(_capture.ScreenWidth, _capture.ScreenHeight);

        // Clipboard monitoring
        _clipboardMonitor = new ClipboardMonitor(_logger);
        _clipboardMonitor.OnClipboardChanged += OnClipboardChanged;
        _clipboardMonitor.StartMonitoring(_streamingCts.Token);

        // File transfer
        _fileTransfer = new FileTransferManager(_logger);
        _fileTransfer.OnSendJson += async (msg) => await _relayClient.SendJsonAsync(msg);
        _fileTransfer.OnFileIncoming += async (type, payload) => await _pipeServer.SendNotificationAsync(type, payload);
        _fileTransfer.OnFileReceived += async (type, payload) => await _pipeServer.SendNotificationAsync(type, payload);

        _ = Task.Run(() => StreamingLoopAsync(_streamingCts.Token));
    }

    private async Task StreamingLoopAsync(CancellationToken ct)
    {
        var desktopCheckCounter = 0;
        var sw = new System.Diagnostics.Stopwatch();

        // Diagnostické počítadla
        var totalFrames = 0;
        var capturedFrames = 0;
        var encodedChunks = 0;
        var sentChunks = 0;
        var regionalFrames = 0;
        var fullFramesSent = 0;
        var skippedFrames = 0;
        var keyframeCounter = 0;
        const int keyframeInterval = 60; // Keyframe každých ~2s při 30fps
        var lastLogTime = DateTime.UtcNow;

        // Frame skip: backpressure detekce
        bool sendInProgress = false;

        var frameIntervalMs = 1000 / _config.CaptureSettings.MaxFps;
        _logger.LogInformation("Streaming loop started (MJPEG+SkiaSharp). Resolution: {W}x{H}, FPS: {Fps}, Interval: {Ms}ms, AdaptiveMode: {Auto}",
            _capture!.ScreenWidth, _capture!.ScreenHeight, _config.CaptureSettings.MaxFps, frameIntervalMs, _adaptiveMode);

        try
        {
            while (!ct.IsCancellationRequested)
            {
                sw.Restart();
                totalFrames++;

                // Periodická kontrola přepnutí desktopu (UAC)
                desktopCheckCounter++;
                if (desktopCheckCounter >= 15)
                {
                    desktopCheckCounter = 0;
                    if (_desktopSwitcher!.CheckDesktopChange())
                    {
                        _logger.LogInformation("Desktop changed, reinitializing capture");
                        _capture!.Reinitialize(_config.CaptureSettings.MonitorIndex);
                    }
                }

                // Zachytit frame
                var frame = _capture!.CaptureFrame();
                if (frame != null)
                {
                    capturedFrames++;
                    keyframeCounter++;

                    // Frame skip: pokud předchozí send ještě běží, přeskočit encode+send
                    if (sendInProgress)
                    {
                        skippedFrames++;
                    }
                    else
                    {
                        var forceKeyframe = keyframeCounter >= keyframeInterval;

                        // Delta encoding: pokud máme dirty rects a nejde o keyframe
                        var sentRegional = false;
                        if (!forceKeyframe && frame.DirtyRegions != null && frame.DirtyRegions.Count > 0)
                        {
                            var regions = _encoder!.EncodeRegions(frame.PixelData, frame.Width, frame.Height, frame.DirtyRegions);
                            if (regions != null)
                            {
                                // Sestavit regionální packet: [0x05][4B total_length][2B region_count][per region...]
                                var totalPayloadSize = 2; // region_count
                                foreach (var (r, jpeg) in regions)
                                    totalPayloadSize += 2 + 2 + 2 + 2 + 4 + jpeg.Length; // x,y,w,h,jpeg_size,jpeg

                                var packet = new byte[1 + 4 + totalPayloadSize];
                                packet[0] = BinaryMessageType.RegionalUpdate;
                                BitConverter.GetBytes(totalPayloadSize).CopyTo(packet, 1);
                                BitConverter.GetBytes((ushort)regions.Count).CopyTo(packet, 5);

                                var offset = 7;
                                foreach (var (r, jpeg) in regions)
                                {
                                    BitConverter.GetBytes((ushort)r.X).CopyTo(packet, offset); offset += 2;
                                    BitConverter.GetBytes((ushort)r.Y).CopyTo(packet, offset); offset += 2;
                                    BitConverter.GetBytes((ushort)r.Width).CopyTo(packet, offset); offset += 2;
                                    BitConverter.GetBytes((ushort)r.Height).CopyTo(packet, offset); offset += 2;
                                    BitConverter.GetBytes(jpeg.Length).CopyTo(packet, offset); offset += 4;
                                    jpeg.CopyTo(packet, offset); offset += jpeg.Length;
                                }

                                sendInProgress = true;
                                await _relayClient.SendBinaryAsync(packet);
                                sendInProgress = false;
                                regionalFrames++;
                                encodedChunks += regions.Count;
                                sentChunks++;
                                sentRegional = true;
                            }
                            // else: dirty area > 50% → fallback na full frame (sentRegional zůstane false)
                        }

                        if (!sentRegional)
                        {
                            // Full frame (keyframe, bez dirty rects, nebo dirty area > 50%)
                            if (forceKeyframe) keyframeCounter = 0;
                            var encoded = _encoder!.EncodeFrame(frame.PixelData);
                            if (encoded != null)
                            {
                                encodedChunks++;
                                sendInProgress = true;
                                await _relayClient.SendVideoFrameAsync(encoded);
                                sendInProgress = false;
                                sentChunks++;
                                fullFramesSent++;
                            }
                        }
                    }
                }

                // Diagnostický log každé 3 sekundy
                if ((DateTime.UtcNow - lastLogTime).TotalSeconds >= 3)
                {
                    _logger.LogInformation(
                        "DIAG: loops={Total}, captured={Cap}, encoded={Enc}, sent={Sent}, full={Full}, regional={Reg}, skipped={Skip}",
                        totalFrames, capturedFrames, encodedChunks, sentChunks, fullFramesSent, regionalFrames, skippedFrames);
                    lastLogTime = DateTime.UtcNow;
                }

                // Stopwatch timing: odečíst dobu capture+encode+send od intervalu
                var currentInterval = _encoder!.Fps > 0 ? 1000 / _encoder.Fps : frameIntervalMs;
                var elapsed = (int)sw.ElapsedMilliseconds;
                var remaining = Math.Max(1, currentInterval - elapsed);
                await Task.Delay(remaining, ct);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Streaming error");
        }

        _logger.LogInformation("Streaming loop ended. Total: {Total}, Captured: {Cap}, Encoded: {Enc}, Sent: {Sent}, Skipped: {Skip}",
            totalFrames, capturedFrames, encodedChunks, sentChunks, skippedFrames);
    }

    private async Task StopStreamingAsync()
    {
        _streamingCts?.Cancel();
        await Task.Delay(100); // Počkat na dokončení loop

        _clipboardMonitor?.Dispose();
        _clipboardMonitor = null;
        _fileTransfer = null;
        _capture?.Dispose();
        _encoder?.Dispose();
        _capture = null;
        _encoder = null;
        _desktopSwitcher = null;
    }

    public override void Dispose()
    {
        _streamingCts?.Cancel();
        _clipboardMonitor?.Dispose();
        _capture?.Dispose();
        _encoder?.Dispose();
        _relayClient.Dispose();
        _pipeServer.Dispose();
        base.Dispose();
    }
}
