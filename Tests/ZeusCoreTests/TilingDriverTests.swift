import Foundation
import Testing
@testable import ZeusCore

private func id(_ n: Int, pid: Int32 = 500) -> TileWindowID { TileWindowID(pid: pid, index: n) }

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TileRect {
    TileRect(x: x, y: y, width: w, height: h)
}

/// A 1440 x 900 main display with a 25 point menu bar, in AppKit terms (origin at the bottom left of the main one).
private func mainDisplay(id: UInt32 = 1) -> TileDisplay {
    TileDisplay(id: id, appKitFrame: rect(0, 0, 1440, 900), appKitVisibleFrame: rect(0, 0, 1440, 875),
                engineFrame: rect(0, 0, 1440, 900))
}

/// A 1920 x 1080 display to the left of the main one, so its AppKit x is negative, and taller, so it reaches
/// above the main display's top edge.
private func leftDisplay(id: UInt32 = 2) -> TileDisplay {
    let appKit = rect(-1920, 0, 1920, 1080)
    return TileDisplay(id: id, appKitFrame: appKit, appKitVisibleFrame: rect(-1920, 0, 1920, 1055),
                       engineFrame: TileDisplay.engineFrame(appKitFrame: appKit, mainScreenHeight: 900))
}

/// A 2560 x 1440 display to the right of the main one and above it.
private func aboveRightDisplay(id: UInt32 = 3) -> TileDisplay {
    let appKit = rect(1440, 900, 2560, 1440)
    return TileDisplay(id: id, appKitFrame: appKit, appKitVisibleFrame: rect(1440, 900, 2560, 1415),
                       engineFrame: TileDisplay.engineFrame(appKitFrame: appKit, mainScreenHeight: 900))
}

// MARK: Coordinates

@Suite struct TilingDriverGeometryTests {
    @Test func theMainDisplayConvertsWithItsMenuBarLeftOut() {
        let display = mainDisplay()
        #expect(display.frame == rect(0, 0, 1440, 900))
        #expect(display.visibleFrame == rect(0, 25, 1440, 875), "the menu bar is 25 points at the top, so the usable area starts at y 25")
        #expect(display.toAppKit(rect(100, 100, 800, 600)) == rect(100, 200, 800, 600))
        #expect(display.toEngine(rect(100, 200, 800, 600)) == rect(100, 100, 800, 600))
    }

    @Test func aDisplayAtANegativeOriginConvertsUsingItsOwnHeight() {
        let display = leftDisplay()
        #expect(display.frame == rect(-1920, -180, 1920, 1080), "its top edge is 180 points above the main display's top edge")
        #expect(display.visibleFrame == rect(-1920, -155, 1920, 1055))
        #expect(display.toAppKit(rect(-1900, -150, 400, 300)) == rect(-1900, 750, 400, 300))
    }

    @Test func aDisplayAboveAndToTheRightConvertsCorrectly() {
        let display = aboveRightDisplay()
        #expect(display.frame == rect(1440, -1440, 2560, 1440))
        #expect(display.visibleFrame == rect(1440, -1415, 2560, 1415))
        #expect(display.toAppKit(rect(1500, -1400, 500, 300)) == rect(1500, 2000, 500, 300))
    }

    @Test func conversionRoundTripsOnEveryDisplay() {
        for display in [mainDisplay(), leftDisplay(), aboveRightDisplay()] {
            let inside = rect(display.frame.x + 40, display.frame.y + 60, 300, 200)
            #expect(display.toEngine(display.toAppKit(inside)) == inside)
            let appKitSide = display.appKitFrame
            let sample = rect(appKitSide.x + 10, appKitSide.y + 20, 120, 90)
            #expect(display.toAppKit(display.toEngine(sample)) == sample)
            #expect(display.toAppKit(display.frame) == display.appKitFrame, "the whole display maps onto its AppKit frame")
        }
    }

    @Test func theMainHeightFallbackMatchesTheThreeLayouts() {
        #expect(TileDisplay.engineFrame(appKitFrame: rect(0, 0, 1440, 900), mainScreenHeight: 900) == rect(0, 0, 1440, 900))
        #expect(TileDisplay.engineFrame(appKitFrame: rect(-1920, 0, 1920, 1080), mainScreenHeight: 900) == rect(-1920, -180, 1920, 1080))
        #expect(TileDisplay.engineFrame(appKitFrame: rect(1440, 900, 2560, 1440), mainScreenHeight: 900) == rect(1440, -1440, 2560, 1440))
    }

