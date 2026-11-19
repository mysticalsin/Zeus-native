import AppKit
import Foundation
import Observation
import Testing
import ZeusCore
@testable import Zeus

// MARK: Fakes

/// A driver that never touches Accessibility. Its windows go through the real, pure admission filter, so a
/// minimized window, Zeus's own window and a system window are refused the way the real driver refuses them.
@MainActor
private final class FakeTilingDriver: TilingWindowDriver {
    struct Candidate {
        var id: TileWindowID
        var facts: TileWindowFacts
        var onScreen: Bool
    }

    static let zeusPID: Int32 = 4242
    static let zeusBundle = "app.zeus.mac"

    var trusted = true
    /// Accessibility is revoked as this write is made: the write fails and trust is gone from then on.
    var revokeAtWrite: Int?
    var screens: [TileDisplay] = [FakeTilingDriver.mainDisplay()]
    var candidates: [Candidate] = []
    /// Apps whose windows the pass cannot read in time: left out of the listing, named in `unreadPIDs`.
    var unreadApps: Set<Int32> = []
    /// Windows whose own read timed out: the driver lists the rest of their app but names the app unread, so the missing
    /// window is unknown and not gone.
    var unreadWindows: Set<TileWindowID> = []
    var front = TileFrontmost.none
    var refuse: Set<TileWindowID> = []
    /// Windows the driver cannot give the keyboard to (minimized or sent to another Space since the last pass): the
    /// keyboard stays where it was.
    var focusRefused: Set<TileWindowID> = []
    /// Windows after which the keyboard is in an app tiling does not read.
    var focusLeavesTiling: Set<TileWindowID> = []

    private(set) var windowReads = 0
    private(set) var listed: Set<TileWindowID> = []
    private(set) var writes: [(window: TileWindowID, frame: TileRect)] = []
    private(set) var unlistedWrites: [TileWindowID] = []
    private(set) var focusCalls: [TileWindowID] = []

    static func mainDisplay(id: UInt32 = 1) -> TileDisplay {
        TileDisplay(id: id, appKitFrame: TileRect(x: 0, y: 0, width: 1440, height: 900),
                    appKitVisibleFrame: TileRect(x: 0, y: 0, width: 1440, height: 876),
                    engineFrame: TileRect(x: 0, y: 0, width: 1440, height: 900))
    }

    /// A second display to the right of the main one, in both coordinate spaces.
    static func rightDisplay(id: UInt32 = 2) -> TileDisplay {
        TileDisplay(id: id, appKitFrame: TileRect(x: 1440, y: 0, width: 1920, height: 1080),
                    appKitVisibleFrame: TileRect(x: 1440, y: 0, width: 1920, height: 1056),
                    engineFrame: TileRect(x: 1440, y: -180, width: 1920, height: 1080))
    }

    func add(_ id: TileWindowID, frame: TileRect = TileRect(x: 100, y: 100, width: 800, height: 600),
             bundle: String? = nil, minimized: Bool = false, fullScreen: Bool = false, onScreen: Bool = true) {
        let facts = TileWindowFacts(pid: id.pid, bundleID: bundle ?? "com.example.app\(id.pid)", isRegularApp: true,
                                    role: "AXWindow", subrole: "AXStandardWindow", isMinimized: minimized,
                                    isFullScreen: fullScreen, isSizeSettable: true, frame: frame)
        candidates.append(Candidate(id: id, facts: facts, onScreen: onScreen))
    }

    func remove(_ id: TileWindowID) { candidates.removeAll { $0.id == id } }

    func frame(of id: TileWindowID) -> TileRect? { candidates.first { $0.id == id }?.facts.frame }

    var isTrusted: Bool { trusted }
    func displays() -> [TileDisplay] { screens }
    private(set) var unreadPIDs: Set<Int32> = []

    func windows(config: TileConfig) -> [TileWindowRef] {
        windowReads += 1
        unreadPIDs = unreadApps.union(unreadWindows.map(\.pid))
        guard trusted else { return [] }
        let policy = TileAdmissionPolicy(config: config, zeusPID: Self.zeusPID, zeusBundleID: Self.zeusBundle)
        let readable = candidates.filter { !unreadApps.contains($0.facts.pid) && !unreadWindows.contains($0.id) }
        let onScreen = readable.compactMap { candidate -> TileOnScreenWindow? in
            guard candidate.onScreen, let frame = candidate.facts.frame else { return nil }
            return TileOnScreenWindow(pid: candidate.facts.pid, frame: frame, layer: 0, ownerName: nil)
        }
        let verdicts = TileAdmission.rejections(readable.map(\.facts), onScreen: onScreen, policy: policy)
        var out: [TileWindowRef] = []
        for (candidate, verdict) in zip(readable, verdicts) where verdict == nil {
            if let frame = candidate.facts.frame, let bundle = candidate.facts.bundleID {
                out.append(TileWindowRef(id: candidate.id, bundleID: bundle, frame: frame))
            }
        }
        listed = Set(out.map(\.id))
        return out
    }

    func setFrame(_ frame: TileRect, for window: TileWindowID) -> Bool {
        guard trusted, listed.contains(window) else {
            unlistedWrites.append(window)
            return false
        }
        if revokeAtWrite == writes.count + 1 {
            trusted = false
            return false
        }
        writes.append((window, frame))
        if refuse.contains(window) { return false }
        if let index = candidates.firstIndex(where: { $0.id == window }) { candidates[index].facts.frame = frame }
        return true
    }

    func focus(_ window: TileWindowID) {
        focusCalls.append(window)
        if focusRefused.contains(window) { return }
        front = focusLeavesTiling.contains(window) ? .none : TileFrontmost(focused: window, isFullScreen: false)
    }
    func frontmost() -> TileFrontmost { front }

    func writes(to id: TileWindowID) -> [TileRect] { writes.filter { $0.window == id }.map(\.frame) }
}

@MainActor
private final class FakeTilingKeys: TilingKeyControlling {
    var onAction: (TileAction, Int) -> Void = { _, _ in }
    var onUnavailable: () -> Void = {}
    private(set) var applies: [(enabled: Bool, paused: Bool, keymap: TileKeymap)] = []
    private(set) var stops = 0

    func apply(enabled: Bool, paused: Bool, keymap: TileKeymap) { applies.append((enabled, paused, keymap)) }
    func stop() { stops += 1 }
    var last: (enabled: Bool, paused: Bool, keymap: TileKeymap)? { applies.last }
}

