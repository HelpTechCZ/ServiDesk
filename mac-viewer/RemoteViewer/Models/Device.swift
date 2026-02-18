import Foundation

struct HwInfo: Codable {
    var cpu: String
    var ramTotalGb: Double
    var os: String
    var disks: [DiskInfo]

    enum CodingKeys: String, CodingKey {
        case cpu
        case ramTotalGb = "ram_total_gb"
        case os
        case disks
    }

    var summary: String {
        let ram = String(format: "%.0f", ramTotalGb)
        let diskSummary = disks.map { "\($0.name) \(String(format: "%.0f", $0.sizeGb))GB" }.joined(separator: ", ")
        if diskSummary.isEmpty {
            return "\(cpu) · \(ram) GB RAM"
        }
        return "\(cpu) · \(ram) GB RAM · \(diskSummary)"
    }
}

struct DiskInfo: Codable {
    var name: String
    var sizeGb: Double
    var type: String

    enum CodingKeys: String, CodingKey {
        case name
        case sizeGb = "size_gb"
        case type
    }
}

struct Device: Identifiable, Codable {
    let id: String          // agent_id
    var hostname: String
    var customerName: String
    var osVersion: String
    var agentVersion: String
    var isOnline: Bool
    var lastSeen: Date
    var unattendedEnabled: Bool
    var hwInfo: HwInfo?

    enum CodingKeys: String, CodingKey {
        case id = "agentId"
        case hostname
        case customerName
        case osVersion
        case agentVersion
        case isOnline
        case lastSeen
        case unattendedEnabled
        case hwInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        hostname = try container.decode(String.self, forKey: .hostname)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion) ?? "Unknown"
        agentVersion = try container.decodeIfPresent(String.self, forKey: .agentVersion) ?? "0.0.0"
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        unattendedEnabled = try container.decodeIfPresent(Bool.self, forKey: .unattendedEnabled) ?? false
        hwInfo = try container.decodeIfPresent(HwInfo.self, forKey: .hwInfo)

        if let dateStr = try container.decodeIfPresent(String.self, forKey: .lastSeen) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastSeen = formatter.date(from: dateStr) ?? Date()
        } else {
            lastSeen = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(customerName, forKey: .customerName)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(agentVersion, forKey: .agentVersion)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(unattendedEnabled, forKey: .unattendedEnabled)
        try container.encodeIfPresent(hwInfo, forKey: .hwInfo)
        try container.encode(ISO8601DateFormatter().string(from: lastSeen), forKey: .lastSeen)
    }
}
