import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// A stand-in for the controller: it records what the card asks for and never opens a tap.
@MainActor
private final class FakeEqualiser: EqualiserControlling {
    var statusReads = 0
    var stored = EqualiserStatus(line: "Off. No app is tapped.", symbol: "waveform.slash", rows: [])
    var status: EqualiserStatus {
        statusReads += 1
        return stored
    }
    var switches: [Bool] = []
    var updates: [AppSoundSettings] = []
    var forgotten: [String] = []
    var retries = 0

    func setSwitch(_ on: Bool) { switches.append(on) }
    func update(_ settings: AppSoundSettings) { updates.append(settings) }
    func forget(bundleID: String) { forgotten.append(bundleID) }
    func tryAgain() { retries += 1 }
}

private func row(
    _ id: String = "com.example.player",
    gains: [Double] = [Double](repeating: 0, count: 10),
    volume: Double = 1,
    shapes: Bool = true
) -> EqualiserRow {
    EqualiserRow(
        settings: AppSoundSettings(bundleID: id, displayName: "Player", gainsDB: gains, volume: volume, shapes: shapes),
        isPlaying: true)
}

@MainActor @Suite("Equaliser card")
struct EqualiserCardTests {
    @Test func aStopOffersTryAgainAndASilentOneAlsoSystemSettings() {
        #expect(EqualiserCardActions.stopButtons(for: nil).isEmpty)
        #expect(EqualiserCardActions.stopButtons(for: .silentWhilePlaying(app: "Music"))
            == ["Open System Settings", "Try again"])
        #expect(EqualiserCardActions.stopButtons(for: .repeatedFailures(app: "Music")) == ["Try again"])
        #expect(EqualiserCardActions.stopButtons(for: .startFailed(status: -50)) == ["Try again"])
        let fake = FakeEqualiser()
        EqualiserCardActions(controller: fake).tryAgain()
        #expect(fake.retries == 1)
    }

    @Test func theSwitchCallsSetSwitch() {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.setSwitch(true)
        actions.setSwitch(false)
        #expect(fake.switches == [true, false])
    }

    @Test func aBandMoveSendsAClampedAndSnappedGain() throws {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.setBand(of: row(), index: 3, gain: 40)
        actions.setBand(of: row(), index: 4, gain: -1.76)
        let first = try #require(fake.updates.first)
        let second = try #require(fake.updates.last)
        #expect(first.gainsDB[3] == 12)
        #expect(first.gainsDB.enumerated().allSatisfy { $0.offset == 3 || $0.element == 0 })
        #expect(second.gainsDB[4] == -2)
        #expect(first.bundleID == "com.example.player")
    }

    @Test func aBandMoveOutsideTheTenBandsIsIgnored() {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.setBand(of: row(), index: 10, gain: 3)
        actions.setBand(of: row(), index: -1, gain: 3)
        #expect(fake.updates.isEmpty)
    }

    @Test func theShapeSwitchAndVolumeKeepTheGains() throws {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        let gains: [Double] = [3, 2, 1, 0, 0, 0, 0, 0, 0, -1]
        actions.setShapes(of: row(gains: gains, shapes: false), on: true)
        actions.setVolume(of: row(gains: gains), percent: 60)
        actions.setVolume(of: row(gains: gains), percent: 250)
        #expect(fake.updates.count == 3)
        #expect(fake.updates[0].shapes)
        #expect(fake.updates[0].gainsDB == gains)
        #expect(abs(fake.updates[1].volume - 0.6) < 0.0001)
        #expect(fake.updates[2].volume == 1)
    }

    @Test func aPresetSetsItsTenGainsAndLeavesTheRest() throws {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.applyPreset(.moreBass, to: row(volume: 0.5))
        let update = try #require(fake.updates.first)
        #expect(update.gainsDB == EqualiserPreset.moreBass.gains)
        #expect(update.volume == 0.5)
        #expect(update.shapes)
    }

    @Test func resetToFlatZeroesTheGainsOnly() throws {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.resetToFlat(row(gains: [4, 3, 2, 0, 0, 0, 0, 0, 0, 0], volume: 0.8))
        let update = try #require(fake.updates.first)
        #expect(update.gainsDB.allSatisfy { $0 == 0 })
        #expect(update.volume == 0.8)
    }

    @Test func forgetCallsForgetWithTheBundleID() {
        let fake = FakeEqualiser()
        let actions = EqualiserCardActions(controller: fake)
        actions.forget(row("com.example.other"))
        #expect(fake.forgotten == ["com.example.other"])
    }

    @Test func aSnapshotShowsTheSampleAndNeverTouchesTheController() {
        let fake = FakeEqualiser()
        let shown = EqualiserCardActions.shownStatus(controller: fake, isSnapshot: true)
        #expect(shown == EqualiserStatus.snapshotSample)
        #expect(fake.statusReads == 0)
        #expect(fake.switches.isEmpty && fake.updates.isEmpty && fake.forgotten.isEmpty && fake.retries == 0)
    }

    @Test func outsideASnapshotTheControllerStatusShows() {
        let fake = FakeEqualiser()
        #expect(EqualiserCardActions.shownStatus(controller: fake, isSnapshot: false) == fake.stored)
        #expect(EqualiserCardActions.shownStatus(controller: nil, isSnapshot: false).rows.isEmpty)
    }

    @Test func theCardWordsCarryNoDash() {
        let words = EqualiserCardActions.allWords + EqualiserExclusion.allCases.map(\.label)
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") })
    }
}
