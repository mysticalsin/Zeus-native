import Foundation
import Testing
@testable import ZeusCore

@Suite("System focus types") struct SystemFocusTypesTests {
    @Test func quietWhenAuthorizedAndFocused() {
        #expect(SystemFocusPublic.quiet(authorized: true, isFocused: true))
    }

    @Test func quietWhenAuthorizedAndNotFocused() {
        #expect(SystemFocusPublic.quiet(authorized: true, isFocused: false) == false)
    }

    @Test func quietWhenAuthorizedAndTheReportIsMissing() {
        #expect(SystemFocusPublic.quiet(authorized: true, isFocused: nil) == false)
    }

    @Test func quietWhenNotAuthorizedEvenIfAFocusIsReported() {
        #expect(SystemFocusPublic.quiet(authorized: false, isFocused: true) == false)
        #expect(SystemFocusPublic.quiet(authorized: false, isFocused: false) == false)
        #expect(SystemFocusPublic.quiet(authorized: false, isFocused: nil) == false)
    }

    @Test func snapshotSampleNamesAFocusAndSaysAllowed() {
        #expect(SystemFocusSurface.snapshotSample.shown == .on(label: "Work", symbol: "moon.fill"))
        #expect(SystemFocusSurface.snapshotSample.row == .allowed)
    }

    @Test func aStampDifferenceIsADifferentFile() {
        let stamp = SystemFocusStamp(inode: 1, size: 20, seconds: 1_700_000_000, nanoseconds: 0)
        let later = SystemFocusStamp(inode: 1, size: 20, seconds: 1_700_000_000, nanoseconds: 1)
        #expect(stamp != later)
        let stamps = SystemFocusStamps(assertions: stamp, configurations: nil)
        #expect(stamps.assertions == stamp)
        #expect(stamps.configurations == nil)
    }

    @Test func aRefusedReadStaysUnreadable() {
        let read = SystemFocusStoreRead.unreadable(.refused)
        #expect(read == .unreadable(.refused))
        #expect(SystemFocusStoreRead.missing != .denied)
        #expect(SystemFocusStoreRead.ok(.off) != .ok(.unknown))
    }

    @Test @MainActor func aMainActorFakeConforms() {
        let fake = SystemFocusControlFake()
        let controlling: any SystemFocusControlling = fake
        #expect(controlling.surface == SystemFocusSurface(shown: .none, row: .off))
        controlling.setEnabled(true)
        controlling.recheck()
        controlling.openSettingsPane()
        #expect(fake.enabled == true)
        #expect(fake.rechecks == 1)
        #expect(fake.paneOpens == 1)
        #expect(fake.surface.row == .off)
    }
}

@MainActor
private final class SystemFocusControlFake: SystemFocusControlling {
    var surface = SystemFocusSurface(shown: .none, row: .off)
    private(set) var enabled: Bool?
    private(set) var rechecks = 0
    private(set) var paneOpens = 0

    func setEnabled(_ on: Bool) { enabled = on }
    func recheck() { rechecks += 1 }
    func openSettingsPane() { paneOpens += 1 }
}