    @Test func aWindowBelongsToTheDisplayItOverlapsMost() {
        let right = TileDisplay(id: 2, appKitFrame: rect(1440, 0, 1920, 1080), appKitVisibleFrame: rect(1440, 0, 1920, 1055),
                                engineFrame: TileDisplay.engineFrame(appKitFrame: rect(1440, 0, 1920, 1080), mainScreenHeight: 900))
        let displays = [mainDisplay(), right]
        #expect(TileDisplays.display(for: rect(100, 100, 400, 300), in: displays)?.id == 1)
        #expect(TileDisplays.display(for: rect(1300, 100, 400, 300), in: displays)?.id == 2, "260 points are on the right, 140 on the left")
        #expect(TileDisplays.display(for: rect(1340, 100, 200, 100), in: displays)?.id == 1, "an equal split goes to the lowest id")
        #expect(TileDisplays.display(for: rect(5000, 5000, 100, 100), in: displays) == nil, "off every display")
        #expect(TileDisplays.display(for: rect(100, 100, 0, 0), in: displays) == nil, "an empty frame has no display")
        #expect(TileDisplays.display(for: rect(100, 100, 400, 300), in: []) == nil)
    }
}

// MARK: Admission

private func facts(_ edit: (inout TileWindowFacts) -> Void = { _ in }) -> TileWindowFacts {
    var value = TileWindowFacts(pid: 500, bundleID: "com.example.editor", isRegularApp: true, role: "AXWindow",
                                subrole: "AXStandardWindow", isMinimized: false, isFullScreen: false,
                                isSizeSettable: true, frame: rect(100, 100, 800, 600))
    edit(&value)
    return value
}

private let onScreenEditor = [TileOnScreenWindow(pid: 500, frame: rect(100, 100, 800, 600), layer: 0, ownerName: "Editor")]

private func policy(excluded: Set<String> = [], minimum: Double = 200) -> TileAdmissionPolicy {
    TileAdmissionPolicy(zeusPID: 42, zeusBundleID: "com.example.zeus", excludedBundleIDs: excluded, minimumSize: minimum)
}

@Suite struct TilingDriverAdmissionTests {
    @Test func aPlainStandardWindowInTheOnScreenListIsAdmitted() {
        #expect(TileAdmission.rejection(facts(), onScreen: onScreenEditor, policy: policy()) == nil)
    }

    @Test func zeusItselfIsNeverTiled() {
        #expect(TileAdmission.rejection(facts { $0.pid = 42 }, onScreen: onScreenEditor, policy: policy()) == .ownWindow)
        #expect(TileAdmission.rejection(facts { $0.bundleID = "com.example.zeus" }, onScreen: onScreenEditor, policy: policy()) == .ownWindow)
    }

