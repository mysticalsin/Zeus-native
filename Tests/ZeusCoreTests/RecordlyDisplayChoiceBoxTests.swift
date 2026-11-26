import Foundation
import Testing
@testable import ZeusCore

/// Display choice as plain numbers. The caller supplies the list. The type does not read a screen,
/// a pointer, or a clock.
@Suite("Recordly display choice box")
struct RecordlyDisplayChoiceBoxTests {
    private func choice(_ id: UInt32, stableID: String? = nil, isMain: Bool = false) -> RecordlyDisplayChoiceBox.Choice {
        .init(id: id, stableID: stableID, isMain: isMain)
    }

    private func frame(_ id: UInt32, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> RecordlyDisplayChoiceBox.Frame {
        .init(id: id, x: x, y: y, width: width, height: height)
    }

    @Test func theCurrentDisplayWinsWhenItIsStillConnected() {
        let decision = RecordlyDisplayChoiceBox.decide(
            displays: [choice(7, stableID: "UUID-LG"), choice(1, stableID: "UUID-BUILTIN", isMain: true)],
            current: 7,
            remembered: "UUID-BUILTIN")
        #expect(decision.selected == 7)
        #expect(decision.source == .current)
        #expect(!decision.lostCurrent)
    }

    @Test func aMissingCurrentFallsThroughToTheRememberedIdentity() {
        let decision = RecordlyDisplayChoiceBox.decide(
            displays: [choice(1, stableID: "UUID-BUILTIN", isMain: true), choice(42, stableID: "UUID-LG")],
            current: 7,
            remembered: "UUID-LG")
        #expect(decision.selected == 42)
        #expect(decision.source == .remembered)
        #expect(decision.lostCurrent)
    }

    @Test func anEmptyRememberedStringIsNotAnIdentity() {
        let blank = RecordlyDisplayChoiceBox.decide(
            displays: [choice(4, stableID: "")],
            current: nil,
            remembered: "")
        #expect(blank.selected == 4)
        #expect(blank.source == .firstAvailable)
        #expect(!blank.lostCurrent)

        let spaces = RecordlyDisplayChoiceBox.decide(
            displays: [choice(8, stableID: "UUID-BUILTIN", isMain: true)],
            current: nil,
            remembered: "   ")
        #expect(spaces.selected == 8)
        #expect(spaces.source == .main)
        #expect(!spaces.lostCurrent)
    }

    @Test func aLostCurrentFallsBackToTheFirstMain() {
        let decision = RecordlyDisplayChoiceBox.decide(
            displays: [choice(2, isMain: true), choice(3, isMain: true)],
            current: 9,
            remembered: nil)
        #expect(decision.selected == 2)
        #expect(decision.source == .main)
        #expect(decision.lostCurrent)
    }

    @Test func theFirstDisplayIsUsedWhenNoneIsMainAndAnEmptyListSelectsNothing() {
        let first = RecordlyDisplayChoiceBox.decide(
            displays: [choice(9)],
            current: nil,
            remembered: nil)
        #expect(first.selected == 9)
        #expect(first.source == .firstAvailable)
        #expect(!first.lostCurrent)

        let none = RecordlyDisplayChoiceBox.decide(displays: [], current: 7, remembered: "x")
        #expect(none.selected == nil)
        #expect(none.source == .none)
        #expect(none.lostCurrent)
    }

    @Test func aZeroIdIsNeverAChoice() {
        let onlyZero = RecordlyDisplayChoiceBox.decide(
            displays: [choice(0, isMain: true)],
            current: nil,
            remembered: nil)
        #expect(onlyZero.selected == nil)
        #expect(onlyZero.source == .none)
        #expect(!onlyZero.lostCurrent)

        let skipped = RecordlyDisplayChoiceBox.decide(
            displays: [choice(0, isMain: true), choice(3)],
            current: 0,
            remembered: nil)
        #expect(skipped.selected == 3)
        #expect(skipped.source == .firstAvailable)
        #expect(skipped.lostCurrent)
    }

    @Test func labelsTrimTheNameAndNumberABlankOne() {
        #expect(RecordlyDisplayChoiceBox.title(name: "  Built-in Retina Display  ", position: 0) == "Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "  ", position: 1) == "Display 2")
        #expect(RecordlyDisplayChoiceBox.title(name: nil, position: 0) == "Display 1")
        #expect(RecordlyDisplayChoiceBox.compactLine(name: "Built-in Retina Display", position: 0, isMain: true)
            == "Built-in Retina Display, Main")
        #expect(RecordlyDisplayChoiceBox.compactLine(name: "LG UltraFine", position: 1, isMain: false) == "LG UltraFine")
        #expect(RecordlyDisplayChoiceBox.spokenLabel(
            name: "Built-in Retina Display", position: 0, width: 1512, height: 982, isMain: true)
            == "Built-in Retina Display, 1512 \u{00D7} 982, main display")
        #expect(RecordlyDisplayChoiceBox.spokenLabel(
            name: "LG UltraFine", position: 1, width: 2560, height: 1440, isMain: false)
            == "LG UltraFine, 2560 \u{00D7} 1440")
    }

    @Test func sizeRoundsHalfAwayFromZero() {
        #expect(RecordlyDisplayChoiceBox.size(width: 1512.5, height: 981.4) == "1513 \u{00D7} 981")
        #expect(RecordlyDisplayChoiceBox.size(width: 0.5, height: -0.5) == "1 \u{00D7} -1")
    }

    @Test func arrangementKeepsOneScaleAndTheRelativePosition() {
        let tiles = RecordlyDisplayChoiceBox.arrangement(
            displays: [
                frame(1, 0, 0, 1512, 982),
                frame(7, 1512, -400, 2560, 1440),
            ],
            boundsWidth: 400,
            boundsHeight: 120,
            gap: 0)
        #expect(tiles.count == 2)
        guard tiles.count == 2 else { return }
        let builtIn = tiles[0].rect
        let external = tiles[1].rect
        #expect(tiles[0].id == 1)
        #expect(tiles[1].id == 7)
        #expect(abs(builtIn.width / builtIn.height - 1512.0 / 982.0) < 0.001)
        #expect(abs(external.width / external.height - 2560.0 / 1440.0) < 0.001)
        #expect(abs(external.width / builtIn.width - 2560.0 / 1512.0) < 0.001)
        #expect(abs(builtIn.x - 30.333333333333343) < 0.001)
        #expect(abs(builtIn.y - 33.33333333333333) < 0.001)
        #expect(abs(builtIn.width - 126) < 0.001)
        #expect(abs(builtIn.height - 81.83333333333333) < 0.001)
        #expect(abs(external.x - 156.33333333333334) < 0.001)
        #expect(abs(external.y - 0) < 0.001)
        #expect(abs(external.width - 213.33333333333331) < 0.001)
        #expect(abs(external.height - 120) < 0.001)
        #expect(external.x >= builtIn.x + builtIn.width - 0.001)
        #expect(external.y < builtIn.y)
        for rect in [builtIn, external] {
            #expect(rect.x >= -0.001 && rect.y >= -0.001)
            #expect(rect.x + rect.width <= 400.001 && rect.y + rect.height <= 120.001)
        }
    }

    @Test func aGapInsetsEachTileAndStopsAtAQuarter() {
        let gapped = RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 128, 64)],
            boundsWidth: 256,
            boundsHeight: 128,
            gap: 8)
        #expect(gapped.count == 1)
        guard gapped.count == 1 else { return }
        #expect(gapped[0].id == 5)
        #expect(gapped[0].rect == .init(x: 4, y: 4, width: 248, height: 120))

        let capped = RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 64, 64)],
            boundsWidth: 64,
            boundsHeight: 64,
            gap: 1000)
        #expect(capped.count == 1)
        guard capped.count == 1 else { return }
        #expect(capped[0].rect == .init(x: 16, y: 16, width: 32, height: 32))
    }

    @Test func oneDisplayIsCentredInTheLeftoverSpace() {
        let wide = RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 128, 64)],
            boundsWidth: 256,
            boundsHeight: 64,
            gap: 0)
        #expect(wide.count == 1)
        guard wide.count == 1 else { return }
        #expect(wide[0].rect == .init(x: 64, y: 0, width: 128, height: 64))

        let tall = RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 64, 128)],
            boundsWidth: 64,
            boundsHeight: 256,
            gap: 0)
        #expect(tall.count == 1)
        guard tall.count == 1 else { return }
        #expect(tall[0].rect == .init(x: 0, y: 64, width: 64, height: 128))
    }

    @Test func negativeOriginsKeepTheirArrangement() {
        let tiles = RecordlyDisplayChoiceBox.arrangement(
            displays: [
                frame(1, -256, -64, 256, 128),
                frame(2, 0, 0, 128, 64),
            ],
            boundsWidth: 384,
            boundsHeight: 128,
            gap: 0)
        #expect(tiles.count == 2)
        guard tiles.count == 2 else { return }
        #expect(tiles[0].id == 1)
        #expect(tiles[0].rect == .init(x: 0, y: 0, width: 256, height: 128))
        #expect(tiles[1].id == 2)
        #expect(tiles[1].rect == .init(x: 256, y: 64, width: 128, height: 64))
    }

    @Test func brokenFramesAndEmptyBoundsDropOut() {
        let tiles = RecordlyDisplayChoiceBox.arrangement(
            displays: [
                frame(0, 0, 0, 10_000, 10_000),
                frame(4, 0, 0, 0, 64),
                frame(6, 0, 0, 64, -8),
                frame(8, .infinity, 0, 64, 64),
                frame(9, 0, 0, .nan, 64),
                frame(5, 0, 0, 64, 64),
            ],
            boundsWidth: 64,
            boundsHeight: 64,
            gap: 0)
        #expect(tiles.count == 1)
        guard tiles.count == 1 else { return }
        #expect(tiles[0].id == 5)
        #expect(tiles[0].rect == .init(x: 0, y: 0, width: 64, height: 64))
        #expect(RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 64, 64)],
            boundsWidth: 0,
            boundsHeight: 64).isEmpty)
        #expect(RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 64, 64)],
            boundsWidth: 64,
            boundsHeight: -1).isEmpty)
        #expect(RecordlyDisplayChoiceBox.arrangement(
            displays: [frame(5, 0, 0, 64, 64)],
            boundsWidth: .nan,
            boundsHeight: 64).isEmpty)
        #expect(RecordlyDisplayChoiceBox.arrangement(
            displays: [],
            boundsWidth: 64,
            boundsHeight: 64).isEmpty)
    }
}
