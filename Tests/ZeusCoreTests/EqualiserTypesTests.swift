import Foundation
import Testing
@testable import ZeusCore

/// A main-actor fake that conforms to the control protocol. If the protocol were not main-actor isolated, a
/// main-actor controller and this fake could not both conform under Swift 6 (the TYPE-012 class of failure).
@MainActor
private final class FakeEqualiserControl: EqualiserControlling {
    var status = EqualiserStatus(line: "Off. No app is tapped.", symbol: "speaker.slash", rows: [])
    private(set) var switches: [Bool] = []
    private(set) var updates: [AppSoundSettings] = []
    private(set) var forgotten: [String] = []
    private(set) var tries = 0

    func setSwitch(_ on: Bool) { switches.append(on) }
    func update(_ settings: AppSoundSettings) { updates.append(settings) }
    func forget(bundleID: String) { forgotten.append(bundleID) }
    func tryAgain() { tries += 1 }
}

@MainActor @Suite struct EqualiserControlProtocolTests {
    @Test func aMainActorFakeConformsToTheControlProtocol() {
        let fake = FakeEqualiserControl()
        let control: any EqualiserControlling = fake
        control.setSwitch(true)
        control.update(AppSoundSettings(bundleID: "com.apple.Music", displayName: "Music"))
        control.forget(bundleID: "com.apple.Music")
        control.tryAgain()
        #expect(fake.switches == [true])
        #expect(fake.updates.map(\.bundleID) == ["com.apple.Music"])
        #expect(fake.forgotten == ["com.apple.Music"])
        #expect(fake.tries == 1)
        #expect(control.status.rows.isEmpty)
    }
}

struct EqualiserTypesTests {
    private func hasNoDash(_ text: String) -> Bool {
        !text.contains("\u{2014}") && !text.contains("\u{2013}")
    }

    @Test func theFilterKindsAreThePeakAndTheTwoShelves() {
        #expect(BiquadKind.allCases == [.peaking, .lowShelf, .highShelf])
    }

    @Test func parametersDefaultToFlatFullVolumeAndNotBypassed() {
        let flat = EqualiserParameters()
        #expect(EqualiserParameters.bandCount == 10)
        #expect(flat.gainsDB == [Double](repeating: 0, count: 10))
        #expect(flat.volume == 1)
        #expect(flat.bypass == false)
        #expect(flat == EqualiserParameters.flat)
    }

    @Test func parametersKeepWhatTheyAreGiven() {
        var gains = [Double](repeating: 0, count: 10)
        gains[0] = 6
        let parameters = EqualiserParameters(gainsDB: gains, volume: 0.5, bypass: true)
        #expect(parameters.gainsDB[0] == 6)
        #expect(parameters.volume == 0.5)
        #expect(parameters.bypass)
        #expect(parameters != .flat)
    }

    @Test func appSettingsStartFlatFullVolumeAndOff() {
        let settings = AppSoundSettings(bundleID: "com.apple.Music", displayName: "Music")
        #expect(settings.gainsDB == [Double](repeating: 0, count: EqualiserParameters.bandCount))
        #expect(settings.volume == 1)
        #expect(settings.shapes == false)
        #expect(settings.lastUsed == Date(timeIntervalSince1970: 0))
    }

    @Test func appSettingsSurviveAJSONRoundTrip() throws {
        var gains = [Double](repeating: 0, count: 10)
        gains[2] = -3.5
        gains[9] = 4
        let original = AppSoundSettings(
            bundleID: "com.apple.podcasts", displayName: "Podcasts", gainsDB: gains,
            volume: 0.8, shapes: true, lastUsed: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSoundSettings.self, from: data)
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
    }

    @Test func eachExclusionIsDistinctAndCoded() throws {
        #expect(EqualiserExclusion.allCases == [.zeus, .callApp, .sharedEngine, .noBundleID, .otherDevice])
        #expect(Set(EqualiserExclusion.allCases.map(\.rawValue)).count == 5)
        for exclusion in EqualiserExclusion.allCases {
            let data = try JSONEncoder().encode(exclusion)
            #expect(try JSONDecoder().decode(EqualiserExclusion.self, from: data) == exclusion)
        }
    }

    @Test func pausesAndStopsCompareByTheirReason() {
        #expect(EqualiserPause.callRecording == .callRecording)
        #expect(EqualiserPause.callRecording != .zeusCaptures)
        #expect(EqualiserPause.unsupportedOutput(reason: "aggregate") != .unsupportedOutput(reason: "rate"))
        #expect(EqualiserStop.silentWhilePlaying(app: "Music") == .silentWhilePlaying(app: "Music"))
        #expect(EqualiserStop.silentWhilePlaying(app: "Music") != .repeatedFailures(app: "Music"))
        #expect(EqualiserStop.startFailed(status: -50) != .startFailed(status: -51))
    }

    @Test func aRowNamesItsAppAndCarriesItsExclusion() {
        let settings = AppSoundSettings(bundleID: "us.zoom.xos", displayName: "Zoom")
        let row = EqualiserRow(
            settings: settings, isPlaying: true, exclusion: .callApp, exclusionLabel: "Call app: never shaped")
        #expect(row.id == "us.zoom.xos")
        #expect(row.bundleID == "us.zoom.xos")
        #expect(row.displayName == "Zoom")
        #expect(row.isPlaying)
        #expect(row.exclusion == .callApp)
        #expect(row.exclusionLabel == "Call app: never shaped")
        let free = EqualiserRow(settings: settings, isPlaying: false)
        #expect(free.exclusion == nil)
        #expect(free.exclusionLabel == nil)
    }

    @Test func theSnapshotSampleIsAWordWithASymbolAndSomeRows() {
        let sample = EqualiserStatus.snapshotSample
        #expect(!sample.line.isEmpty)
        #expect(!sample.symbol.isEmpty)
        #expect(sample.rows.count >= 2)
        #expect(Set(sample.rows.map(\.id)).count == sample.rows.count)
        #expect(sample.rows.allSatisfy { $0.settings.gainsDB.count == EqualiserParameters.bandCount })
        #expect(sample.rows.allSatisfy { (0...1).contains($0.settings.volume) })
        #expect(sample.rows.contains { $0.isPlaying && $0.settings.shapes })
    }

    @Test func theSnapshotSampleHasNoDashAndNoColourOnlyStatus() {
        let sample = EqualiserStatus.snapshotSample
        #expect(hasNoDash(sample.line))
        #expect(sample.rows.allSatisfy { hasNoDash($0.displayName) && hasNoDash($0.exclusionLabel ?? "") })
        #expect(sample.line.contains { $0.isLetter })
    }
}
