import Foundation
import Testing
@testable import ZeusCore

@Suite("Lock surface")
struct LockSurfaceTests {
    private let display = LockDisplay(
        id: "built-in",
        frame: LockRect(x: 0, y: 0, width: 1440, height: 900),
        scale: 2
    )
    private let full = LockLayoutScene(isEmpty: false, showsClock: false, card: .full(lyric: false))
    private let visible = LockPresenceInput(lockSurfaceMayShow: true)
    private let hide = LockPresenceInput(lockSurfaceMayShow: false)
    private let cleanMarker = LockMarker(bootID: "boot-a", osBuild: "25A362", failedStep: nil)

    @Test func offIgnoresWorkAndDoesNotLoadSymbols() {
        var state = LockSurface.State()
        let events: [LockSurface.Event] = [
            .presence(visible),
            .scene(full),
            .display(display),
            .symbolsLoaded(missing: []),
            .symbolsLoaded(missing: ["WindowSpaceCreate"]),
            .opened(1, failedStep: nil),
            .opened(1, failedStep: "windowNumber"),
            .closed(1, failedStep: nil),
            .closed(1, failedStep: "leftover"),
            .turnOnAgain,
            .willQuit,
            .enabled(false),
            .launched(enabled: false, marker: nil, osMajor: 26, bootID: "boot-a", osBuild: "25A362"),
        ]
        for event in events {
            let (next, effects) = LockSurface.reduce(state, event)
            #expect(effects == [])
            #expect(next.phase == .off)
            #expect(next.awaitingSymbols == false)
            state = next
        }
    }

    @Test func aMarkerAtLaunchStopsBeforeAnySymbolLoad() {
        let same = launched(marker: cleanMarker)
        #expect(same.effects == [])
        #expect(same.state.phase == .stopped(.problemLastTime))

        let unreadable = launched(marker: LockMarker(bootID: "", osBuild: "25A362", failedStep: nil))
        #expect(unreadable.effects == [])
        #expect(unreadable.state.phase == .stopped(.problemLastTime))

        let otherBoot = launched(marker: LockMarker(bootID: "boot-b", osBuild: "25A362", failedStep: nil))
        #expect(otherBoot.effects == [])
        #expect(otherBoot.state.phase == .stopped(.restartLastTime))

        let failed = launched(marker: LockMarker(bootID: "boot-b", osBuild: "25A362", failedStep: "attach"))
        #expect(failed.effects == [])
        #expect(failed.state.phase == .stopped(.callFailed(step: "attach")))

        let (stays, effects) = LockSurface.reduce(same.state, .presence(visible))
        #expect(effects == [])
        #expect(stays.phase == .stopped(.problemLastTime))
    }

    @Test func onlyTurnOnAgainLeavesAStop() {
        let stopped = launched(marker: cleanMarker).state
        let (ignored, noEffects) = LockSurface.reduce(stopped, .enabled(true))
        #expect(noEffects == [])
        #expect(ignored.phase == .stopped(.problemLastTime))

        let (loading, effects) = LockSurface.reduce(stopped, .turnOnAgain)
        #expect(effects == [.clearMarker, .loadSymbols])
        #expect(loading.phase == .off)
        #expect(loading.awaitingSymbols == true)
        let (ready, loaded) = LockSurface.reduce(loading, .symbolsLoaded(missing: []))
        #expect(loaded == [])
        #expect(ready.phase == .ready)

        let (stillReady, again) = LockSurface.reduce(ready, .turnOnAgain)
        #expect(again == [])
        #expect(stillReady.phase == .ready)
    }

    @Test func turnOnAgainOnAnUntestedMajorClearsTheMarkerAndLoadsNothing() {
        let stopped = launched(major: 14, marker: cleanMarker).state
        #expect(stopped.phase == .stopped(.problemLastTime))
        let (next, effects) = LockSurface.reduce(stopped, .turnOnAgain)
        #expect(effects == [.clearMarker])
        #expect(next.phase == .unavailable(.untestedSystem(14)))
        #expect(next.awaitingSymbols == false)
    }