@MainActor
private final class Pending {
    let delay: TimeInterval
    let work: () -> Void
    var cancelled = false
    init(delay: TimeInterval, work: @escaping () -> Void) { self.delay = delay; self.work = work }
}

/// One controller wired to fakes, a hand-run scheduler and private notification centres.
@MainActor
private final class Rig {
    let driver = FakeTilingDriver()
    let keys = FakeTilingKeys()
    var config = TileConfig(enabled: true)
    var focusBorder = true
    /// The note the key clash check gives for a base; nil means the base is free.
    var clashNote: (TileModifierBase) -> String? = { _ in nil }
    /// Whether VoiceOver is running. A test that makes the key clash depend on it also calls `changeVoiceOver`.
    var voiceOverOn = false
    private(set) var voiceOverWatchers: [TilingWork] = []
    private(set) var voiceOverCancels = 0
    var scheduled: [Pending] = []
    let appCenter = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    var rings: [TilingRingTarget?] = []
    var sheets: [[TileKeyRow]?] = []
    var settingWrites: [String] = []
    var trustWaiters: [() -> Void] = []
    var trustCancels = 0
    /// Each call to the controller's clock moves it on by this much.
    var clockStep = 0.0
    private var clock = 0.0
    private(set) var controller: TilingController!

    init() {
        controller = TilingController(services: TilingController.Services(
            driver: driver, keys: keys,
            readConfig: { [unowned self] in config },
            focusBorderOn: { [unowned self] in focusBorder },
            keyClash: { [unowned self] base, _ in clashNote(base) },
            watchVoiceOver: { [unowned self] changed in
                voiceOverWatchers.append(changed)
                return { [unowned self] in voiceOverCancels += 1 }
            },
            whenTrusted: { [unowned self] work in trustWaiters.append(work) },
            cancelTrustWait: { [unowned self] in trustCancels += 1 },
            schedule: { [unowned self] delay, work in
                let item = Pending(delay: delay, work: work)
                scheduled.append(item)
                return { item.cancelled = true }
            },
            appCenter: appCenter, workspaceCenter: workspaceCenter,
            showRing: { [unowned self] target in rings.append(target) },
            showSheet: { [unowned self] rows in sheets.append(rows) },
            writeSetting: { [unowned self] id, value in settingWrites.append("\(id)=\(value)") },
            now: { [unowned self] in defer { clock += clockStep }; return clock }))
    }

    var pending: [Pending] { scheduled.filter { !$0.cancelled } }

    /// VoiceOver started or stopped: tells every watcher the controller installed.
    func changeVoiceOver(to on: Bool) {
        voiceOverOn = on
        for watcher in voiceOverWatchers { watcher() }
    }

    /// Runs what is scheduled now, once. Work scheduled while it runs stays pending.
    func runOnce() {
        let batch = pending
        scheduled.removeAll { item in batch.contains { $0 === item } }
        for item in batch where !item.cancelled { item.work() }
    }

    /// Runs until nothing is pending (a few rounds at most).
    func settle() {
        for _ in 0..<12 where !pending.isEmpty { runOnce() }
    }

    func post(app name: Notification.Name) { appCenter.post(name: name, object: nil) }
    func post(workspace name: Notification.Name) { workspaceCenter.post(name: name, object: nil) }

    var lastRing: TilingRingTarget? { rings.last ?? nil }
}

private func id(_ n: Int, pid: Int32 = 900) -> TileWindowID { TileWindowID(pid: pid, index: n) }

/// What a pass gives two windows added in order on the main display: the second splits the first.
private let leftTile = TileRect(x: 8, y: 32, width: 708, height: 860)
private let rightTile = TileRect(x: 724, y: 32, width: 708, height: 860)
private let wholeTile = TileRect(x: 8, y: 32, width: 1424, height: 860)

// MARK: Suite

@MainActor
@Suite("Tiling controller with a fake driver", .serialized)
struct TilingControllerTests {
    // MARK: Off means nothing exists

    @Test func whileOffNothingExistsNoObserverNoTimerNoTapNoRingNoRead() {
        let rig = Rig()
        rig.config = TileConfig(enabled: false)
        rig.driver.add(id(1))
        rig.controller.start()
        #expect(!rig.controller.isRunning)
        #expect(rig.controller.observerCount == 0)
        #expect(rig.pending.isEmpty)
        #expect(rig.trustWaiters.isEmpty)
        #expect(rig.driver.windowReads == 0 && rig.driver.writes.isEmpty)
        #expect(rig.keys.last?.enabled != true, "the key layer is never asked to install a tap")
        #expect(rig.rings.allSatisfy { $0 == nil } && rig.sheets.allSatisfy { $0 == nil })
        #expect(rig.controller.phase == .off)
    }

    @Test func everyActionIsIgnoredWhileOff() {
        let rig = Rig()
        rig.config = TileConfig(enabled: false)
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        for action in TileAction.all { rig.controller.handle(action) }
        rig.settle()
        #expect(rig.driver.windowReads == 0 && rig.driver.writes.isEmpty && rig.driver.focusCalls.isEmpty)
        #expect(rig.sheets.isEmpty)
    }

    // MARK: Turning on

