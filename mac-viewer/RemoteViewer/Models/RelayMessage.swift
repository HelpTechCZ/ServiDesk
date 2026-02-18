import Foundation

// MARK: - Základní obálka

struct RelayMessage: Codable {
    let type: String
    let timestamp: String?
    let payload: AnyCodable?
}

// MARK: - Admin → Relay

struct AdminAuthPayload: Codable {
    let admin_token: String
    let admin_name: String
}

struct AcceptSupportPayload: Codable {
    let session_id: String
    let admin_token: String
}

struct SessionEndPayload: Codable {
    let session_id: String
    let reason: String
}

// MARK: - Relay → Viewer

struct AdminAuthResultPayload: Codable {
    let success: Bool
    let pending_requests: [SupportRequestPayload]?
}

struct SupportRequestPayload: Codable {
    let session_id: String
    let customer_name: String
    let hostname: String
    let os_version: String
    let requested_at: String
    let message: String?
    let hw_info: HwInfo?
}

struct SessionStartedPayload: Codable {
    let session_id: String
    let screen_width: Int
    let screen_height: Int
}

struct SessionEndedPayload: Codable {
    let reason: String
    let ended_by: String
}

struct ErrorPayload: Codable {
    let code: String
    let message: String
}

// MARK: - Quality

struct QualityChangePayload: Codable {
    let fps: Int
    let quality: String
    let request_keyframe: Bool
}

// MARK: - Multi-Monitor

struct MonitorInfoPayload: Codable {
    let monitors: [MonitorDetail]
    let active_index: Int
}

struct MonitorDetail: Codable, Identifiable {
    let index: Int
    let name: String
    let width: Int
    let height: Int
    let is_primary: Bool

    var id: Int { index }
}

struct MonitorSwitchedPayload: Codable {
    let monitor_index: Int
    let width: Int
    let height: Int
}

// MARK: - Binární zprávy

enum BinaryMessageType: UInt8 {
    case videoFrame = 0x01
    case inputEvent = 0x02
    case clipboardData = 0x03
    case fileTransfer = 0x04
    case regionalUpdate = 0x05
}

/// Regionální update – jedna změněná oblast obrazovky
struct RegionUpdate {
    let x: UInt16
    let y: UInt16
    let width: UInt16
    let height: UInt16
    let jpegData: Data
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String { try container.encode(string) }
        else if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}
