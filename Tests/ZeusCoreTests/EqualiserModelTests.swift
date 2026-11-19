import Foundation
import Testing
@testable import ZeusCore

private func hasNoDash(_ text: String) -> Bool {
    !text.contains("\u{2014}") && !text.contains("\u{2013}")
}

private func shaped(
    _ id: String,
    name: String? = nil,
    gains: [Double]? = nil,
    volume: Double = 1,
    shapes: Bool = true,
    lastUsed: TimeInterval = 1_700_000_000
) -> AppSoundSettings {
    AppSoundSettings(
        bundleID: id,
        displayName: name ?? id,
        gainsDB: gains ?? [Double](repeating: 0, count: 10),
        volume: volume,
        shapes: shapes,
        lastUsed: Date(timeIntervalSince1970: lastUsed))
}

private func movedGains(_ band: Int = 3, by amount: Double = 3) -> [Double] {
    var gains = [Double](repeating: 0, count: 10)
    gains[band] = amount
    return gains
}

@Suite struct EqualiserBandTests {
    @Test func theStandardTableIsTenOctaveBandsWithShelvesAtTheEnds() {
        let bands = EqualiserBand.standard
        #expect(bands.map(\.frequency) == [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        #expect(bands.first?.kind == .lowShelf)
        #expect(bands.last?.kind == .highShelf)
        #expect(bands.dropFirst().dropLast().allSatisfy { $0.kind == .peaking })
    }

    @Test func peaksUseQOnePointFourOneAndShelvesPointSevenOne() {
        for band in EqualiserBand.standard {
            #expect(band.q == (band.kind == .peaking ? 1.41 : 0.71))
        }
    }

    @Test func theTableMatchesTheFilterLayoutTheKernelUses() {
        let bands = EqualiserBand.standard
        #expect(bands.count == EqualiserParameters.bandCount)
        for (index, band) in bands.enumerated() {
            #expect(band.frequency == EqualiserBandLayout.frequency(at: index, count: bands.count))
            #expect(band.kind == EqualiserBandLayout.kind(at: index, count: bands.count))
            #expect(band.q == EqualiserBandLayout.q(for: band.kind))
        }
    }
}

@Suite struct EqualiserGainTests {
    @Test func theRangeIsPlusOrMinusTwelveInHalfDecibelSteps() {
        #expect(EqualiserGain.range == -12...12)
        #expect(EqualiserGain.step == 0.5)
    }

    @Test func clampingKeepsValuesInRangeAndTurnsNaNIntoZero() {
        #expect(EqualiserGain.clamp(3.2) == 3.2)
        #expect(EqualiserGain.clamp(20) == 12)
        #expect(EqualiserGain.clamp(-20) == -12)
        #expect(EqualiserGain.clamp(.infinity) == 12)
        #expect(EqualiserGain.clamp(-.infinity) == -12)
        #expect(EqualiserGain.clamp(.nan) == 0)
    }

    @Test func spokenValueNamesPlusMinusAndZero() {
        #expect(EqualiserGain.spokenValue(3) == "plus 3 decibels")
        #expect(EqualiserGain.spokenValue(-3) == "minus 3 decibels")
        #expect(EqualiserGain.spokenValue(0) == "0 decibels")
        #expect(EqualiserGain.spokenValue(1) == "plus 1 decibel")
        #expect(EqualiserGain.spokenValue(-1) == "minus 1 decibel")
        #expect(EqualiserGain.spokenValue(0.5) == "plus 0.5 decibels")
        #expect(EqualiserGain.spokenValue(-1.5) == "minus 1.5 decibels")
        #expect(EqualiserGain.spokenValue(20) == "plus 12 decibels")
    }

    @Test func spokenValuesCarryNoDash() {
        for value in stride(from: -12.0, through: 12.0, by: 0.5) {
            #expect(hasNoDash(EqualiserGain.spokenValue(value)))
        }
    }
}

