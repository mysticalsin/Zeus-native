import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// A store that records every read and write, so a test can say what the model touched.
@MainActor
private final class FakeDrawnStore: DrawnNotchStore {
    var rows: [String: String]
    private(set) var reads = 0
    private(set) var writes: [(id: String, value: String)] = []

    init(_ rows: [String: String] = [:]) { self.rows = rows }

    func string(_ id: String) -> String {
        reads += 1
        return rows[id] ?? ""
    }

    func write(_ id: String, _ value: String) {
        writes.append((id, value))
        rows[id] = value
    }
}

@MainActor
private struct Harness {
    let store: FakeDrawnStore
    let appCenter = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    let distributedCenter = NotificationCenter()
    let model: DrawnNotchModel
    let announcements: Announcements

    final class Announcements { var lines: [String] = [] }

    init(_ rows: [String: String] = Harness.notchRows) {
        let store = FakeDrawnStore(rows)
        let announcements = Announcements()
        let app = appCenter, workspace = workspaceCenter, distributed = distributedCenter
        self.store = store
        self.announcements = announcements
        model = DrawnNotchModel(store: store, appCenter: app, workspaceCenter: workspace, distributedCenter: distributed,
                                announce: { announcements.lines.append($0) })
    }

    static let notchRows = [
        DrawnNotchModel.Row.style: "Notch", DrawnNotchModel.Row.width: "185",
        DrawnNotchModel.Row.height: "32", DrawnNotchModel.Row.offset: "0",
    ]

    static let plainDisplay = NotchDisplayFacts(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                                safeAreaTop: 0, leftAreaWidth: 0, rightAreaWidth: 0)
    static let notchedDisplay = NotchDisplayFacts(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                  safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 663)

    /// Notification blocks hop through the main queue; let them run.
    func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }

    func beginAdjusting(width: Double? = nil) {
        model.send(.begin(saved: model.saved))
        if let width { model.send(.setWidth(width)) }
    }
}

@MainActor @Suite("Drawn notch model", .serialized)
struct DrawnNotchModelTests {
    @Test func doneWritesTheSizeRowsOnce() {
        let harness = Harness()
        harness.beginAdjusting(width: 200)
        harness.model.send(.setHeight(36))
        harness.model.send(.done)
        let ids = harness.store.writes.map(\.id).sorted()
        #expect(ids == [DrawnNotchModel.Row.height, DrawnNotchModel.Row.offset, DrawnNotchModel.Row.width])
        #expect(harness.store.rows[DrawnNotchModel.Row.width] == "200")
        #expect(harness.store.rows[DrawnNotchModel.Row.height] == "36")
        #expect(harness.model.state == .idle)
        #expect(harness.announcements.lines == [DrawnNotchCalibration.savedAnnouncement])
    }

    @Test func doneWithoutAChangeWritesNothingAndSaysSo() {
        let harness = Harness()
        harness.beginAdjusting()
        harness.model.send(.done)
        #expect(harness.store.writes.isEmpty)
        #expect(harness.announcements.lines == [DrawnNotchCalibration.unchangedAnnouncement])
    }

    @Test func cancelWritesNothing() {
        let harness = Harness()
        harness.beginAdjusting(width: 240)
        harness.model.send(.cancel)
        #expect(harness.store.writes.isEmpty)
        #expect(harness.model.state == .idle)
        #expect(harness.model.saved.width == 185)
    }

    @Test func theFootprintOnADisplayWithoutANotchFollowsTheDraft() {
        let harness = Harness()
        #expect(harness.model.footprint(for: Harness.plainDisplay) == .drawn(DrawnNotchShape(width: 185, height: 32, offset: 0)))
        harness.beginAdjusting(width: 220)
        #expect(harness.model.footprint(for: Harness.plainDisplay) == .drawn(DrawnNotchShape(width: 220, height: 32, offset: 0)))
        harness.model.send(.cancel)
        #expect(harness.model.footprint(for: Harness.plainDisplay) == .drawn(DrawnNotchShape(width: 185, height: 32, offset: 0)))
    }

    @Test func aNotchedDisplayIgnoresTheStyleAndTheDraft() {
        let harness = Harness()
        harness.beginAdjusting(width: 220)
        #expect(harness.model.footprint(for: Harness.notchedDisplay) == .hardware(CGSize(width: 186, height: 32)))
    }

    @Test func thePillStyleDrawsThePill() {
        let harness = Harness([DrawnNotchModel.Row.style: "Pill"])
        #expect(harness.model.footprint(for: Harness.plainDisplay) == .pill)
        let unknown = Harness([DrawnNotchModel.Row.style: "Banana"])
        #expect(unknown.model.footprint(for: Harness.plainDisplay) == .pill)
        let empty = Harness([:])
        #expect(empty.model.footprint(for: Harness.plainDisplay) == .pill)
    }