    @Test func systemProcessesAreLeftAlone() {
        for bundle in ["com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui",
                       "com.apple.Spotlight", "com.apple.loginwindow", "com.apple.systemuiserver"] {
            #expect(TileAdmission.rejection(facts { $0.bundleID = bundle }, onScreen: onScreenEditor, policy: policy()) == .systemProcess,
                    "\(bundle) is a system process")
        }
        let owned = [TileOnScreenWindow(pid: 500, frame: rect(100, 100, 800, 600), layer: 0, ownerName: "Notification Center")]
        #expect(TileAdmission.rejection(facts(), onScreen: owned, policy: policy()) == .systemProcess, "the on-screen owner name counts too")
    }

    @Test func anAppThatIsNotARegularAppIsLeftAlone() {
        #expect(TileAdmission.rejection(facts { $0.isRegularApp = false }, onScreen: onScreenEditor, policy: policy()) == .notRegularApp)
    }

    @Test func theUserExclusionListIsHonoured() {
        #expect(TileAdmission.rejection(facts(), onScreen: onScreenEditor, policy: policy(excluded: ["com.example.editor"])) == .excludedApp)
        #expect(TileAdmission.rejection(facts(), onScreen: onScreenEditor, policy: policy(excluded: ["com.example.other"])) == nil)
    }

    @Test func onlyStandardWindowsAreAdmitted() {
        #expect(TileAdmission.rejection(facts { $0.role = "AXSheet"; $0.subrole = nil }, onScreen: onScreenEditor, policy: policy()) == .unreadable,
                "a sheet has no subrole to read")
        #expect(TileAdmission.rejection(facts { $0.role = "AXSheet"; $0.subrole = "AXDialog" }, onScreen: onScreenEditor, policy: policy()) == .notStandardWindow)
        #expect(TileAdmission.rejection(facts { $0.subrole = "AXFloatingWindow" }, onScreen: onScreenEditor, policy: policy()) == .notStandardWindow)
        #expect(TileAdmission.rejection(facts { $0.subrole = "AXDialog" }, onScreen: onScreenEditor, policy: policy()) == .notStandardWindow)
        #expect(TileAdmission.rejection(facts { $0.role = "AXMenu" }, onScreen: onScreenEditor, policy: policy()) == .notStandardWindow)
    }

    @Test func minimizedAndFullScreenWindowsAreLeftAlone() {
        #expect(TileAdmission.rejection(facts { $0.isMinimized = true }, onScreen: onScreenEditor, policy: policy()) == .minimized)
        #expect(TileAdmission.rejection(facts { $0.isFullScreen = true }, onScreen: onScreenEditor, policy: policy()) == .fullScreen)
    }

    @Test func aWindowThatCannotBeResizedIsLeftAlone() {
        #expect(TileAdmission.rejection(facts { $0.isSizeSettable = false }, onScreen: onScreenEditor, policy: policy()) == .notResizable)
    }

    @Test func aWindowAbsentFromTheOnScreenListIsOnAnotherSpace() {
        #expect(TileAdmission.rejection(facts(), onScreen: [], policy: policy()) == .otherSpace)
        let otherPid = [TileOnScreenWindow(pid: 501, frame: rect(100, 100, 800, 600), layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts(), onScreen: otherPid, policy: policy()) == .otherSpace, "the frame matches but the pid does not")
        let otherFrame = [TileOnScreenWindow(pid: 500, frame: rect(400, 300, 800, 600), layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts(), onScreen: otherFrame, policy: policy()) == .otherSpace, "the pid matches but the frame does not")
        let floatingLayer = [TileOnScreenWindow(pid: 500, frame: rect(100, 100, 800, 600), layer: 3, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts(), onScreen: floatingLayer, policy: policy()) == .otherSpace, "only normal-level windows count")
    }

    @Test func theOnScreenMatchAllowsTheReadBackTolerance() {
        let close = [TileOnScreenWindow(pid: 500, frame: rect(101, 99, 799, 601), layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts(), onScreen: close, policy: policy()) == nil)
        let far = [TileOnScreenWindow(pid: 500, frame: rect(106, 100, 800, 600), layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts(), onScreen: far, policy: policy()) == .otherSpace)
    }

    @Test func aWindowBelowTheMinimumSizeIsLeftAlone() {
        let small = rect(100, 100, 150, 600)
        let list = [TileOnScreenWindow(pid: 500, frame: small, layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts { $0.frame = small }, onScreen: list, policy: policy(minimum: 200)) == .tooSmall)
        #expect(TileAdmission.rejection(facts { $0.frame = small }, onScreen: list, policy: policy(minimum: 120)) == nil)
        let exact = rect(100, 100, 200, 200)
        let exactList = [TileOnScreenWindow(pid: 500, frame: exact, layer: 0, ownerName: "Editor")]
        #expect(TileAdmission.rejection(facts { $0.frame = exact }, onScreen: exactList, policy: policy(minimum: 200)) == nil, "the minimum itself is allowed")
    }

    @Test func anyUnreadablePropertyLeavesTheWindowAlone() {
        let edits: [(String, (inout TileWindowFacts) -> Void)] = [
            ("bundle id", { $0.bundleID = nil }),
            ("regular app", { $0.isRegularApp = nil }),
            ("role", { $0.role = nil }),
            ("subrole", { $0.subrole = nil }),
            ("minimized", { $0.isMinimized = nil }),
            ("full screen", { $0.isFullScreen = nil }),
            ("size settable", { $0.isSizeSettable = nil }),
            ("frame", { $0.frame = nil }),
        ]
        for (name, edit) in edits {
            #expect(TileAdmission.rejection(facts(edit), onScreen: onScreenEditor, policy: policy()) == .unreadable, "\(name) unreadable")
        }
    }

    @Test func aFrameThatIsNotANumberIsUnreadable() {
        let bad = rect(.nan, 100, 800, 600)
        #expect(TileAdmission.rejection(facts { $0.frame = bad }, onScreen: onScreenEditor, policy: policy()) == .unreadable)
    }

    @Test func theAppLevelCheckRunsBeforeAnyWindowIsRead() {
        #expect(TileAdmission.appRejection(pid: 500, bundleID: "com.example.editor", isRegularApp: true, policy: policy()) == nil)
        #expect(TileAdmission.appRejection(pid: 42, bundleID: "com.example.zeus", isRegularApp: true, policy: policy()) == .ownWindow)
        #expect(TileAdmission.appRejection(pid: 500, bundleID: "com.apple.dock", isRegularApp: true, policy: policy()) == .systemProcess)
        #expect(TileAdmission.appRejection(pid: 500, bundleID: nil, isRegularApp: true, policy: policy()) == .unreadable)
        #expect(TileAdmission.appRejection(pid: 500, bundleID: "com.example.editor", isRegularApp: false, policy: policy()) == .notRegularApp)
        #expect(TileAdmission.appRejection(pid: 500, bundleID: "com.example.editor", isRegularApp: true,
                                           policy: policy(excluded: ["com.example.editor"])) == .excludedApp)
    }

    @Test func thePolicyReadsTheConfig() {
        let config = TileConfig(minTileSize: 300, excludedBundleIDs: ["com.example.editor"])
        let built = TileAdmissionPolicy(config: config, zeusPID: 42, zeusBundleID: "com.example.zeus")
        #expect(built.minimumSize == 300)
        #expect(built.excludedBundleIDs == ["com.example.editor"])
        #expect(built.zeusPID == 42)
    }
}

