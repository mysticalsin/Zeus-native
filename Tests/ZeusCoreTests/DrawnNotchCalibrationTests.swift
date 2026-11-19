import Foundation
import Testing
@testable import ZeusCore

@Suite("Drawn notch calibration") struct DrawnNotchCalibrationTests {
    typealias Calibration = DrawnNotchCalibration

    private let saved = DrawnNotchShape(width: 200, height: 36, offset: 20)
    private let defaults = DrawnNotchLimits.defaultShape

    private func shape(_ width: Double, _ height: Double, _ offset: Double) -> DrawnNotchShape {
        DrawnNotchShape(width: width, height: height, offset: offset)
    }

    private func adjusting(_ draft: DrawnNotchShape, saved: DrawnNotchShape? = nil) -> Calibration.State {
        .adjusting(draft: draft, saved: saved ?? self.saved)
    }

    private func run(_ events: [Calibration.Event], from start: Calibration.State = .idle) -> (Calibration.State, [Calibration.Effect]) {
        var state = start
        var effects: [Calibration.Effect] = []
        for event in events {
            let step = Calibration.reduce(state, event)
            state = step.0
            effects += step.1
        }
        return (state, effects)
    }

    private func persisted(_ effects: [Calibration.Effect]) -> [DrawnNotchShape] {
        effects.compactMap { if case .persist(let value) = $0 { value } else { nil } }
    }

    // MARK: Begin

    @Test func beginCopiesTheSavedShapeIntoTheDraft() {
        let (state, effects) = Calibration.reduce(.idle, .begin(saved: saved))
        #expect(state == adjusting(saved))
        #expect(effects.isEmpty)
    }

    @Test func beginSanitizesAHostileSavedShape() {
        let (state, _) = Calibration.reduce(.idle, .begin(saved: shape(.nan, 9000, 187)))
        let clean = shape(defaults.width, 44, 185)
        #expect(state == adjusting(clean, saved: clean))
    }

    @Test func aSecondBeginChangesNothing() {
        let draft = shape(250, 40, -60)
        let (state, effects) = Calibration.reduce(adjusting(draft), .begin(saved: defaults))
        #expect(state == adjusting(draft))
        #expect(effects.isEmpty)
    }

    // MARK: Setting a field

    @Test func eachSetClampsAndSnaps() {
        let start = adjusting(saved)
        #expect(Calibration.reduce(start, .setWidth(9000)).0 == adjusting(shape(280, 36, 20)))
        #expect(Calibration.reduce(start, .setWidth(1)).0 == adjusting(shape(140, 36, 20)))
        #expect(Calibration.reduce(start, .setWidth(187)).0 == adjusting(shape(185, 36, 20)))
        #expect(Calibration.reduce(start, .setHeight(99)).0 == adjusting(shape(200, 44, 20)))
        #expect(Calibration.reduce(start, .setHeight(3)).0 == adjusting(shape(200, 30, 20)))
        #expect(Calibration.reduce(start, .setHeight(40.4)).0 == adjusting(shape(200, 40, 20)))
        #expect(Calibration.reduce(start, .setOffset(-9000)).0 == adjusting(shape(200, 36, -400)))
        #expect(Calibration.reduce(start, .setOffset(9000)).0 == adjusting(shape(200, 36, 400)))
        #expect(Calibration.reduce(start, .setOffset(-3)).0 == adjusting(shape(200, 36, -5)))
    }

    @Test func aNonFiniteSetTakesTheDefaultForThatField() {
        let start = adjusting(saved)
        #expect(Calibration.reduce(start, .setWidth(.nan)).0 == adjusting(shape(defaults.width, 36, 20)))
        #expect(Calibration.reduce(start, .setHeight(.infinity)).0 == adjusting(shape(200, defaults.height, 20)))
        #expect(Calibration.reduce(start, .setOffset(-.infinity)).0 == adjusting(shape(200, 36, defaults.offset)))
    }

    @Test func aSetLeavesTheSavedShapeAndEmitsNothing() {
        let (state, effects) = Calibration.reduce(adjusting(saved), .setWidth(250))
        #expect(state == adjusting(shape(250, 36, 20), saved: saved))
        #expect(effects.isEmpty)
    }

