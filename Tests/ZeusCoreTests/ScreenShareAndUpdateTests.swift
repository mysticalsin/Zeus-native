import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen share policy")
struct ZeusScreenSharePolicyTests {
    @Test func defaultHiddenUntilEnabled() {
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "ZeusScreenSharePolicyTests.\(UUID().uuidString)")!
        #expect(ZeusScreenSharePolicy.showInScreenSharing(from: defaults) == false)
    }

    @Test func migratesLegacyHideKey() {
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "ZeusScreenSharePolicyTests2.\(UUID().uuidString)")!
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

    /// The "..." row. A click with the pointer left on the row must hide, then show,
    /// then hide again. The same mouse-up delivered twice flips once. A hover does not.
    /// The capture write still ends on the new value when the getter is stuck on hidden
    /// and when the pointer is on the window.
    @Test func aClickOnTheRowFlipsHideAndShowEvenWhenThePointerStays() {
        var shown = false
        var ledger = ScreenShareClickLedger()
        var remembered: Bool? = true
        var getter: Bool? = true

        func flip(pointerOnWindow: Bool) {
            shown = ScreenShareQuickToggleLogic.nextShown(shown)
            let update = CaptureExclusionUpdate(
                wantHidden: !shown,
                rememberedHidden: remembered,
                getterHidden: getter,
                pointerOnWindow: pointerOnWindow,
                force: false)
            let steps = update.steps
            #expect(steps?.last == !shown)
            remembered = steps?.last
            // The getter stays at hidden, which is the failure that used to skip the next hide.
            getter = true
        }

        #expect(ScreenShareQuickToggleLogic.title(shown: shown) == "Show Zeus in screen shares")
        #expect(ScreenShareQuickToggleLogic.storedValue(shown: shown) == "false")

        ledger.pointerUpOnRow()
        #expect(ledger.action() == false)
        flip(pointerOnWindow: true)
        #expect(shown)
        #expect(ScreenShareQuickToggleLogic.title(shown: shown) == "Hide Zeus from screen shares")
        #expect(ScreenShareQuickToggleLogic.storedValue(shown: shown) == "true")
        #expect(remembered == false)

        ledger.menuClosed()
        ledger.pointerUpOnRow()
        #expect(ledger.action() == false)
        flip(pointerOnWindow: true)
        #expect(!shown)
        #expect(ScreenShareQuickToggleLogic.title(shown: shown) == "Show Zeus in screen shares")
        #expect(remembered == true)

        ledger.menuClosed()
        ledger.pointerUpOnRow()
        flip(pointerOnWindow: true)
        #expect(shown)
        #expect(remembered == false)
        #expect(ledger.flips == 3)

        var hover = ScreenShareClickLedger()
        #expect(hover.flips == 0)
        // `#expect` captures the receiver of a bare call, so a mutating method
        // has to run first and the Bool is what the expectation sees.
        let firstHover = hover.action()
        let secondHover = hover.action()
        #expect(firstHover)
        #expect(secondHover)
        #expect(hover.flips == 2)

        var afterClose = ScreenShareClickLedger()
        afterClose.pointerUpOnRow()
        #expect(afterClose.action() == false)
        afterClose.menuClosed()
        let keyAfterClose = afterClose.action()
        #expect(keyAfterClose)
        #expect(afterClose.flips == 2)

        let repeatHide = CaptureExclusionUpdate(
            wantHidden: true, rememberedHidden: true, getterHidden: true, pointerOnWindow: false, force: false)
        #expect(repeatHide.steps == nil)
        let forced = CaptureExclusionUpdate(
            wantHidden: true, rememberedHidden: true, getterHidden: true, pointerOnWindow: true, force: true)
        #expect(forced.steps == [false, true])
        let firstWrite = CaptureExclusionUpdate(
            wantHidden: true, rememberedHidden: nil, getterHidden: false, pointerOnWindow: true, force: false)
        #expect(firstWrite.steps == [true])
        let awayFromThePointer = CaptureExclusionUpdate(
            wantHidden: false, rememberedHidden: true, getterHidden: true, pointerOnWindow: false, force: false)
        #expect(awayFromThePointer.steps == [false])
        let stuckGetter = CaptureExclusionUpdate(
            wantHidden: true, rememberedHidden: false, getterHidden: true, pointerOnWindow: false, force: false)
        #expect(stuckGetter.steps == [false, true])
        #expect(ScreenShareQuickToggleLogic.isToggleRow(ScreenShareQuickToggleLogic.rowMarker))
        #expect(!ScreenShareQuickToggleLogic.isToggleRow("always"))
    }
}

@Suite("Update badge logic")
struct UpdateBadgeLogicTests {
    @Test func versionCompareAndBadge() throws {
        let current = try #require(ZeusVersion(parsing: "3.0.1"))
        let newer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "3.1.0")))
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "UpdateBadgeLogicTests.\(UUID().uuidString)")!
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
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "UpdateBadgeLogicTests2.\(UUID().uuidString)")!
        let state = UpdateBadgeLogic.badgeState(current: current, offer: newer, feedEnabled: false, debugFake: nil, defaults: defaults)
        #expect(state == .hidden)
    }

    @Test func debugFakeShowsBadge() throws {
        let current = try #require(ZeusVersion(parsing: "1.0.0"))
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "UpdateBadgeLogicTests3.\(UUID().uuidString)")!
        let state = UpdateBadgeLogic.badgeState(current: current, offer: nil, feedEnabled: false, debugFake: "3.1.0", defaults: defaults)
        guard case .available(let offer, _) = state else {
            Issue.record("expected fake badge")
            return
        }
        #expect(offer.latest.displayShort == "3.1")
    }

    @Test func dismissalPerVersion() throws {
        let offer = UpdateOffer(latest: try #require(ZeusVersion(parsing: "3.1.0")))
        let defaults = UserDefaults(suiteName: NSTemporaryDirectory() + "UpdateBadgeLogicTests4.\(UUID().uuidString)")!
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