    @Test func storedRowsAreSanitizedAndAMissingRowTakesItsDefault() {
        let hostile = Harness([DrawnNotchModel.Row.width: "99999", DrawnNotchModel.Row.height: "abc", DrawnNotchModel.Row.offset: "nan"])
        #expect(hostile.model.saved == DrawnNotchShape(width: 280, height: 32, offset: 0))
        let missing = Harness([:])
        #expect(missing.model.saved == DrawnNotchLimits.defaultShape)
    }

    @Test func noTargetLeftEndsCalibrationAndWritesNothing() {
        let harness = Harness()
        harness.beginAdjusting(width: 240)
        harness.model.displaysChanged(targetsWithoutNotch: 0, connectedWithoutNotch: 0)
        #expect(harness.model.state == .idle)
        #expect(harness.store.writes.isEmpty)
        #expect(harness.model.availability == .noDisplay)
    }

    @Test func aTargetThatRemainsKeepsCalibrationRunning() {
        let harness = Harness()
        harness.beginAdjusting(width: 240)
        harness.model.displaysChanged(targetsWithoutNotch: 1, connectedWithoutNotch: 2)
        #expect(DrawnNotchCalibration.showsGuide(harness.model.state))
        #expect(harness.model.availability == .ready)
    }

    @Test(arguments: [(0, 0, DrawnNotchAvailability.noDisplay), (0, 1, .notShown), (0, 2, .notShown),
                      (1, 1, .ready), (1, 2, .ready), (2, 2, .ready), (-1, -1, .noDisplay)])
    func availabilityFollowsTheTwoCounts(targets: Int, connected: Int, expected: DrawnNotchAvailability) {
        let harness = Harness()
        harness.model.displaysChanged(targetsWithoutNotch: targets, connectedWithoutNotch: connected)
        #expect(harness.model.availability == expected)
    }

    enum Loss: CaseIterable { case locked, sleeping, sessionResigned, appHidden }

    @Test(arguments: Loss.allCases)
    func eachSystemNoticeEndsCalibrationWithoutSaving(loss: Loss) {
        let harness = Harness()
        harness.model.start()
        defer { harness.model.stop() }
        harness.beginAdjusting(width: 240)
        switch loss {
        case .locked: harness.distributedCenter.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        case .sleeping: harness.workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        case .sessionResigned: harness.workspaceCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        case .appHidden: harness.appCenter.post(name: NSApplication.didHideNotification, object: nil)
        }
        harness.settle()
        #expect(harness.model.state == .idle)
        #expect(harness.store.writes.isEmpty)
    }

    @Test func stopRemovesTheObservers() {
        let harness = Harness()
        harness.model.start()
        harness.model.start()
        harness.model.stop()
        harness.beginAdjusting(width: 240)
        harness.appCenter.post(name: NSApplication.didHideNotification, object: nil)
        harness.workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        harness.settle()
        #expect(DrawnNotchCalibration.showsGuide(harness.model.state), "after stop, a notice changes nothing")
    }

    @Test func choosingPillEndsCalibration() {
        let harness = Harness()
        harness.beginAdjusting(width: 240)
        harness.model.setStyle(.pill)
        #expect(harness.model.state == .idle)
        #expect(harness.store.rows[DrawnNotchModel.Row.style] == "Pill")
        harness.model.setStyle(.drawn)
        #expect(harness.store.rows[DrawnNotchModel.Row.style] == "Notch")
    }

    @Test func calibrationBlocksThePointerOnlyWhileTheDrawnShapeIsTheOneShown() {
        let harness = Harness()
        #expect(!harness.model.isCalibrating)
        harness.beginAdjusting()
        #expect(harness.model.isCalibrating)
        harness.store.rows[DrawnNotchModel.Row.style] = "Pill"
        #expect(!harness.model.isCalibrating, "a pill is on screen, nothing is being calibrated")
    }

    @Test func snapshotsReadNoStore() {
        let harness = Harness()
        let pinned = NotchFootprint.drawn(DrawnNotchShape(width: 200, height: 34, offset: 0))
        let view = NotchView(model: NotchModel(), facts: Harness.plainDisplay, footprintOverride: pinned,
                             guideOverride: true, drawnNotch: harness.model)
        #expect(view.footprint == pinned)
        #expect(view.showsGuide)
        #expect(harness.store.reads == 0)
        #expect(harness.store.writes.isEmpty)
    }

    @Test func theViewAsksTheModelWhenNothingIsPinned() {
        let harness = Harness()
        let view = NotchView(model: NotchModel(), facts: Harness.plainDisplay, drawnNotch: harness.model)
        #expect(view.footprint == .drawn(DrawnNotchLimits.defaultShape))
        #expect(!view.showsGuide)
        harness.beginAdjusting()
        #expect(view.showsGuide)
        let open = NotchModel()
        open.presentation = .panel
        let covered = NotchView(model: open, facts: Harness.plainDisplay, drawnNotch: harness.model)
        #expect(!covered.showsGuide, "the guide is for the closed notch")
    }
}
