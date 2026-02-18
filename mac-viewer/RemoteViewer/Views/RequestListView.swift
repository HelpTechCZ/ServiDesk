import SwiftUI

struct RequestListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Čekající žádosti")
                    .font(.headline)

                Spacer()

                Text("\(appState.relay.pendingRequests.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(appState.relay.pendingRequests.isEmpty ? Color.gray.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if appState.relay.pendingRequests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Žádné čekající žádosti")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.relay.pendingRequests) { request in
                            RequestRowView(
                                request: request,
                                onAccept: { appState.relay.acceptRequest(request) },
                                onReject: { appState.relay.rejectRequest(request) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            Spacer()

            // Spodní bar
            HStack {
                Text("Aktivní sessions: \(appState.activeSession != nil ? 1 : 0)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
