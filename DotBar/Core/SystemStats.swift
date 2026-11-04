import Darwin
import Foundation

/// CPU and memory read in-process through Mach host statistics: `dotbar cpu` / `dotbar ram`
/// cost no child shell, `sysctl`, `vm_stat` or `awk`, and work the same in the sandbox.
enum SystemStats {
    private static let lock = NSLock()
    private static var lastTicks: (busy: UInt64, total: UInt64)?
    private static var lastSample = Date.distantPast
    private static var lastPercent: Double?

    /// Whole-machine CPU busy % since the previous call (any caller). The first call, or one
    /// coming within half a second of the last, measures over a short window instead.
    static func cpuPercent() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(lastSample) < 0.5, let p = lastPercent { return p }
        guard var cur = cpuTicks() else { return nil }
        var prev = lastTicks
        if prev == nil || prev!.total == cur.total {
            prev = cur
            Thread.sleep(forTimeInterval: 0.5)
            guard let t = cpuTicks() else { return nil }
            cur = t
        }
        let dTotal = cur.total &- prev!.total, dBusy = cur.busy &- prev!.busy
        lastTicks = cur; lastSample = Date()
        guard dTotal > 0 else { return lastPercent }
        let p = min(100, Double(dBusy) * 100 / Double(dTotal))
        lastPercent = p
        return p
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Pages in use (active + wired + compressed) as a share of all counted pages — the same
    /// figure the old `vm_stat | awk` recipe printed.
    static func ramPercent() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let used = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        let total = used + Double(stats.free_count) + Double(stats.inactive_count) + Double(stats.speculative_count)
        return total > 0 ? used * 100 / total : nil
    }

    /// Output of `dotbar cpu|ram`: the rounded percentage, no `%` sign (dot colors read it as a number).
    static func output(for what: String) -> String? {
        switch what {
        case "cpu": return cpuPercent().map { String(format: "%.0f", $0) } ?? ""
        case "ram": return ramPercent().map { String(format: "%.0f", $0) } ?? ""
        default: return nil
        }
    }
}
