import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let utc = TimeZone(identifier: "UTC")!
private let english = Locale(identifier: "en_US")

private func meeting(title: String = "Weekly sync", startsIn: TimeInterval = 120, lasting: TimeInterval? = 2_700,
                     guests: [String] = [], link: URL? = nil) -> ScribeMeeting {
    let start = t0.addingTimeInterval(startsIn)
    let slot = ScribeCalendarSlot(id: "slot", title: title, start: start, end: lasting.map { start.addingTimeInterval($0) },
                                  attendeeNames: guests, hasCallLink: link != nil, callLink: link)
    return ScribeMeeting(key: slot.id, title: title, callApp: .other("Synthetic"), slot: slot)
}

private func bareCall() -> ScribeMeeting {
    ScribeMeeting(key: "call:Synthetic", title: "Synthetic call", callApp: .other("Synthetic"))
}

@Suite("Meeting card design")
struct ScribeMeetingCardDesignTests {
    // MARK: Metrics

    @Test func theSlabIsACompactGlassCardOfThreeHundredAndFortyByNinetySix() {
        typealias M = ScribeMeetingCardMetrics
        #expect(M.width == 340)
        #expect((90...100).contains(M.height))
        #expect(M.height == 96)
        #expect(M.cornerRadius == 22)
        #expect(M.padding == 12)
        #expect(M.orb == 40)
        #expect(M.ringDiameter == 48)
        #expect(M.ringWidth == 2)
        #expect(M.orbSymbolSize == 18)
        #expect(M.tile == 16)
        #expect(M.maxApps == 3)
        #expect((1...1.5).contains(M.rim))
        #expect(M.titleSize == 15)
        #expect(M.pillTextSize == 10)
        #expect(M.pillHeight == 16)
        #expect(M.timeSize == 12)
        #expect(M.detailSize == 11)
        #expect(M.capsuleHeight == 26)
        #expect(M.capsuleLabelSize == 12)
        #expect(M.closeSize == 20)
        #expect(M.shadowRadius == 12)
        #expect(M.shadowY == 6)
    }

    @Test func theOrbColumnIsANarrowSixtyFourAndHoldsTheOrbTheRingAndThreeTiles() {
        typealias M = ScribeMeetingCardMetrics
        #expect(M.leftColumnWidth == 64)
        #expect(M.orb + 2 * M.ringInset <= M.leftColumnWidth)
        let row = CGFloat(M.maxApps) * M.tile + CGFloat(M.maxApps - 1) * M.tileSpacing
        #expect(row <= M.leftColumnWidth)
    }

    @Test func theWindowAddsTheShadowRoomOnEverySideAndTheOrbSitsInTheLeftColumn() {
        typealias M = ScribeMeetingCardMetrics
        #expect(M.shadowRoom == 16)
        #expect(M.windowSize == CGSize(width: M.width + 2 * M.shadowRoom, height: M.height + 2 * M.shadowRoom))
        #expect(M.windowSize == CGSize(width: 372, height: 128))
        let center = M.orbCenter
        #expect(center.x == M.padding + M.leftColumnWidth / 2)
        #expect(center.y > M.orb / 2 && center.y < M.height / 2)
        #expect(center.y - M.ringDiameter / 2 >= M.padding)
    }

