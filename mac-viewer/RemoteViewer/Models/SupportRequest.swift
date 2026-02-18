import Foundation

struct SupportRequest: Identifiable {
    let id: String          // session_id
    let customerName: String
    let hostname: String
    let osVersion: String
    let requestedAt: Date
    let message: String
    let hwInfo: HwInfo?

    var waitingTime: String {
        let interval = Date().timeIntervalSince(requestedAt)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "Právě teď" }
        if minutes == 1 { return "1 minuta" }
        if minutes < 5 { return "\(minutes) minuty" }
        return "\(minutes) minut"
    }

    static func from(payload: SupportRequestPayload) -> SupportRequest {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: payload.requested_at) ?? Date()

        return SupportRequest(
            id: payload.session_id,
            customerName: payload.customer_name,
            hostname: payload.hostname,
            osVersion: payload.os_version,
            requestedAt: date,
            message: payload.message ?? "",
            hwInfo: payload.hw_info
        )
    }
}
