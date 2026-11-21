import Foundation
import Testing
@testable import ZeusCore

/// The inline reply row. Approve is the only release. Deny, Cancel, Escape, and the
/// timeout type nothing. The type is absent when this file is added, so the suite fails closed.
@Suite("Pending reply row")
struct HubPendingReplyTests {
    private let offer = HubPendingReplyOffer(
        id: "row-7",
        destination: "Harbor, notes",
        draft: "  also\nupdate   the changelog\t"
    )
    private let cleaned = "also update the changelog"
    private let stale = "row-6"

    @Test func approveIsTheOnlyPathThatReleases() {
        for action in HubPendingReplyAction.allCases {
            for focus in [HubPendingReplyFocus?.none] + HubPendingReplyFocus.allCases.map(Optional.some) {
                var model = awaiting()
                let verdict = model.decide(action, id: offer.id, focus: focus, at: 1)
                let releases = action == .approve || (action == .return && focus == .approve)
                if releases {
                    #expect(verdict == .release(id: offer.id, line: cleaned))
                } else if case .release = verdict {
                    Issue.record("\(action) with focus \(String(describing: focus)) released a line")
                }
            }
        }
    }

    @Test func denyCancelAndTimeoutTypeNothing() {
        for action in [HubPendingReplyAction.deny, .cancel, .timeout] {
            var model = awaiting()
            let verdict = model.decide(action, id: offer.id, focus: .approve, at: 1)
            #expect(releasedLine(verdict) == nil)
            #expect(model.displayed(at: 1) == nil)
            let again = model.decide(.approve, id: offer.id, focus: .approve, at: 2)
            #expect(releasedLine(again) == nil)
        }
    }

    @Test func aDoubleTapReleasesAtMostOnce() {
        for second in [HubPendingReplyAction.approve, .return] {
            var model = awaiting()
            let first = model.decide(.approve, id: offer.id, focus: nil, at: 1)
            let follow = model.decide(second, id: offer.id, focus: .approve, at: 2)
            #expect(first == .release(id: offer.id, line: cleaned))
            #expect(follow == .ignore)
            #expect(model.displayed(at: 2) == nil)
        }
    }

    @Test func aStaleIdIsIgnored() {
        for action in HubPendingReplyAction.allCases {
            var model = awaiting()
            let verdict = model.decide(action, id: stale, focus: .approve, at: 4)
            #expect(verdict == .ignore)
            let shown = model.displayed(at: 4)
            #expect(shown?.id == offer.id)
            #expect(shown?.line == cleaned)
            let real = model.decide(.approve, id: offer.id, focus: nil, at: 5)
            #expect(real == .release(id: offer.id, line: cleaned))
        }
    }

    @Test func escapeMapsToDeny() {
        var byEscape = awaiting()
        var byDeny = awaiting()
        var byCancel = awaiting()
        let escape = byEscape.decide(.escape, id: offer.id, focus: .approve, at: 3)
        let deny = byDeny.decide(.deny, id: offer.id, focus: .cancel, at: 3)
        let cancel = byCancel.decide(.cancel, id: offer.id, focus: .deny, at: 3)
        #expect(escape == .withhold(id: offer.id, reason: .deny))
        #expect(escape == deny)
        #expect(escape != cancel)
        #expect(cancel == .withhold(id: offer.id, reason: .cancel))
        #expect(releasedLine(escape) == nil)
        #expect(byEscape.displayed(at: 3) == nil)
    }

    @Test func returnApprovesOnlyWhileApproveIsFocused() {
        for focus in [HubPendingReplyFocus?.none, .summary, .deny, .cancel] {
            var model = awaiting()
            let verdict = model.decide(.return, id: offer.id, focus: focus, at: 2)
            #expect(verdict == .ignore)
            #expect(model.displayed(at: 2)?.line == cleaned)
        }
        var focused = awaiting()
        #expect(focused.decide(.return, id: offer.id, focus: .approve, at: 2) == .release(id: offer.id, line: cleaned))
    }

    @Test func appearingDoesNotDecide() {
        var model = awaiting()
        let before = model
        let verdict = model.decide(.appear, id: offer.id, focus: .approve, at: 9)
        #expect(verdict == .ignore)
        #expect(model == before)
        #expect(model.displayed(at: 0)?.secondsLeft == 30)
    }

    @Test func theCountdownUsesTheExistingWaitAndDoesNotRelease() {
        #expect(HubPendingReplyModel.waitSeconds == 30)
        var model = awaiting(at: 100, deadline: 130)
        #expect(model.displayed(at: 100)?.secondsLeft == 30)
        #expect(model.displayed(at: 100)?.caption == "30 s left, then it's denied.")
        #expect(model.displayed(at: 118)?.secondsLeft == 12)
        #expect(model.displayed(at: 118)?.caption == "12 s left, then it's denied.")
        #expect(model.displayed(at: 130)?.secondsLeft == 0)
        #expect(model.displayed(at: 130)?.caption == "0 s left, then it's denied.")
        #expect(model.displayed(at: 131)?.id == offer.id)
        let still = model.decide(.approve, id: offer.id, focus: nil, at: 131)
        #expect(still == .release(id: offer.id, line: cleaned))
    }

