import Foundation
import Testing
@testable import ZeusCore

@Suite struct AlertStackTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func alert(_ id: String, title: String = "Anna", body: String = "Hi", priority: AlertPriority = .normal, app: String = "com.apple.MobileSMS") -> AlertItem {
        AlertItem(id: id, appID: app, appName: "Messages", title: title, body: body, priority: priority, postedAt: t0)
    }

    @Test func newestAlertIsFirstAndStackShowsAtMostThree() {
        var stack = AlertStack()
        for index in 1...5 { stack.post(alert("a\(index)", title: "T\(index)"), now: t0) }
        #expect(stack.visible.map(\.id) == ["a5", "a4", "a3"])
        #expect(stack.hiddenCount == 2)
    }

    @Test func identicalAlertsWithinFiveSecondsCoalesce() {
        var stack = AlertStack()
        #expect(stack.post(alert("a"), now: t0) == .added("a"))
        let second = stack.post(alert("b"), now: t0.addingTimeInterval(4.9))
        #expect(second == .coalesced("a"))
        #expect(stack.items.count == 1)
        #expect(stack.items[0].count == 2)
    }

    @Test func identicalAlertAfterTheWindowIsANewCard() {
        var stack = AlertStack()
        stack.post(alert("a"), now: t0)
        #expect(stack.post(alert("b"), now: t0.addingTimeInterval(5.1)) == .added("b"))
        #expect(stack.items.count == 2)
    }

    @Test func coalescingRestartsTheClockAndKeepsTheHigherPriority() {
        var stack = AlertStack()
        stack.post(alert("a", priority: .low), now: t0)                  // deadline t0+4
        stack.post(alert("b", priority: .high), now: t0.addingTimeInterval(3))
        #expect(stack.items[0].priority == .high)
        #expect(stack.nextDeadline() == t0.addingTimeInterval(13))       // 3 + 10
    }

    @Test func deadlineFollowsPriority() {
        for (priority, seconds) in [(AlertPriority.low, 4.0), (.normal, 6), (.high, 10)] {
            var stack = AlertStack()
            stack.post(alert("a", priority: priority), now: t0)
            #expect(stack.nextDeadline() == t0.addingTimeInterval(seconds))
        }
        var urgent = AlertStack()
        urgent.post(alert("u", priority: .urgent), now: t0)
        #expect(urgent.nextDeadline() == nil)
        #expect(urgent.expire(now: t0.addingTimeInterval(3600)).isEmpty)
    }

    @Test func expireRemovesOnlyDueAlerts() {
        var stack = AlertStack()
        stack.post(alert("a", title: "A", priority: .low), now: t0)
        stack.post(alert("b", title: "B", priority: .high), now: t0)
        #expect(stack.expire(now: t0.addingTimeInterval(3.9)).isEmpty)
        #expect(stack.expire(now: t0.addingTimeInterval(4)) == ["a"])
        #expect(stack.items.map(\.id) == ["b"])
    }

    @Test func hoverPausesAutoDismissAndResumesWithTimeLeft() {
        var stack = AlertStack()
        stack.post(alert("a"), now: t0)                                   // due t0+6
        stack.setHovered(true, now: t0.addingTimeInterval(4))             // 2 s left
        #expect(stack.nextDeadline() == nil)
        #expect(stack.expire(now: t0.addingTimeInterval(600)).isEmpty)
        stack.setHovered(false, now: t0.addingTimeInterval(10))
        #expect(stack.nextDeadline() == t0.addingTimeInterval(12))
    }

    @Test func leavingWithAlmostNoTimeLeftStillGivesAGraceMoment() {
        var stack = AlertStack()
        stack.post(alert("a"), now: t0)
        stack.setHovered(true, now: t0.addingTimeInterval(5.95))
        stack.setHovered(false, now: t0.addingTimeInterval(20))
        #expect(stack.nextDeadline() == t0.addingTimeInterval(21.5))
    }

    @Test func queuedAlertStartsItsClockWhenItReachesTheFront() {
        var stack = AlertStack()
        for index in 1...4 { stack.post(alert("a\(index)", title: "T\(index)", priority: .low), now: t0) }
        // a1 is queued (index 3) and has no deadline yet.
        stack.dismiss(id: "a4", now: t0.addingTimeInterval(1))
        #expect(stack.visible.map(\.id) == ["a3", "a2", "a1"])
        #expect(stack.expire(now: t0.addingTimeInterval(4)).sorted() == ["a2", "a3"])
        #expect(stack.items.map(\.id) == ["a1"])
        #expect(stack.nextDeadline() == t0.addingTimeInterval(5))         // promoted at t0+1, low = 4 s
    }

    @Test func alertPostedWhileHoveredWaitsForTheHoverToEnd() {
        var stack = AlertStack()
        stack.post(alert("a"), now: t0)
        stack.setHovered(true, now: t0.addingTimeInterval(1))
        stack.post(alert("b", title: "B"), now: t0.addingTimeInterval(2))
        #expect(stack.nextDeadline() == nil)
        stack.setHovered(false, now: t0.addingTimeInterval(3))
        #expect(stack.nextDeadline() != nil)
        #expect(stack.visible.count == 2)
    }

    @Test func clearEmptiesEverythingAndLeavesNothingToWakeFor() {
        var stack = AlertStack()
        stack.post(alert("a"), now: t0)
        stack.clear()
        #expect(stack.isEmpty)
        #expect(stack.nextDeadline() == nil)
    }

    @Test func spokenTextNamesAppTitleAndBody() {
        #expect(alert("a").spokenText == "Messages. Anna. Hi")
        #expect(AlertItem(id: "x", appID: "a", appName: "Mail", title: "", body: "Body", postedAt: t0).spokenText == "Mail. Body")
    }
}

