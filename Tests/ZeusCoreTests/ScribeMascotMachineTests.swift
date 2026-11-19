import Testing
@testable import ZeusCore

@Suite("Scribe Memory mascot machine")
struct ScribeMascotMachineTests {
    /// 0.6 of the lane at 0.3 lane widths a second is two seconds.
    private func walking(from start: Double = 0.1, to target: Double = 0.7, at now: Double = 0) -> ScribeMascot {
        var mascot = ScribeMascot(startX: start)
        mascot.send(.goTo(target), at: now)
        return mascot
    }

    @Test func startsSittingWhereItWasPlacedAndDoesNotAnimate() {
        let mascot = ScribeMascot(startX: 0.2)
        #expect(mascot.mode == .sitting)
        #expect(mascot.x(at: 100) == 0.2)
        #expect(!mascot.isAnimating)
        #expect(mascot.pose == .idle)
    }

    @Test func goToStartsWalkingTowardTheTarget() {
        let mascot = walking()
        #expect(mascot.mode == .walking)
        #expect(mascot.isAnimating)
        #expect(mascot.pose == .walking)
        #expect(mascot.facing == 1)
        #expect(abs(mascot.x(at: 1) - 0.4) < 0.0001)
    }

    @Test func walkingLeftFacesLeft() {
        let mascot = walking(from: 0.8, to: 0.2)
        #expect(mascot.facing == -1)
    }

    @Test func goToTheSamePlaceKeepsSitting() {
        var mascot = ScribeMascot(startX: 0.4)
        mascot.send(.goTo(0.4), at: 5)
        #expect(mascot.mode == .sitting)
    }

    @Test func aWalkEndsSittingAtTheTargetOnTick() {
        var mascot = walking()
        #expect(!mascot.needsTick(at: 1.9))
        #expect(mascot.needsTick(at: 2.01))
        mascot.send(.tick, at: 2.5)
        #expect(mascot.mode == .sitting)
        #expect(mascot.restX == 0.7)
        #expect(mascot.x(at: 99) == 0.7)
    }

    @Test func anyEventAfterArrivalFindsItSitting() {
        var mascot = walking()
        mascot.send(.hover(0.1), at: 5)
        #expect(mascot.mode == .looking)
        #expect(mascot.restX == 0.7)
    }

    @Test func goToWhileWalkingTurnsAroundFromTheCurrentSpot() {
        var mascot = walking()
        mascot.send(.goTo(0.1), at: 1)
        #expect(mascot.mode == .walking)
        #expect(mascot.facing == -1)
        #expect(abs(mascot.x(at: 1) - 0.4) < 0.0001)
        #expect(abs(mascot.x(at: 2) - 0.1) < 0.0001)
    }

    @Test func hoverStopsAWalkAndLooksTowardTheItem() {
        var mascot = walking()
        mascot.send(.hover(0.1), at: 1)
        #expect(mascot.mode == .looking)
        #expect(mascot.pose == .curious)
        #expect(mascot.facing == -1)
        #expect(abs(mascot.restX - 0.4) < 0.0001)
        #expect(mascot.x(at: 50) == mascot.restX)
    }

    @Test func hoverEndedResumesTheWalkThatWasWaiting() {
        var mascot = walking()
        mascot.send(.hover(0.1), at: 1)
        mascot.send(.hoverEnded, at: 3)
        #expect(mascot.mode == .walking)
        #expect(mascot.facing == 1)
        #expect(abs(mascot.x(at: 3) - 0.4) < 0.0001)
    }

