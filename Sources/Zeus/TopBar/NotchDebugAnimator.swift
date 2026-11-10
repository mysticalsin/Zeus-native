import Foundation
import SwiftUI
import ZeusCore

/// `zeus debug animate <name>`: drives the same light, cue and mascot paths the app uses for real
/// events, so QA can see each one on demand. Pulled out of AppDelegate so each kind is testable.
///
/// QA round 23: pulse, airdrop, battery and thinking returned "triggered" and nothing changed. The
/// one-shot lights are 0.9 to 3 s of thin crests on the arms, easy to miss, so those kinds now pair the
/// light with its wings cue and repeat the light for a few seconds; "thinking" was caught by the
/// reminder light and never reached the mascot.
@MainActor
enum NotchDebugAnimator {
    /// How long repeating lights keep replaying (the capture boost lasts about 3.5 s).
    static let replayWindow: TimeInterval = 3.5

    static func run(_ name: String, topBar: TopBarModel, avatar: AvatarStatus = .shared) -> Bool {
        switch name {
        case "volume": topBar.presentSystemHUDForDebug(.volume, value: 0.75, muted: false)
        case "brightness": topBar.presentSystemHUDForDebug(.brightness, value: 0.75, muted: false)
        case "keyboard": topBar.presentSystemHUDForDebug(.keyboardBacklight, value: 0.6, muted: false)
        case "mute": topBar.presentSystemHUDForDebug(.volume, value: 0, muted: true)
        case "thinking", "spark":
            // The mascot's thinking pose (with its sway) in the wings, and the sky-blue working light.
            avatar.flash(.thinking, for: 4)
            topBar.flashForDebug(.entrance(.sweep, .sky))
            replay(.entrance(.sweep, .sky), on: topBar)
        case "glow": topBar.flashForDebug(.edgeWave(.white))
        case "pulse":
            // The attention pulse: the event ribbon on the arms and a banner in the wings.
            topBar.show(.decided(engine: "Zeus", summary: "Pulse"))
            topBar.flashForDebug(.eventRibbon)
            replay(.eventRibbon, on: topBar)
        case "copy": topBar.flashForDebug(.copySweep)
        case "edge": topBar.flashForDebug(.edgeWave(.cyan))
        case "entrance": topBar.flashForDebug(.entrance(.sweep, .mint))
        case "airdrop":
            topBar.show(.shelfAdded(1))
            topBar.flashForDebug(.landed(airDrop: true))
            replay(.landed(airDrop: true), on: topBar)
        case "capslock", "caps-lock", "caps":
            let spring = Animation.spring(
                response: NotchClosedBodyLayout.wingsSpringResponse,
                dampingFraction: NotchClosedBodyLayout.wingsSpringDamping)
            withAnimation(spring) {
                topBar.show(.capsLock(true))
                topBar.flashForDebug(.capsLock(true))
            }
        case "battery":
            topBar.show(.lowBattery(42))
            topBar.flashForDebug(.battery(level: 0.42, charging: false))
        case "charging":
            topBar.show(.charging(42))
            topBar.flashForDebug(.battery(level: 0.42, charging: true))
        case "shiftcrest", "shift-crest": topBar.flashForDebug(.shiftCrest)
        case "bloom": topBar.flashForDebug(.entrance(.shimmer, .mint))
        case "halo":
            topBar.flashForDebug(.entrance(.sweep, .sky))
            topBar.flashForDebug(.edgeWave(.sky))
        case "timer": topBar.focus.startTimer(seconds: 90)
        case "music":
            topBar.nowPlaying = NowPlaying(player: .music, title: "Preview", artist: "Zeus", album: "", isPlaying: true, duration: 240, position: 60)
            topBar.liveMusicWings = true
        // "sleep"/"wake" aren't `AvatarState` cases (they're the `asleep`/`waking` booleans the real
        // idle-timer drives): preview the poses those booleans show.
        case "sleep": avatar.previewPose(.sleepingClean, for: 3)
        case "wake": avatar.previewPose(.waking, for: 3)
        default:
            // A mascot state name, then an exact v2 pose name (working, approval_wait, carrying, ...).
            if let state = AvatarState(rawValue: name) {
                if state == .idle { avatar.previewPose(.idle, for: 3) } else { avatar.flash(state, for: 3) }
            } else if let pose = LivingPose(rawValue: name) {
                avatar.previewPose(pose, for: 3)
            } else {
                return false
            }
        }
        return true
    }

    /// Plays `kind` again each time the previous one ends, until `replayWindow` is over.
    private static func replay(_ kind: NotchLightKind, on topBar: TopBarModel) {
        let step = kind.duration + 0.1
        guard step < replayWindow else { return }
        Task { @MainActor [weak topBar] in
            var elapsed = step
            while elapsed < replayWindow {
                try? await Task.sleep(for: .seconds(step))
                guard let topBar else { return }
                topBar.flashForDebug(kind)
                elapsed += step
            }
        }
    }
}