    @Test func theRowAnnouncesTheDestinationAndTheCleanedLine() {
        let row = awaiting().displayed(at: 0)
        #expect(row?.destination == offer.destination)
        #expect(row?.line == cleaned)
        #expect(row?.accessibilityLabel.contains(offer.destination) == true)
        #expect(row?.accessibilityLabel.contains(cleaned) == true)
        #expect(row?.accessibilityHint.contains(offer.destination) == true)
        #expect(row?.accessibilityHint.contains(cleaned) == true)
        let approve = row?.buttons.first { $0.focus == .approve }
        let deny = row?.buttons.first { $0.focus == .deny }
        let cancel = row?.buttons.first { $0.focus == .cancel }
        #expect(approve?.isPrimary == true)
        #expect(approve?.title == "Approve")
        #expect(approve?.hint.contains(cleaned) == true)
        #expect(approve?.hint.contains(offer.destination) == true)
        #expect(deny?.isPrimary == false)
        #expect(deny?.hint.contains(cleaned) == true)
        #expect(deny?.hint.contains(offer.destination) == true)
        #expect(cancel?.hint.contains(cleaned) == true)
        #expect(cancel?.hint.contains(offer.destination) == true)
        #expect(row?.buttons.map(\.focus) == [.deny, .cancel, .approve])
        #expect(row?.buttons.map(\.isPrimary) == [false, false, true])
    }

    @Test func focusOrderPutsApproveLastAndReducedMotionDoesNotTravel() {
        #expect(HubPendingReplyModel.focusOrder == [.summary, .deny, .cancel, .approve])
        #expect(HubPendingReplyModel.primary == .approve)
        let priorities = HubPendingReplyModel.focusOrder.map(HubPendingReplyModel.sortPriority)
        #expect(priorities == priorities.sorted(by: >))
        #expect(Set(priorities).count == priorities.count)
        let reduced = HubPendingReplyModel.motion(reduceMotion: true)
        #expect(reduced.opacity == 1)
        #expect(reduced.offset == 0)
        #expect(reduced.usesSpring == false)
        let moving = HubPendingReplyModel.motion(reduceMotion: false)
        #expect(moving.opacity == 1)
        #expect(moving.offset != 0)
        #expect(moving.usesSpring == true)
    }

    @Test func aLineThatCannotBeTypedIsNotOffered() {
        var model = HubPendingReplyModel()
        let empty = HubPendingReplyOffer(id: offer.id, destination: offer.destination, draft: " \n\t ")
        #expect(model.present(empty, at: 0, deadline: 30) == .ignore)
        #expect(model.displayed(at: 0) == nil)
        let broken = HubPendingReplyOffer(id: "row-8", destination: offer.destination, draft: "hello\u{2028}there")
        #expect(model.present(broken, at: 0, deadline: 30) == .ignore)
        #expect(model.displayed(at: 0) == nil)
    }

    @Test func presentingAgainKeepsTheSameWait() {
        var model = awaiting(at: 10, deadline: 40)
        let again = model.present(offer, at: 25, deadline: 80)
        #expect(again == .ignore)
        #expect(model.displayed(at: 25)?.secondsLeft == 15)
        #expect(model.displayed(at: 25)?.id == offer.id)
    }

    @Test func theViewCallsTheThreeHubMethodsAndDoesNotApproveOnAppear() throws {
        let view = try #require(Self.loaded("Sources/Zeus/TopBar/HubPendingReplyRow.swift"))
        let page = try #require(Self.loaded("Sources/Zeus/TopBar/ChatPage.swift"))
        let hub = try #require(Self.loaded("Sources/Zeus/Agents/AgentHub.swift"))
        #expect(view.contains("approveReply"))
        #expect(view.contains("denyReply"))
        #expect(view.contains("cancelReply"))
        #expect(view.contains("accessibilityLabel"))
        #expect(view.contains("accessibilityHint"))
        #expect(view.contains("accessibilitySortPriority"))
        #expect(view.contains("sortPriority"))
        #expect(view.contains(".opacity"))
        #expect(view.contains("usesSpring"))
        #expect(view.contains("onExitCommand") || view.contains(".cancelAction"))
        #expect(view.contains("focus == .approve"))
        #expect(!view.contains("keyboardShortcut(.defaultAction)"))
        #expect(!view.contains(".defaultAction"))
        let appear = try #require(Self.functionBody("bind", in: view))
        #expect(appear.contains("present"))
        #expect(!appear.contains("approveReply"))
        #expect(!appear.contains("denyReply"))
        #expect(!appear.contains("cancelReply"))
        #expect(page.contains("HubPendingReplyRow") || page.contains("AgentReplyPane"))
        let wait = try #require(Self.functionBody("armReplyTimeout", in: hub))
        #expect(wait.contains(".seconds(30)"))
        #expect(!wait.contains(".seconds(45)"))
        #expect(!wait.contains(".seconds(20)"))
    }

    private func awaiting(at now: TimeInterval = 0, deadline: TimeInterval = 30) -> HubPendingReplyModel {
        var model = HubPendingReplyModel()
        let verdict = model.present(offer, at: now, deadline: deadline)
        #expect(verdict == .ignore)
        return model
    }

    private func releasedLine(_ verdict: HubPendingReplyVerdict) -> String? {
        if case .release(_, let line) = verdict { return line }
        return nil
    }

    private static func loaded(_ relative: String) -> String? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = (try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)) ?? ""
        return source.isEmpty ? nil : source
    }

    /// The body of one function, from its opening brace through the matching close.
    private static func functionBody(_ name: String, in source: String) -> String? {
        guard let signature = source.range(of: "func \(name)") else { return nil }
        guard let open = source[signature.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
