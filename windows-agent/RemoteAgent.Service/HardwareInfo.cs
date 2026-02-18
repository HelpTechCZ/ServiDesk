using System.Management;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.Service;

public static class HardwareInfoCollector
{
    public static HardwareInfoPayload Collect()
    {
        var info = new HardwareInfoPayload
        {
            Cpu = GetCpu(),
            RamTotalGb = GetRamGb(),
            Os = GetOs(),
            Disks = GetDisks(),
        };
        return info;
    }

    private static string GetCpu()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_Processor");
            foreach (var obj in searcher.Get())
            {
                return obj["Name"]?.ToString()?.Trim() ?? "Unknown";
            }
        }
        catch { }
        return "Unknown";
    }

    private static double GetRamGb()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem");
            foreach (var obj in searcher.Get())
            {
                if (ulong.TryParse(obj["TotalPhysicalMemory"]?.ToString(), out var bytes))
                    return Math.Round(bytes / 1073741824.0, 1);
            }
        }
        catch { }
        return 0;
    }

    private static string GetOs()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Caption, Version FROM Win32_OperatingSystem");
            foreach (var obj in searcher.Get())
            {
                var caption = obj["Caption"]?.ToString()?.Trim() ?? "";
                var version = obj["Version"]?.ToString()?.Trim() ?? "";
                if (!string.IsNullOrEmpty(caption))
                    return string.IsNullOrEmpty(version) ? caption : $"{caption} ({version})";
            }
        }
        catch { }
        return "Unknown";
    }

    private static List<DiskInfoPayload> GetDisks()
    {
        var disks = new List<DiskInfoPayload>();
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Model, Size, MediaType FROM Win32_DiskDrive");
            foreach (var obj in searcher.Get())
            {
                var sizeGb = 0.0;
                if (ulong.TryParse(obj["Size"]?.ToString(), out var bytes))
                    sizeGb = Math.Round(bytes / 1073741824.0, 1);

                var mediaType = obj["MediaType"]?.ToString() ?? "";
                var diskType = mediaType.Contains("SSD", StringComparison.OrdinalIgnoreCase)
                    ? "SSD"
                    : mediaType.Contains("Fixed", StringComparison.OrdinalIgnoreCase)
                        ? "HDD"
                        : mediaType;

                disks.Add(new DiskInfoPayload
                {
                    Name = obj["Model"]?.ToString()?.Trim() ?? "Unknown",
                    SizeGb = sizeGb,
                    Type = diskType,
                });
            }
        }
        catch { }
        return disks;
    }
}
