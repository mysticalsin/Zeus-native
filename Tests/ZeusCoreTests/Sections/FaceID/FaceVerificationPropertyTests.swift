import Foundation
import Testing
@testable import ZeusCore

@Suite("Face verification properties")
struct FaceVerificationPropertyTests {
    @Test func noPathReachesMatchedWithoutPassingLiveness() {
        var generator = SplitMix(seed: 0xF4CE_11FE)
        for _ in 0..<240 {
            var machine = FaceVerificationMachine()
            let length = 8 + Int(generator.next() % 28)
            for step in 0..<length {
                let phaseBefore = machine.phase
                let passedBefore = machine.livenessPassed
                let event = generator.event(step: step)
                _ = machine.handle(event)
                if machine.phase == .matched {
                    let passedNow = eventPassesLiveness(event, from: phaseBefore)
                    #expect(passedBefore || passedNow)
                    #expect(machine.livenessPassed)
                    #expect(machine.grant?.method == .face)
                    #expect(machine.grant?.nonce == machine.openAction?.nonce)
                    #expect(machine.openAction?.isBound == true)
                }
                #expect(cameraFollowsThePhase(machine))
                #expect(machine.failures <= FaceVerificationPolicy.failureLimit)
                if machine.phase == .lockedOut {
                    #expect(machine.grant == nil)
                    #expect(machine.fallbackOffer?.canApproveNow == false)
                }
            }
        }
    }

    @Test func shortSequencesNeverMatchWithoutLiveness() {
        let alphabet = 8
        for first in 0..<alphabet {
            for second in 0..<alphabet {
                for third in 0..<alphabet {
                    var machine = FaceVerificationMachine()
                    for (offset, index) in [first, second, third].enumerated() {
                        let phaseBefore = machine.phase
                        let passedBefore = machine.livenessPassed
                        let event = shortEvent(index, step: offset)
                        _ = machine.handle(event)
                        if machine.phase == .matched {
                            #expect(passedBefore || eventPassesLiveness(event, from: phaseBefore))
                        }
                    }
                }
            }
        }
    }

    private func eventPassesLiveness(_ event: FaceVerificationEvent, from phase: FaceVerificationPhase) -> Bool {
        guard phase == .livenessCheck, case .liveness(let result, _) = event else { return false }
        return result.passed
    }

    private func cameraFollowsThePhase(_ machine: FaceVerificationMachine) -> Bool {
        let livePhases: Set<FaceVerificationPhase> = [.enrolling, .capturing, .livenessCheck]
        let allowed = machine.approvalEnabled && machine.camera == .authorized && livePhases.contains(machine.phase)
        return machine.wantsCamera == allowed
    }

    private func shortEvent(_ index: Int, step: Int) -> FaceVerificationEvent {
        let uptime = Double(step + 1)
        switch index {
        case 0: return .enable(enrolled: true, camera: .authorized, uptime: uptime)
        case 1: return .beginApproval(ApprovalAction(id: "a", nonce: "n\(step)"), uptime: uptime)
        case 2: return .capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: uptime)
        case 3: return .liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: false), uptime: uptime)
        case 4: return .identity(matched: true, uptime: uptime)
        case 5: return .capture(.seen(distance: 0, spoof: [.glossGlare], virtualCamera: false), uptime: uptime)
        case 6: return .disable
        default: return .identity(matched: true, uptime: uptime)
        }
    }
}

private struct SplitMix: Sendable {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func event(step: Int) -> FaceVerificationEvent {
        let uptime = Double(step)
        switch Int(next() % 14) {
        case 0: return .enable(enrolled: next() % 2 == 0, camera: .authorized, uptime: uptime)
        case 1: return .disable
        case 2: return .beginEnrollment
        case 3: return .enrollmentSaved(image: next() % 5 == 0 ? Data([1]) : nil, thumbnail: nil)
        case 4: return .deleteTemplate
        case 5: return .beginApproval(ApprovalAction(id: "action", nonce: "n\(next() % 17)"), uptime: uptime)
        case 6: return .capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: uptime)
        case 7: return .capture(.seen(distance: 0, spoof: [.deviceBezel], virtualCamera: false), uptime: uptime)
        case 8: return .liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: false), uptime: uptime)
        case 9: return .liveness(FaceLivenessResult(blinked: true, turnedHead: false, virtualCamera: true), uptime: uptime)
        case 10: return .identity(matched: true, uptime: uptime)
        case 11: return .chooseFallback
        case 12: return .fallbackResult(succeeded: true, action: ApprovalAction(id: "action", nonce: "n\(step)"), uptime: uptime)
        default: return .tick(uptime: uptime + 10_000)
        }
    }
}
