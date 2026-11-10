import Foundation

/// The lightness contract, checked by scripts/check-perf-budget.sh and shown in Diagnostics > Energy.
public enum PerformanceBudget {
    public static let idleCPUPercent = 1.0
    public static let idleMemoryMB = 150.0
    public static let notchFPS = 60
    public static let modelIdleUnload: TimeInterval = 300
    /// Helper processes that must not be running by default.
    public static let forbiddenDefaultProcesses = ["ollama", "kev", "laya-serve"]
}

/// Whether to fall back to lighter engines: Low Power Mode or a serious or critical thermal state.
public struct PowerState: Equatable, Sendable {
    public var lowPower: Bool
    public var thermal: ProcessInfo.ThermalState
    public init(lowPower: Bool, thermal: ProcessInfo.ThermalState) { self.lowPower = lowPower; self.thermal = thermal }
    public static var current: PowerState {
        PowerState(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState)
    }
    public var constrained: Bool { lowPower || thermal == .serious || thermal == .critical }
}

/// Large local models (Parakeet, Laya, Kokoro) load on first use, unload after five idle minutes,
/// and only one is resident at a time: loading one unloads the other. Driven by events and a
/// single one-shot timer per load, never a polling loop.
public final class ModelResidency: @unchecked Sendable {
    public enum Model: String, CaseIterable, Sendable { case parakeet, laya, kokoro }
    public struct Hooks: Sendable {
        public var load: @Sendable (Model) -> Void
        public var unload: @Sendable (Model) -> Void
        public init(load: @escaping @Sendable (Model) -> Void, unload: @escaping @Sendable (Model) -> Void) { self.load = load; self.unload = unload }
    }

    private let lock = NSLock()
    private let hooks: Hooks
    private let idle: TimeInterval
    public private(set) var resident: Model?
    private var lastUse: Date = .distantPast

    public init(hooks: Hooks, idle: TimeInterval = PerformanceBudget.modelIdleUnload) { self.hooks = hooks; self.idle = idle }

    /// Call before each use. Returns true when this call loaded the model.
    @discardableResult public func use(_ model: Model, now: Date = Date()) -> Bool {
        lock.lock()
        let previous = resident
        let loads = previous != model
        resident = model
        lastUse = now
        lock.unlock()
        if loads {
            if let previous { hooks.unload(previous) }
            hooks.load(model)
        }
        return loads
    }

    /// Call from the one-shot idle timer (or any event). Unloads when idle long enough.
    public func sweep(now: Date = Date()) {
        lock.lock()
        guard let model = resident, now.timeIntervalSince(lastUse) >= idle else { lock.unlock(); return }
        resident = nil
        lock.unlock()
        hooks.unload(model)
    }

    /// When the next sweep is due, so the caller can schedule exactly one timer.
    public var nextSweep: Date? {
        lock.lock(); defer { lock.unlock() }
        return resident == nil ? nil : lastUse.addingTimeInterval(idle)
    }
}

/// Live CPU and memory of this process, for Diagnostics > Energy.
public struct ProcessEnergy: Equatable, Sendable {
    public var cpuSeconds: Double
    public var residentMB: Double

    public static func sample() -> ProcessEnergy {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let footprint = kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
        return ProcessEnergy(cpuSeconds: cpu, residentMB: footprint)
    }

    /// Average CPU percent of one core between two samples.
    public static func cpuPercent(from a: ProcessEnergy, to b: ProcessEnergy, over seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return max(0, (b.cpuSeconds - a.cpuSeconds) / seconds * 100)
    }
}
