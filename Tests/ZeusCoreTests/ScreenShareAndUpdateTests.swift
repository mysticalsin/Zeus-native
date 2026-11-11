import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen share policy")
struct ZeusScreenSharePolicyTests {
    @Test func defaultHiddenUntilEnabled() {
        let defaults = UserDefaults(suiteName: "ZeusScreenSharePolicyTests")!
        defaults.removePersistentDomain(forName: "ZeusScreenSharePolicyTests")
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults) == false)
    }

    @Test func migratesLegacyHideKey() {
        let defaults = UserDefaults(suiteName: "ZeusScreenSharePolicyTests2")!
        defaults.removePersistentDomain(forName: "ZeusScreenSharePolicyTests2")
        defaults.set(true, forKey: ZeusScreenSharePolicy.legacyHideKey)
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults) == false)
        defaults.set(false, forKey: ZeusScreenSharePolicy.legacyHideKey)
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults) == true)
    }

    /// The matrix: the default (nothing chosen, switch off) is hidden in and out of a meeting; an explicit
    /// "show" is visible in a meeting too (it used to be forced hidden, so the switch looked broken); the
    /// teleprompter's private session always hides.
    @Test func explicitShowWinsOverMeetingAutoHide() {
        func visible(show: Bool, meeting: Bool, prompter: Bool) -> Bool {
            ZeusScreenSharePolicy.zeusSurfacesVisible(showInScreenSharing: show, meetingActive: meeting, teleprompterSessionHidden: prompter)
        }
        #expect(visible(show: true, meeting: true, prompter: false))
        #expect(visible(show: true, meeting: false, prompter: false))
        #expect(!visible(show: false, meeting: true, prompter: false))
        #expect(!visible(show: false, meeting: false, prompter: false))
        #expect(!visible(show: true, meeting: true, prompter: true))
        #expect(!visible(show: true, meeting: false, prompter: true))
    }

    @Test func captureKindFollowsVisibility() {
        #expect(ZeusScreenSharePolicy.captureKind(visible: true) == .visibleInShare)
        #expect(ZeusScreenSharePolicy.captureKind(visible: false) == .hidden)
    }
}

@Suite("Update badge logic")
struct UpdateBadgeLogicTests {
    @Test func versionCompareAndBadge() throws {
        let current = try #require(ZeusVersion(parsing: "3.0.1"))
        let newer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "3.1.0")))
        let defaults = UserDefaults(suiteName: "UpdateBadgeLogicTests")!
        defaults.removePersistentDomain(forName: "UpdateBadgeLogicTests")
        let state = UpdateBadgeLogic.badgeState(current: current, offer: newer, feedEnabled: true, debugFake: nil, defaults: defaults)
        guard case .available(let offer, _) = state else {
            Issue.record("expected available badge")
            return
        }
        #expect(offer.latest == newer.latest)
    }

    @Test func feedOffAndNoFakeHidesBadge() throws {
        let current = try #require(ZeusVersion(parsing: "1.0.0"))
        let newer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "9.0.0")))
        let defaults = UserDefaults(suiteName: "UpdateBadgeLogicTests2")!
        defaults.removePersistentDomain(forName: "UpdateBadgeLogicTests2")
        let state = UpdateBadgeLogic.badgeState(current: current, offer: newer, feedEnabled: false, debugFake: nil, defaults: defaults)
        #expect(state == .hidden)
    }

    @Test func debugFakeShowsBadge() throws {
        let current = try #require(ZeusVersion(parsing: "1.0.0"))
        let defaults = UserDefaults(suiteName: "UpdateBadgeLogicTests3")!
        defaults.removePersistentDomain(forName: "UpdateBadgeLogicTests3")
        let state = UpdateBadgeLogic.badgeState(current: current, offer: nil, feedEnabled: false, debugFake: "3.1.0", defaults: defaults)
        guard case .available(let offer, _) = state else {
            Issue.record("expected fake badge")
            return
        }
        #expect(offer.latest.displayShort == "3.1")
    }

    @Test func dismissalPerVersion() throws {
        let offer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "3.1.0")))
        let defaults = UserDefaults(suiteName: "UpdateBadgeLogicTests4")!
        defaults.removePersistentDomain(forName: "UpdateBadgeLogicTests4")
        UpdateDismissalStore.dismiss(offer.latest, defaults: defaults)
        #expect(UpdateDismissalStore.isDismissed(offer, defaults: defaults))
        #expect(UpdateHUDPresentation.shouldShowHUD(for: offer, defaults: defaults))
        UpdateHUDPresentation.markHUDShown(for: offer, defaults: defaults)
        #expect(!UpdateHUDPresentation.shouldShowHUD(for: offer, defaults: defaults))
    }

    @Test func rollLabel() throws {
        let v = try #require(ZeusVersion(parsing: "3.1.2"))
        #expect(UpdateBadgeLogic.rollLabel(from: nil, to: v) == "Update 3.1")
    }
}