@Suite struct EqualiserPresetTests {
    @Test func theEightPresetsComeInTheDocumentedOrder() {
        #expect(EqualiserPreset.allCases.map(\.title) == [
            "Flat", "More bass", "Less bass", "More treble", "Less treble",
            "Clear voice", "Fuller sound", "Small speakers",
        ])
        #expect(EqualiserPreset.customTitle == "Custom")
    }

    @Test func everyPresetHasTenGainsInsideTheRangeOnTheHalfDecibelGrid() {
        for preset in EqualiserPreset.allCases {
            #expect(preset.gains.count == EqualiserParameters.bandCount)
            for gain in preset.gains {
                #expect(EqualiserGain.range.contains(gain))
                #expect((gain / EqualiserGain.step).rounded() == gain / EqualiserGain.step)
            }
        }
    }

    @Test func flatIsZeroAndNoOtherPresetIsFlatOrARepeat() {
        #expect(EqualiserPreset.flat.gains == [Double](repeating: 0, count: 10))
        let all = EqualiserPreset.allCases
        for (index, preset) in all.enumerated() {
            for other in all[(index + 1)...] {
                #expect(preset.gains != other.gains)
            }
        }
    }

    @Test func bassAndTrebleMoveTheEndsInTheNamedDirection() {
        #expect(EqualiserPreset.moreBass.gains[0] > 0)
        #expect(EqualiserPreset.lessBass.gains[0] < 0)
        #expect(EqualiserPreset.moreTreble.gains[9] > 0)
        #expect(EqualiserPreset.lessTreble.gains[9] < 0)
    }

    @Test func matchingFindsEachPresetAndCustomIsNil() {
        for preset in EqualiserPreset.allCases {
            #expect(EqualiserPreset.matching(preset.gains) == preset)
        }
    }

    @Test func matchingReturnsNilAfterOneBandMoves() {
        for preset in EqualiserPreset.allCases {
            var gains = preset.gains
            gains[4] += EqualiserGain.step
            #expect(EqualiserPreset.matching(gains) == nil)
        }
    }

    @Test func matchingIgnoresRoundingNoiseAndRejectsAWrongCount() {
        var gains = EqualiserPreset.moreBass.gains
        gains[0] += 1e-9
        #expect(EqualiserPreset.matching(gains) == .moreBass)
        #expect(EqualiserPreset.matching([0, 0, 0]) == nil)
        #expect(EqualiserPreset.matching([]) == nil)
    }

    @Test func titlesAndTheCustomLabelCarryNoDash() {
        for preset in EqualiserPreset.allCases {
            #expect(hasNoDash(preset.title))
        }
        #expect(hasNoDash(EqualiserPreset.customTitle))
    }
}

@Suite struct AppSoundSettingsRuleTests {
    @Test func aNewAppIsNeutralBecauseItsSwitchIsOff() {
        #expect(AppSoundSettings(bundleID: "a", displayName: "A").isNeutral)
    }

    @Test func flatAtFullVolumeIsNeutralEvenWithTheSwitchOn() {
        #expect(shaped("a").isNeutral)
    }

    @Test func aMovedBandOrALowerVolumeWithTheSwitchOnIsNotNeutral() {
        #expect(!shaped("a", gains: movedGains()).isNeutral)
        #expect(!shaped("a", volume: 0.8).isNeutral)
        #expect(!shaped("a", volume: 0).isNeutral)
    }

    @Test func theSwitchOffIsNeutralWhateverTheGainsAndVolume() {
        #expect(shaped("a", gains: movedGains(), volume: 0.3, shapes: false).isNeutral)
    }

    @Test func nonFiniteValuesAreJudgedAfterClamping() {
        #expect(shaped("a", volume: .nan).isNeutral)
        #expect(shaped("a", gains: movedGains(2, by: .nan)).isNeutral)
    }

    @Test func clampedKeepsGainsAndVolumeInRange() {
        var gains = [Double](repeating: 0, count: 10)
        gains[0] = 40
        gains[1] = -40
        gains[2] = .nan
        gains[3] = 2.5
        let result = shaped("a", gains: gains, volume: 3).clamped()
        #expect(result.gainsDB == [12, -12, 0, 2.5, 0, 0, 0, 0, 0, 0])
        #expect(result.volume == 1)
        #expect(shaped("a", volume: -2).clamped().volume == 0)
        #expect(shaped("a", volume: .nan).clamped().volume == 1)
    }

    @Test func clampedPadsAShortGainListAndTrimsALongOne() {
        #expect(shaped("a", gains: [1, 2, 3]).clamped().gainsDB == [1, 2, 3, 0, 0, 0, 0, 0, 0, 0])
        let long = [Double](repeating: 1, count: 14)
        #expect(shaped("a", gains: long).clamped().gainsDB == [Double](repeating: 1, count: 10))
    }

    @Test func clampedKeepsTheOtherFields() {
        let original = shaped("com.example.app", name: "Example", volume: 0.5, shapes: true, lastUsed: 1234.5)
        let result = original.clamped()
        #expect(result == original)
    }

    @Test func parametersCarryTheGainsAndVolumeAndBypassWhenTheSwitchIsOff() {
        let on = shaped("a", gains: movedGains(), volume: 0.7).parameters
        #expect(on.gainsDB == movedGains())
        #expect(on.volume == 0.7)
        #expect(on.bypass == false)
        #expect(shaped("a", shapes: false).parameters.bypass == true)
    }
}