// MARK: Tolerance and self writes

@Suite struct TilingDriverReadBackTests {
    @Test func aFrameWithinTwoPointsOnEveryEdgeLanded() {
        let intended = rect(100, 100, 800, 600)
        #expect(TileReadBack.matches(intended, intended))
        #expect(TileReadBack.matches(intended, rect(101, 102, 799, 598)))
        #expect(TileReadBack.matches(intended, rect(102, 98, 802, 602)))
        #expect(!TileReadBack.matches(intended, rect(103, 100, 800, 600)))
        #expect(!TileReadBack.matches(intended, rect(100, 100, 800, 597)))
        #expect(!TileReadBack.matches(intended, rect(100, 100, 700, 600)), "an app that kept a larger minimum size did not land")
    }

    @Test func anUnreadableOrNonNumericFrameNeverCountsAsLanded() {
        let intended = rect(100, 100, 800, 600)
        #expect(!TileReadBack.landed(intended: intended, actual: nil))
        #expect(!TileReadBack.landed(intended: intended, actual: rect(.nan, 100, 800, 600)))
        #expect(!TileReadBack.landed(intended: rect(.infinity, 0, 1, 1), actual: rect(.infinity, 0, 1, 1)))
        #expect(TileReadBack.landed(intended: intended, actual: rect(101, 101, 800, 600)))
    }

    @Test func aCustomToleranceIsUsed() {
        #expect(TileReadBack.matches(rect(0, 0, 10, 10), rect(5, 0, 10, 10), tolerance: 5))
        #expect(!TileReadBack.matches(rect(0, 0, 10, 10), rect(6, 0, 10, 10), tolerance: 5))
    }

    @Test func aMoveNotificationThatMatchesTheIntendedFrameIsOurOwnEcho() {
        var writes = TileSelfWrites()
        writes.record([id(1): rect(16, 16, 940, 1048)], at: 10)
        #expect(writes.isOwnEcho(id(1), observed: rect(16, 16, 940, 1048), at: 10.2))
        #expect(writes.isOwnEcho(id(1), observed: rect(17, 16, 940, 1048), at: 10.4), "a second notification for the same write still matches")
        #expect(!writes.isOwnEcho(id(1), observed: rect(300, 16, 940, 1048), at: 10.4), "the person moved it somewhere else")
        #expect(!writes.isOwnEcho(id(2), observed: rect(16, 16, 940, 1048), at: 10.4), "no write for that window")
        #expect(!writes.isOwnEcho(id(1), observed: rect(16, 16, 940, 1048), at: 10 + TileSelfWrites.lifetime + 0.1), "an old write expires")
    }