    @Test func everyRowAndTheActionCapsuleFitInsideTheSlabForTheTallestState() {
        typealias M = ScribeMeetingCardMetrics
        let inner = M.height - 2 * M.padding
        // The tallest state has a title with a close button, the status row, and a reason beside an action.
        #expect(M.titleRowHeight >= M.closeSize)
        #expect(M.titleRowHeight >= M.titleSize * 1.25, "the title's line fits its row")
        #expect(M.pillHeight >= M.pillTextSize * 1.25)
        #expect(M.statusRowHeight >= M.timeSize * 1.25, "the time text fits the status row")
        #expect(M.capsuleHeight >= M.detailSize * 1.25, "the third line fits beside the capsule")
        #expect(M.capsuleHeight >= M.capsuleLabelSize * 1.25)
        #expect(M.contentHeight == M.titleRowHeight + M.titleGap + M.statusRowHeight + M.bottomGap + M.capsuleHeight)
        #expect(M.contentHeight <= inner, "title, status and capsule rows fit the \(inner) pt inside the padding")
        #expect(M.orbGroupHeight <= inner, "the ring and the tiles fit the same height")
        #expect(M.orbGroupHeight == M.ringDiameter + M.orbTileGap + M.tile)
        let textWidth = M.width - 2 * M.padding - M.leftColumnWidth
        #expect(textWidth >= 240, "the text column keeps room for the status row")
    }

    // MARK: Placement

    @Test func theSlabSitsAnEvenMarginFromTheTopAndRightOfTheVisibleFrame() {
        typealias M = ScribeMeetingCardMetrics
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = ScribeMeetingCardPlacement.windowOrigin(windowSize: M.windowSize, visibleFrame: frame)
        let slabRight = origin.x + M.windowSize.width - M.shadowRoom
        let slabTop = origin.y + M.windowSize.height - M.shadowRoom
        #expect(frame.maxX - slabRight == M.margin)
        #expect(frame.maxY - slabTop == M.margin)
    }

    @Test func thePlacementFollowsAnotherDisplayAndStaysInsideAFrameSmallerThanTheWindow() {
        typealias M = ScribeMeetingCardMetrics
        let frame = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        let origin = ScribeMeetingCardPlacement.windowOrigin(windowSize: M.windowSize, visibleFrame: frame)
        #expect(frame.maxX - (origin.x + M.windowSize.width - M.shadowRoom) == M.margin)
        let tiny = ScribeMeetingCardPlacement.windowOrigin(windowSize: M.windowSize,
                                                           visibleFrame: CGRect(x: 10, y: 20, width: 200, height: 50))
        #expect(tiny == CGPoint(x: 10, y: 20))
    }

    // MARK: Pill

    @Test(arguments: [
        (ScribeMeetingCard.offer(meeting(), blocked: nil), "Starting soon"),
        (.offer(meeting(), blocked: .microphoneDenied), "Starting soon"),
        (.next(meeting()), "Starting soon"),
        (.countdown(meeting(), seconds: 5, deadline: 105, total: 5), "Recording in 5"),
        (.countdown(meeting(), seconds: 2, deadline: 102, total: 5), "Recording in 2"),
        (.waiting(meeting()), "Waiting to record"),
        (.starting(meeting(), cancellable: true), "Starting"),
        (.starting(meeting(), cancellable: false), "Starting"),
        (.recording(meeting()), "Recording"),
        (.failed(meeting(), .noResponse), "Not recorded"),
        (.failed(meeting(), .microphoneOff), "Not recorded"),
        (.hidden, ""),
    ])
    func eachStateHasItsPillPhrase(card: ScribeMeetingCard, phrase: String) {
        #expect(ScribeMeetingCardText.pill(card) == phrase)
    }