    // MARK: Stepping

    @Test func eachStepMovesOneStepOfItsField() {
        let start = adjusting(saved)
        #expect(Calibration.reduce(start, .step(.width, .up)).0 == adjusting(shape(205, 36, 20)))
        #expect(Calibration.reduce(start, .step(.width, .down)).0 == adjusting(shape(195, 36, 20)))
        #expect(Calibration.reduce(start, .step(.height, .up)).0 == adjusting(shape(200, 37, 20)))
        #expect(Calibration.reduce(start, .step(.height, .down)).0 == adjusting(shape(200, 35, 20)))
        #expect(Calibration.reduce(start, .step(.offset, .up)).0 == adjusting(shape(200, 36, 25)))
        #expect(Calibration.reduce(start, .step(.offset, .down)).0 == adjusting(shape(200, 36, 15)))
    }

    @Test func aStepAtAnEndStaysThere() {
        #expect(Calibration.reduce(adjusting(shape(280, 44, 400)), .step(.width, .up)).0 == adjusting(shape(280, 44, 400)))
        #expect(Calibration.reduce(adjusting(shape(280, 44, 400)), .step(.height, .up)).0 == adjusting(shape(280, 44, 400)))
        #expect(Calibration.reduce(adjusting(shape(280, 44, 400)), .step(.offset, .up)).0 == adjusting(shape(280, 44, 400)))
        #expect(Calibration.reduce(adjusting(shape(140, 30, -400)), .step(.width, .down)).0 == adjusting(shape(140, 30, -400)))
        #expect(Calibration.reduce(adjusting(shape(140, 30, -400)), .step(.height, .down)).0 == adjusting(shape(140, 30, -400)))
        #expect(Calibration.reduce(adjusting(shape(140, 30, -400)), .step(.offset, .down)).0 == adjusting(shape(140, 30, -400)))
    }

    @Test func aStepFromAnOffStepDraftLandsOnTheNextStep() {
        // A draft is always sanitized, but a step must still end on the step if it were not.
        #expect(Calibration.reduce(adjusting(shape(201, 36, 20)), .step(.width, .up)).0 == adjusting(shape(205, 36, 20)))
    }

    // MARK: Reset

    @Test func resetReturnsTheDraftToTheDefaultsAndKeepsTheSavedShape() {
        let (state, effects) = Calibration.reduce(adjusting(shape(250, 40, -60)), .reset)
        #expect(state == adjusting(defaults, saved: saved))
        #expect(effects.isEmpty)
    }

    // MARK: Outside adjusting

    @Test func aSetStepOrResetWhileIdleIsIgnored() {
        let events: [Calibration.Event] = [.setWidth(250), .setHeight(40), .setOffset(10), .step(.width, .up),
                                            .step(.offset, .down), .reset]
        for event in events {
            let (state, effects) = Calibration.reduce(.idle, event)
            #expect(state == .idle)
            #expect(effects.isEmpty)
        }
    }

    @Test func doneAndCancelWhileIdleDoNothing() {
        for event in [Calibration.Event.done, .cancel] {
            let (state, effects) = Calibration.reduce(.idle, event)
            #expect(state == .idle)
            #expect(effects.isEmpty)
        }
    }

    // MARK: Done