@Suite struct AppSoundBookTests {
    private func fullBook(neutral: Set<Int>) -> AppSoundBook {
        var book = AppSoundBook()
        for index in 0..<AppSoundBook.maxApps {
            let gains = neutral.contains(index) ? nil : movedGains(index % 10, by: 3)
            // Later indexes are newer, so index 0 is the oldest entry.
            let result = book.add(shaped("app.\(index)", gains: gains, lastUsed: 1_000 + Double(index)))
            #expect(result == .added)
        }
        return book
    }

    @Test func anEmptyBookIsVersionOneAndHoldsNothing() {
        let book = AppSoundBook()
        #expect(AppSoundBook.currentVersion == 1)
        #expect(AppSoundBook.maxApps == 64)
        #expect(book.apps.isEmpty)
        #expect(book.settings(for: "x") == nil)
        #expect(book.parameters(for: "x") == nil)
    }

    @Test func theStorageKeysAreTheRawKeysTheControllerUses() {
        #expect(AppSoundBook.storageKey == "equaliser.apps")
        #expect(AppSoundBook.unreadableKey == "equaliser.apps.unreadable")
    }

    @Test func addingStoresAClampedCopyAndUpdatingReplacesIt() {
        var book = AppSoundBook()
        #expect(book.add(shaped("a", gains: movedGains(0, by: 99), volume: 5)) == .added)
        #expect(book.settings(for: "a")?.gainsDB[0] == 12)
        #expect(book.settings(for: "a")?.volume == 1)
        #expect(book.add(shaped("a", gains: movedGains(1, by: 2))) == .updated)
        #expect(book.apps.count == 1)
        #expect(book.settings(for: "a")?.gainsDB[1] == 2)
    }

    @Test func parametersForAnAppComeFromItsSavedSettings() {
        var book = AppSoundBook()
        book.add(shaped("a", gains: movedGains(), volume: 0.6))
        let parameters = book.parameters(for: "a")
        #expect(parameters?.gainsDB == movedGains())
        #expect(parameters?.volume == 0.6)
        #expect(parameters?.bypass == false)
        #expect(book.parameters(for: "missing") == nil)
    }

    @Test func removingForgetsAnApp() {
        var book = AppSoundBook()
        book.add(shaped("a"))
        book.add(shaped("b"))
        book.remove(bundleID: "a")
        #expect(book.apps.keys.sorted() == ["b"])
        book.remove(bundleID: "never-saved")
        #expect(book.apps.count == 1)
    }

    @Test func aBookRoundTripsThroughItsEncoding() throws {
        var book = AppSoundBook()
        book.add(shaped("com.apple.Music", name: "Music", gains: EqualiserPreset.moreBass.gains, volume: 0.8,
                        lastUsed: 1_700_000_000.25))
        book.add(shaped("com.spotify.client", name: "Spotify", shapes: false, lastUsed: 1_700_000_100))
        let data = try book.encode()
        let decoded = AppSoundBook.decode(data)
        #expect(decoded.failed == false)
        #expect(decoded.book == book)
    }

    @Test func encodingTheSameBookTwiceGivesTheSameBytes() throws {
        var book = AppSoundBook()
        for id in ["c", "a", "b"] { book.add(shaped(id)) }
        #expect(try book.encode() == book.encode())
    }

    @Test func noDataIsAnEmptyBookAndNotAFailure() {
        let decoded = AppSoundBook.decode(nil)
        #expect(decoded.book.apps.isEmpty)
        #expect(decoded.failed == false)
    }

    @Test func anEmptyBookRoundTripsWithoutFailing() throws {
        let decoded = AppSoundBook.decode(try AppSoundBook().encode())
        #expect(decoded.book.apps.isEmpty)
        #expect(decoded.failed == false)
    }

    @Test func corruptJSONGivesAnEmptyBookAndFailed() {
        for text in ["", "not json", "{", "[]", "{\"version\":1}", "{\"version\":1,\"apps\":5}"] {
            let decoded = AppSoundBook.decode(Data(text.utf8))
            #expect(decoded.book.apps.isEmpty, "\(text)")
            #expect(decoded.failed, "\(text)")
        }
    }