    @Test func aMissingSymbolIsUnavailable() {
        let booted = launched()
        #expect(booted.effects == [.loadSymbols])
        let (next, effects) = LockSurface.reduce(booted.state, .symbolsLoaded(missing: ["WindowSpaceCreate"]))
        #expect(effects == [])
        #expect(next.phase == .unavailable(.missingSymbols(["WindowSpaceCreate"])))
        let (later, more) = LockSurface.reduce(next, .presence(visible))
        #expect(more == [])
        #expect(later.phase == .unavailable(.missingSymbols(["WindowSpaceCreate"])))
    }

    @Test(arguments: [14, 15, 28])
    func anUntestedMajorLoadsNoSymbols(_ major: Int) {
        let booted = launched(major: major)
        #expect(booted.effects == [])
        #expect(booted.state.phase == .unavailable(.untestedSystem(major)))
        #expect(booted.state.awaitingSymbols == false)
    }

    @Test(arguments: [26, 27])
    func aCheckedMajorAsksForSymbols(_ major: Int) {
        let booted = launched(major: major)
        #expect(booted.effects == [.loadSymbols])
        #expect(booted.state.awaitingSymbols == true)
        #expect(booted.state.phase == .off)
    }

    @Test func symbolsArriveReadyAndAStrayLoadIsIgnored() {
        let (ready, effects) = LockSurface.reduce(launched().state, .symbolsLoaded(missing: []))
        #expect(effects == [])
        #expect(ready.phase == .ready)
        let (same, more) = LockSurface.reduce(ready, .symbolsLoaded(missing: ["WindowSpaceCreate"]))
        #expect(more == [])
        #expect(same.phase == .ready)
    }

