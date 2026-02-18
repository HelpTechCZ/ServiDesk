import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardwarově akcelerované H.264 dekódování přes VideoToolbox.
class VideoDecoder {
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?

    var onFrameDecoded: ((CVPixelBuffer, CMTime) -> Void)?

    // MARK: - NAL Unit Parsing

    /// Extrahuje SPS a PPS z H.264 streamu pro inicializaci decoderu.
    private var nalProcessCount = 0

    func processNALUnit(_ data: Data) {
        nalProcessCount += 1
        guard data.count > 4 else {
            print(">>> [NAL] #\(nalProcessCount): data too small (\(data.count) bytes)")
            return
        }

        if nalProcessCount <= 5 {
            print(">>> [NAL] #\(nalProcessCount): \(data.count) bytes, first 20: \(Array(data.prefix(20)))")
        }

        var offset = 0
        var foundNals = 0

        while offset < data.count - 4 {
            if data[offset] == 0x00 && data[offset + 1] == 0x00 {
                var startCodeLen = 0
                if data[offset + 2] == 0x01 {
                    startCodeLen = 3
                } else if data[offset + 2] == 0x00 && offset + 3 < data.count && data[offset + 3] == 0x01 {
                    startCodeLen = 4
                }

                if startCodeLen > 0 {
                    let nalStart = offset + startCodeLen
                    guard nalStart < data.count else { break }

                    let nalType = data[nalStart] & 0x1F
                    foundNals += 1

                    var nalEnd = data.count
                    for i in (nalStart + 1)..<(data.count - 3) {
                        if data[i] == 0x00 && data[i+1] == 0x00 &&
                           (data[i+2] == 0x01 || (data[i+2] == 0x00 && i+3 < data.count && data[i+3] == 0x01)) {
                            nalEnd = i
                            break
                        }
                    }

                    let nalData = data.subdata(in: nalStart..<nalEnd)

                    if nalProcessCount <= 5 || nalType == 7 || nalType == 8 {
                        print(">>> [NAL] type=\(nalType), size=\(nalData.count), session=\(decompressionSession != nil)")
                    }

                    switch nalType {
                    case 7: // SPS
                        spsData = nalData
                        print(">>> [NAL] SPS stored (\(nalData.count) bytes)")
                        tryCreateSession()
                    case 8: // PPS
                        ppsData = nalData
                        print(">>> [NAL] PPS stored (\(nalData.count) bytes)")
                        tryCreateSession()
                    case 1, 5: // Coded slice, IDR slice
                        decodeFrame(nalData: nalData)
                    default:
                        if nalProcessCount <= 5 {
                            print(">>> [NAL] Ignoring type \(nalType)")
                        }
                    }

                    offset = nalEnd
                    continue
                }
            }
            offset += 1
        }

        if nalProcessCount <= 5 && foundNals == 0 {
            print(">>> [NAL] WARNING: No start codes found in \(data.count) bytes!")
        }
    }

    // MARK: - Session

    private func tryCreateSession() {
        guard let sps = spsData, let pps = ppsData else {
            print(">>> [DECODER] tryCreateSession: waiting for SPS=\(spsData != nil) PPS=\(ppsData != nil)")
            return
        }
        guard decompressionSession == nil else {
            return
        }
        print(">>> [DECODER] Creating session with SPS(\(sps.count)B) + PPS(\(pps.count)B)")

        var formatDesc: CMFormatDescription?

        // Pointery musí být platné po celou dobu volání CMVideoFormatDescription
        // → vnořit withUnsafeBytes aby pointery žily dostatečně dlouho
        let status = sps.withUnsafeBytes { spsBuffer -> OSStatus in
            pps.withUnsafeBytes { ppsBuffer -> OSStatus in
                let spsPtr = spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let ppsPtr = ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)

                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                return parameterSetPointers.withUnsafeBufferPointer { pointers in
                    parameterSetSizes.withUnsafeBufferPointer { sizes in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointers.baseAddress!,
                            parameterSetSizes: sizes.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDesc
                        )
                    }
                }
            }
        }

        guard status == noErr, let desc = formatDesc else {
            print(">>> [DECODER] FAILED to create format description: \(status)")
            return
        }

        print(">>> [DECODER] Format description created OK")
        formatDescription = desc
        createDecompressionSession(formatDescription: desc)
    }

    private func createDecompressionSession(formatDescription: CMFormatDescription) {
        let outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, pixelBuffer, presentationTime, _ in
                guard status == noErr, let pixelBuffer = pixelBuffer else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon!).takeUnretainedValue()
                decoder.onFrameDecoded?(pixelBuffer, presentationTime)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var session: VTDecompressionSession?
        var callback = outputCallback
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )

        guard status == noErr else {
            print(">>> [DECODER] FAILED to create decompression session: \(status)")
            return
        }

        print(">>> [DECODER] Decompression session created OK!")
        decompressionSession = session
    }

    // MARK: - Decode

    private func decodeFrame(nalData: Data) {
        guard let session = decompressionSession, let formatDesc = formatDescription else { return }

        // Převést Annex B → AVCC (nahradit start code délkou)
        var avccData = Data()
        var length = UInt32(nalData.count).bigEndian
        avccData.append(Data(bytes: &length, count: 4))
        avccData.append(nalData)

        var blockBuffer: CMBlockBuffer?
        let dataLength = avccData.count
        avccData.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: baseAddress,
                blockLength: dataLength,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataLength,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard let block = blockBuffer else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccData.count

        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard let sample = sampleBuffer else { return }

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    // MARK: - Cleanup

    func invalidate() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
        spsData = nil
        ppsData = nil
    }

    deinit {
        invalidate()
    }
}
