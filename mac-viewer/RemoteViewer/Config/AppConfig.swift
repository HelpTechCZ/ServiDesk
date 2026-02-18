import Foundation

class AppConfig: ObservableObject, Codable {
    @Published var relayServerURL: String = "wss://your-relay-domain.example.com/ws"
    @Published var adminToken: String = ""
    @Published var adminName: String = "Technik"
    @Published var autoReconnect: Bool = true
    @Published var reconnectMaxRetries: Int = 5
    @Published var notificationsEnabled: Bool = true
    @Published var soundEnabled: Bool = true
    @Published var defaultQuality: StreamQuality = .auto
    @Published var mapCmdToCtrl: Bool = true

    enum CodingKeys: String, CodingKey {
        case relayServerURL, adminToken, adminName, autoReconnect
        case reconnectMaxRetries, notificationsEnabled, soundEnabled
        case defaultQuality, mapCmdToCtrl
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relayServerURL = try container.decodeIfPresent(String.self, forKey: .relayServerURL) ?? "wss://your-relay-domain.example.com/ws"
        adminToken = try container.decodeIfPresent(String.self, forKey: .adminToken) ?? ""
        adminName = try container.decodeIfPresent(String.self, forKey: .adminName) ?? "Technik"
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        reconnectMaxRetries = try container.decodeIfPresent(Int.self, forKey: .reconnectMaxRetries) ?? 5
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        let qualityStr = try container.decodeIfPresent(String.self, forKey: .defaultQuality) ?? "auto"
        defaultQuality = StreamQuality(rawValue: qualityStr) ?? .auto
        mapCmdToCtrl = try container.decodeIfPresent(Bool.self, forKey: .mapCmdToCtrl) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relayServerURL, forKey: .relayServerURL)
        try container.encode(adminToken, forKey: .adminToken)
        try container.encode(adminName, forKey: .adminName)
        try container.encode(autoReconnect, forKey: .autoReconnect)
        try container.encode(reconnectMaxRetries, forKey: .reconnectMaxRetries)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(defaultQuality.rawValue, forKey: .defaultQuality)
        try container.encode(mapCmdToCtrl, forKey: .mapCmdToCtrl)
    }

    // MARK: - Persistence

    private static let configURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RemoteViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() {
        // Automaticky trimovat URL při ukládání
        relayServerURL = relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.configURL)
    }
}
