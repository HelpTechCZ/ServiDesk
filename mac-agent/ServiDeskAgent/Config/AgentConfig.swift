import Foundation
import CryptoKit

class AgentConfig: ObservableObject, Codable {
    @Published var relayServerURL: String = ""
    @Published var agentId: String = ""
    @Published var agentVersion: String = "1.0.0"
    @Published var captureMaxFps: Int = 30
    @Published var captureDefaultQuality: String = "medium"
    @Published var provisionToken: String = ""
    @Published var agentToken: String = ""
    @Published var unattendedAccessEnabled: Bool = false
    @Published var unattendedAccessPasswordHash: String = ""

    enum CodingKeys: String, CodingKey {
        case relayServerURL, agentId, agentVersion
        case captureMaxFps, captureDefaultQuality
        case provisionToken, agentToken, unattendedAccessEnabled, unattendedAccessPasswordHash
    }

    init() {
        // Generovat nové UUID při prvním spuštění
        agentId = UUID().uuidString
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relayServerURL = try container.decodeIfPresent(String.self, forKey: .relayServerURL) ?? ""
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? UUID().uuidString
        agentVersion = try container.decodeIfPresent(String.self, forKey: .agentVersion) ?? "1.0.0"
        captureMaxFps = try container.decodeIfPresent(Int.self, forKey: .captureMaxFps) ?? 30
        captureDefaultQuality = try container.decodeIfPresent(String.self, forKey: .captureDefaultQuality) ?? "medium"
        provisionToken = try container.decodeIfPresent(String.self, forKey: .provisionToken) ?? ""
        agentToken = try container.decodeIfPresent(String.self, forKey: .agentToken) ?? ""
        unattendedAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .unattendedAccessEnabled) ?? false
        unattendedAccessPasswordHash = try container.decodeIfPresent(String.self, forKey: .unattendedAccessPasswordHash) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relayServerURL, forKey: .relayServerURL)
        try container.encode(agentId, forKey: .agentId)
        try container.encode(agentVersion, forKey: .agentVersion)
        try container.encode(captureMaxFps, forKey: .captureMaxFps)
        try container.encode(captureDefaultQuality, forKey: .captureDefaultQuality)
        try container.encode(provisionToken, forKey: .provisionToken)
        try container.encode(agentToken, forKey: .agentToken)
        try container.encode(unattendedAccessEnabled, forKey: .unattendedAccessEnabled)
        try container.encode(unattendedAccessPasswordHash, forKey: .unattendedAccessPasswordHash)
    }

    // MARK: - Password hashing

    /// SHA-256 hash hesla pro unattended access
    static func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Nastaví heslo pro unattended access (uloží hash)
    func setUnattendedPassword(_ password: String) {
        if password.isEmpty {
            unattendedAccessPasswordHash = ""
            unattendedAccessEnabled = false
        } else {
            unattendedAccessPasswordHash = Self.hashPassword(password)
            unattendedAccessEnabled = true
        }
    }

    // MARK: - Persistence

    private static let configURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ServiDeskAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> AgentConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AgentConfig.self, from: data) else {
            let newConfig = AgentConfig()
            newConfig.save()
            return newConfig
        }
        return config
    }

    func save() {
        relayServerURL = relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.configURL)
    }
}