    private func mutatedBook(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var book = AppSoundBook()
        book.add(shaped("com.apple.Music", name: "Music", gains: movedGains()))
        let data = try book.encode()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func aWrongGainCountFails() throws {
        for count in [0, 9, 11] {
            let data = try mutatedBook { object in
                var apps = object["apps"] as? [[String: Any]] ?? []
                apps[0]["gainsDB"] = [Double](repeating: 1, count: count)
                object["apps"] = apps
            }
            let decoded = AppSoundBook.decode(data)
            #expect(decoded.failed, "count \(count)")
            #expect(decoded.book.apps.isEmpty)
        }
    }

    @Test func aFutureOrUnknownVersionFails() throws {
        for version in [0, 2, 99] {
            let data = try mutatedBook { $0["version"] = version }
            let decoded = AppSoundBook.decode(data)
            #expect(decoded.failed, "version \(version)")
            #expect(decoded.book.apps.isEmpty)
        }
    }

    @Test func aFutureVersionWithAnUnknownShapeFails() {
        let decoded = AppSoundBook.decode(Data("{\"version\":2,\"apps\":{\"x\":{}}}".utf8))
        #expect(decoded.failed)
        #expect(decoded.book.apps.isEmpty)
    }

    @Test func aRepeatedBundleIdOrTooManyAppsFailRatherThanLoseData() throws {
        let duplicate = try mutatedBook { object in
            let apps = object["apps"] as? [[String: Any]] ?? []
            object["apps"] = apps + apps
        }
        #expect(AppSoundBook.decode(duplicate).failed)

        let oversize = try mutatedBook { object in
            let template = (object["apps"] as? [[String: Any]] ?? [])[0]
            object["apps"] = (0...AppSoundBook.maxApps).map { index -> [String: Any] in
                var entry = template
                entry["bundleID"] = "app.\(index)"
                return entry
            }
        }
        let decoded = AppSoundBook.decode(oversize)
        #expect(decoded.failed)
        #expect(decoded.book.apps.isEmpty)
    }

    @Test func outOfRangeStoredValuesAreClampedNotRefused() throws {
        let data = try mutatedBook { object in
            var apps = object["apps"] as? [[String: Any]] ?? []
            apps[0]["gainsDB"] = [Double](repeating: 50, count: 10)
            apps[0]["volume"] = 7.0
            object["apps"] = apps
        }
        let decoded = AppSoundBook.decode(data)
        #expect(decoded.failed == false)
        #expect(decoded.book.settings(for: "com.apple.Music")?.gainsDB == [Double](repeating: 12, count: 10))
        #expect(decoded.book.settings(for: "com.apple.Music")?.volume == 1)
    }

    @Test func aSixtyFifthAppDropsTheOldestNeutralEntry() {
        var book = fullBook(neutral: [5, 9, 20])
        #expect(book.apps.count == 64)
        let result = book.add(shaped("newcomer", gains: movedGains(), lastUsed: 5_000))
        #expect(result == .added)
        #expect(book.apps.count == 64)
        #expect(book.settings(for: "newcomer") != nil)
        #expect(book.settings(for: "app.5") == nil)
        #expect(book.settings(for: "app.9") != nil)
        #expect(book.settings(for: "app.20") != nil)
        // Every shaped app survives.
        #expect(book.settings(for: "app.0") != nil)
    }

    @Test func theOldestNeutralEntryIsChosenByLastUsedNotByInsertionOrder() {
        var book = AppSoundBook()
        for index in 0..<AppSoundBook.maxApps {
            // Index 7 is neutral and the oldest; index 3 is neutral and newer.
            let neutral = index == 7 || index == 3
            let stamp: TimeInterval = index == 7 ? 10 : 1_000 + Double(index)
            book.add(shaped("app.\(index)", gains: neutral ? nil : movedGains(), lastUsed: stamp))
        }
        book.add(shaped("newcomer", gains: movedGains()))
        #expect(book.settings(for: "app.7") == nil)
        #expect(book.settings(for: "app.3") != nil)
    }

    @Test func aFullBookWithNoNeutralEntryRefusesAndStaysUnchanged() {
        var book = fullBook(neutral: [])
        let before = book
        let result = book.add(shaped("newcomer", gains: movedGains()))
        #expect(result == .full)
        #expect(book == before)
        #expect(book.settings(for: "newcomer") == nil)
    }

    @Test func updatingAnExistingAppInAFullBookNeverDropsAnything() {
        var book = fullBook(neutral: [4])
        let result = book.add(shaped("app.10", gains: movedGains(2, by: 1)))
        #expect(result == .updated)
        #expect(book.apps.count == 64)
        #expect(book.settings(for: "app.4") != nil)
    }

    @Test func theFullMessageIsTheCardCopyWithNoDash() {
        #expect(AppSoundBook.fullMessage == "Too many apps saved. Forget one to add another.")
        #expect(hasNoDash(AppSoundBook.fullMessage))
    }
}

@Suite struct EqualiserListRulesTests {
    private typealias Group = EqualiserPlayingGroup