    @Test func aNewWriteReplacesTheOldOneAndPruningDropsExpiredOnes() {
        var writes = TileSelfWrites()
        writes.record([id(1): rect(0, 0, 500, 500)], at: 1)
        writes.record([id(1): rect(600, 0, 500, 500)], at: 2)
        #expect(!writes.isOwnEcho(id(1), observed: rect(0, 0, 500, 500), at: 2.1))
        #expect(writes.isOwnEcho(id(1), observed: rect(600, 0, 500, 500), at: 2.1))
        writes.prune(now: 2 + TileSelfWrites.lifetime + 1)
        #expect(writes.isEmpty)
    }
}

// MARK: Identity

@Suite struct TilingDriverIdentityTests {
    @Test func eachAppNumbersItsWindowsFromOneAndNeverReusesANumber() {
        var allocator = TileIDAllocator()
        #expect(allocator.next(pid: 10) == TileWindowID(pid: 10, index: 1))
        #expect(allocator.next(pid: 10) == TileWindowID(pid: 10, index: 2))
        #expect(allocator.next(pid: 20) == TileWindowID(pid: 20, index: 1))
        #expect(allocator.next(pid: 10) == TileWindowID(pid: 10, index: 3))
    }
}

// MARK: Eligible windows and the plan

@Suite struct TilingDriverPlanTests {
    private func ref(_ n: Int, _ frame: TileRect, bundle: String = "com.example.editor", pid: Int32 = 500) -> TileWindowRef {
        TileWindowRef(id: id(n, pid: pid), bundleID: bundle, frame: frame)
    }

    @Test func theEngineInputsDropWhatAdmissionWouldHaveDropped() {
        let displays = [mainDisplay()]
        let good = ref(1, rect(100, 100, 800, 600))
        let floating = ref(2, rect(100, 100, 800, 600))
        let excluded = ref(3, rect(100, 100, 800, 600), bundle: "com.example.skip")
        let tiny = ref(4, rect(100, 100, 100, 600))
        let offscreen = ref(5, rect(9000, 9000, 800, 600))
        let duplicate = ref(1, rect(300, 300, 800, 600))
        let config = TileConfig(minTileSize: 200, floating: [id(2)], excludedBundleIDs: ["com.example.skip"])
        let kept = TilePlanner.eligible([good, floating, excluded, tiny, offscreen, duplicate], config: config, displays: displays)
        #expect(kept == [good])
    }

    @Test func eligibleKeepsTheDiscoveryOrder() {
        let displays = [mainDisplay()]
        let a = ref(3, rect(0, 30, 600, 500)), b = ref(1, rect(700, 30, 600, 500)), c = ref(2, rect(0, 400, 600, 400))
        #expect(TilePlanner.eligible([a, b, c], config: TileConfig(), displays: displays).map(\.id) == [id(3), id(1), id(2)])
    }

    private let display = TileDisplay(id: 1, appKitFrame: rect(0, 0, 1920, 1080), appKitVisibleFrame: rect(0, 0, 1920, 1080),
                                      engineFrame: rect(0, 0, 1920, 1080))
    private var config: TileConfig { TileConfig(innerGap: 8, outerGap: 16, maxDepth: 3, minTileSize: 200) }

    private func twoWindowTree() -> TileTree {
        var tree = TileTree(displayID: 1)
        for n in 1...2 {
            guard case .inserted(let next) = TileOps.insert(id(n), into: tree, focused: nil, display: display.visibleFrame, config: config) else {
                Issue.record("window \(n) was refused")
                return tree
            }
            tree = next
        }
        return tree
    }

