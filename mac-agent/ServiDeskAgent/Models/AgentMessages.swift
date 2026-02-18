import Foundation

// MARK: - Binární zprávy (sdílené s viewer)

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

// MARK: - Agent → Relay

struct AgentRegisterPayload: Codable {
    let agent_id: String
    let customer_name: String
    let hostname: String
    let os_version: String
    let agent_version: String
    let unattended_enabled: Bool
    let unattended_password_hash: String
}

struct RequestSupportPayload: Codable {
    let customer_name: String
    let message: String
    let screen_width: Int
    let screen_height: Int
}

struct UpdateAgentInfoPayload: Codable {
    let unattended_enabled: Bool
    let unattended_password_hash: String
}

// MARK: - Relay → Agent

struct AgentRegisteredPayload: Codable {
    let session_id: String
    let status: String
}

struct SessionAcceptedPayload: Codable {
    let admin_name: String
    let message: String
    let unattended: Bool?
}

struct SessionEndedPayload: Codable {
    let reason: String
    let ended_by: String
}

struct ErrorPayload: Codable {
    let code: String
    let message: String
}

// MARK: - Sdílené zprávy

struct ChatMessage: Identifiable {
    let id = UUID()
    let message: String
    let sender: String  // "admin" nebo "customer"
    let timestamp: String
}

// MARK: - Monitor info (agent → viewer přes relay)

struct MonitorInfo: Codable {
    let monitors: [MonitorDetail]
    let active_index: Int
}

struct MonitorDetail: Codable {
    let index: Int
    let name: String
    let width: Int
    let height: Int
    let is_primary: Bool
}
