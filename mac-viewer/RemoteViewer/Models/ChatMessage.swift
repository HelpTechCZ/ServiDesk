import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let message: String
    let sender: String  // "admin" nebo "customer"
    let timestamp: String
}
