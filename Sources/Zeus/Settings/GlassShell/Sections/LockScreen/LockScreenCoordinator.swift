import Foundation
import ZeusCore

/// Hears lock and unlock, then plays the owner's cue. The card stays hidden when the private call cannot be shown.
@MainActor
final class LockScreenCoordinator {
    static let shared = LockScreenCoordinator()

    private var session = LockScreenSession()
    private var installed = false
    private var tokens: [NSObjectProtocol] = []
    private let answer: @Sendable (Int) -> LockScreenSpaceAnswer = { _ in LockScreenSpaceLoader.probe() }

    func sync(_ settings: LockScreenSettings) {
        let effects = session.replaceSettings(
            settings,
            playback: .none,
            space: answer,
            soundFileExists: LockScreenCuePlayer.exists
        )
        perform(effects)
        guard !installed, !StartupPolicy.current.isQA, !TopBarStyle.isSnapshot else { return }
        installed = true
        let seeded = session.handle(
            .sawUnlocked,
            playback: .none,
            space: answer,
            soundFileExists: LockScreenCuePlayer.exists
        )
        perform(seeded)
        let center = DistributedNotificationCenter.default()
        observe(center, "com.apple.screenIsLocked", .sawLocked)
        observe(center, "com.apple.screenIsUnlocked", .sawUnlocked)
    }

    private func observe(_ center: DistributedNotificationCenter, _ name: String, _ event: LockObservationEvent) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        tokens.append(token)
    }

    private func receive(_ event: LockObservationEvent) {
        let effects = session.handle(
            event,
            playback: .none,
            space: answer,
            soundFileExists: LockScreenCuePlayer.exists
        )
        perform(effects)
    }

    private func perform(_ effects: [LockScreenEffect]) {
        for effect in effects {
            if case .play(let cue) = effect { LockScreenCuePlayer.play(cue) }
        }
    }
}