    @Test func playingAppsComeFirstThenSavedAppsEachByName() {
        var book = AppSoundBook()
        book.add(shaped("saved.zed", name: "Zed player"))
        book.add(shaped("saved.alpha", name: "alpha deck"))
        book.add(shaped("playing.saved", name: "Old name", gains: movedGains()))
        let rows = EqualiserListRules.rows(
            groups: [
                Group(bundleID: "playing.new", displayName: "Notes"),
                Group(bundleID: "playing.saved", displayName: "Music"),
            ],
            book: book,
            exclusions: [:])
        #expect(rows.map(\.bundleID) == ["playing.saved", "playing.new", "saved.alpha", "saved.zed"])
        #expect(rows.map(\.isPlaying) == [true, true, false, false])
    }

    @Test func aPlayingAppThatIsNotSavedGetsFlatDefaultsAndItsPlayingName() {
        let rows = EqualiserListRules.rows(
            groups: [Group(bundleID: "playing.new", displayName: "Notes")],
            book: AppSoundBook(),
            exclusions: [:])
        let row = rows[0]
        #expect(row.displayName == "Notes")
        #expect(row.settings.gainsDB == [Double](repeating: 0, count: 10))
        #expect(row.settings.volume == 1)
        #expect(row.settings.shapes == false)
        #expect(row.exclusion == nil)
        #expect(row.exclusionLabel == nil)
    }

    @Test func aPlayingSavedAppKeepsItsSettingsAndTakesTheCurrentName() {
        var book = AppSoundBook()
        book.add(shaped("a", name: "Old name", gains: movedGains(), volume: 0.4))
        let rows = EqualiserListRules.rows(
            groups: [Group(bundleID: "a", displayName: "New name")], book: book, exclusions: [:])
        #expect(rows[0].displayName == "New name")
        #expect(rows[0].settings.gainsDB == movedGains())
        #expect(rows[0].settings.volume == 0.4)
    }

    @Test func aGroupListedTwiceGivesOneRow() {
        let rows = EqualiserListRules.rows(
            groups: [Group(bundleID: "a", displayName: "A"), Group(bundleID: "a", displayName: "A")],
            book: AppSoundBook(), exclusions: [:])
        #expect(rows.count == 1)
    }

    @Test func equalNamesFallBackToTheBundleIdSoTheOrderIsStable() {
        let groups = [
            Group(bundleID: "b.id", displayName: "Same"),
            Group(bundleID: "a.id", displayName: "same"),
        ]
        let rows = EqualiserListRules.rows(groups: groups, book: AppSoundBook(), exclusions: [:])
        #expect(rows.map(\.bundleID) == ["a.id", "b.id"])
        let reversed = EqualiserListRules.rows(groups: groups.reversed(), book: AppSoundBook(), exclusions: [:])
        #expect(reversed.map(\.bundleID) == rows.map(\.bundleID))
    }

    @Test func excludedPlayingAppsCarryTheirReason() {
        let rows = EqualiserListRules.rows(
            groups: [
                Group(bundleID: "call", displayName: "Call"),
                Group(bundleID: "web", displayName: "Web"),
                Group(bundleID: "far", displayName: "Far"),
                Group(bundleID: "free", displayName: "Free"),
            ],
            book: AppSoundBook(),
            exclusions: ["call": .callApp, "web": .sharedEngine, "far": .otherDevice])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.bundleID, $0) })
        #expect(byID["call"]?.exclusion == .callApp)
        #expect(byID["call"]?.exclusionLabel == "Call app: never shaped")
        #expect(byID["web"]?.exclusionLabel == "Shared web audio: never shaped")
        #expect(byID["far"]?.exclusionLabel == "Plays to another output")
        #expect(byID["free"]?.exclusionLabel == nil)
    }

    @Test func aSavedAppThatIsNotPlayingShowsNoExclusion() {
        var book = AppSoundBook()
        book.add(shaped("quiet"))
        let rows = EqualiserListRules.rows(groups: [], book: book, exclusions: ["quiet": .callApp])
        #expect(rows.count == 1)
        #expect(rows[0].isPlaying == false)
        #expect(rows[0].exclusion == nil)
    }

    @Test func everyExclusionLabelIsWordsWithNoDash() {
        for exclusion in EqualiserExclusion.allCases {
            #expect(!exclusion.label.isEmpty)
            #expect(hasNoDash(exclusion.label))
        }
    }
}
