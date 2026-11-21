import Foundation
import Testing
@testable import ZeusCore

/// S07-01 and S07-02. A quiet pose and Reduce Motion do not search neighbours.
/// An active pose still does, so the living animation stays.
@Suite("Orb idle cost")
struct OrbIdleCostTests {
    @Test func idleDoesNotSearchLines() {
        var idle = OrbSimulation(seed: 1, state: .idle)
        for _ in 0..<180 {
            idle.renderFrame(delta: 1.0 / 60.0, audio: .silent, reduceMotion: false)
        }
        #expect(idle.lineCount == 0)
        #expect(idle.lines.isEmpty)
    }

    @Test func reduceMotionDoesNotSearchLines() {
        var reduced = OrbSimulation(seed: 4, state: .thinking)
        let frozen = reduced.particles[0]
        for _ in 0..<90 {
            reduced.renderFrame(delta: 1.0 / 60.0, audio: OrbAudioBands(bass: 1, mid: 1), reduceMotion: true)
        }
        #expect(reduced.lineCount == 0)
        #expect(reduced.particles[0].x == frozen.x)
        #expect(reduced.particles[0].y == frozen.y)
        #expect(reduced.particles[0].z == frozen.z)
        #expect(reduced.electrons.isEmpty)
    }

    @Test func quietPoseAndReduceMotionPauseTheRedraw() {
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .idle, reduceMotion: false))
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .speaking, reduceMotion: true))
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .thinking, reduceMotion: true))
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .speaking, reduceMotion: false) == false)
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .listening, reduceMotion: false) == false)
        #expect(OrbRedrawPolicy.pausesRedraw(visualState: .compacting, reduceMotion: false) == false)
        #expect(OrbRedrawPolicy.activeFramesPerSecond == 120)
    }

    @Test func speakingStillBuildsLines() {
        var speaking = OrbSimulation(seed: 11, state: .speaking)
        for _ in 0..<30 {
            speaking.integrateFixedStep(audio: .silent, reduceMotion: false)
        }
        #expect(speaking.lineCount > 0)
    }
}
