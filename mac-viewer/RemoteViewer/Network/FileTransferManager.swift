import Foundation

/// Správa odesílání souborů z Mac vieweru na Windows agenta.
/// Soubor se chunked odesílá přes binární 0x04 zprávy.
class FileTransferManager: ObservableObject {
    @Published var isTransferring = false
    @Published var transferProgress: Double = 0
    @Published var transferFileName: String = ""

    private let maxChunkSize = 1_500_000 // 1.5MB

    var onSendJson: (([String: Any]) -> Void)?
    var onSendBinary: ((Data) -> Void)?

    private var currentTransferId: String?
    private var pendingFileData: Data?
    private var pendingFileName: String?

    /// Zahájí přenos souboru - odešle file_offer a čeká na file_accept
    func sendFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }

        let transferId = UUID().uuidString
        let fileName = url.lastPathComponent

        currentTransferId = transferId
        pendingFileData = data
        pendingFileName = fileName
        transferFileName = fileName
        transferProgress = 0
        isTransferring = true

        onSendJson?([
            "type": "file_offer",
            "payload": [
                "transfer_id": transferId,
                "file_name": fileName,
                "file_size": data.count
            ]
        ])
    }

    /// Zpracuje příchozí control zprávy (file_accept, file_error)
    func handleControlMessage(type: String, payload: [String: Any]) {
        guard let transferId = payload["transfer_id"] as? String,
              transferId == currentTransferId else { return }

        switch type {
        case "file_accept":
            sendChunks()

        case "file_error":
            let message = payload["message"] as? String ?? "Unknown error"
            print(">>> File transfer error: \(message)")
            resetTransfer()

        default:
            break
        }
    }

    private func sendChunks() {
        guard let data = pendingFileData,
              let transferId = currentTransferId else { return }

        let idData = Data(transferId.utf8)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var offset = 0
            let total = data.count

            while offset < total {
                let end = min(offset + self.maxChunkSize, total)
                let chunkData = data.subdata(in: offset..<end)

                // Build binary packet: [0x04][4B length LE][transfer_id_len(1B)][transfer_id][chunk]
                var packet = Data()
                packet.append(BinaryMessageType.fileTransfer.rawValue)

                let payloadSize = 1 + idData.count + chunkData.count
                var length = UInt32(payloadSize).littleEndian
                packet.append(Data(bytes: &length, count: 4))
                packet.append(UInt8(idData.count))
                packet.append(idData)
                packet.append(chunkData)

                self.onSendBinary?(packet)

                offset = end
                let progress = Double(offset) / Double(total)
                DispatchQueue.main.async {
                    self.transferProgress = progress
                }

                // Small delay to avoid overwhelming WebSocket
                Thread.sleep(forTimeInterval: 0.01)
            }

            // Send file_complete
            self.onSendJson?([
                "type": "file_complete",
                "payload": ["transfer_id": transferId]
            ])

            DispatchQueue.main.async {
                self.transferProgress = 1.0
                // Reset after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.resetTransfer()
                }
            }
        }
    }

    private func resetTransfer() {
        isTransferring = false
        transferProgress = 0
        transferFileName = ""
        currentTransferId = nil
        pendingFileData = nil
        pendingFileName = nil
    }
}
