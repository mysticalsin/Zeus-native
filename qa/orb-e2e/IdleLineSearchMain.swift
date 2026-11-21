import Foundation

/// S07-02. Idle and Reduce Motion must not run the neighbour search.
/// Speaking still may. Exits 1 while the search runs for a quiet pose.
@main
struct IdleLineSearchMain {
    static func main() {
        var failed = false
        func expect(_ ok: Bool, _ message: String) {
            if ok { return }
            failed = true
            fputs("FAIL \(message)\n", stderr)
        }

        var idle = OrbSimulation(seed: 1, state: .idle)
        let idleStarted = ContinuousClock.now
        for _ in 0..<180 {
            idle.renderFrame(delta: 1.0 / 60.0, audio: .silent, reduceMotion: false)
        }
        let idleElapsed = ContinuousClock.now - idleStarted
        let idleMilliseconds = milliseconds(idleElapsed)
        fputs(String(format: "idle180 %.2f ms lines %d\n", idleMilliseconds, idle.lineCount), stderr)
        expect(idle.lineCount == 0, "idle searched \(idle.lineCount) lines")
        expect(idle.lines.isEmpty, "idle kept \(idle.lines.count) line values")

        var reduced = OrbSimulation(seed: 4, state: .thinking)
        let frozen = reduced.particles[0]
        for _ in 0..<90 {
            reduced.renderFrame(delta: 1.0 / 60.0, audio: OrbAudioBands(bass: 1, mid: 1), reduceMotion: true)
        }
        fputs("reduceMotion lines \(reduced.lineCount)\n", stderr)
        expect(reduced.lineCount == 0, "Reduce Motion searched \(reduced.lineCount) lines")
        expect(reduced.particles[0].x == frozen.x && reduced.particles[0].y == frozen.y && reduced.particles[0].z == frozen.z,
               "Reduce Motion moved a particle")

        var speaking = OrbSimulation(seed: 11, state: .speaking)
        for _ in 0..<30 {
            speaking.integrateFixedStep(audio: .silent, reduceMotion: false)
        }
        expect(speaking.lineCount > 0, "speaking produced no lines")
        expect(OrbRedrawPolicy.pausesRedraw(visualState: .idle, reduceMotion: false), "idle redraw stays scheduled")
        expect(OrbRedrawPolicy.pausesRedraw(visualState: .speaking, reduceMotion: true), "Reduce Motion redraw stays scheduled")
        expect(OrbRedrawPolicy.pausesRedraw(visualState: .speaking, reduceMotion: false) == false, "speaking redraw paused")
        expect(OrbRedrawPolicy.activeFramesPerSecond == 120, "active frame rate changed")

        if failed { exit(1) }
    }

    private static func milliseconds(_ elapsed: Duration) -> Double {
        let parts = elapsed.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