    @Test func doneWithAChangeSavesTheDraftThenAnnounces() {
        let draft = shape(250, 40, -60)
        let (state, effects) = Calibration.reduce(adjusting(draft), .done)
        #expect(state == .idle)
        #expect(persisted(effects) == [draft])
        #expect(effects.count == 2)
        if case .persist = effects.first {} else { Issue.record("persist comes first") }
        if case .announce(let text) = effects.last { #expect(!text.isEmpty) } else { Issue.record("announce comes last") }
    }

    @Test func doneWithoutAChangeAnnouncesAndSavesNothing() {
        let (state, effects) = Calibration.reduce(adjusting(saved), .done)
        #expect(state == .idle)
        #expect(persisted(effects).isEmpty)
        #expect(effects.count == 1)
        if case .announce(let text) = effects.first { #expect(!text.isEmpty) } else { Issue.record("announce") }
    }

    @Test func doneAfterAChangeAndAnUndoSavesNothing() {
        let (state, effects) = run([.begin(saved: saved), .step(.width, .up), .step(.width, .down), .done])
        #expect(state == .idle)
        #expect(persisted(effects).isEmpty)
    }

    @Test func theTwoDoneAnnouncementsDiffer() {
        let changed = Calibration.reduce(adjusting(shape(250, 40, -60)), .done).1
        let same = Calibration.reduce(adjusting(saved), .done).1
        #expect(changed.last != same.last)
    }

    // MARK: Cancel and surface loss

    @Test func cancelDropsTheDraftWithNoEffect() {
        let (state, effects) = Calibration.reduce(adjusting(shape(250, 40, -60)), .cancel)
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func everySurfaceLossFromAdjustingEndsCalibrationWithoutSaving() {
        #expect(Calibration.SurfaceLoss.allCases.count == 9)
        for loss in Calibration.SurfaceLoss.allCases {
            let (state, effects) = Calibration.reduce(adjusting(shape(250, 40, -60)), .surfaceGone(loss))
            #expect(state == .idle)
            #expect(effects.isEmpty)
        }
    }

    @Test func everySurfaceLossFromIdleDoesNothing() {
        for loss in Calibration.SurfaceLoss.allCases {
            let (state, effects) = Calibration.reduce(.idle, .surfaceGone(loss))
            #expect(state == .idle)
            #expect(effects.isEmpty)
        }
    }

    @Test func theNineLossesAreTheNamedOnes() {
        let names = Calibration.SurfaceLoss.allCases.map(\.rawValue)
        #expect(names == ["pageLeft", "settingsClosed", "settingsMinimised", "appHidden", "pillChosen", "noDisplay",
                          "locked", "sleeping", "sessionResigned"])
    }

    @Test func noPathThroughCancelOrALossEmitsPersist() {
        let edits: [Calibration.Event] = [.begin(saved: saved), .setWidth(250), .setHeight(40), .setOffset(-60),
                                           .step(.width, .up), .reset]
        var enders: [Calibration.Event] = [.cancel]
        enders += Calibration.SurfaceLoss.allCases.map { Calibration.Event.surfaceGone($0) }
        for ender in enders {
            let (_, effects) = run(edits + [ender, .done])
            #expect(persisted(effects).isEmpty)
        }
    }

    @Test func aLossThenBeginStartsFromTheSavedShapeAgain() {
        let (state, _) = run([.begin(saved: saved), .setWidth(250), .surfaceGone(.locked), .begin(saved: saved)])
        #expect(state == adjusting(saved))
    }

    // MARK: Read-only helpers

    @Test func theDraftIsShownWhileAdjustingAndTheSavedShapeOtherwise() {
        let draft = shape(250, 40, -60)
        #expect(Calibration.shown(adjusting(draft), saved: saved) == draft)
        #expect(Calibration.shown(.idle, saved: saved) == saved)
    }

    @Test func theGuideShowsAndPointerOpeningStopsOnlyWhileAdjusting() {
        #expect(Calibration.showsGuide(adjusting(saved)))
        #expect(!Calibration.showsGuide(.idle))
        #expect(!Calibration.allowsOpen(adjusting(saved)))
        #expect(Calibration.allowsOpen(.idle))
    }

    // MARK: Words

    @Test func everyAnnouncementIsFreeOfDashes() {
        var texts: [String] = []
        for start in [adjusting(shape(250, 40, -60)), adjusting(saved)] {
            for case .announce(let text) in Calibration.reduce(start, .done).1 { texts.append(text) }
        }
        for loss in Calibration.SurfaceLoss.allCases { texts.append(loss.rawValue) }
        #expect(!texts.isEmpty)
        for text in texts {
            #expect(!text.contains("\u{2014}"))
            #expect(!text.contains("\u{2013}"))
        }
    }
}
