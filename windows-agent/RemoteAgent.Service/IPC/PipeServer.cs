using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service.IPC;

/// <summary>
/// Named Pipe server pro komunikaci služby s GUI aplikací.
/// Pipe: \\.\pipe\RemoteAgentIPC
/// </summary>
public class PipeServer : IDisposable
{
    private const string PipeName = "RemoteAgentIPC";
    private NamedPipeServerStream? _pipeServer;
    private StreamReader? _reader;
    private StreamWriter? _writer;
    private CancellationTokenSource? _cts;
    private bool _disposed;

    public event Action<string, JsonElement?>? OnCommand;
    public bool IsClientConnected => _pipeServer?.IsConnected == true;

    public async Task StartAsync(CancellationToken ct = default)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        while (!_cts.Token.IsCancellationRequested)
        {
            try
            {
                // Vytvořit pipe s ACL – přístup SYSTEM + aktuální uživatel
                var pipeSecurity = new PipeSecurity();
                pipeSecurity.AddAccessRule(new PipeAccessRule(
                    new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                    PipeAccessRights.FullControl, AccessControlType.Allow));
                pipeSecurity.AddAccessRule(new PipeAccessRule(
                    new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
                    PipeAccessRights.ReadWrite, AccessControlType.Allow));

                _pipeServer = NamedPipeServerStreamAcl.Create(
                    PipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous,
                    inBufferSize: 65536,
                    outBufferSize: 65536,
                    pipeSecurity);

                await _pipeServer.WaitForConnectionAsync(_cts.Token);

                _reader = new StreamReader(_pipeServer, Encoding.UTF8);
                _writer = new StreamWriter(_pipeServer, Encoding.UTF8) { AutoFlush = true };

                // Čtení příkazů od GUI
                await ReadCommandsAsync(_cts.Token);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception)
            {
                // GUI se odpojilo, čekat na nové připojení
                DisposePipe();
                await Task.Delay(500, _cts.Token);
            }
        }
    }

    private async Task ReadCommandsAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested && _pipeServer?.IsConnected == true)
            {
                var line = await _reader!.ReadLineAsync(ct);
                if (line == null) break; // Klient se odpojil

                try
                {
                    var doc = JsonDocument.Parse(line);
                    var type = doc.RootElement.GetProperty("type").GetString() ?? "";
                    JsonElement? payload = doc.RootElement.TryGetProperty("payload", out var p) ? p : null;
                    OnCommand?.Invoke(type, payload);
                }
                catch { /* nevalidní JSON */ }
            }
        }
        catch (OperationCanceledException) { }
        catch { /* pipe broken */ }
        finally
        {
            DisposePipe();
        }
    }

    public async Task SendNotificationAsync(string type, object? payload = null)
    {
        if (_writer == null || _pipeServer?.IsConnected != true) return;

        var msg = new IpcMessage { Type = type, Payload = payload };
        var json = JsonSerializer.Serialize(msg);

        try
        {
            await _writer.WriteLineAsync(json);
        }
        catch { /* pipe broken */ }
    }

    public async Task SendStatusAsync(string status, string? message = null)
    {
        await SendNotificationAsync(IpcNotification.StatusUpdate,
            new StatusUpdatePayload { Status = status, Message = message });
    }

    public async Task SendErrorAsync(string code, string message)
    {
        await SendNotificationAsync(IpcNotification.Error,
            new ErrorIpcPayload { Code = code, Message = message });
    }

    private void DisposePipe()
    {
        _reader?.Dispose();
        _writer?.Dispose();
        _pipeServer?.Dispose();
        _reader = null;
        _writer = null;
        _pipeServer = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _cts?.Cancel();
        DisposePipe();
        _cts?.Dispose();
    }
}