    @Test func turningOnTilesTheWindowsOfTheCurrentSpaceAndInstallsTheObservers() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.controller.start()
        #expect(rig.controller.isRunning)
        #expect(rig.controller.observerCount == 7)
        #expect(rig.keys.last?.enabled == true && rig.keys.last?.paused == false)
        #expect(rig.keys.last?.keymap == TileKeymap.defaults(base: TileConfig.defaults.base))
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) == leftTile)
        #expect(rig.driver.frame(of: id(2)) == rightTile)
        #expect(rig.controller.phase == .running)
        #expect(rig.controller.picture.count == 1)
        #expect(rig.controller.picture[0].tiles.map(\.window) == [id(1), id(2)])
    }

    @Test func startingTwiceChangesNothing() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.controller.start()
        rig.settle()
        let reads = rig.driver.windowReads
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.observerCount == 7, "no second set of observers")
        #expect(rig.driver.writes.count == 1, "a window already in place is not written again")
        #expect(rig.driver.windowReads >= reads)
    }

    @Test func eachDisplayGetsItsOwnTreeAndWindowsStayOnTheirDisplay() {
        let rig = Rig()
        let right = FakeTilingDriver.rightDisplay()
        rig.driver.screens = [FakeTilingDriver.mainDisplay(), right]
        rig.driver.add(id(1), frame: TileRect(x: 100, y: 100, width: 800, height: 600))
        rig.driver.add(id(2), frame: TileRect(x: 1600, y: 100, width: 800, height: 600))
        rig.controller.start()
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
        let usable = TileFrames.usableRect(display: right.visibleFrame, outerGap: 8)
        #expect(rig.driver.frame(of: id(2)) == usable)
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)])
        #expect(rig.controller.layoutWindows(on: 2) == [id(2)])
        #expect(rig.controller.picture.count == 2)
    }

    // MARK: Fail closed

    @Test func accessibilityDeniedStartsNothingAndWaitsWithoutAPrompt() {
        let rig = Rig()
        rig.driver.trusted = false
        rig.driver.add(id(1))
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.phase == .needsAccessibility)
        #expect(!rig.controller.accessibilityOn)
        #expect(rig.controller.observerCount == 0, "no observer before Accessibility is on")
        #expect(rig.driver.windowReads == 0 && rig.driver.writes.isEmpty)
        #expect(rig.trustWaiters.count == 1, "it waits through the no-prompt gate")
        #expect(rig.lastRing == nil)
        // The owner turns Accessibility on in System Settings: the gate runs the waiting work.
        rig.driver.trusted = true
        rig.trustWaiters.first?()
        rig.settle()
        #expect(rig.controller.accessibilityOn && rig.controller.phase == .running)
        #expect(rig.controller.observerCount == 7)
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
    }

    @Test func accessibilityRevokedWhileRunningStopsEveryWrite() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.controller.start()
        rig.settle()
        let written = rig.driver.writes.count
        rig.driver.trusted = false
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.settle()
        #expect(rig.driver.writes.count == written)
        #expect(rig.controller.phase == .needsAccessibility)
        #expect(rig.lastRing == nil)
        #expect(!rig.trustWaiters.isEmpty, "it waits for the permission to come back")
    }

    @Test func accessibilityRevokedInTheMiddleOfAPassFloatsNoWindowAndTilingResumesWhenItReturns() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.driver.revokeAtWrite = 2
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.phase == .needsAccessibility)
        #expect(rig.controller.floatingWindows.isEmpty, "a write that failed because access went away says nothing about the window")
        // The permission comes back: the window the revoke cut off is tiled again, not left floating for the session.
        rig.driver.trusted = true
        rig.driver.revokeAtWrite = nil
        rig.trustWaiters.last?()
        rig.settle()
        #expect(rig.controller.floatingWindows.isEmpty)
        #expect(rig.driver.frame(of: id(1)) == leftTile)
        #expect(rig.driver.frame(of: id(2)) == rightTile)
    }

    @Test func aMoveThatDoesNotLandFloatsTheWindowForTheSessionAndTheRestLayOutAgain() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.driver.refuse = [id(2)]
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.floatingWindows == [id(2)])
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)], "the tree is rebuilt without the window that would not move")
        #expect(rig.driver.frame(of: id(1)) == wholeTile, "its neighbour takes the whole area")
        // No retry loop: a later pass never writes to it again.
        let attempts = rig.driver.writes(to: id(2)).count
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.settle()
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.driver.writes(to: id(2)).count == attempts)
        #expect(attempts == 1)
    }

    @Test func onePassHasOneTimeBudgetAcrossEveryDisplay() {
        let rig = Rig()
        rig.driver.screens = [FakeTilingDriver.mainDisplay(), FakeTilingDriver.rightDisplay()]
        rig.clockStep = 0.6
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.driver.add(id(3), frame: TileRect(x: 1600, y: 100, width: 800, height: 600))
        rig.driver.add(id(4), frame: TileRect(x: 1700, y: 120, width: 800, height: 600))
        rig.controller.start()
        rig.runOnce()
        #expect(rig.driver.writes.map(\.window) == [id(1), id(2)],
                "the second display does not get a fresh budget: the pass defers its moves")
        #expect(rig.controller.floatingWindows.isEmpty, "deferred is not floated")
        #expect(rig.pending.count == 1, "a follow-up pass takes the rest")
        rig.clockStep = 0
        rig.settle()
        #expect(Set(rig.driver.writes.map(\.window)) == [id(1), id(2), id(3), id(4)])
    }

    @Test func windowsTheBudgetDeferredAreNotFloatedAndALaterPassTakesThem() {
        let rig = Rig()
        rig.clockStep = 0.7
        for n in 1...3 { rig.driver.add(id(n)) }
        rig.controller.start()
        rig.runOnce()
        #expect(rig.driver.writes.count == 1, "the pass stops starting writes once its time is up")
        #expect(rig.controller.floatingWindows.isEmpty, "a deferred window is not floated")
        #expect(rig.pending.count == 1, "one follow-up pass is queued")
        rig.clockStep = 0
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) != nil && rig.controller.layoutWindows(on: 1).count == 3)
        let outside = rig.driver.candidates.filter { candidate in
            guard let frame = candidate.facts.frame else { return true }
            return !(frame.minX >= 8 && frame.maxX <= 1432 && frame.minY >= 32 && frame.maxY <= 892)
        }
        #expect(outside.isEmpty, "every window ends up inside the usable area")
    }

    @Test func aWindowTheDriverRefusesToListIsNeverWritten() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2), minimized: true)
        rig.driver.add(id(3, pid: FakeTilingDriver.zeusPID))
        rig.driver.add(id(4, pid: 77), bundle: "com.apple.dock")
        rig.driver.add(id(5, pid: 78), onScreen: false)
        rig.controller.start()
        rig.settle()
        #expect(rig.driver.writes.map(\.window) == [id(1)], "only the one admitted window is written")
        #expect(rig.driver.unlistedWrites.isEmpty)
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)])
        #expect(rig.driver.frame(of: id(2)) == TileRect(x: 100, y: 100, width: 800, height: 600), "a minimized window is left where it is")
    }

    @Test func aWindowTooSmallExcludedOrOnNoDisplayIsLeftAloneEvenIfTheDriverListsIt() {
        let rig = Rig()
        rig.config = TileConfig(enabled: true, excludedBundleIDs: ["com.example.skip"])
        rig.driver.add(id(1))
        rig.driver.add(id(2, pid: 11), bundle: "com.example.skip")
        rig.driver.add(id(3, pid: 12), frame: TileRect(x: 5000, y: 5000, width: 800, height: 600))
        rig.controller.start()
        rig.settle()
        #expect(rig.driver.writes.map(\.window) == [id(1)])
    }

    @Test func aWindowMissingFromACompleteListingLeavesTheLayoutAndItsSiblingGrows() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.controller.start()
        rig.settle()
        rig.driver.remove(id(2))
        rig.post(workspace: NSWorkspace.didTerminateApplicationNotification)
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)])
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
    }

    @Test func aWindowOfAnAppThatDidNotAnswerKeepsItsSlotAndIsNotWritten() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2, pid: 901))
        rig.controller.start()
        rig.settle()
        let writes = rig.driver.writes.count
        rig.driver.unreadApps = [901]
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1) == [id(1), id(2, pid: 901)], "an app that did not answer is unknown, not gone")
        #expect(rig.driver.writes.count == writes, "nothing is written to the slot of the missing window or around it")
        #expect(rig.driver.frame(of: id(1)) == leftTile)
    }

    @Test func aWindowWhoseOwnReadTimedOutKeepsItsSlotWhileItsSiblingsAreListed() {
        let rig = Rig()
        rig.driver.add(id(1, pid: 901))
        rig.driver.add(id(2, pid: 901))
        rig.driver.add(id(3, pid: 902))
        rig.controller.start()
        rig.settle()
        #expect(Set(rig.controller.layoutWindows(on: 1)) == [id(1, pid: 901), id(2, pid: 901), id(3, pid: 902)])
        let writes = rig.driver.writes.count
        rig.driver.unreadWindows = [id(2, pid: 901)]
        rig.controller.handle(.retile)
        rig.settle()
        #expect(Set(rig.controller.layoutWindows(on: 1)) == [id(1, pid: 901), id(2, pid: 901), id(3, pid: 902)],
                "the slow window is unknown, not closed: its sibling does not grow over it")
        #expect(rig.driver.writes.count == writes, "nothing is written around the slow window")
        rig.driver.remove(id(2, pid: 901))
        rig.driver.unreadWindows = []
        rig.controller.handle(.retile)
        rig.settle()
        #expect(Set(rig.controller.layoutWindows(on: 1)) == [id(1, pid: 901), id(3, pid: 902)], "once the app answers, the closed window's slot goes")
    }

    @Test func oneSlowAppDoesNotPinTheSlotsOfWindowsThatClosedInOtherApps() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2, pid: 901))
        rig.driver.add(id(3, pid: 902))
        rig.controller.start()
        rig.settle()
        #expect(Set(rig.controller.layoutWindows(on: 1)) == [id(1), id(2, pid: 901), id(3, pid: 902)])
        rig.driver.remove(id(3, pid: 902))
        rig.driver.unreadApps = [901]
        rig.controller.handle(.retile)
        rig.settle()
        #expect(Set(rig.controller.layoutWindows(on: 1)) == [id(1), id(2, pid: 901)],
                "the closed window of an app that answered is gone; the slow app's window keeps its slot")
        #expect(rig.controller.preTilingFrame(of: id(2, pid: 901)) != nil, "the slow app's undo memory stays")
        #expect(rig.controller.preTilingFrame(of: id(3, pid: 902)) == nil, "the closed window's undo memory is dropped in the same pass")
        rig.driver.remove(id(2, pid: 901))
        rig.driver.unreadApps = []
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)], "once the app answers, the slot of its closed window goes")
        #expect(rig.controller.preTilingFrame(of: id(2, pid: 901)) == nil)
    }

    @Test func aFullScreenAppInFrontPausesEveryWriteUntilItEnds() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.controller.start()
        rig.settle()
        let writes = rig.driver.writes.count
        rig.driver.front = TileFrontmost(focused: nil, isFullScreen: true)
        rig.driver.add(id(3, pid: 901))
        rig.post(workspace: NSWorkspace.activeSpaceDidChangeNotification)
        rig.settle()
        #expect(rig.driver.writes.count == writes)
        #expect(rig.controller.layoutWindows(on: 1) == [id(1), id(2)], "the layout is kept, not rebuilt from a Space with one window")
        #expect(rig.lastRing == nil)
        rig.driver.front = .none
        rig.post(workspace: NSWorkspace.activeSpaceDidChangeNotification)
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1).contains(id(3, pid: 901)))
    }

    // MARK: Key clash

    private static let talkNote = "Control-Option is also your Talk to Zeus key."

    @Test func aPairAnotherZeusKeyHoldsIsRefusedAndNothingExists() {
        let rig = Rig()
        rig.config.base = .controlOption
        rig.clashNote = { $0 == .controlOption ? Self.talkNote : nil }
        rig.driver.add(id(1))
        rig.controller.start()
        #expect(!rig.controller.isRunning)
        #expect(rig.controller.phase == .keyClash)
        #expect(rig.controller.keyClashNote == Self.talkNote)
        #expect(rig.controller.observerCount == 0 && rig.pending.isEmpty && rig.trustWaiters.isEmpty)
        #expect(rig.keys.last?.enabled != true, "the tap is never installed over another Zeus key")
        #expect(rig.driver.windowReads == 0 && rig.driver.writes.isEmpty)
        rig.controller.handle(.retile)
        #expect(rig.driver.windowReads == 0, "a chord does nothing while refused")
    }

    @Test func choosingAnotherPairStartsTilingAndClearsTheNote() {
        let rig = Rig()
        rig.config.base = .controlOption
        rig.clashNote = { $0 == .controlOption ? Self.talkNote : nil }
        rig.driver.add(id(1))
        rig.controller.start()
        rig.config.base = .optionCommand
        rig.controller.start()
        #expect(rig.controller.isRunning && rig.controller.phase == .running)
        #expect(rig.controller.keyClashNote == nil)
        #expect(rig.keys.last?.enabled == true)
        #expect(rig.keys.last?.keymap == TileKeymap.defaults(base: .optionCommand))
    }

    @Test func aClashThatAppearsWhileRunningRemovesTheTapAndTheObservers() {
        let rig = Rig()
        twoWindows(rig)
        #expect(rig.controller.isRunning && rig.keys.last?.enabled == true)
        rig.clashNote = { _ in Self.talkNote }
        rig.controller.start()
        #expect(!rig.controller.isRunning && rig.controller.phase == .keyClash)
        #expect(rig.controller.observerCount == 0 && rig.pending.isEmpty)
        #expect(rig.keys.last?.enabled == false)
        #expect(rig.driver.frame(of: id(1)) == leftTile, "windows stay where they are")
        rig.clashNote = { _ in nil }
        rig.controller.start()
        #expect(rig.controller.isRunning && rig.controller.phase == .running && rig.controller.keyClashNote == nil)
    }

    @Test func turningTheSwitchOffClearsTheNote() {
        let rig = Rig()
        rig.clashNote = { _ in Self.talkNote }
        rig.controller.start()
        #expect(rig.controller.phase == .keyClash)
        rig.config = TileConfig(enabled: false)
        rig.controller.start()
        #expect(rig.controller.phase == .off && rig.controller.keyClashNote == nil)
    }

    private static let voiceOverNote = "Control-Option is the VoiceOver key pair and VoiceOver is running."

    @Test func voiceOverStartingWhileTilingRunsRemovesTheTapAndStoppingItBringsTilingBack() {
        let rig = Rig()
        rig.config.base = .controlOption
        rig.clashNote = { [unowned rig] base in rig.voiceOverOn && base == .controlOption ? Self.voiceOverNote : nil }
        twoWindows(rig)
        #expect(rig.controller.isRunning && rig.keys.last?.enabled == true)
        rig.changeVoiceOver(to: true)
        #expect(!rig.controller.isRunning && rig.controller.phase == .keyClash)
        #expect(rig.controller.keyClashNote == Self.voiceOverNote)
        #expect(rig.keys.last?.enabled == false, "the tap is gone the moment VoiceOver takes the pair")
        #expect(rig.controller.observerCount == 0 && rig.pending.isEmpty)
        rig.changeVoiceOver(to: false)
        #expect(rig.controller.isRunning && rig.controller.phase == .running && rig.controller.keyClashNote == nil)
        #expect(rig.keys.last?.enabled == true)
    }

    @Test func theVoiceOverWatchIsInstalledOnceWhileTheSwitchIsOnAndKeptWhileAClashHoldsTiling() {
        let rig = Rig()
        rig.clashNote = { [unowned rig] _ in rig.voiceOverOn ? Self.voiceOverNote : nil }
        rig.controller.start()
        rig.controller.start()
        #expect(rig.voiceOverWatchers.count == 1, "start() runs on every settings write and must not stack watches")
        rig.changeVoiceOver(to: true)
        #expect(rig.controller.phase == .keyClash)
        #expect(rig.voiceOverCancels == 0, "the watch stays so that VoiceOver going away can clear the clash")
        rig.controller.start()
        #expect(rig.voiceOverWatchers.count == 1)
    }

    @Test func turningTheSwitchOffRemovesTheVoiceOverWatchAndANewOnInstallsOneAgain() {
        let rig = Rig()
        rig.config = TileConfig(enabled: false)
        rig.controller.start()
        #expect(rig.voiceOverWatchers.isEmpty, "nothing is watched while tiling is off")
        rig.config = TileConfig(enabled: true)
        rig.controller.start()
        #expect(rig.voiceOverWatchers.count == 1 && rig.voiceOverCancels == 0)
        rig.config = TileConfig(enabled: false)
        rig.controller.start()
        #expect(rig.voiceOverCancels == 1)
        rig.config = TileConfig(enabled: true)
        rig.controller.start()
        #expect(rig.voiceOverWatchers.count == 2)
    }

    // MARK: Actions that move nothing

    @Test func resumingFromPauseWorksOverAFullScreenApp() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.togglePause)
        #expect(rig.controller.phase == .paused)
        rig.driver.front = TileFrontmost(focused: nil, isFullScreen: true)
        rig.controller.handle(.togglePause)
        #expect(rig.controller.phase == .running, "the resume chord is not swallowed by the full-screen guard")
        #expect(rig.keys.last?.paused == false)
    }

    @Test func theKeySheetShowsOverAFullScreenApp() {
        let rig = Rig()
        twoWindows(rig)
        rig.driver.front = TileFrontmost(focused: nil, isFullScreen: true)
        rig.controller.handle(.showKeys)
        #expect(rig.sheets.last! != nil)
        let writes = rig.driver.writes.count
        rig.controller.handle(.retile)
        #expect(rig.driver.writes.count == writes, "a window action still waits for the full-screen app to end")
    }

    // MARK: A front app that is not tiled

    @Test func actionsOnTheFocusedWindowDoNothingWhenTheFrontAppIsNotTiled() {
        let rig = Rig()
        twoWindows(rig)
        let before = rig.controller.layoutWindows(on: 1)
        let writes = rig.driver.writes.count
        rig.driver.front = .none
        for action in [TileAction.swap(.right), .flipSplit, .toggleFloat, .nudge(.right)] { rig.controller.handle(action) }
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1) == before)
        #expect(rig.controller.floatingWindows.isEmpty)
        #expect(rig.driver.writes.count == writes, "the hidden window was not touched")
        rig.controller.handle(.focus(.right))
        #expect(rig.driver.focusCalls == [id(2)], "a focus key still brings a tiled window forward")
    }

    // MARK: Settings that change while running

    @Test func turningTheRingOffWhileRunningOrdersItOutAndTurningItOnBringsItBack() {
        let rig = Rig()
        twoWindows(rig)
        #expect(rig.lastRing?.frame == leftTile)
        rig.focusBorder = false
        rig.controller.start()
        #expect(rig.lastRing == nil)
        rig.focusBorder = true
        rig.controller.start()
        #expect(rig.lastRing?.frame == leftTile)
    }

    @Test func accessibilityRevokedThenASettingChangeWaitsAndComesBackWhenItIsGranted() {
        let rig = Rig()
        twoWindows(rig)
        rig.driver.trusted = false
        rig.config = TileConfig(enabled: true, innerGap: 12)
        rig.controller.start()
        #expect(rig.controller.phase == .needsAccessibility)
        #expect(rig.controller.observerCount == 0, "nothing observes while Accessibility is off")
        #expect(!rig.trustWaiters.isEmpty)
        rig.driver.trusted = true
        rig.trustWaiters.last?()
        rig.settle()
        #expect(rig.controller.phase == .running)
        #expect(rig.controller.observerCount == 7)
    }

    @Test func aSettingsWriteThatChangesNothingStillNoticesRevokedAccessibility() {
        let rig = Rig()
        twoWindows(rig)
        #expect(rig.controller.observerCount == 7)
        let applies = rig.keys.applies.count
        rig.driver.trusted = false
        rig.controller.start()
        #expect(rig.controller.observerCount == 0, "nothing observes once the permission is gone")
        #expect(!rig.controller.accessibilityOn && rig.controller.phase == .needsAccessibility)
        #expect(rig.keys.applies.count > applies && rig.keys.last?.enabled == true, "the key layer is told, and drops its tap itself")
        #expect(!rig.trustWaiters.isEmpty, "it waits for the permission to come back")
        #expect(rig.lastRing == nil)
    }

    @Test func aPausedControllerNoticesRevokedAccessibilityOnAnUnchangedSettingsWriteToo() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.togglePause()
        #expect(rig.controller.isPaused && rig.controller.observerCount == 7)
        let applies = rig.keys.applies.count
        rig.driver.trusted = false
        rig.controller.start()
        #expect(rig.controller.observerCount == 0)
        #expect(!rig.controller.accessibilityOn)
        #expect(rig.keys.applies.count > applies && rig.keys.last?.paused == true, "the pause is kept")
        #expect(!rig.trustWaiters.isEmpty)
        rig.driver.trusted = true
        rig.trustWaiters.last?()
        rig.settle()
        #expect(rig.controller.accessibilityOn && rig.controller.isPaused && rig.controller.observerCount == 7)
    }

    @Test func aWindowThatIsGoneLeavesTheUndoMemory() {
        let rig = Rig()
        twoWindows(rig)
        #expect(rig.controller.preTilingFrame(of: id(2)) != nil)
        rig.driver.remove(id(2))
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.controller.preTilingFrame(of: id(2)) == nil)
        #expect(rig.controller.preTilingFrame(of: id(1)) != nil)
    }

    private final class Flag: @unchecked Sendable { var raised = false }

    @Test func aSettingsWriteThatChangesNothingDoesNotNotifyThePage() {
        let rig = Rig()
        twoWindows(rig)
        let flag = Flag()
        withObservationTracking {
            _ = rig.controller.config
            _ = rig.controller.phase
            _ = rig.controller.accessibilityOn
            _ = rig.controller.keyRows
            _ = rig.controller.keyClashNote
        } onChange: { flag.raised = true }
        rig.controller.start()
        rig.controller.refresh()
        #expect(!flag.raised)
    }

    // MARK: Generation counter

    @Test func aDisplayChangeDropsStaleWorkAndRebuildsOnce() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.controller.start()
        let stale = rig.pending
        #expect(!stale.isEmpty)
        let before = rig.controller.generationValue
        rig.post(app: NSApplication.didChangeScreenParametersNotification)
        #expect(rig.controller.generationValue > before)
        for item in stale { item.work() }
        #expect(rig.driver.writes.isEmpty && rig.driver.windowReads == 0, "work scheduled before the change does nothing")
        #expect(rig.pending.count == 1, "one fresh pass is queued, not one per notification")
        rig.post(app: NSApplication.didChangeScreenParametersNotification)
        #expect(rig.pending.count == 1)
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
    }

    @Test func aDisplayThatIsGoneTakesItsTreeAndTheWindowsMoveToTheDisplayThatRemains() {
        let rig = Rig()
        rig.driver.screens = [FakeTilingDriver.mainDisplay(), FakeTilingDriver.rightDisplay()]
        rig.driver.add(id(1))
        rig.driver.add(id(2), frame: TileRect(x: 1600, y: 100, width: 800, height: 600))
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 2) == [id(2)])
        rig.driver.screens = [FakeTilingDriver.mainDisplay()]
        rig.driver.candidates[1].facts.frame = TileRect(x: 300, y: 200, width: 800, height: 600)
        rig.post(app: NSApplication.didChangeScreenParametersNotification)
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 2).isEmpty)
        #expect(rig.controller.layoutWindows(on: 1) == [id(1), id(2)])
        #expect(rig.controller.picture.count == 1)
    }

    @Test func aSpaceChangeCancelsStaleWorkToo() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.controller.start()
        let stale = rig.pending
        let before = rig.controller.generationValue
        rig.post(workspace: NSWorkspace.activeSpaceDidChangeNotification)
        #expect(rig.controller.generationValue > before)
        for item in stale { item.work() }
        #expect(rig.driver.writes.isEmpty)
        rig.settle()
        #expect(rig.driver.writes.count == 1)
    }

    @Test func sleepCancelsPendingWorkAndWakeRebuildsOnce() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.controller.start()
        rig.settle()
        rig.post(workspace: NSWorkspace.activeSpaceDidChangeNotification)
        #expect(rig.pending.count == 1)
        rig.post(workspace: NSWorkspace.willSleepNotification)
        #expect(rig.pending.isEmpty, "nothing runs while the Mac sleeps")
        let writes = rig.driver.writes.count
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.settle()
        #expect(rig.driver.writes.count == writes)
        rig.driver.candidates[0].facts.frame = TileRect(x: 50, y: 50, width: 800, height: 600)
        rig.post(workspace: NSWorkspace.didWakeNotification)
        #expect(rig.pending.count == 1)
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
    }

    @Test func aBurstOfApplicationEventsQueuesOnePass() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.controller.start()
        rig.settle()
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            rig.post(workspace: name)
        }
        #expect(rig.pending.count == 1)
    }

    // MARK: Keys

    private func twoWindows(_ rig: Rig, focused: TileWindowID = id(1)) {
        rig.driver.add(id(1))
        rig.driver.add(id(2))
        rig.driver.front = TileFrontmost(focused: focused, isFullScreen: false)
        rig.controller.start()
        rig.settle()
    }

    @Test func theKeyLayerHandsActionsToTheController() {
        let rig = Rig()
        twoWindows(rig)
        rig.keys.onAction(.focus(.right), 1)
        #expect(rig.driver.focusCalls == [id(2)])
    }

    @Test func aRunOfNudgesIsOneResizePassWithTheSameResultAsOneAtATime() {
        let merged = Rig()
        twoWindows(merged)
        let before = merged.driver.writes.count
        merged.keys.onAction(.nudge(.right), 3)
        let single = Rig()
        twoWindows(single)
        for _ in 0..<3 { single.controller.handle(.nudge(.right)) }
        #expect(merged.driver.writes(to: id(1)).last == single.driver.writes(to: id(1)).last, "the same split")
        #expect(merged.driver.writes(to: id(2)).last == single.driver.writes(to: id(2)).last)
        #expect(merged.driver.writes.count - before == 2, "one pass over two windows, not three")
        #expect(single.driver.writes.count - before == 6)
    }

    @Test func aFocusKeyFocusesTheNeighbourThroughTheDriverAndMovesTheRing() {
        let rig = Rig()
        twoWindows(rig)
        #expect(rig.lastRing?.frame == leftTile, "the ring starts on the focused window")
        rig.controller.handle(.focus(.right))
        #expect(rig.driver.focusCalls == [id(2)])
        #expect(rig.lastRing?.frame == rightTile)
        #expect(rig.driver.writes.count == 2, "moving focus writes no frame")
    }

    @Test func aFocusTheWindowCannotTakeLeavesTheRingWhereTheKeyboardIs() {
        let rig = Rig()
        twoWindows(rig)
        // The neighbour was minimized after the last pass: the listing is stale, the driver cannot focus it.
        rig.driver.focusRefused = [id(2)]
        rig.controller.handle(.focus(.right))
        #expect(rig.driver.focusCalls == [id(2)])
        #expect(rig.lastRing?.frame == leftTile, "the first window still has the keyboard, so it keeps the ring")
        // The next pass drops the dead slot.
        rig.driver.remove(id(2))
        rig.settle()
        #expect(rig.controller.layoutWindows(on: 1) == [id(1)])
    }

    @Test func aFocusAfterWhichTheKeyboardIsInAnUntiledAppDrawsNoRing() {
        let rig = Rig()
        twoWindows(rig)
        rig.driver.focusLeavesTiling = [id(2)]
        rig.controller.handle(.focus(.right))
        #expect(rig.lastRing == nil, "the ring marks only a window that has the keyboard")
        // The keys that act on the focused window wait until a tiled window has the keyboard.
        let before = rig.controller.layoutWindows(on: 1)
        rig.controller.handle(.swap(.left))
        #expect(rig.controller.layoutWindows(on: 1) == before)
    }

    @Test func aFocusKeyWithNothingThatWayDoesNothing() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.focus(.left))
        #expect(rig.driver.focusCalls.isEmpty)
        #expect(rig.lastRing?.frame == leftTile)
    }

    @Test func aSwapKeyExchangesTheFramesAndKeepsFocusOnTheMovedWindow() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.swap(.right))
        rig.settle()
        #expect(rig.driver.frame(of: id(1)) == rightTile)
        #expect(rig.driver.frame(of: id(2)) == leftTile)
        #expect(rig.lastRing?.frame == rightTile, "the ring follows the window that moved")
    }

    @Test func aFlipKeyStacksTheTwoWindows() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.flipSplit)
        rig.settle()
        let top = rig.driver.frame(of: id(1))!, bottom = rig.driver.frame(of: id(2))!
        #expect(top.width == wholeTile.width && bottom.width == wholeTile.width)
        #expect(top.maxY < bottom.minY)
    }

    @Test func aNudgeKeyMovesTheSplit() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.nudge(.right))
        rig.settle()
        #expect(rig.driver.frame(of: id(1))!.width > leftTile.width)
        #expect(rig.driver.frame(of: id(2))!.width < rightTile.width)
    }

    @Test func theFloatKeyReleasesTheFocusedWindowAndTakesItBack() {
        let rig = Rig()
        twoWindows(rig, focused: id(2))
        rig.controller.handle(.toggleFloat)
        rig.settle()
        #expect(rig.controller.floatingWindows == [id(2)])
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
        #expect(rig.driver.frame(of: id(2)) == rightTile, "the floated window stays where it was")
        #expect(rig.lastRing == nil, "a floating window gets no ring")
        rig.controller.handle(.toggleFloat)
        rig.settle()
        #expect(rig.controller.floatingWindows.isEmpty)
        #expect(rig.controller.layoutWindows(on: 1).sorted() == [id(1), id(2)])
        #expect(rig.driver.frame(of: id(1)) == leftTile && rig.driver.frame(of: id(2)) == rightTile)
    }

    @Test func retileLaysADraggedWindowBackIntoItsSlot() {
        let rig = Rig()
        twoWindows(rig)
        rig.driver.candidates[1].facts.frame = TileRect(x: 400, y: 300, width: 500, height: 400)
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.driver.frame(of: id(2)) == rightTile)
    }

    @Test func pausingStopsWritingAndResumingLaysEverythingOutAgain() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.togglePause)
        #expect(rig.controller.phase == .paused)
        #expect(rig.keys.last?.paused == true, "the tap now takes only the resume chord")
        rig.driver.candidates[1].facts.frame = TileRect(x: 400, y: 300, width: 500, height: 400)
        let writes = rig.driver.writes.count
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.controller.handle(.retile)
        rig.controller.handle(.focus(.right))
        rig.settle()
        #expect(rig.driver.writes.count == writes && rig.driver.focusCalls.isEmpty, "a pause leaves windows where they are")
        #expect(rig.lastRing == nil)
        rig.controller.handle(.togglePause)
        rig.settle()
        #expect(rig.controller.phase == .running)
        #expect(rig.keys.last?.paused == false)
        #expect(rig.driver.frame(of: id(2)) == rightTile)
    }

    @Test func theTapGivingUpPausesTilingAndTheSectionSaysSo() {
        let rig = Rig()
        twoWindows(rig)
        rig.keys.onUnavailable()
        #expect(rig.controller.phase == .keysUnavailable)
        #expect(rig.controller.isPaused)
        let writes = rig.driver.writes.count
        rig.driver.candidates[1].facts.frame = TileRect(x: 400, y: 300, width: 500, height: 400)
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.settle()
        #expect(rig.driver.writes.count == writes)
        // The pause control cannot bring back keys that are not there.
        rig.controller.togglePause()
        #expect(rig.controller.phase == .keysUnavailable)
    }

    @Test func showKeysShowsTheSheetAndATimerOrTheNextKeyHidesIt() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.showKeys)
        #expect(rig.sheets.last??.count == 8)
        #expect(rig.sheets.last??.first?.title == "Move focus")
        #expect(rig.pending.contains { $0.delay >= 3 }, "a short timer is set")
        rig.runOnce()
        #expect(rig.sheets.last! == nil)
        // The next key also hides it.
        rig.controller.handle(.showKeys)
        #expect(rig.sheets.last! != nil)
        rig.controller.handle(.focus(.right))
        #expect(rig.sheets.last! == nil)
        #expect(!rig.pending.contains { $0.delay >= 3 }, "the timer of a hidden sheet is cancelled")
    }

    // MARK: Ring

    @Test func theRingFollowsTheFocusedWindowOnlyWhileTheSettingIsOn() {
        let rig = Rig()
        rig.focusBorder = false
        twoWindows(rig)
        #expect(rig.rings.allSatisfy { $0 == nil })
        rig.focusBorder = true
        rig.controller.handle(.retile)
        rig.settle()
        #expect(rig.lastRing?.frame == leftTile)
        #expect(rig.lastRing?.display.id == 1)
    }

    @Test func aFocusedWindowThatIsNotTiledGetsNoRing() {
        let rig = Rig()
        rig.driver.add(id(1))
        rig.driver.add(id(2, pid: 11), bundle: "com.example.excluded")
        rig.config = TileConfig(enabled: true, excludedBundleIDs: ["com.example.excluded"])
        rig.driver.front = TileFrontmost(focused: id(2, pid: 11), isFullScreen: false)
        rig.controller.start()
        rig.settle()
        #expect(rig.lastRing == nil)
    }

    // MARK: Turning off

    @Test func turningOffRemovesEveryObserverTimerTapAndOverlayAndLeavesWindowsWhereTheyAre() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.handle(.showKeys)
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        #expect(!rig.pending.isEmpty)
        let writes = rig.driver.writes.count
        rig.config = TileConfig(enabled: false)
        rig.controller.start()
        #expect(!rig.controller.isRunning)
        #expect(rig.controller.observerCount == 0)
        #expect(rig.pending.isEmpty, "every pending item is cancelled")
        #expect(rig.keys.last?.enabled == false)
        #expect(rig.trustCancels >= 1)
        #expect(rig.lastRing == nil && rig.sheets.last! == nil)
        #expect(rig.controller.phase == .off)
        #expect(rig.driver.writes.count == writes, "turning off never moves a window")
        rig.post(workspace: NSWorkspace.didActivateApplicationNotification)
        rig.post(app: NSApplication.didChangeScreenParametersNotification)
        #expect(rig.pending.isEmpty, "nothing observes the system any more")
        #expect(rig.driver.frame(of: id(1)) == leftTile && rig.driver.frame(of: id(2)) == rightTile)
    }

    @Test func stopIsTheSameAsTurningOff() {
        let rig = Rig()
        twoWindows(rig)
        rig.controller.stop()
        #expect(!rig.controller.isRunning && rig.controller.observerCount == 0 && rig.pending.isEmpty)
        #expect(rig.keys.last?.enabled == false)
        rig.controller.stop()
        #expect(rig.controller.observerCount == 0, "stopping twice is harmless")
    }

    @Test func theFramesBeforeTilingAreRememberedAndNeverRestored() {
        let rig = Rig()
        let original = TileRect(x: 120, y: 90, width: 640, height: 480)
        rig.driver.add(id(1), frame: original)
        rig.controller.start()
        rig.settle()
        #expect(rig.controller.preTilingFrame(of: id(1)) == original)
        rig.controller.stop()
        let writes = rig.driver.writes.count
        #expect(rig.driver.writes.count == writes)
        #expect(rig.controller.preTilingFrame(of: id(1)) == original, "kept for a later undo, not applied in this slice")
        #expect(rig.driver.frame(of: id(1)) == wholeTile)
    }

    // MARK: Settings

    @Test func aChangedKeyBaseReachesTheKeyLayerAndAChangedGapRelaysTheWindows() {
        let rig = Rig()
        twoWindows(rig)
        rig.config = TileConfig(enabled: true, innerGap: 16, base: .optionCommand)
        rig.controller.start()
        #expect(rig.keys.last?.keymap == TileKeymap.defaults(base: .optionCommand))
        rig.settle()
        let left = rig.driver.frame(of: id(1))!, right = rig.driver.frame(of: id(2))!
        #expect(right.minX - left.maxX == 16)
        #expect(rig.controller.config.innerGap == 16)
    }

    @Test func anUnchangedConfigIsNotAChange() {
        let rig = Rig()
        twoWindows(rig)
        let applies = rig.keys.applies.count
        rig.controller.start()
        rig.settle()
        #expect(rig.keys.applies.count == applies, "a settings notification with nothing new does no work")
        #expect(rig.driver.writes.count == 2)
    }

    @Test func theSectionWritesThroughTheSettingsStoreAndNothingElse() {
        let rig = Rig()
        rig.controller.setEnabled(true)
        rig.controller.setGap(inner: true, to: 12)
        rig.controller.setGap(inner: false, to: 70)
        rig.controller.chooseBase(.controlOptionCommand)
        #expect(rig.settingWrites == ["tiling.enabled=true", "tiling.innerGap=12", "tiling.outerGap=64", "tiling.keyBase=Control-Option-Command"])
        #expect(rig.controller.observerCount == 0 && rig.driver.windowReads == 0, "writing a setting starts nothing by itself")
    }

    // MARK: Snapshot

    @Test func theSnapshotFixtureReadsNothingAndStartsNothing() {
        let driver = FakeTilingDriver()
        let controller = TilingController.snapshotFixture(.running, driver: driver)
        #expect(controller.phase == .running)
        #expect(controller.picture.first?.tiles.count == 3)
        #expect(controller.keyRows.count == 8)
        controller.start()
        controller.refresh()
        controller.handle(.retile)
        controller.stop()
        #expect(driver.windowReads == 0 && driver.writes.isEmpty && controller.observerCount == 0)
    }

    @Test func everySnapshotFixtureIsDeterministic() {
        for state in TilingSnapshotState.allCases {
            let a = TilingController.snapshotFixture(state, driver: FakeTilingDriver())
            let b = TilingController.snapshotFixture(state, driver: FakeTilingDriver())
            #expect(a.phase == b.phase && a.picture == b.picture && a.config == b.config && a.keyRows == b.keyRows, "\(state)")
        }
        #expect(TilingController.snapshotFixture(.off, driver: FakeTilingDriver()).phase == .off)
        #expect(TilingController.snapshotFixture(.needsAccessibility, driver: FakeTilingDriver()).phase == .needsAccessibility)
        #expect(TilingController.snapshotFixture(.paused, driver: FakeTilingDriver()).phase == .paused)
    }
}