    /// QA m1: a meeting already under way read "Starting soon" next to its "Now" time.
    @Test func aMeetingThatHasStartedDoesNotSayStartingSoon() {
        let started = ScribeMeetingCard.offer(meeting(startsIn: -30), blocked: nil)
        #expect(ScribeMeetingCardText.pill(started, now: t0) == "Meeting started")
        #expect(ScribeMeetingCardText.pill(.next(meeting(startsIn: 0)), now: t0) == "Meeting started")
        #expect(ScribeMeetingCardText.pill(.offer(meeting(startsIn: 120), blocked: nil), now: t0) == "Starting soon")
        #expect(ScribeMeetingCardText.pill(.offer(meeting(startsIn: -30), blocked: nil)) == "Starting soon",
                "with no clock the pill keeps its old phrase")
    }

    @Test func theDotColourFollowsTheState() {
        #expect(ScribeMeetingCardText.tone(.offer(meeting(), blocked: nil)) == .soon)
        #expect(ScribeMeetingCardText.tone(.countdown(meeting(), seconds: 3, deadline: 103, total: 5)) == .soon)
        #expect(ScribeMeetingCardText.tone(.starting(meeting(), cancellable: true)) == .soon)
        #expect(ScribeMeetingCardText.tone(.recording(meeting())) == .recording)
        #expect(ScribeMeetingCardText.tone(.failed(meeting(), .noResponse)) == .problem)
    }

    // MARK: Time line

    @Test func theTimeLineHasARangeAndTheRelativeTimeInCapitals() {
        let line = ScribeMeetingCardText.timeLine(meeting(), now: t0, locale: english, timeZone: utc)
        #expect(line.relative == "In 2 min")
        let range = line.range ?? ""
        #expect(range.contains("8:02"))
        #expect(range.contains("8:47"))
        #expect(range.contains(" to "))
    }

    @Test func aMeetingThatHasStartedIsNow() {
        #expect(ScribeMeetingCardText.timeLine(meeting(startsIn: 0), now: t0, locale: english, timeZone: utc).relative == "Now")
        #expect(ScribeMeetingCardText.timeLine(meeting(startsIn: -60), now: t0, locale: english, timeZone: utc).relative == "Now")
    }

    @Test func aMeetingWithNoEndShowsOnlyItsStartAndACallWithNoMeetingHasNoRange() {
        let open = ScribeMeetingCardText.timeLine(meeting(lasting: nil), now: t0, locale: english, timeZone: utc)
        #expect(open.range?.contains("8:02") == true)
        #expect(open.range?.contains(" to ") == false)
        let call = ScribeMeetingCardText.timeLine(bareCall(), now: t0, locale: english, timeZone: utc)
        #expect(call.range == nil)
        #expect(call.relative == "Now")
    }

    @Test func theRelativeTimeRoundsUpLikeTheStatus() {
        #expect(ScribeMeetingCardText.relative(startsAt: t0.addingTimeInterval(61), now: t0) == "In 2 min")
        #expect(ScribeMeetingCardText.relative(startsAt: t0.addingTimeInterval(1), now: t0) == "In 1 min")
    }

    // MARK: Participants and detail

    @Test func participantsAreShownOnlyWhenTheCalendarNamesGuests() {
        #expect(ScribeMeetingCardText.participants(meeting()) == nil)
        #expect(ScribeMeetingCardText.participants(bareCall()) == nil)
        #expect(ScribeMeetingCardText.participants(meeting(guests: ["Ana", "Ben"])) == "3 participants")
        #expect(ScribeMeetingCardText.participants(meeting(guests: ["Ana"])) == "2 participants")
    }

    @Test func theDetailLineCarriesTheReasonOrTheWaitAndNothingElse() {
        let m = meeting()
        #expect(ScribeMeetingCardText.detail(.offer(m, blocked: nil)) == nil)
        #expect(ScribeMeetingCardText.detail(.offer(m, blocked: .notChosen)) == nil)
        #expect(ScribeMeetingCardText.detail(.offer(m, blocked: .microphoneDenied)) == "Microphone is off for Zeus")
        #expect(ScribeMeetingCardText.detail(.failed(m, .stillSaving)) == "Still saving your last meeting")
        #expect(ScribeMeetingCardText.detail(.waiting(m)) == "Starts once your last meeting is saved")
        #expect(ScribeMeetingCardText.detail(.countdown(m, seconds: 5, deadline: 105, total: 5)) == nil)
        #expect(ScribeMeetingCardText.detail(.recording(m)) == nil)
        #expect(ScribeMeetingCardText.detail(.next(m)) == nil)
    }

    // MARK: Join and controls

    @Test func joinNamesTheApp() {
        #expect(ScribeMeetingCardText.join("Synthetic App") == "Join in Synthetic App")
    }

    @Test func aCardJoinsOnlyBeforeTheStartWithALinkAndAnInstalledApp() {
        let link = URL(string: "https://example.org/room")
        let app = ScribeJoinApp(name: "Synthetic App", bundleID: "synthetic.app")
        #expect(ScribeMeetingCardText.canJoin(.offer(meeting(link: link), blocked: nil), apps: [app]))
        #expect(ScribeMeetingCardText.canJoin(.offer(meeting(link: link), blocked: .microphoneDenied), apps: [app]))
        #expect(!ScribeMeetingCardText.canJoin(.offer(meeting(link: link), blocked: nil), apps: []), "no app to open it in")
        #expect(!ScribeMeetingCardText.canJoin(.offer(meeting(), blocked: nil), apps: [app]), "no link")
        #expect(!ScribeMeetingCardText.canJoin(.offer(bareCall(), blocked: nil), apps: [app]), "no calendar meeting")
        #expect(!ScribeMeetingCardText.canJoin(.next(meeting(link: link)), apps: [app]), "Switch stays the action")
        #expect(!ScribeMeetingCardText.canJoin(.failed(meeting(link: link), .noResponse), apps: [app]))
        #expect(!ScribeMeetingCardText.canJoin(.countdown(meeting(link: link), seconds: 3, deadline: 103, total: 5), apps: [app]))
    }

    @Test func theControlsAtRestFollowTheState() {
        let m = meeting()
        #expect(ScribeMeetingCardText.controlsAtRest(.offer(m, blocked: nil), canJoin: false) == [.primary])
        #expect(ScribeMeetingCardText.controlsAtRest(.offer(m, blocked: nil), canJoin: true) == [.primary, .apps])
        #expect(ScribeMeetingCardText.controlsAtRest(.countdown(m, seconds: 4, deadline: 104, total: 5), canJoin: false) == [.cancel])
        #expect(ScribeMeetingCardText.controlsAtRest(.waiting(m), canJoin: false) == [.cancel])
        #expect(ScribeMeetingCardText.controlsAtRest(.starting(m, cancellable: true), canJoin: false) == [.cancel])
        #expect(ScribeMeetingCardText.controlsAtRest(.starting(m, cancellable: false), canJoin: false).isEmpty)
        #expect(ScribeMeetingCardText.controlsAtRest(.recording(m), canJoin: false).isEmpty)
        #expect(ScribeMeetingCardText.controlsAtRest(.failed(m, .noResponse), canJoin: false) == [.primary])
        #expect(ScribeMeetingCardText.controlsAtRest(.next(m), canJoin: false) == [.primary])
        #expect(ScribeMeetingCardText.controlsAtRest(.hidden, canJoin: false).isEmpty)
    }

    @Test func onlyTheCloseButtonAppearsOnHoverAndOnlyWhereTheCardCanBeDismissed() {
        let m = meeting()
        for card in [ScribeMeetingCard.offer(m, blocked: nil), .failed(m, .noResponse), .next(m)] {
            #expect(ScribeMeetingCardText.revealedOnHover(card) == [.dismiss])
        }
        for card in [ScribeMeetingCard.countdown(m, seconds: 4, deadline: 104, total: 5), .waiting(m),
                     .starting(m, cancellable: true), .starting(m, cancellable: false), .recording(m), .hidden] {
            #expect(ScribeMeetingCardText.revealedOnHover(card).isEmpty)
        }
    }

    @Test func everyStateWithAButtonHasASymbolForIt() {
        let m = meeting()
        for card in [ScribeMeetingCard.offer(m, blocked: nil), .failed(m, .microphoneOff), .failed(m, .noResponse), .next(m)] {
            #expect(ScribeMeetingCardText.primarySymbol(card) != nil)
        }
        #expect(ScribeMeetingCardText.primarySymbol(.recording(m)) == nil)
        #expect(ScribeMeetingCardText.cancelSymbol == "xmark")
        #expect(ScribeMeetingCardText.orbSymbol == "calendar")
    }

    // MARK: Words

    @Test func noNewWordHasADashOrAProductName() {
        let m = meeting(guests: ["Ana"])
        var words = ["Starting soon", "Meeting started", "Recording in 5", ScribeMeetingCardText.join("App")]
        for card in [ScribeMeetingCard.offer(m, blocked: nil), .offer(m, blocked: .firstRecordingOwed),
                     .countdown(m, seconds: 5, deadline: 105, total: 5), .waiting(m), .starting(m, cancellable: true),
                     .recording(m), .failed(m, .stillSaving), .next(m)] {
            words.append(ScribeMeetingCardText.pill(card))
            words.append(ScribeMeetingCardText.detail(card) ?? "")
            words.append(ScribeMeetingCardText.primarySymbol(card) ?? "")
        }
        let line = ScribeMeetingCardText.timeLine(m, now: t0, locale: english, timeZone: utc)
        words.append(contentsOf: [line.range ?? "", line.relative, ScribeMeetingCardText.participants(m) ?? "",
                                  ScribeMeetingCardText.orbSymbol, ScribeMeetingCardText.cancelSymbol])
        let banned = ["\u{2014}", "\u{2013}", "-", "Teams", "Zoom", "Webex", "Google", "Microsoft", "Slack", "Scribe"]
        for word in words {
            for item in banned { #expect(!word.contains(item), "\"\(word)\" contains \"\(item)\"") }
        }
    }
}

