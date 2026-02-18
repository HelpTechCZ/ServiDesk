import Foundation

/// Parsování binárních zpráv z relay serveru.
struct MessageParser {

    /// Parsuje binární zprávu s headerem [typ][4B délka][payload]
    static func parseBinaryMessage(_ data: Data) -> (type: BinaryMessageType, payload: Data)? {
        guard data.count >= 5 else { return nil }

        guard let msgType = BinaryMessageType(rawValue: data[0]) else { return nil }

        let length = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let payloadStart = 5
        let payloadEnd = payloadStart + Int(length)

        guard data.count >= payloadEnd else { return nil }

        let payload = data.subdata(in: payloadStart..<payloadEnd)
        return (type: msgType, payload: payload)
    }

    /// Parsuje video frame data z binární zprávy
    static func parseVideoFrame(_ data: Data) -> Data? {
        guard data.count >= 5 else { return nil }
        let msgType = data[0]

        // Full frame: [0x01][4B length][JPEG]
        if msgType == BinaryMessageType.videoFrame.rawValue {
            guard let parsed = parseBinaryMessage(data), parsed.type == .videoFrame else { return nil }
            return parsed.payload
        }

        return nil
    }

    /// Parsuje regionální update: [0x05][4B total_length][2B region_count][per region: 2B x, 2B y, 2B w, 2B h, 4B jpeg_size, JPEG]
    static func parseRegionalUpdate(_ data: Data) -> [RegionUpdate]? {
        guard data.count >= 7, data[0] == BinaryMessageType.regionalUpdate.rawValue else { return nil }

        let regionCount = data.subdata(in: 5..<7).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        var offset = 7
        var regions: [RegionUpdate] = []

        for _ in 0..<regionCount {
            guard offset + 12 <= data.count else { break } // 2+2+2+2+4 = 12 bytes header per region

            let x = data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            offset += 2
            let y = data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            offset += 2
            let w = data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            offset += 2
            let h = data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            offset += 2
            let jpegSize = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            offset += 4

            guard offset + Int(jpegSize) <= data.count else { break }
            let jpegData = data.subdata(in: offset..<offset+Int(jpegSize))
            offset += Int(jpegSize)

            regions.append(RegionUpdate(x: x, y: y, width: w, height: h, jpegData: jpegData))
        }

        return regions.isEmpty ? nil : regions
    }
}
