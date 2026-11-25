import Foundation
import Testing
@testable import ZeusCore

@Suite("Lock layout")
struct LockLayoutTests {
    private let builtIn = LockDisplay(
        id: "built-in",
        frame: LockRect(x: 0, y: 0, width: 1440, height: 900),
        scale: 2
    )
    private let external = LockDisplay(
        id: "external",
        frame: LockRect(x: 1920, y: 0, width: 2560, height: 1440),
        scale: 1
    )
    private let full = LockLayoutScene(isEmpty: false, showsClock: false, card: .full(lyric: false))
    private let clockOnly = LockLayoutScene(isEmpty: false, showsClock: true, card: nil)

    @Test func theCardIsCentredInsideTheBandOnABuiltInAndAnExternalDisplay() {
        let builtInFrame = LockLayout.frame(display: builtIn, scene: full)
        #expect(builtInFrame == LockRect(x: 540, y: 442.25, width: 360, height: 128))
        expectInsideBand(builtInFrame, on: builtIn)

        let externalFrame = LockLayout.frame(display: external, scene: full)
        #expect(externalFrame == LockRect(x: 3020, y: 746, width: 360, height: 128))
        expectInsideBand(externalFrame, on: external)
    }

    @Test func scaleDoesNotChangeThePointFrame() {
        var doubled = builtIn
        doubled.scale = 1
        #expect(LockLayout.frame(display: builtIn, scene: full) == LockLayout.frame(display: doubled, scene: full))
    }

    @Test func aSystemBandIsLeftClear() {
        let band = LockRect(x: 0, y: 400, width: 1440, height: 220)
        let frame = LockLayout.frame(display: builtIn, scene: full, systemBands: [band])
        #expect(frame == LockRect(x: 540, y: 248.5, width: 360, height: 128))
        if let frame {
            #expect(frame.intersects(band) == false)
        }
    }

    @Test func aBandBesideTheCardLeavesTheCentredFrame() {
        let band = LockRect(x: 0, y: 400, width: 100, height: 300)
        #expect(LockLayout.frame(display: builtIn, scene: full, systemBands: [band])
            == LockLayout.frame(display: builtIn, scene: full))
    }

    @Test func aBandThatFillsTheFreeAreaReturnsNil() {
        let band = LockRect(x: 0, y: 200, width: 1440, height: 600)
        #expect(LockLayout.frame(display: builtIn, scene: full, systemBands: [band]) == nil)
    }

    @Test func aShortBandReturnsNilForTheFullCardAndFitsTheClock() {
        let short = LockDisplay(id: "short", frame: LockRect(x: 0, y: 0, width: 1440, height: 200), scale: 2)
        #expect(LockLayout.frame(display: short, scene: full) == nil)
        let clock = LockLayout.frame(display: short, scene: clockOnly)
        #expect(clock == LockRect(x: 540, y: 82.5, width: 360, height: 60))
        expectInsideBand(clock, on: short)
    }

    @Test func aNarrowDisplayReturnsNil() {
        let narrow = LockDisplay(id: "narrow", frame: LockRect(x: 0, y: 0, width: 300, height: 900), scale: 2)
        #expect(LockLayout.frame(display: narrow, scene: full) == nil)
    }

    @Test func clockOnlyAndFullHeightsDiffer() {
        let clockHeight = LockLayout.contentHeight(clockOnly)
        let fullHeight = LockLayout.contentHeight(full)
        let lyric = LockLayoutScene(isEmpty: false, showsClock: true, card: .full(lyric: true))
        #expect(clockHeight == 60)
        #expect(fullHeight == 128)
        #expect(clockHeight != fullHeight)
        #expect(LockLayout.contentHeight(lyric) == 176)
        #expect(LockLayout.frame(display: builtIn, scene: clockOnly)?.height == clockHeight)
        #expect(LockLayout.frame(display: builtIn, scene: full)?.height == fullHeight)
    }

    @Test func anEmptySceneHasNoFrame() {
        let markedEmpty = LockLayoutScene(isEmpty: true, showsClock: true, card: .full(lyric: true))
        let blank = LockLayoutScene(isEmpty: false, showsClock: false, card: nil)
        #expect(LockLayout.contentHeight(markedEmpty) == 0)
        #expect(LockLayout.contentHeight(blank) == 0)
        #expect(LockLayout.frame(display: builtIn, scene: .empty) == nil)
        #expect(LockLayout.frame(display: builtIn, scene: markedEmpty) == nil)
        #expect(LockLayout.frame(display: builtIn, scene: blank) == nil)
    }

    @Test func statusWordsNameTheProblemAndCarryNoDash() {
        #expect(LockStatusText.status(for: .off) == nil)
        #expect(LockStatusText.status(for: .ready) == nil)
        #expect(LockStatusText.status(for: .opening(1)) == nil)
        #expect(LockStatusText.status(for: .open(1)) == nil)
        #expect(LockStatusText.status(for: .closing(1)) == nil)

        let unavailable = LockStatusText.status(for: .unavailable(.untestedSystem(15)))
        let missing = LockStatusText.status(for: .unavailable(.missingSymbols(["SLSSpaceCreate"])))
        #expect(unavailable == LockStatus(word: "Not available on this macOS", symbol: "exclamationmark.triangle", canTurnOnAgain: false))
        #expect(missing == unavailable)

        let problem = LockStatus(word: "Stopped after a problem", symbol: "exclamationmark.triangle", canTurnOnAgain: true)
        #expect(LockStatusText.status(for: .stopped(.problemLastTime)) == problem)
        #expect(LockStatusText.status(for: .stopped(.callFailed(step: "attach"))) == problem)
        #expect(LockStatusText.status(for: .stopped(.restartLastTime))
            == LockStatus(word: "Stopped after a restart", symbol: "exclamationmark.triangle", canTurnOnAgain: true))

        for word in [LockStatusText.unavailable, LockStatusText.problem, LockStatusText.restart, LockStatusText.symbol] {
            #expect(word.contains("\u{2014}") == false)
            #expect(word.contains("\u{2013}") == false)
        }
    }

    @Test @MainActor func aControllerCanTurnOnAgain() {
        let screen = RecordingLockScreen()
        screen.turnOnAgain()
        #expect(screen.requests == 1)
        #expect(screen.status == nil)
    }

    private func expectInsideBand(_ frame: LockRect?, on display: LockDisplay) {
        guard let frame else {
            Issue.record("missing frame")
            return
        }
        let screen = display.frame
        let signInTop = screen.y + screen.height * LockLayout.signInBand
        let clockBottom = screen.y + screen.height - screen.height * LockLayout.clockBand
        #expect(frame.x == screen.x + (screen.width - LockLayout.width) / 2)
        #expect(frame.width == LockLayout.width)
        #expect(frame.y >= signInTop)
        #expect(frame.maxY <= clockBottom)
    }
}

@MainActor
private final class RecordingLockScreen: LockScreenControlling {
    var status: LockStatus?
    private(set) var requests = 0
    func turnOnAgain() { requests += 1 }
}
