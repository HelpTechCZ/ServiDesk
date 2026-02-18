import SwiftUI

struct RequestRowView: View {
    let request: SupportRequest
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Zelená tečka
            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.customerName)
                    .font(.headline)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text(request.hostname)
                        .font(.caption)
                    Text("·")
                        .font(.caption)
                    Text(request.osVersion)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                if let hw = request.hwInfo {
                    Text(hw.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !request.message.isEmpty {
                    Text("\"\(request.message)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(2)
                }

                Text("Čeká \(request.waitingTime)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            Spacer()

            Button("Zamítnout") {
                onReject()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)

            Button("Připojit") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