@Suite struct AlertSupportTests {
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)

    private func note(_ id: Int64, _ app: String, ago: TimeInterval) -> MirroredNotification {
        MirroredNotification(id: id, app: app, title: "t\(id)", subtitle: nil, body: "b", date: now.addingTimeInterval(-ago))
    }

    @Test func groupsByAppOrderedByNewestWithNewestRowFirst() {
        let items = [note(1, "com.a", ago: 600), note(2, "com.b", ago: 60), note(3, "COM.A", ago: 30), note(4, "com.b", ago: 900)]
        let groups = AlertGrouping.groups(items) { $0.uppercased() }
        #expect(groups.map(\.appID) == ["COM.A", "com.b"])
        #expect(groups[0].items.map(\.id) == [3, 1])
        #expect(groups[1].items.map(\.id) == [2, 4])
        #expect(groups[0].appName == "COM.A")
    }

    @Test func emptyInputHasNoGroups() {
        #expect(AlertGrouping.groups([], appName: { $0 }).isEmpty)
    }

    @Test func relativeTimeIsShort() {
        func text(_ ago: TimeInterval) -> String { AlertRelativeTime.text(from: now.addingTimeInterval(-ago), now: now) }
        #expect(text(5) == "now")
        #expect(text(120) == "2m")
        #expect(text(3600) == "1h")
        #expect(text(3 * 3600 + 5) == "3h")
        #expect(text(2 * 86_400) == "2d")
        #expect(AlertRelativeTime.text(from: now.addingTimeInterval(50), now: now) == "now")
    }

    @Test func blankIconIsDetected() {
        #expect(AlertIconPixels.isBlank(rgba: [UInt8](repeating: 0, count: 64 * 64 * 4)))
        #expect(AlertIconPixels.isBlank(rgba: []))
        #expect(!AlertIconPixels.isBlank(rgba: [UInt8](repeating: 255, count: 64 * 64 * 4)))
        var sparse = [UInt8](repeating: 0, count: 100 * 4)
        sparse[3] = 255 // 1 % visible
        #expect(AlertIconPixels.isBlank(rgba: sparse))
    }

    @Test func dominantColourPicksTheStrongestHue() {
        var pixels: [UInt8] = []
        for index in 0..<400 {
            if index < 300 { pixels += [250, 40, 40, 255] }   // red
            else { pixels += [40, 40, 250, 255] }              // blue
        }
        let hex = AlertAccent.dominantHex(rgba: pixels)
        #expect(hex == 0xFA2828)
    }

    @Test func greyscaleAndTransparentIconsHaveNoAccent() {
        #expect(AlertAccent.dominantHex(rgba: [UInt8](repeating: 128, count: 4 * 400)) == nil)
        #expect(AlertAccent.dominantHex(rgba: [UInt8](repeating: 0, count: 4 * 400)) == nil)
    }

    @Test func fallbackGlyphsAndReplySupport() {
        #expect(AlertAppGlyph.symbol(for: "com.apple.mail") == "envelope.fill")
        #expect(AlertAppGlyph.symbol(for: "unknown.app") == "app.fill")
    }

    private func alert(_ app: String, title: String, body: String = "") -> AlertItem {
        AlertItem(id: "1", appID: app, appName: "App", title: title, body: body, postedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func messagesRepliesOpenTheChatOnlyWhenTheTitleIsAnAddress() {
        #expect(AlertReply.url(for: alert("com.apple.MobileSMS", title: "+1 (514) 555-0100"))?.absoluteString
                == "imessage:%2B1%20(514)%20555-0100")
        #expect(AlertReply.url(for: alert("com.apple.MobileSMS", title: "ana@example.com"))?.absoluteString == "imessage:ana@example.com")
        #expect(AlertReply.url(for: alert("com.apple.MobileSMS", title: "Marie Dubois")) == nil, "a name cannot address a chat")
    }

    @Test func mailRepliesOpenADraftWithReAndNeverSend() {
        let withAddress = AlertReply.url(for: alert("com.apple.mail", title: "ana@example.com", body: "Budget\nsecond line"))
        #expect(withAddress?.absoluteString == "mailto:ana@example.com?subject=Re:%20Budget")
        let named = AlertReply.url(for: alert("com.apple.mail", title: "Ana Lopez", body: "Re: Budget"))
        #expect(named?.absoluteString == "mailto:?subject=Re:%20Budget", "no double Re:")
        #expect(AlertReply.url(for: alert("com.apple.mail", title: "Ana Lopez")) == nil, "nothing to reply to")
    }

    @Test func slackTeamsAndOtherAppsHideReplyInsteadOfDuplicatingOpen() {
        for app in ["com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.iCal", "unknown.app"] {
            #expect(!AlertReply.supportsReply(alert(app, title: "Marie", body: "hello")), "\(app)")
        }
    }

    @Test func animationWindowEndsSoIdleOwnsNoClock() {
        #expect(AlertMotion.isAnimating(elapsed: 0.5, reduceMotion: false))
        #expect(!AlertMotion.isAnimating(elapsed: AlertMotion.sweepDuration, reduceMotion: false))
        #expect(!AlertMotion.isAnimating(elapsed: 60, reduceMotion: false))
        #expect(!AlertMotion.sweepActive(elapsed: 0.2, reduceMotion: true))
        #expect(AlertMotion.sweepActive(elapsed: 0.2, reduceMotion: false))
        #expect(!AlertMotion.isAnimating(elapsed: 0.5, reduceMotion: true))
        #expect(AlertMotion.contentDelay(index: 2) - AlertMotion.contentDelay(index: 1) == AlertMotion.contentStagger)
        #expect(AlertMotion.stretchResponse == 0.42 && AlertMotion.stretchDamping == 0.78)
    }
}
