import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// QA23: `zeus debug animate pulse|airdrop|battery|thinking` returned "triggered" and nothing changed.
/// Each kind must leave a non-empty light or cue (or mascot state) in the models.
@MainActor @Suite struct NotchDebugAnimatorTests {
    private func lit(_ topBar: TopBarModel) -> Bool { !topBar.lights.isEmpty || topBar.cue != nil }

    @Test func pulseAirdropAndBatteryLightTheNotch() {
        for name in ["pulse", "airdrop", "battery", "charging", "volume", "brightness", "keyboard", "mute", "copy", "capslock", "shiftcrest", "entrance", "bloom"] {
            let topBar = TopBarModel()
            #expect(NotchDebugAnimator.run(name, topBar: topBar, avatar: AvatarStatus()), "\(name)")
            #expect(lit(topBar), "\(name) left nothing lit")
        }
    }

    @Test func eachKindShowsALightAndItsCue() {
        let pulse = TopBarModel()
        _ = NotchDebugAnimator.run("pulse", topBar: pulse, avatar: AvatarStatus())
        #expect(pulse.lights.contains { $0.kind == .eventRibbon })
        #expect(pulse.cue != nil)

        let airdrop = TopBarModel()
        _ = NotchDebugAnimator.run("airdrop", topBar: airdrop, avatar: AvatarStatus())
        #expect(airdrop.lights.contains { $0.kind == .landed(airDrop: true) })
        #expect(airdrop.cue == .shelfAdded(1))

        let battery = TopBarModel()
        _ = NotchDebugAnimator.run("battery", topBar: battery, avatar: AvatarStatus())
        #expect(battery.lights.contains { if case .battery = $0.kind { true } else { false } })
        #expect(battery.cue == .lowBattery(42))
    }

    @Test func thinkingDrivesTheMascotAndALight() {
        let topBar = TopBarModel()
        let avatar = AvatarStatus()
        #expect(avatar.current == .idle)
        #expect(NotchDebugAnimator.run("thinking", topBar: topBar, avatar: avatar))
        #expect(avatar.current == .thinking)
        #expect(!topBar.lights.isEmpty)
        // And the mascot wings are what the closed notch would show.
        #expect(AvatarState.thinking.pose == .thinking)
    }

    @Test func unknownNamesAreRefusedAndMascotNamesStillWork() {
        let topBar = TopBarModel()
        let avatar = AvatarStatus()
        #expect(!NotchDebugAnimator.run("no-such-effect", topBar: topBar, avatar: avatar))
        #expect(NotchDebugAnimator.run("listening", topBar: topBar, avatar: avatar))
        #expect(avatar.current == .listening)
        #expect(NotchDebugAnimator.run("celebrate", topBar: topBar, avatar: avatar))
        #expect(avatar.posePreview == .celebrate)
    }

    @Test func everyAdvertisedLightNameIsHandled() {
        for name in NotchDebugEffects.lightNames + NotchDebugEffects.mascotStateNames {
            #expect(NotchDebugAnimator.run(name, topBar: TopBarModel(), avatar: AvatarStatus()), "\(name)")
        }
    }

    @Test func edgeDebugNameIsHandled() {
        #expect(NotchDebugAnimator.run("edge", topBar: TopBarModel(), avatar: AvatarStatus()))
    }

    @Test func volumeHudUsesWingsSpringTiming() {
        #expect(NotchClosedBodyLayout.wingsSpringResponse <= 0.12)
    }
}
