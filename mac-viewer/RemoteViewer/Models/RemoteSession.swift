import Foundation

struct RemoteSession {
    let sessionId: String
    let customerName: String
    let hostname: String
    var screenWidth: Int
    var screenHeight: Int
    var startedAt: Date
    var fps: Int = 0
    var latencyMs: Int = 0
    var quality: StreamQuality = .high
}

enum StreamQuality: String, CaseIterable {
    case auto
    case low
    case medium
    case high
}
