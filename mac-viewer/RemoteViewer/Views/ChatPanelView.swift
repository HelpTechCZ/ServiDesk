import SwiftUI

struct ChatPanelView: View {
    @ObservedObject var sessionVM: RemoteSessionViewModel
    @State private var chatInput = ""

    var body: some View {
        VStack(spacing: 0) {
            // Zprávy
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sessionVM.chatMessages) { msg in
                            ChatBubbleView(message: msg)
                        }
                    }
                    .padding(8)
                    .id("chatBottom")
                }
                .onChange(of: sessionVM.chatMessages.count) { _ in
                    withAnimation {
                        scrollProxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Napiste zpravu...", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }

                Button("Odeslat") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .frame(minWidth: 250, idealWidth: 300)
    }

    private func sendMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sessionVM.sendChatMessage(text)
        chatInput = ""
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.sender == "admin" ? .trailing : .leading, spacing: 2) {
            Text(message.sender == "admin" ? "Vy" : "Zakaznik")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(message.message)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(message.sender == "admin" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: message.sender == "admin" ? .trailing : .leading)
    }
}
