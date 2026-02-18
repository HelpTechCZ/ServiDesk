import Foundation
import IOKit

struct HardwareInfoCollector {

    static func collect() -> [String: Any] {
        return [
            "cpu": getCpu(),
            "ram_total_gb": getRamGb(),
            "os": getOs(),
            "disks": getDisks()
        ]
    }

    // MARK: - CPU

    private static func getCpu() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - RAM

    private static func getRamGb() -> Double {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return (Double(bytes) / 1_073_741_824.0 * 10).rounded() / 10
    }

    // MARK: - OS

    private static func getOs() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    // MARK: - Disks

    private static func getDisks() -> [[String: Any]] {
        var disks: [[String: Any]] = []

        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeIsInternalKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return disks }

        for volume in volumes {
            guard let values = try? volume.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeName ?? volume.lastPathComponent
            let totalBytes = values.volumeTotalCapacity ?? 0
            let sizeGb = (Double(totalBytes) / 1_073_741_824.0 * 10).rounded() / 10
            let isInternal = values.volumeIsInternal ?? false

            // Skip tiny volumes (system snapshots etc.)
            guard sizeGb > 1 else { continue }

            disks.append([
                "name": name,
                "size_gb": sizeGb,
                "type": isInternal ? "SSD" : "External"
            ])
        }

        return disks
    }
}
