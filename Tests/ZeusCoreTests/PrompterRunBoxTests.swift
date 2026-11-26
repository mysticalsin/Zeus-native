import Foundation
import Testing
@testable import ZeusCore

@Suite("Prompter run box")
struct PrompterRunBoxTests {
    private typealias Box = PrompterRunBox

    @Test func beginWithVoiceFollowStartsThatSession() {
        let (phase, effects) = Box.reduce(.idle, .began(voiceFollow: true, session: 1))
        #expect(phase == .running(mic: 1))
        #expect(effects == [.startMic(session: 1)])
        #expect(Box.isRunning(phase))
        #expect(Box.acceptsLevel(phase, from: 1))
        #expect(!Box.isRunning(.idle))
    }

    @Test func beginWithoutVoiceFollowScrollsWithNoMic() {
        let (phase, effects) = Box.reduce(.idle, .began(voiceFollow: false, session: 1))
        #expect(phase == .running(mic: nil))
        #expect(effects.isEmpty)
        #expect(Box.isRunning(phase))
        #expect(!Box.acceptsLevel(phase, from: 1))
    }

    @Test func aBeginWhileRunningIsIgnored() {
        let live = Box.reduce(.running(mic: 1), .began(voiceFollow: true, session: 2))
        #expect(live.0 == .running(mic: 1))
        #expect(live.1.isEmpty)
        let steady = Box.reduce(.running(mic: nil), .began(voiceFollow: true, session: 4))
        #expect(steady.0 == .running(mic: nil))
        #expect(steady.1.isEmpty)
        let alreadyOff = Box.reduce(.running(mic: nil), .began(voiceFollow: false, session: 9))
        #expect(alreadyOff.0 == .running(mic: nil) && alreadyOff.1.isEmpty)
        let alreadyOn = Box.reduce(.running(mic: 3), .began(voiceFollow: false, session: 8))
        #expect(alreadyOn.0 == .running(mic: 3) && alreadyOn.1.isEmpty)
    }

    @Test func endingALiveMicStopsIt() {
        let (phase, effects) = Box.reduce(.running(mic: 1), .ended)
        #expect(phase == .idle)
        #expect(effects == [.stopMic])
        #expect(!Box.isRunning(phase))
        #expect(!Box.acceptsLevel(phase, from: 1))
    }

    @Test func endingASteadyScrollOrIdleHasNoEffect() {
        let (steady, steadyEffects) = Box.reduce(.running(mic: nil), .ended)
        #expect(steady == .idle && steadyEffects.isEmpty)
        let (idle, idleEffects) = Box.reduce(.idle, .ended)
        #expect(idle == .idle && idleEffects.isEmpty)
        let again = Box.reduce(idle, .ended)
        #expect(again.0 == .idle && again.1.isEmpty)
    }

    @Test func voiceFollowOnFromASteadyScrollStartsTheNamedSession() {
        let (phase, effects) = Box.reduce(.running(mic: nil), .voiceChanged(on: true, session: 4))
        #expect(phase == .running(mic: 4))
        #expect(effects == [.startMic(session: 4)])
        #expect(Box.acceptsLevel(phase, from: 4))
        #expect(!Box.acceptsLevel(phase, from: 1))
    }

    @Test func voiceFollowOffStopsTheLiveMicEvenWhenTheEventNamesAnotherSession() {
        let (phase, effects) = Box.reduce(.running(mic: 1), .voiceChanged(on: false, session: 2))
        #expect(phase == .running(mic: nil))
        #expect(effects == [.stopMic])
        #expect(Box.isRunning(phase))
        #expect(!Box.acceptsLevel(phase, from: 1))
        #expect(!Box.acceptsLevel(phase, from: 2))
    }

    @Test func voiceFollowThatIsAlreadyInThatStateDoesNothing() {
        let (on, onEffects) = Box.reduce(.running(mic: 1), .voiceChanged(on: true, session: 2))
        #expect(on == .running(mic: 1) && onEffects.isEmpty)
        let (same, sameEffects) = Box.reduce(.running(mic: 5), .voiceChanged(on: true, session: 5))
        #expect(same == .running(mic: 5) && sameEffects.isEmpty)
        let (off, offEffects) = Box.reduce(.running(mic: nil), .voiceChanged(on: false, session: 2))
        #expect(off == .running(mic: nil) && offEffects.isEmpty)
    }

    @Test func voiceFollowWhileIdleDoesNothing() {
        let (on, onEffects) = Box.reduce(.idle, .voiceChanged(on: true, session: 1))
        #expect(on == .idle && onEffects.isEmpty)
        let (off, offEffects) = Box.reduce(.idle, .voiceChanged(on: false, session: 1))
        #expect(off == .idle && offEffects.isEmpty)
        #expect(!Box.isRunning(on))
    }

    @Test func aMicFailureClearsOnlyTheLiveSession() {
        let (phase, effects) = Box.reduce(.running(mic: 2), .micFailed(session: 2))
        #expect(phase == .running(mic: nil))
        #expect(effects == [.stopMic])
        #expect(Box.isRunning(phase))
        #expect(!Box.acceptsLevel(phase, from: 2))
    }

