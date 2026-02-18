using System.Text.Json.Serialization;

namespace RemoteAgent.Shared.Messages;

/// <summary>
/// Zprávy mezi GUI aplikací a Windows službou přes Named Pipe.
/// </summary>
public class IpcMessage
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("payload")]
    public object? Payload { get; set; }
}

// ── GUI → Služba ──

public static class IpcCommand
{
    public const string ConnectRelay = "connect_relay";
    public const string RequestSupport = "request_support";
    public const string CancelSupport = "cancel_support";
    public const string Disconnect = "disconnect";
    public const string EndSession = "end_session";
    public const string SendChat = "send_chat";
    public const string FileSavePath = "file_save_path";
    public const string SetUnattendedPassword = "set_unattended_password";
    public const string DisableUnattendedAccess = "disable_unattended_access";
    public const string CheckUpdate = "check_update";
}

public class ConnectRelayPayload
{
    [JsonPropertyName("customer_name")]
    public string CustomerName { get; set; } = string.Empty;
}

public class RequestSupportIpcPayload
{
    [JsonPropertyName("customer_name")]
    public string CustomerName { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string? Message { get; set; }
}

// ── Služba → GUI ──

public static class IpcNotification
{
    public const string StatusUpdate = "status_update";
    public const string SessionAccepted = "session_accepted";
    public const string SessionEnded = "session_ended";
    public const string Error = "error";
    public const string ChatMessage = "chat_message";
    public const string UpdateAvailable = "update_available";
    public const string FileIncoming = "file_incoming";
    public const string FileReceived = "file_received";
    public const string UpdateCheckResult = "update_check_result";
}

public class FileIncomingPayload
{
    [JsonPropertyName("transfer_id")]
    public string TransferId { get; set; } = string.Empty;

    [JsonPropertyName("file_name")]
    public string FileName { get; set; } = string.Empty;

    [JsonPropertyName("file_size")]
    public long FileSize { get; set; }
}

public class FileSavePathPayload
{
    [JsonPropertyName("transfer_id")]
    public string TransferId { get; set; } = string.Empty;

    [JsonPropertyName("save_path")]
    public string SavePath { get; set; } = string.Empty;
}

public class FileReceivedPayload
{
    [JsonPropertyName("file_name")]
    public string FileName { get; set; } = string.Empty;

    [JsonPropertyName("save_path")]
    public string SavePath { get; set; } = string.Empty;
}

public class UpdateAvailablePayload
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;

    [JsonPropertyName("release_notes")]
    public string? ReleaseNotes { get; set; }
}

public class UpdateCheckResultPayload
{
    [JsonPropertyName("up_to_date")]
    public bool UpToDate { get; set; }

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}

public class ChatMessagePayload
{
    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("sender")]
    public string Sender { get; set; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public string Timestamp { get; set; } = string.Empty;
}

public class StatusUpdatePayload
{
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty; // connected, waiting, streaming, disconnected, error

    [JsonPropertyName("message")]
    public string? Message { get; set; }
}

public class SessionAcceptedIpcPayload
{
    [JsonPropertyName("admin_name")]
    public string AdminName { get; set; } = string.Empty;
}

public class SessionEndedIpcPayload
{
    [JsonPropertyName("reason")]
    public string Reason { get; set; } = string.Empty;

    [JsonPropertyName("ended_by")]
    public string EndedBy { get; set; } = string.Empty;
}

public class ErrorIpcPayload
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}

public class SetUnattendedPasswordPayload
{
    [JsonPropertyName("password")]
    public string Password { get; set; } = string.Empty;
}
