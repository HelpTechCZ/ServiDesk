import Foundation
import AppKit

/// Správa příjmu souborů od vieweru (technika).
/// Opak viewer FileTransferManager, který POSÍLÁ.
/// Flow: file_offer → NSSavePanel → file_accept → 0x04 chunky → file_complete
class FileTransferManager: ObservableObject {
    @Published var isTransferring = false
    @Published var transferProgress: Double = 0
    @Published var transferFileName: String = ""

    var onSendJson: (([String: Any]) -> Void)?

    private var currentTransferId: String?
    private var expectedFileSize: Int = 0
    private var receivedData = Data()
    private var saveURL: URL?

    /// Zpracuje příchozí control zprávu
    func handleControlMessage(type: String, payload: [String: Any]) {
        switch type {
        case "file_offer":
            handleFileOffer(payload)
        case "file_complete":
            handleFileComplete(payload)
        case "file_error":
            let message = payload["message"] as? String ?? "Neznámá chyba"
            print(">>> File transfer error: \(message)")
            resetTransfer()
        default:
            break
        }
    }

    /// Zpracuje binární 0x04 chunk
    func handleFileData(_ data: Data) {
        guard let parsed = MessageParser.parseBinaryMessage(data),
              parsed.type == .fileTransfer else { return }

        let payload = parsed.payload
        guard payload.count >= 1 else { return }

        let idLen = Int(payload[0])
        guard payload.count >= 1 + idLen else { return }

        let transferIdData = payload.subdata(in: 1..<(1 + idLen))
        guard let transferId = String(data: transferIdData, encoding: .utf8),
              transferId == currentTransferId else { return }

        let chunkData = payload.subdata(in: (1 + idLen)..<payload.count)
        receivedData.append(chunkData)

        if expectedFileSize > 0 {
            DispatchQueue.main.async {
                self.transferProgress = Double(self.receivedData.count) / Double(self.expectedFileSize)
            }
        }
    }

    // MARK: - Private

    private func handleFileOffer(_ payload: [String: Any]) {
        guard let transferId = payload["transfer_id"] as? String,
              let fileName = payload["file_name"] as? String,
              let fileSize = payload["file_size"] as? Int else { return }

        // Zobrazit NSSavePanel na hlavním vlákně
        DispatchQueue.main.async { [weak self] in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileName
            panel.title = "Uložit přijatý soubor"
            panel.canCreateDirectories = true

            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                self?.currentTransferId = transferId
                self?.expectedFileSize = fileSize
                self?.receivedData = Data()
                self?.saveURL = url
                self?.transferFileName = fileName
                self?.transferProgress = 0
                self?.isTransferring = true

                // Potvrdit příjem
                self?.onSendJson?([
                    "type": "file_accept",
                    "payload": ["transfer_id": transferId]
                ])
            } else {
                // Odmítnout
                self?.onSendJson?([
                    "type": "file_error",
                    "payload": [
                        "transfer_id": transferId,
                        "message": "Uživatel odmítl přenos souboru"
                    ]
                ])
            }
        }
    }

    private func handleFileComplete(_ payload: [String: Any]) {
        guard let transferId = payload["transfer_id"] as? String,
              transferId == currentTransferId,
              let url = saveURL else { return }

        do {
            try receivedData.write(to: url)
            print(">>> File saved: \(url.path) (\(receivedData.count) bytes)")
        } catch {
            print(">>> File save error: \(error)")
        }

        DispatchQueue.main.async {
            self.transferProgress = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.resetTransfer()
            }
        }
    }

    private func resetTransfer() {
        DispatchQueue.main.async {
            self.isTransferring = false
            self.transferProgress = 0
            self.transferFileName = ""
            self.currentTransferId = nil
            self.expectedFileSize = 0
            self.receivedData = Data()
            self.saveURL = nil
        }
    }
}
