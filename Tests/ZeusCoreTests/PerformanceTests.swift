import Foundation
import Testing
@testable import ZeusCore

private final class Log: @unchecked Sendable {
    let lock = NSLock(); var events: [String] = []
    func add(_ s: String) { lock.lock(); events.append(s); lock.unlock() }
}

@Suite struct PerformanceTests {
    @Test func oneLargeModelAtATimeAndIdleUnload() {
        let log = Log()
        let r = ModelResidency(hooks: .init(load: { log.add("load \($0.rawValue)") }, unload: { log.add("unload \($0.rawValue)") }), idle: 300)
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = r.use(.laya, now: t0)
        #expect(first)
        let again = r.use(.laya, now: t0.addingTimeInterval(10))
        #expect(!again)
        r.use(.parakeet, now: t0.addingTimeInterval(20))
        #expect(log.events == ["load laya", "unload laya", "load parakeet"])
        r.sweep(now: t0.addingTimeInterval(200))
        #expect(r.resident == .parakeet)
        #expect(r.nextSweep == t0.addingTimeInterval(320))
        r.sweep(now: t0.addingTimeInterval(320))
        #expect(r.resident == nil)
        #expect(log.events.last == "unload parakeet")
    }

    @Test func lowPowerAndHeatAreConstrained() {
        #expect(PowerState(lowPower: true, thermal: .nominal).constrained)
        #expect(PowerState(lowPower: false, thermal: .serious).constrained)
        #expect(!PowerState(lowPower: false, thermal: .fair).constrained)
    }

    @Test func energySampleReadsThisProcess() {
        let s = ProcessEnergy.sample()
        #expect(s.residentMB > 1)
        #expect(abs(ProcessEnergy.cpuPercent(from: .init(cpuSeconds: 1, residentMB: 0), to: .init(cpuSeconds: 1.05, residentMB: 0), over: 10) - 0.5) < 1e-9)
    }
}
