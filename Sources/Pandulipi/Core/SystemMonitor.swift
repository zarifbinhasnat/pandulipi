import Darwin
import Foundation

/// Samples system RAM, this app's footprint, swap, and the Ollama model's memory.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var used: UInt64 = 0
    @Published var app: UInt64 = 0
    @Published var swap: UInt64 = 0
    @Published var peak: UInt64 = 0
    @Published var modelBytes: UInt64 = 0
    @Published var loadedModels: [String] = []
    @Published var ollamaUp = false

    private var timer: Timer?
    private var tick = 0

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    func resetPeak() { peak = used }

    private func sample() {
        used = Self.systemUsed()
        app = Self.appFootprint()
        swap = Self.swapUsed()
        peak = max(peak, used)
        tick += 1
        if tick % 2 == 1 {
            Task {
                let running = try? await OllamaClient.shared.running()
                self.ollamaUp = running != nil
                self.modelBytes = UInt64(running?.reduce(0) { $0 + $1.size } ?? 0)
                self.loadedModels = running?.map(\.name) ?? []
            }
        }
    }

    /// Roughly matches Activity Monitor's "Memory Used" (app + wired + compressed).
    static func systemUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        return (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func appFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }
}