    @Test func aLockWithASceneWritesTheMarkerBeforeItOpens() {
        let (state, effects) = show()
        let frame = LockLayout.frame(display: display, scene: full)
        #expect(effects == [
            .writeMarker(cleanMarker),
            .open(generation: 1, frame: frame!, scene: full),
        ])
        #expect(state.phase == .opening(1))
        #expect(state.nextGeneration == 2)
    }

    @Test func inputsThatArriveBeforeSymbolsOpenWhenTheSymbolsDo() {
        var state = launched().state
        state = LockSurface.reduce(state, .display(display)).0
        state = LockSurface.reduce(state, .scene(full)).0
        let (waiting, held) = LockSurface.reduce(state, .presence(visible))
        #expect(held == [])
        #expect(waiting.phase == .off)
        let (opening, effects) = LockSurface.reduce(waiting, .symbolsLoaded(missing: []))
        let frame = LockLayout.frame(display: display, scene: full)
        #expect(effects == [
            .writeMarker(cleanMarker),
            .open(generation: 1, frame: frame!, scene: full),
        ])
        #expect(opening.phase == .opening(1))
    }

    @Test func aSecondLockWhileOpenEmitsNothing() {
        let open = openedSurface()
        let (next, effects) = LockSurface.reduce(open, .presence(visible))
        #expect(effects == [])
        #expect(next.phase == .open(1))
        #expect(next.nextGeneration == 2)
    }

    @Test func hidingTheSessionOrTheSceneCloses() {
        let (hidden, hideEffects) = LockSurface.reduce(openedSurface(), .presence(hide))
        #expect(hideEffects == [.close(generation: 1)])
        #expect(hidden.phase == .closing(1))
        let (empty, effects) = LockSurface.reduce(openedSurface(), .scene(.empty))
        #expect(effects == [.close(generation: 1)])
        #expect(empty.phase == .closing(1))
        let blank = LockLayoutScene(isEmpty: false, showsClock: false, card: nil)
        let (noRows, noRowEffects) = LockSurface.reduce(openedSurface(), .scene(blank))
        #expect(noRowEffects == [.close(generation: 1)])
        #expect(noRows.phase == .closing(1))
    }

    @Test func lockThenUnlockThenLockUsesTwoGenerationsAndIgnoresTheFirstWindow() {
        let first = openedSurface()
        let (closing, closeEffects) = LockSurface.reduce(first, .presence(hide))
        #expect(closeEffects == [.close(generation: 1)])
        let (ready, cleared) = LockSurface.reduce(closing, .closed(1, failedStep: nil))
        #expect(cleared == [.clearMarker])
        #expect(ready.phase == .ready)
        #expect(ready.nextGeneration == 2)

        let (second, openEffects) = LockSurface.reduce(ready, .presence(visible))
        let frame = LockLayout.frame(display: display, scene: full)
        #expect(openEffects == [
            .writeMarker(cleanMarker),
            .open(generation: 2, frame: frame!, scene: full),
        ])
        #expect(second.phase == .opening(2))
        #expect(second.nextGeneration == 3)

        let (ignoredOpen, openLate) = LockSurface.reduce(second, .opened(1, failedStep: nil))
        #expect(openLate == [])
        #expect(ignoredOpen.phase == .opening(2))
        let (ignoredClose, closeLate) = LockSurface.reduce(ignoredOpen, .closed(1, failedStep: nil))
        #expect(closeLate == [])
        #expect(ignoredClose.phase == .opening(2))

        let (live, opened) = LockSurface.reduce(ignoredClose, .opened(2, failedStep: nil))
        #expect(opened == [])
        #expect(live.phase == .open(2))
        let (still, lateAgain) = LockSurface.reduce(live, .closed(1, failedStep: "leftover"))
        #expect(lateAgain == [])
        #expect(still.phase == .open(2))
    }

    @Test func aFailedOpenStopsKeepsTheMarkerAndDoesNotRetry() {
        let (opening, _) = show()
        let (stopped, effects) = LockSurface.reduce(opening, .opened(1, failedStep: "attach"))
        #expect(effects == [
            .close(generation: 1),
            .writeMarker(LockMarker(bootID: "boot-a", osBuild: "25A362", failedStep: "attach")),
        ])
        #expect(stopped.phase == .stopped(.callFailed(step: "attach")))
        let (again, more) = LockSurface.reduce(stopped, .presence(visible))
        #expect(more == [])
        #expect(again.phase == .stopped(.callFailed(step: "attach")))
        let (still, scene) = LockSurface.reduce(again, .scene(full))
        #expect(scene == [])
        #expect(still.phase == .stopped(.callFailed(step: "attach")))
    }

    @Test func aFailedCloseStopsAndDoesNotOpenAgain() {
        let (closing, _) = LockSurface.reduce(openedSurface(), .presence(hide))
        let (stopped, effects) = LockSurface.reduce(closing, .closed(1, failedStep: "destroy"))
        #expect(effects == [
            .close(generation: 1),
            .writeMarker(LockMarker(bootID: "boot-a", osBuild: "25A362", failedStep: "destroy")),
        ])
        #expect(stopped.phase == .stopped(.callFailed(step: "destroy")))
        let (again, more) = LockSurface.reduce(stopped, .presence(visible))
        #expect(more == [])
        #expect(again.phase == .stopped(.callFailed(step: "destroy")))
    }

    @Test func anOpenThatArrivesWhileClosingChangesNothing() {
        let (opening, _) = show()
        let (closing, _) = LockSurface.reduce(opening, .presence(hide))
        let (next, effects) = LockSurface.reduce(closing, .opened(1, failedStep: nil))
        #expect(effects == [])
        #expect(next.phase == .closing(1))
    }

    @Test func aSceneChangeRedrawsWithoutOpeningAgain() {
        let clock = LockLayoutScene(isEmpty: false, showsClock: true, card: nil)
        let (next, effects) = LockSurface.reduce(openedSurface(), .scene(clock))
        let frame = LockLayout.frame(display: display, scene: clock)
        #expect(effects == [.redraw(clock), .move(frame!)])
        #expect(next.phase == .open(1))
        #expect(effects.contains { if case .open = $0 { true } else { false } } == false)
    }

    @Test func aDisplayChangeMovesAndAFrameThatDoesNotFitCloses() {
        let external = LockDisplay(id: "external", frame: LockRect(x: 1920, y: 0, width: 2560, height: 1440), scale: 1)
        let (moved, move) = LockSurface.reduce(openedSurface(), .display(external))
        let frame = LockLayout.frame(display: external, scene: full)
        #expect(move == [.move(frame!)])
        #expect(moved.phase == .open(1))

        var sameGeometry = display
        sameGeometry.scale = 1
        let (kept, none) = LockSurface.reduce(openedSurface(), .display(sameGeometry))
        #expect(none == [])
        #expect(kept.phase == .open(1))

        let tiny = LockDisplay(id: "tiny", frame: LockRect(x: 0, y: 0, width: 1440, height: 200), scale: 2)
        let (closing, effects) = LockSurface.reduce(openedSurface(), .display(tiny))
        #expect(effects == [.close(generation: 1)])
        #expect(closing.phase == .closing(1))
        let (noDisplay, closed) = LockSurface.reduce(openedSurface(), .display(nil))
        #expect(closed == [.close(generation: 1)])
        #expect(noDisplay.phase == .closing(1))
    }

    @Test func switchingOffClosesThenClearsTheMarkerAndEndsOff() {
        let (closing, effects) = LockSurface.reduce(openedSurface(), .enabled(false))
        #expect(effects == [.close(generation: 1)])
        #expect(closing.phase == .closing(1))
        #expect(closing.enabled == false)
        #expect(closing.nextGeneration == 2)
        let (done, cleared) = LockSurface.reduce(closing, .closed(1, failedStep: nil))
        #expect(cleared == [.clearMarker])
        #expect(done.phase == .off)
        #expect(done.nextGeneration == 2)

        let (idle, none) = LockSurface.reduce(readySurface(), .enabled(false))
        #expect(none == [])
        #expect(idle.phase == .off)
    }

    @Test func quitClosesThenClearsTheMarker() {
        let (done, effects) = LockSurface.reduce(openedSurface(), .willQuit)
        #expect(effects == [.close(generation: 1), .clearMarker])
        #expect(done.phase == .off)
        #expect(done.enabled == false)
        let (late, ignored) = LockSurface.reduce(done, .opened(1, failedStep: nil))
        #expect(ignored == [])
        #expect(late.phase == .off)
    }

    @Test func aReadySurfaceWithNoFrameStaysDown() {
        var state = readySurface()
        state = LockSurface.reduce(state, .scene(full)).0
        state = LockSurface.reduce(state, .presence(visible)).0
        let (next, effects) = LockSurface.reduce(state, .display(nil))
        #expect(effects == [])
        #expect(next.phase == .ready)
        let short = LockDisplay(id: "short", frame: LockRect(x: 0, y: 0, width: 1440, height: 200), scale: 2)
        let (still, more) = LockSurface.reduce(next, .display(short))
        #expect(more == [])
        #expect(still.phase == .ready)
    }

    private func launched(major: Int = 26, marker: LockMarker? = nil) -> (state: LockSurface.State, effects: [LockSurface.Effect]) {
        LockSurface.reduce(
            .init(),
            .launched(enabled: true, marker: marker, osMajor: major, bootID: "boot-a", osBuild: "25A362")
        )
    }

    private func readySurface() -> LockSurface.State {
        let (state, effects) = LockSurface.reduce(launched().state, .symbolsLoaded(missing: []))
        #expect(effects == [])
        #expect(state.phase == .ready)
        return state
    }

    private func show() -> (LockSurface.State, [LockSurface.Effect]) {
        var state = readySurface()
        state = LockSurface.reduce(state, .display(display)).0
        state = LockSurface.reduce(state, .scene(full)).0
        return LockSurface.reduce(state, .presence(visible))
    }

    private func openedSurface() -> LockSurface.State {
        let (opening, effects) = show()
        #expect(effects.count == 2)
        let (open, opened) = LockSurface.reduce(opening, .opened(1, failedStep: nil))
        #expect(opened == [])
        #expect(open.phase == .open(1))
        return open
    }
}
