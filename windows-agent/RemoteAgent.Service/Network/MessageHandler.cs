using System.Text;
using System.Text.Json;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service.Network;

/// <summary>
/// Zpracování příchozích zpráv z relay serveru.
/// </summary>
public class MessageHandler
{
    public event Action<string>? OnRegistered;           // session_id
    public event Action<string, string>? OnSessionAccepted;  // admin_name, message
    public event Action<string, string>? OnSessionEnded;     // reason, ended_by
    public event Action<string>? OnRequestRejected;           // reason
    public event Action<string, string>? OnError;            // code, message
    public event Action<QualityChangePayload>? OnQualityChange;
    public event Action<byte[]>? OnInputData;            // binární input eventy
    public event Action<ChatMessagePayload>? OnChatMessage;
    public event Action<string>? OnClipboardData;          // clipboard text z vieweru
    public event Action<byte[]>? OnFileTransferData;       // file transfer binary chunk
    public event Action<string, JsonElement>? OnFileTransferControl;  // file control messages
    public event Action<string>? OnE2EKeyExchange;         // peer's ECDH public key (base64)
    public event Action<string>? OnEncryptedChatMessage;   // encrypted chat payload (base64)
    public event Action<long>? OnHeartbeatRtt;             // RTT in milliseconds

    public void HandleJsonMessage(string type, JsonElement payload)
    {
        switch (type)
        {
            case "agent_registered":
                var sessionId = payload.GetProperty("session_id").GetString() ?? "";
                OnRegistered?.Invoke(sessionId);
                break;

            case "session_accepted":
                var adminName = payload.GetProperty("admin_name").GetString() ?? "";
                var msg = payload.TryGetProperty("message", out var m) ? m.GetString() ?? "" : "";
                OnSessionAccepted?.Invoke(adminName, msg);
                break;

            case "session_ended":
                var reason = payload.GetProperty("reason").GetString() ?? "";
                var endedBy = payload.GetProperty("ended_by").GetString() ?? "";
                OnSessionEnded?.Invoke(reason, endedBy);
                break;

            case "request_rejected":
                var rejectReason = payload.TryGetProperty("reason", out var rr) ? rr.GetString() ?? "rejected" : "rejected";
                OnRequestRejected?.Invoke(rejectReason);
                break;

            case "quality_change":
                var qc = JsonSerializer.Deserialize<QualityChangePayload>(payload.GetRawText());
                if (qc != null) OnQualityChange?.Invoke(qc);
                break;

            case "error":
                var code = payload.GetProperty("code").GetString() ?? "";
                var errMsg = payload.GetProperty("message").GetString() ?? "";
                OnError?.Invoke(code, errMsg);
                break;

            case "chat_message":
                // Detekce šifrované zprávy (obsahuje "encrypted" pole)
                if (payload.ValueKind != JsonValueKind.Undefined &&
                    payload.TryGetProperty("encrypted", out var encProp))
                {
                    var encPayload = encProp.GetString();
                    if (encPayload != null) OnEncryptedChatMessage?.Invoke(encPayload);
                }
                else
                {
                    var chat = JsonSerializer.Deserialize<ChatMessagePayload>(payload.GetRawText());
                    if (chat != null) OnChatMessage?.Invoke(chat);
                }
                break;

            case "e2e_key_exchange":
                var peerKey = payload.GetProperty("public_key").GetString();
                if (peerKey != null) OnE2EKeyExchange?.Invoke(peerKey);
                break;

            case "file_offer":
            case "file_complete":
            case "file_error":
                OnFileTransferControl?.Invoke(type, payload);
                break;

            case "heartbeat_ack":
                if (payload.ValueKind != JsonValueKind.Undefined &&
                    payload.TryGetProperty("timestamp", out var tsProp) &&
                    tsProp.TryGetInt64(out var sentTimestamp))
                {
                    var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                    var rtt = now - sentTimestamp;
                    if (rtt >= 0) OnHeartbeatRtt?.Invoke(rtt);
                }
                break;

            default:
                break;
        }
    }

    public void HandleBinaryMessage(byte[] data)
    {
        if (data.Length < 5) return;

        var msgType = data[0];
        if (msgType == BinaryMessageType.InputEvent)
        {
            OnInputData?.Invoke(data);
        }
        else if (msgType == BinaryMessageType.ClipboardData)
        {
            var payloadLength = BitConverter.ToInt32(data, 1);
            if (data.Length >= 5 + payloadLength)
            {
                var text = Encoding.UTF8.GetString(data, 5, payloadLength);
                OnClipboardData?.Invoke(text);
            }
        }
        else if (msgType == BinaryMessageType.FileTransfer)
        {
            OnFileTransferData?.Invoke(data);
        }
    }
}