@Suite("Call link and join apps")
struct ScribeJoinAppsTests {
    private func app(_ id: String) -> ScribeJoinApp { ScribeJoinApp(name: "App \(id)", bundleID: id) }

    @Test func aSlotCarriesItsCallLinkAndDefaultsToNone() {
        let plain = ScribeCalendarSlot(id: "a", title: "A", start: t0)
        #expect(plain.callLink == nil)
        let link = URL(string: "https://example.org/room")
        let linked = ScribeCalendarSlot(id: "a", title: "A", start: t0, hasCallLink: true, callLink: link)
        #expect(linked.callLink == link)
        #expect(linked != plain)
    }

    @Test func eachCallBrandOwnsItsLinkHostsAndSubdomains() {
        let brands = AppBrandCatalog.brands.filter { !$0.linkHosts.isEmpty }
        #expect(brands.count >= 3)
        for brand in brands {
            for host in brand.linkHosts {
                #expect(ScribeJoinApps.providerBrand(for: URL(string: "https://\(host)/j/1")!)?.name == brand.name)
                #expect(ScribeJoinApps.providerBrand(for: URL(string: "https://eu.\(host)/j/1")!)?.name == brand.name)
                #expect(ScribeJoinApps.providerBrand(for: URL(string: "https://not\(host)/j/1")!) == nil, "a look-alike host")
            }
        }
        #expect(ScribeJoinApps.providerBrand(for: URL(string: "https://example.org/x")!) == nil)
        #expect(ScribeJoinApps.providerBrand(for: URL(string: "mailto:a@example.org")!) == nil)
    }

    @Test func theProviderAppComesFirstThenBrowsersWithoutDuplicates() {
        let chosen = ScribeJoinApps.choose(provider: [app("p")], browsers: [app("b1"), app("p"), app("b2")])
        #expect(chosen.map(\.bundleID) == ["p", "b1", "b2"])
    }

    @Test func atMostThreeAppsAreChosen() {
        let chosen = ScribeJoinApps.choose(provider: [app("p")], browsers: (1...6).map { app("b\($0)") })
        #expect(chosen.count == 3)
        #expect(chosen.first?.bundleID == "p")
        #expect(ScribeJoinApps.choose(provider: [], browsers: []).isEmpty)
    }
}
