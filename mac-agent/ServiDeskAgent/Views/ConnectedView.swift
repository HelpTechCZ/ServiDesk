import SwiftUI

struct ConnectedView: View {
    @EnvironmentObject var appState: AppState
    let adminName: String
    @State private var chatInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Status
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                Text("Technik připojen: \(adminName)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))

            // File transfer progress
            if appState.fileTransferManager.isTransferring {
                fileTransferBanner
            }

            Divider()

            // Chat
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.chatMessages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.chatMessages.count) { _ in
                    if let last = appState.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Chat input
            HStack(spacing: 8) {
                TextField("Napište zprávu...", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            Divider()

            // Odpojit
            Button(action: { appState.endSession() }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Odpojit")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func sendMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        appState.sendChat(text)
        chatInput = ""
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        let isMe = msg.sender == "customer"
        HStack {
            if isMe { Spacer() }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(msg.message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color.orange.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                Text(isMe ? "Vy" : msg.sender)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !isMe { Spacer() }
        }
    }

    @ViewBuilder
    private var fileTransferBanner: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "arrow.down.doc")
                Text("Přenos: \(appState.fileTransferManager.transferFileName)")
                    .font(.caption)
                Spacer()
                Text("\(Int(appState.fileTransferManager.transferProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: appState.fileTransferManager.transferProgress)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.05))
    }
}
