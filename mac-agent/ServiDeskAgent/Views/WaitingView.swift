import SwiftUI

struct WaitingView: View {
    @EnvironmentObject var appState: AppState
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(message)
                .font(.title3)
                .foregroundColor(.secondary)

            if case .waiting = appState.state {
                Text("Technik bude brzy k dispozici")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { appState.cancelRequest() }) {
                HStack {
                    Image(systemName: "xmark")
                    Text("Zrušit")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
