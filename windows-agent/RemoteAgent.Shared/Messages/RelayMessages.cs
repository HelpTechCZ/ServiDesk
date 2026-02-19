using System.Text.Json.Serialization;

namespace RemoteAgent.Shared.Messages;

// ── Základní obálka zprávy ──

public class RelayMessage
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public string? Timestamp { get; set; }

    [JsonPropertyName("payload")]
    public object? Payload { get; set; }
}

// ── Agent → Relay ──

public class AgentRegisterPayload
{
    [JsonPropertyName("agent_id")]
    public string AgentId { get; set; } = string.Empty;

    [JsonPropertyName("customer_name")]
    public string CustomerName { get; set; } = string.Empty;

    [JsonPropertyName("hostname")]
    public string Hostname { get; set; } = string.Empty;

    [JsonPropertyName("os_version")]
    public string OsVersion { get; set; } = string.Empty;

    [JsonPropertyName("agent_version")]
    public string AgentVersion { get; set; } = string.Empty;

    [JsonPropertyName("unattended_enabled")]
    public bool UnattendedEnabled { get; set; }

    [JsonPropertyName("unattended_password_hash")]
    public string UnattendedPasswordHash { get; set; } = string.Empty;

    [JsonPropertyName("hw_info")]
    public HardwareInfoPayload? HwInfo { get; set; }

    [JsonPropertyName("agent_token")]
    public string AgentToken { get; set; } = string.Empty;

    [JsonPropertyName("agent_secret")]
    public string AgentSecret { get; set; } = string.Empty;
}

public class HardwareInfoPayload
{
    [JsonPropertyName("cpu")]
    public string Cpu { get; set; } = "";

    [JsonPropertyName("ram_total_gb")]
    public double RamTotalGb { get; set; }

    [JsonPropertyName("os")]
    public string Os { get; set; } = "";

    [JsonPropertyName("disks")]
    public List<DiskInfoPayload> Disks { get; set; } = new();
}

public class DiskInfoPayload
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("size_gb")]
    public double SizeGb { get; set; }

    [JsonPropertyName("type")]
    public string Type { get; set; } = "";
}

public class RequestSupportPayload
{
    [JsonPropertyName("session_id")]
    public string SessionId { get; set; } = string.Empty;

    [JsonPropertyName("customer_name")]
    public string CustomerName { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("screen_width")]
    public int ScreenWidth { get; set; }

    [JsonPropertyName("screen_height")]
    public int ScreenHeight { get; set; }
}

public class SessionEndPayload
{
    [JsonPropertyName("session_id")]
    public string SessionId { get; set; } = string.Empty;

    [JsonPropertyName("reason")]
    public string Reason { get; set; } = "completed";
}

public class HeartbeatPayload
{
    [JsonPropertyName("session_id")]
    public string? SessionId { get; set; }
}

// ── Relay → Agent ──

public class AgentRegisteredPayload
{
    [JsonPropertyName("session_id")]
    public string SessionId { get; set; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;
}

public class SessionAcceptedPayload
{
    [JsonPropertyName("admin_name")]
    public string AdminName { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string? Message { get; set; }
}

public class SessionEndedPayload
{
    [JsonPropertyName("reason")]
    public string Reason { get; set; } = string.Empty;

    [JsonPropertyName("ended_by")]
    public string EndedBy { get; set; } = string.Empty;
}

public class ErrorPayload
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}

// ── Kvalita streamu ──

public class QualityChangePayload
{
    [JsonPropertyName("fps")]
    public int Fps { get; set; }

    [JsonPropertyName("quality")]
    public string Quality { get; set; } = "medium";

    [JsonPropertyName("request_keyframe")]
    public bool RequestKeyframe { get; set; }
}

// ── Binární zprávy – typy ──

public static class BinaryMessageType
{
    public const byte VideoFrame = 0x01;
    public const byte InputEvent = 0x02;
    public const byte ClipboardData = 0x03;
    public const byte FileTransfer = 0x04;
    public const byte RegionalUpdate = 0x05;
}

// ── Input eventy (JSON uvnitř binární zprávy) ──

public class InputEvent
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;
}

public class MouseMoveEvent : InputEvent
{
    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }
}

public class MouseClickEvent : InputEvent
{
    [JsonPropertyName("button")]
    public string Button { get; set; } = "left";

    [JsonPropertyName("action")]
    public string Action { get; set; } = "down";

    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }
}

public class MouseScrollEvent : InputEvent
{
    [JsonPropertyName("delta_x")]
    public int DeltaX { get; set; }

    [JsonPropertyName("delta_y")]
    public int DeltaY { get; set; }

    [JsonPropertyName("x")]
    public int X { get; set; }

    [JsonPropertyName("y")]
    public int Y { get; set; }
}

public class KeyEvent : InputEvent
{
    [JsonPropertyName("action")]
    public string Action { get; set; } = "down";

    [JsonPropertyName("key_code")]
    public int KeyCode { get; set; }

    [JsonPropertyName("modifiers")]
    public KeyModifiers? Modifiers { get; set; }
}

public class KeyModifiers
{
    [JsonPropertyName("ctrl")]
    public bool Ctrl { get; set; }

    [JsonPropertyName("alt")]
    public bool Alt { get; set; }

    [JsonPropertyName("shift")]
    public bool Shift { get; set; }

    [JsonPropertyName("win")]
    public bool Win { get; set; }
}

public class SpecialKeyEvent : InputEvent
{
    [JsonPropertyName("combination")]
    public string Combination { get; set; } = string.Empty;
}
