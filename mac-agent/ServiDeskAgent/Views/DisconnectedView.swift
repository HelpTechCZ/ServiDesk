import SwiftUI

struct DisconnectedView: View {
    @EnvironmentObject var appState: AppState
    let reason: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Session ukončena")
                .font(.title3)
                .fontWeight(.medium)

            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: { appState.resetToIdle() }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Nová žádost")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
    }
}
