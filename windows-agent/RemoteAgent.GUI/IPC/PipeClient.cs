using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.GUI.IPC;

/// <summary>
/// Named Pipe klient pro komunikaci GUI s Windows službou.
/// </summary>
public class PipeClient : IDisposable
{
    private const string PipeName = "RemoteAgentIPC";
    private NamedPipeClientStream? _pipeClient;
    private StreamReader? _reader;
    private StreamWriter? _writer;
    private CancellationTokenSource? _cts;
    private bool _disposed;

    public event Action<string, JsonElement?>? OnNotification;
    public event Action? OnDisconnected;
    public bool IsConnected => _pipeClient?.IsConnected == true;

    public async Task ConnectAsync(CancellationToken ct = default)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        _pipeClient = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        await _pipeClient.ConnectAsync(5000, _cts.Token);

        _reader = new StreamReader(_pipeClient, Encoding.UTF8);
        _writer = new StreamWriter(_pipeClient, Encoding.UTF8) { AutoFlush = true };

        // Čtení notifikací od služby
        _ = Task.Run(() => ReadNotificationsAsync(_cts.Token), _cts.Token);
    }

    private async Task ReadNotificationsAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested && _pipeClient?.IsConnected == true)
            {
                var line = await _reader!.ReadLineAsync(ct);
                if (line == null) break;

                try
                {
                    var doc = JsonDocument.Parse(line);
                    var type = doc.RootElement.GetProperty("type").GetString() ?? "";
                    JsonElement? payload = doc.RootElement.TryGetProperty("payload", out var p) ? p : null;
                    OnNotification?.Invoke(type, payload);
                }
                catch { }
            }
        }
        catch (OperationCanceledException) { }
        catch { }
        finally
        {
            OnDisconnected?.Invoke();
        }
    }

    public async Task SendCommandAsync(string type, object? payload = null)
    {
        if (_writer == null || _pipeClient?.IsConnected != true) return;

        var msg = new IpcMessage { Type = type, Payload = payload };
        var json = JsonSerializer.Serialize(msg);

        try
        {
            await _writer.WriteLineAsync(json);
        }
        catch { }
    }

    public async Task ConnectRelayAsync(string customerName)
    {
        await SendCommandAsync(IpcCommand.ConnectRelay, new ConnectRelayPayload { CustomerName = customerName });
    }

    public async Task RequestSupportAsync(string customerName, string? message = null)
    {
        await SendCommandAsync(IpcCommand.RequestSupport,
            new RequestSupportIpcPayload { CustomerName = customerName, Message = message });
    }

    public async Task CancelSupportAsync()
    {
        await SendCommandAsync(IpcCommand.CancelSupport);
    }

    public async Task DisconnectAsync()
    {
        await SendCommandAsync(IpcCommand.Disconnect);
    }

    public async Task SetUnattendedPasswordAsync(string password)
    {
        await SendCommandAsync(IpcCommand.SetUnattendedPassword,
            new SetUnattendedPasswordPayload { Password = password });
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _cts?.Cancel();
        _reader?.Dispose();
        _writer?.Dispose();
        _pipeClient?.Dispose();
        _cts?.Dispose();
    }
}