    @Test func aMicFailureForAnotherSessionOrIdleDoesNothing() {
        let (other, otherEffects) = Box.reduce(.running(mic: 3), .micFailed(session: 2))
        #expect(other == .running(mic: 3) && otherEffects.isEmpty)
        let (steady, steadyEffects) = Box.reduce(.running(mic: nil), .micFailed(session: 2))
        #expect(steady == .running(mic: nil) && steadyEffects.isEmpty)
        let (idle, idleEffects) = Box.reduce(.idle, .micFailed(session: 2))
        #expect(idle == .idle && idleEffects.isEmpty)
    }

    @Test func aLevelIsAcceptedOnlyFromTheLiveSession() {
        #expect(Box.acceptsLevel(.running(mic: 3), from: 3))
        #expect(!Box.acceptsLevel(.running(mic: 3), from: 1))
        #expect(!Box.acceptsLevel(.running(mic: 3), from: 0))
        #expect(!Box.acceptsLevel(.running(mic: nil), from: 3))
        #expect(!Box.acceptsLevel(.idle, from: 3))
        let (ended, _) = Box.reduce(.running(mic: 3), .ended)
        #expect(!Box.acceptsLevel(ended, from: 3))
        let (next, _) = Box.reduce(.running(mic: nil), .voiceChanged(on: true, session: 6))
        #expect(Box.acceptsLevel(next, from: 6))
        #expect(!Box.acceptsLevel(next, from: 3))
    }

    @Test func zeroAndNegativeSessionsAreRealSessions() {
        let (zero, zeroEffects) = Box.reduce(.idle, .began(voiceFollow: true, session: 0))
        #expect(zero == .running(mic: 0))
        #expect(zeroEffects == [.startMic(session: 0)])
        #expect(Box.acceptsLevel(zero, from: 0))
        #expect(!Box.acceptsLevel(zero, from: -7))
        let (negative, negativeEffects) = Box.reduce(.idle, .began(voiceFollow: true, session: -7))
        #expect(negative == .running(mic: -7))
        #expect(negativeEffects == [.startMic(session: -7)])
        #expect(Box.acceptsLevel(negative, from: -7))
        let (failed, failedEffects) = Box.reduce(negative, .micFailed(session: -7))
        #expect(failed == .running(mic: nil) && failedEffects == [.stopMic])
        let (off, offEffects) = Box.reduce(.running(mic: 0), .voiceChanged(on: false, session: 0))
        #expect(off == .running(mic: nil) && offEffects == [.stopMic])
    }

    @Test func thePublicRunReadsTheBox() {
        let (started, startedEffects) = PrompterRun.reduce(.idle, .began(voiceFollow: true, session: 1))
        #expect(started == .running(mic: 1))
        #expect(startedEffects == [.startMic(session: 1)])
        #expect(started.isRunning)
        #expect(started.acceptsLevel(from: 1))
        #expect(!started.acceptsLevel(from: 2))
        let (steady, steadyEffects) = PrompterRun.reduce(.idle, .began(voiceFollow: false, session: 1))
        #expect(steady == .running(mic: nil) && steadyEffects.isEmpty)
        #expect(steady.isRunning)
        #expect(!steady.acceptsLevel(from: 1))
        let (ignored, ignoredEffects) = PrompterRun.reduce(.running(mic: 1), .began(voiceFollow: true, session: 2))
        #expect(ignored == .running(mic: 1) && ignoredEffects.isEmpty)
        let (ended, endedEffects) = PrompterRun.reduce(.running(mic: 1), .ended)
        #expect(ended == .idle && endedEffects == [.stopMic])
        #expect(!ended.isRunning)
        #expect(!ended.acceptsLevel(from: 1))
        let (plain, plainEffects) = PrompterRun.reduce(.running(mic: nil), .ended)
        #expect(plain == .idle && plainEffects.isEmpty)
        let (idleEnd, idleEndEffects) = PrompterRun.reduce(.idle, .ended)
        #expect(idleEnd == .idle && idleEndEffects.isEmpty)
        let (on, onEffects) = PrompterRun.reduce(.running(mic: nil), .voiceChanged(on: true, session: 3))
        #expect(on == .running(mic: 3) && onEffects == [.startMic(session: 3)])
        #expect(on.acceptsLevel(from: 3))
        #expect(!PrompterRun.State.idle.acceptsLevel(from: 3))
        let (off, offEffects) = PrompterRun.reduce(on, .voiceChanged(on: false, session: 9))
        #expect(off == .running(mic: nil) && offEffects == [.stopMic])
        #expect(PrompterRun.reduce(.running(mic: 1), .voiceChanged(on: true, session: 2)).1.isEmpty)
        #expect(PrompterRun.reduce(.idle, .voiceChanged(on: true, session: 1)).1.isEmpty)
        let (failed, failedEffects) = PrompterRun.reduce(.running(mic: 2), .micFailed(session: 2))
        #expect(failed == .running(mic: nil) && failedEffects == [.stopMic])
        let (other, otherEffects) = PrompterRun.reduce(.running(mic: 3), .micFailed(session: 2))
        #expect(other == .running(mic: 3) && otherEffects.isEmpty)
    }
}
