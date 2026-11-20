import Foundation
import Testing
@testable import ZeusCore

@Suite struct OnboardingPresentationTests {
    private func guide(step: Int = 3, reduceMotion: Bool = false) -> OnboardingPresentation {
        OnboardingPresentation(
            progress: .init(step: step, choices: ["agent"], permissionState: ["microphone-allowed"]),
            reduceMotion: reduceMotion)
    }

    @Test func escapeCollapsesAndKeepsTheStep() {
        var guide = guide()
        let effects = guide.send(.escape)
        #expect(guide.phase == .minimized)
        #expect(guide.progress.step == 3)
        #expect(guide.progress.choices == ["agent"])
        #expect(guide.progress.permissionState == ["microphone-allowed"])
        #expect(effects.contains(.resize(OnboardingPresentation.minimizedSize)))
        #expect(effects.contains(.announce("Setup minimized")))
        #expect(effects.contains(.releaseKeyFocus))
        #expect(effects.contains(.animated(true)))
    }

    @Test func reopenRestoresTheSameStep() {
        var guide = guide(step: 6)
        _ = guide.send(.minimizeControl)
        let effects = guide.send(.reopen)
        #expect(guide.phase == .expanded)
        #expect(guide.progress.step == 6)
        #expect(guide.progress.choices == ["agent"])
        #expect(effects.contains(.resize(OnboardingPresentation.expandedSize)))
        #expect(effects.contains(.announce("Setup restored")))
    }

    @Test func theMinimizeControlMatchesEscape() {
        var fromEscape = guide()
        var fromControl = guide()
        #expect(fromEscape.send(.escape) == fromControl.send(.minimizeControl))
        #expect(fromEscape.phase == fromControl.phase)
    }

    @Test func aSecondEscapeWhileMinimizedIsHarmless() {
        var guide = guide()
        _ = guide.send(.escape)
        let again = guide.send(.escape)
        #expect(again.isEmpty)
        #expect(guide.phase == .minimized)
        #expect(guide.progress.step == 3)
    }

    @Test func reduceMotionSkipsTheResizeAnimation() {
        var guide = guide(reduceMotion: true)
        let effects = guide.send(.escape)
        #expect(effects.contains(.animated(false)))
        #expect(!effects.contains(.animated(true)))
        let restored = guide.send(.reopen)
        #expect(restored.contains(.animated(false)))
    }

    @Test func everyStepSurvivesMinimizeAndTheSizeEdgesStayPut() {
        for step in [0, 1, 9] {
            var guide = guide(step: step)
            _ = guide.send(.escape)
            #expect(guide.phase == .minimized)
            #expect(guide.progress.step == step)
            _ = guide.send(.reopen)
            #expect(guide.phase == .expanded)
            #expect(guide.progress.step == step)
        }
        #expect(OnboardingPresentation.expandedSize == .init(width: 960, height: 760))
        #expect(OnboardingPresentation.minimizedSize.height < OnboardingPresentation.expandedSize.height)
        #expect(OnboardingPresentation.takesKeyFocusOnFirstShow == false)
    }

    @Test func aTimeoutIsAnInfrastructureErrorAfterOneRetry() async {
        let tries = Counter()
        await #expect(throws: VerifyInfrastructure.timedOut("onboarding")) {
            try await verifyWithin("onboarding") {
                tries.add()
                throw VerifyInfrastructure.timedOut("onboarding")
            }
        }
        #expect(tries.value == 2)
    }
}

private enum VerifyInfrastructure: Error, Equatable {
    case timedOut(String)
}

private func verifyWithin<T>(_ label: String, _ body: () async throws -> T) async throws -> T {
    for attempt in 1...2 {
        do { return try await body() }
        catch let error as VerifyInfrastructure {
            if attempt == 2 { throw error }
        }
    }
    throw VerifyInfrastructure.timedOut(label)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func add() { lock.withLock { stored += 1 } }
}