    @Test func eachLeafGetsTheEngineFrameAndWindowsAlreadyThereAreSkipped() {
        let tree = twoWindowTree()
        let left = rect(16, 16, 940, 1048), right = rect(964, 16, 940, 1048)
        let plan = TilePlanner.plan(tree: tree, display: display, config: config,
                                    windows: [ref(1, rect(300, 200, 700, 500)), ref(2, right)])
        #expect(plan.moves == [TileMove(id: id(1), target: left, current: rect(300, 200, 700, 500))])
        #expect(plan.inPlace == [id(2)])
        #expect(plan.missing.isEmpty)
    }

    @Test func aFrameWithinTheToleranceCountsAsAlreadyThere() {
        let tree = twoWindowTree()
        let plan = TilePlanner.plan(tree: tree, display: display, config: config,
                                    windows: [ref(1, rect(17, 15, 939, 1049)), ref(2, rect(964, 16, 940, 1048))])
        #expect(plan.moves.isEmpty)
        #expect(plan.inPlace == [id(1), id(2)])
    }

    @Test func aLeafWithNoLiveWindowIsReportedMissingAndNotMoved() {
        let tree = twoWindowTree()
        let plan = TilePlanner.plan(tree: tree, display: display, config: config, windows: [ref(2, rect(0, 0, 500, 500))])
        #expect(plan.moves.map(\.id) == [id(2)])
        #expect(plan.missing == [id(1)])
    }

    @Test func aWindowOutsideTheTreeIsNeverMoved() {
        let tree = twoWindowTree()
        let stray = ref(9, rect(50, 50, 600, 400))
        let plan = TilePlanner.plan(tree: tree, display: display, config: config,
                                    windows: [ref(1, rect(0, 0, 500, 500)), ref(2, rect(0, 0, 500, 500)), stray])
        #expect(!plan.moves.contains { $0.id == id(9) })
        #expect(!plan.inPlace.contains(id(9)))
    }

    @Test func aFloatingWindowInTheTreeIsNotMoved() {
        let tree = twoWindowTree()
        let floatingConfig = TileConfig(innerGap: 8, outerGap: 16, maxDepth: 3, minTileSize: 200, floating: [id(1)])
        let plan = TilePlanner.plan(tree: tree, display: display, config: floatingConfig,
                                    windows: [ref(1, rect(0, 0, 500, 500)), ref(2, rect(0, 0, 500, 500))])
        #expect(plan.moves.map(\.id) == [id(2)])
    }

    @Test func movesFollowTheTreeOrderAndAnEmptyTreePlansNothing() {
        let tree = twoWindowTree()
        let plan = TilePlanner.plan(tree: tree, display: display, config: config,
                                    windows: [ref(2, rect(0, 0, 500, 500)), ref(1, rect(0, 0, 500, 500))])
        #expect(plan.moves.map(\.id) == [id(1), id(2)])
        let empty = TilePlanner.plan(tree: TileTree(displayID: 1), display: display, config: config, windows: [ref(1, rect(0, 0, 500, 500))])
        #expect(empty.moves.isEmpty && empty.inPlace.isEmpty && empty.missing.isEmpty)
    }
}

// MARK: Applying a plan through a driver

/// Records every call. A window in `refuse` never lands. A window in `clamp` lands at its own size instead.
@MainActor private final class FakeDriver: TilingWindowDriver {
    var isTrusted = true
    var screens: [TileDisplay] = [mainDisplay()]
    var refs: [TileWindowRef] = []
    var refuse: Set<TileWindowID> = []
    var writes: [(window: TileWindowID, frame: TileRect)] = []
    var focused: [TileWindowID] = []
    var onWrite: () -> Void = {}
    var configs: [TileConfig] = []

    func displays() -> [TileDisplay] { screens }

    func windows(config: TileConfig) -> [TileWindowRef] {
        configs.append(config)
        return isTrusted ? refs : []
    }

    func setFrame(_ frame: TileRect, for window: TileWindowID) -> Bool {
        guard isTrusted else { return false }
        writes.append((window, frame))
        onWrite()
        if refuse.contains(window) { return false }
        if let index = refs.firstIndex(where: { $0.id == window }) { refs[index].frame = frame }
        return true
    }

    func focus(_ window: TileWindowID) { focused.append(window) }
}

@Suite @MainActor struct TilingDriverApplyTests {
    private func moves(_ count: Int) -> TileMovePlan {
        let list = (1...count).map { n in
            TileMove(id: id(n), target: rect(Double(n) * 100, 0, 90, 90), current: rect(0, 500, 50, 50))
        }
        return TileMovePlan(moves: list, inPlace: [], missing: [])
    }