    @Test func hoverEndedSitsWhenNothingWaits() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.hover(0.9), at: 0)
        #expect(mascot.mode == .looking)
        #expect(mascot.facing == 1)
        mascot.send(.hoverEnded, at: 1)
        #expect(mascot.mode == .sitting)
    }

    @Test func movingBetweenItemsKeepsLookingAndTurns() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.hover(0.9), at: 0)
        mascot.send(.hover(0.1), at: 1)
        #expect(mascot.mode == .looking)
        #expect(mascot.facing == -1)
    }

    @Test func goToWhileLookingWaitsForTheHoverToEnd() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.hover(0.9), at: 0)
        mascot.send(.goTo(0.2), at: 1)
        #expect(mascot.mode == .looking)
        mascot.send(.hoverEnded, at: 2)
        #expect(mascot.mode == .walking)
        #expect(mascot.facing == -1)
    }

    @Test func searchingMakesItReadAndStandStill() {
        var mascot = walking()
        mascot.send(.searchStarted, at: 1)
        #expect(mascot.mode == .reading)
        #expect(mascot.pose == .searching)
        #expect(abs(mascot.restX - 0.4) < 0.0001)
        #expect(mascot.isAnimating)
    }

    @Test func readingWinsOverHover() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.searchStarted, at: 0)
        mascot.send(.hover(0.1), at: 1)
        #expect(mascot.mode == .reading)
        mascot.send(.hoverEnded, at: 2)
        #expect(mascot.mode == .reading)
    }

    @Test func searchEndedResumesWhateverIsStillWanted() {
        var mascot = walking()
        mascot.send(.searchStarted, at: 1)
        mascot.send(.searchEnded, at: 4)
        #expect(mascot.mode == .walking)

        var other = ScribeMascot(startX: 0.5)
        other.send(.searchStarted, at: 0)
        other.send(.hover(0.1), at: 1)
        other.send(.searchEnded, at: 2)
        #expect(other.mode == .looking)

        var quiet = ScribeMascot(startX: 0.5)
        quiet.send(.searchStarted, at: 0)
        quiet.send(.searchEnded, at: 1)
        #expect(quiet.mode == .sitting)
    }

    @Test func goToWhileReadingIsWalkedAfterTheSearch() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.searchStarted, at: 0)
        mascot.send(.goTo(0.9), at: 1)
        #expect(mascot.mode == .reading)
        mascot.send(.searchEnded, at: 2)
        #expect(mascot.mode == .walking)
    }

    @Test func theEmptyStateWavesThenSitsAfterAWhile() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.emptyShown, at: 10)
        #expect(mascot.mode == .waving)
        #expect(mascot.pose == .welcome)
        #expect(mascot.isAnimating)
        #expect(!mascot.needsTick(at: 10 + ScribeMascot.wavingSeconds - 0.1))
        #expect(mascot.needsTick(at: 10 + ScribeMascot.wavingSeconds + 0.01))
        mascot.send(.tick, at: 10 + ScribeMascot.wavingSeconds + 0.01)
        #expect(mascot.mode == .sitting)
        #expect(!mascot.isAnimating)
    }

    @Test func tickBeforeTheWaveIsOverChangesNothing() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.emptyShown, at: 0)
        mascot.send(.tick, at: 1)
        #expect(mascot.mode == .waving)
    }

    @Test func leavingTheEmptyStateStopsTheWave() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.emptyShown, at: 0)
        mascot.send(.emptyHidden, at: 1)
        #expect(mascot.mode == .sitting)
    }

    @Test func wavingWinsOverHoverButNotOverReading() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.emptyShown, at: 0)
        mascot.send(.hover(0.1), at: 1)
        #expect(mascot.mode == .waving)
        mascot.send(.searchStarted, at: 2)
        #expect(mascot.mode == .reading)
        mascot.send(.emptyShown, at: 3)
        #expect(mascot.mode == .reading)
    }

    @Test func waveEndsIntoTheHoverThatArrivedDuringIt() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.emptyShown, at: 0)
        mascot.send(.hover(0.9), at: 1)
        mascot.send(.tick, at: 4)
        #expect(mascot.mode == .looking)
    }

    @Test func reduceMotionShowsTheDestinationInAStillPose() {
        let mascot = walking()
        #expect(mascot.stillFrame.x == 0.7)
        #expect(mascot.stillFrame.pose == .idle)
        var reading = ScribeMascot(startX: 0.3)
        reading.send(.searchStarted, at: 0)
        #expect(reading.stillFrame.x == 0.3)
        #expect(reading.stillFrame.pose == .searching)
    }

    @Test func positionsAreClampedToTheLane() {
        var mascot = ScribeMascot(startX: 0.5)
        mascot.send(.goTo(4), at: 0)
        #expect(abs(mascot.x(at: 100) - 1) < 0.0001)
        var nan = ScribeMascot(startX: .nan)
        nan.send(.hover(.infinity), at: 0)
        #expect(nan.restX == 0.5)
    }

    @Test func onlySittingIsStill() {
        let modes: [ScribeMascot.Mode] = [.walking, .looking, .waving, .reading]
        for mode in modes {
            var mascot = ScribeMascot(startX: 0.5)
            switch mode {
            case .walking: mascot.send(.goTo(0.9), at: 0)
            case .looking: mascot.send(.hover(0.9), at: 0)
            case .waving: mascot.send(.emptyShown, at: 0)
            case .reading: mascot.send(.searchStarted, at: 0)
            case .sitting: break
            }
            #expect(mascot.mode == mode)
            #expect(mascot.isAnimating)
        }
    }
}
