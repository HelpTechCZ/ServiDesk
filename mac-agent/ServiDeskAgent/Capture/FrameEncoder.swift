import Foundation
import CoreMedia
import CoreImage
import AppKit

/// Konvertuje CMSampleBuffer → JPEG a vytváří binární pakety pro odesílání.
class FrameEncoder {
    private let ciContext = CIContext()
    private var jpegQuality: CGFloat = 0.50

    /// Kvalita JPEG podle úrovně
    enum Quality: String {
        case low = "low"
        case medium = "medium"
        case high = "high"

        var jpegValue: CGFloat {
            switch self {
            case .low: return 0.30
            case .medium: return 0.50
            case .high: return 0.75
            }
        }

        var defaultFps: Int {
            switch self {
            case .low: return 10
            case .medium: return 20
            case .high: return 30
            }
        }
    }

    private var currentQuality: Quality = .medium
    private var currentFps: Int = 20

    /// Převede CMSampleBuffer na JPEG data
    func encode(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        ) else { return nil }

        return jpegData
    }

    /// Vytvoří binární paket: [0x01][4B length LE][JPEG data]
    func buildFullFramePacket(_ jpegData: Data) -> Data {
        var packet = Data()
        packet.append(BinaryMessageType.videoFrame.rawValue)
        var length = UInt32(jpegData.count).littleEndian
        packet.append(Data(bytes: &length, count: 4))
        packet.append(jpegData)
        return packet
    }

    /// Změní kvalitu a FPS (volané při quality_change od vieweru)
    func changeQuality(quality: String, fps: Int) {
        if let q = Quality(rawValue: quality) {
            currentQuality = q
            jpegQuality = q.jpegValue
        }
        currentFps = fps
    }

    var activeFps: Int { currentFps }
    var activeQuality: Quality { currentQuality }
}