    private func driver(_ count: Int) -> FakeDriver {
        let fake = FakeDriver()
        fake.refs = (1...count).map { TileWindowRef(id: id($0), bundleID: "com.example.editor", frame: rect(0, 500, 50, 50)) }
        return fake
    }

    @Test func withAccessibilityOffNothingIsWrittenAndTheStateIsReported() {
        let fake = driver(2)
        fake.isTrusted = false
        let outcome = TileApplier.apply(moves(2), with: fake)
        #expect(outcome.state == .accessibilityOff)
        #expect(fake.writes.isEmpty)
        #expect(outcome.moved.isEmpty && outcome.refused.isEmpty && outcome.deferred.isEmpty)
    }

    @Test func everyMoveIsWrittenOnceAndAReapplyOfTheSameLayoutWritesNothing() {
        let fake = driver(3)
        let first = TileApplier.apply(moves(3), with: fake)
        #expect(first.state == .applied)
        #expect(first.moved == [id(1), id(2), id(3)])
        #expect(fake.writes.count == 3)
        #expect(fake.refs.map(\.frame) == [rect(100, 0, 90, 90), rect(200, 0, 90, 90), rect(300, 0, 90, 90)])

        let reapplied = TileApplier.apply(TileMovePlan(moves: [], inPlace: [id(1), id(2), id(3)], missing: []), with: fake)
        #expect(reapplied.moved.isEmpty)
        #expect(reapplied.skipped == [id(1), id(2), id(3)])
        #expect(fake.writes.count == 3, "no further write")
    }

    @Test func aWindowThatReadsBackWrongIsRefusedAndNeverRetried() {
        let fake = driver(3)
        fake.refuse = [id(2)]
        let outcome = TileApplier.apply(moves(3), with: fake)
        #expect(outcome.refused == [id(2)], "the caller marks it floating for the session and rebuilds")
        #expect(outcome.moved == [id(1), id(3)])
        #expect(fake.writes.filter { $0.window == id(2) }.count == 1, "one attempt, no retry loop")
        #expect(fake.writes.count == 3)
    }

    @Test func theIntendedFramesOfEveryWriteAreReportedSoTheirEchoesCanBeIgnored() {
        let fake = driver(2)
        fake.refuse = [id(2)]
        let outcome = TileApplier.apply(moves(2), with: fake)
        #expect(outcome.intended == [id(1): rect(100, 0, 90, 90), id(2): rect(200, 0, 90, 90)])
        var writes = TileSelfWrites()
        writes.record(outcome.intended, at: 5)
        #expect(writes.isOwnEcho(id(1), observed: rect(100, 0, 90, 90), at: 5.1))
        #expect(writes.isOwnEcho(id(2), observed: rect(200, 0, 90, 90), at: 5.1))
    }

    @Test func theTimeBudgetDefersTheRestInsteadOfFloatingThem() {
        let fake = driver(5)
        var now = 0.0
        fake.onWrite = { now += 0.4 }
        let outcome = TileApplier.apply(moves(5), with: fake, budget: 1.0, clock: { now })
        #expect(outcome.moved == [id(1), id(2), id(3)], "the pass starts a move only while time is left")
        #expect(outcome.deferred == [id(4), id(5)])
        #expect(outcome.refused.isEmpty, "a deferred window is not marked floating")
        #expect(fake.writes.count == 3)
    }

    @Test func theSkippedListIsTheInPlaceListAndPassesStillRunMoves() {
        let fake = driver(2)
        let plan = TileMovePlan(moves: [TileMove(id: id(2), target: rect(5, 5, 90, 90), current: rect(0, 500, 50, 50))],
                                inPlace: [id(1)], missing: [])
        let outcome = TileApplier.apply(plan, with: fake)
        #expect(outcome.skipped == [id(1)])
        #expect(outcome.moved == [id(2)])
    }

    @Test func focusAndWindowListGoThroughTheDriver() {
        let fake = driver(1)
        let config = TileConfig(minTileSize: 300)
        #expect(fake.windows(config: config).count == 1)
        #expect(fake.configs == [config])
        fake.focus(id(1))
        #expect(fake.focused == [id(1)])
    }
}
