using Microsoft.Extensions.Logging;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service.FileTransfer;

/// <summary>
/// Správa příjmu souborů z vieweru.
/// Při file_offer pošle do GUI notifikaci → GUI zobrazí SaveFileDialog →
/// pošle zpět cestu → Service začne přijímat chunky.
/// </summary>
public class FileTransferManager
{
    private readonly ILogger _logger;

    // Aktivní příjmy
    private readonly Dictionary<string, IncomingTransfer> _incoming = new();
    // Pending offers čekající na cestu od GUI
    private readonly Dictionary<string, PendingOffer> _pendingOffers = new();

    // Eventy pro odesílání zpráv zpět (relay)
    public event Action<object>? OnSendJson;

    // Event pro notifikaci GUI (file_incoming)
    public event Func<string, FileIncomingPayload, Task>? OnFileIncoming;
    // Event pro notifikaci GUI (file_received)
    public event Func<string, FileReceivedPayload, Task>? OnFileReceived;

    private const int MaxChunkSize = 1_500_000;

    public FileTransferManager(ILogger logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Zpracuje příchozí JSON control zprávu pro file transfer.
    /// </summary>
    public void HandleControlMessage(string type, System.Text.Json.JsonElement payload)
    {
        switch (type)
        {
            case "file_offer":
                HandleFileOffer(payload);
                break;

            case "file_complete":
                HandleFileComplete(payload);
                break;

            case "file_error":
                var transferId = payload.GetProperty("transfer_id").GetString() ?? "";
                _logger.LogWarning("File transfer error for {Id}", transferId);
                _incoming.Remove(transferId);
                _pendingOffers.Remove(transferId);
                break;
        }
    }

    /// <summary>
    /// GUI poslal cestu pro uložení souboru.
    /// </summary>
    public void SetSavePath(string transferId, string savePath)
    {
        if (!_pendingOffers.TryGetValue(transferId, out var offer))
        {
            _logger.LogWarning("SetSavePath for unknown transfer: {Id}", transferId);
            return;
        }

        _pendingOffers.Remove(transferId);

        if (string.IsNullOrEmpty(savePath))
        {
            // Uživatel zrušil dialog → odmítnout transfer
            _logger.LogInformation("File transfer {Id} cancelled by user", transferId);
            OnSendJson?.Invoke(new
            {
                type = "file_error",
                payload = new { transfer_id = transferId, message = "User cancelled" }
            });
            return;
        }

        _logger.LogInformation("File transfer {Id} saving to: {Path}", transferId, savePath);

        var transfer = new IncomingTransfer
        {
            TransferId = transferId,
            FileName = offer.FileName,
            FilePath = savePath,
            TotalSize = offer.FileSize,
            Stream = new FileStream(savePath, FileMode.Create, FileAccess.Write)
        };

        _incoming[transferId] = transfer;

        // Přijmout transfer
        OnSendJson?.Invoke(new
        {
            type = "file_accept",
            payload = new { transfer_id = transferId }
        });
    }

    /// <summary>
    /// Zpracuje příchozí binární chunk (0x04 typ).
    /// </summary>
    public void HandleBinaryChunk(byte[] data)
    {
        if (data.Length < 6) return;

        var payloadLength = BitConverter.ToInt32(data, 1);
        if (data.Length < 5 + payloadLength) return;

        var payload = new ReadOnlySpan<byte>(data, 5, payloadLength);
        if (payload.Length < 2) return;

        var idLength = payload[0];
        if (payload.Length < 1 + idLength) return;

        var transferId = System.Text.Encoding.ASCII.GetString(payload.Slice(1, idLength));
        var chunkData = payload.Slice(1 + idLength).ToArray();

        if (!_incoming.TryGetValue(transferId, out var transfer))
        {
            // Chunk přišel dřív než GUI odpověděl, nebo neznámé ID
            return;
        }

        try
        {
            transfer.Stream.Write(chunkData, 0, chunkData.Length);
            transfer.ReceivedBytes += chunkData.Length;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error writing chunk for transfer {Id}", transferId);
            SendError(transferId, ex.Message);
            CleanupTransfer(transferId);
        }
    }

    private void HandleFileOffer(System.Text.Json.JsonElement payload)
    {
        var transferId = payload.GetProperty("transfer_id").GetString() ?? Guid.NewGuid().ToString();
        var fileName = payload.GetProperty("file_name").GetString() ?? "unknown";
        var fileSize = payload.GetProperty("file_size").GetInt64();

        _logger.LogInformation("File offer: {Name} ({Size} bytes), ID: {Id}", fileName, fileSize, transferId);

        var safeName = Path.GetFileName(fileName);

        // Uložit pending offer
        _pendingOffers[transferId] = new PendingOffer
        {
            TransferId = transferId,
            FileName = safeName,
            FileSize = fileSize
        };

        // Poslat do GUI → zobrazí SaveFileDialog
        OnFileIncoming?.Invoke(IpcNotification.FileIncoming, new FileIncomingPayload
        {
            TransferId = transferId,
            FileName = safeName,
            FileSize = fileSize
        });
    }

    private void HandleFileComplete(System.Text.Json.JsonElement payload)
    {
        var transferId = payload.GetProperty("transfer_id").GetString() ?? "";

        if (!_incoming.TryGetValue(transferId, out var transfer))
        {
            _logger.LogWarning("file_complete for unknown transfer: {Id}", transferId);
            return;
        }

        transfer.Stream.Close();
        transfer.Stream.Dispose();

        _logger.LogInformation("File transfer complete: {Name} ({Received} bytes) → {Path}",
            transfer.FileName, transfer.ReceivedBytes, transfer.FilePath);

        // Notifikovat GUI
        OnFileReceived?.Invoke(IpcNotification.FileReceived, new FileReceivedPayload
        {
            FileName = transfer.FileName,
            SavePath = transfer.FilePath
        });

        _incoming.Remove(transferId);
    }

    private void SendError(string transferId, string message)
    {
        OnSendJson?.Invoke(new
        {
            type = "file_error",
            payload = new { transfer_id = transferId, message }
        });
    }

    private void CleanupTransfer(string transferId)
    {
        if (_incoming.TryGetValue(transferId, out var transfer))
        {
            transfer.Stream.Close();
            transfer.Stream.Dispose();
            try { File.Delete(transfer.FilePath); } catch { }
            _incoming.Remove(transferId);
        }
    }

    private class PendingOffer
    {
        public string TransferId { get; set; } = "";
        public string FileName { get; set; } = "";
        public long FileSize { get; set; }
    }

    private class IncomingTransfer
    {
        public string TransferId { get; set; } = "";
        public string FileName { get; set; } = "";
        public string FilePath { get; set; } = "";
        public long TotalSize { get; set; }
        public long ReceivedBytes { get; set; }
        public FileStream Stream { get; set; } = null!;
    }
}
