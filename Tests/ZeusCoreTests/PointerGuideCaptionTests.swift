import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointer guide caption lines")
struct PointerGuideCaptionTests {
    private func loaded(named name: String) throws -> PointerGuideCaptionFrame {
        switch name {
        case "share-menu":
            return PointerGuideCaptionFrame(
                bolt: CGPoint(x: 80, y: 740),
                ring: CGRect(x: 40, y: 720, width: 80, height: 28),
                whatItIs: "Share button", whatToDo: "Click Share",
                whatHappensNext: "The share menu opens",
                detail: "Exporting as PDF is a different command in the File menu and stays in the thread.",
                reduceMotion: false)
        case "share-menu-reduced":
            return PointerGuideCaptionFrame(
                bolt: CGPoint(x: 80, y: 740),
                ring: CGRect(x: 40, y: 720, width: 80, height: 28),
                whatItIs: "Share button", whatToDo: "Click Share",
                whatHappensNext: "The share menu opens",
                detail: "Exporting as PDF is a different command in the File menu and stays in the thread.",
                reduceMotion: true)
        case "file-only":
            return PointerGuideCaptionFrame(
                bolt: CGPoint(x: 180, y: 640),
                ring: CGRect(x: 140, y: 620, width: 120, height: 32),
                whatItIs: "File menu", whatToDo: "Click File",
                whatHappensNext: "", detail: "", reduceMotion: false)
        default:
            throw LoadError.invalid
        }
    }

    private enum LoadError: Error { case invalid }

    private let shareLines = ["Share button", "Click Share", "The share menu opens"]

    @Test func theBoltShowsThreeShortLinesAndDropsAFourth() {
        let shown = PointerGuideCaptionSplit.boltText("Share button\nClick Share\nThe share menu opens")
        #expect(shown == shareLines.joined(separator: "\n"))
        #expect(PointerGuideCaptionSplit.boltText("Click File") == "Click File")
        #expect(PointerGuideCaptionSplit.boltText(String(repeating: "a", count: 41)) == nil)
        #expect(PointerGuideCaptionSplit.boltText("One\nTwo\nThree\nFour") == nil)
        #expect(PointerGuideCaptionSplit.boltText("   \n  ") == nil)
    }

    @Test func theCaptionIsThreeShortLinesAndTheDetailStaysOff() throws {
        let frame = try loaded(named: "share-menu")
        let lines = try #require(PointerGuideCaptionSplit.overlayLines(
            whatItIs: frame.whatItIs, whatToDo: frame.whatToDo,
            whatHappensNext: frame.whatHappensNext, detail: frame.detail
        ))
        #expect(lines == shareLines)
        #expect(lines.count <= PointerGuideCaptionSplit.maxLines)
        #expect(lines.allSatisfy { (1...PointerGuideCaptionSplit.maxLineCharacters).contains($0.count) })
        #expect(lines.allSatisfy { !$0.contains("\n") && !$0.contains("\r") })
        #expect(lines.joined(separator: "\n").contains("Exporting as PDF") == false)
    }

    @Test func twoRolesStayUnderThreeLines() throws {
        let frame = try loaded(named: "file-only")
        let lines = try #require(PointerGuideCaptionSplit.overlayLines(
            whatItIs: frame.whatItIs, whatToDo: frame.whatToDo,
            whatHappensNext: frame.whatHappensNext, detail: frame.detail
        ))
        #expect(lines == ["File menu", "Click File"])
        #expect(lines.count <= PointerGuideCaptionSplit.maxLines)
    }

    @Test func anEmptyMiddleRoleIsSkipped() throws {
        let lines = try #require(PointerGuideCaptionSplit.overlayLines(
            whatItIs: "Share button", whatToDo: "   ", whatHappensNext: "The share menu opens", detail: "Kept in the thread."
        ))
        #expect(lines == ["Share button", "The share menu opens"])
    }

    @Test func detailAloneIsNotACaption() {
        #expect(PointerGuideCaptionSplit.overlayLines(
            whatItIs: "", whatToDo: " ", whatHappensNext: "", detail: "This stays in the thread."
        ) == nil)
    }

    @Test func aBlankCaptionIsRejected() {
        #expect(PointerGuideCaptionSplit.overlayLines(
            whatItIs: "", whatToDo: "", whatHappensNext: "", detail: ""
        ) == nil)
    }

    @Test func anOverlongRoleIsNotShown() throws {
        let long = String(repeating: "a", count: PointerGuideCaptionSplit.maxLineCharacters + 1)
        #expect(PointerGuideCaptionSplit.overlayLines(
            whatItIs: long, whatToDo: "Click Share", whatHappensNext: "The share menu opens", detail: ""
        ) == nil)
        let exact = String(repeating: "b", count: PointerGuideCaptionSplit.maxLineCharacters)
        let lines = try #require(PointerGuideCaptionSplit.overlayLines(
            whatItIs: exact, whatToDo: "", whatHappensNext: "", detail: "not on screen"
        ))
        #expect(lines == [exact])
    }

    @Test func aLineBreakInsideARoleIsNotShown() {
        #expect(PointerGuideCaptionSplit.overlayLines(
            whatItIs: "Share button", whatToDo: "Click\nShare", whatHappensNext: "The share menu opens", detail: ""
        ) == nil)
    }

    @Test func theBoltAndRingStayOnZeusFlight() throws {
        let frame = try loaded(named: "share-menu")
        let origin = CGPoint(x: 12, y: 40)
        let pose = try #require(frame.pose(from: origin, at: 0, beganAt: 0, reduceMotion: false))
        let flight = CompanionFlight.plan(from: origin, to: frame.bolt, reducedMotion: false)
        #expect(pose.flight == flight)
        #expect(pose.flight.duration > 0)
        #expect(pose.bolt == flight.sample(at: 0).position)
        #expect(pose.ring == frame.ring)
        #expect(pose.ring.width == 80)
        #expect(pose.ring.height == 28)
    }

    @Test func reducedMotionSettlesTheBoltAndShowsTheThreeLines() throws {
        let frame = try loaded(named: "share-menu-reduced")
        let origin = CGPoint(x: 10, y: 10)
        let pose = try #require(frame.pose(from: origin, at: 0, beganAt: 0, reduceMotion: true))
        let flight = CompanionFlight.plan(from: origin, to: frame.bolt, reducedMotion: true)
        #expect(pose.flight == flight)
        #expect(pose.flight.duration == 0)
        #expect(pose.bolt == frame.bolt)
        #expect(pose.ring == frame.ring)
        #expect(pose.lines == shareLines)
        #expect(pose.visibleLines == shareLines)
    }

    @Test func reducedMotionMidStepShowsEveryLine() throws {
        let frame = try loaded(named: "share-menu")
        let origin = CGPoint(x: 12, y: 40)
        let pose = try #require(frame.pose(from: origin, at: 0.2, beganAt: 0, reduceMotion: true))
        #expect(pose.lines == shareLines)
        #expect(pose.visibleLines == shareLines)
        #expect(pose.bolt == frame.bolt)
        #expect(pose.flight.duration == 0)
        #expect(pose.ring == frame.ring)
    }

    @Test func theCaptionRevealUsesThePointingLabel() throws {
        let frame = try loaded(named: "share-menu")
        let origin = CGPoint(x: 12, y: 40)
        let began: TimeInterval = 5
        let pose = try #require(frame.pose(from: origin, at: began, beganAt: began, reduceMotion: false))
        let text = shareLines.joined(separator: "\n")
        var label = CompanionPointingLabel(text: text, beganAt: began, reduceMotion: false)
        #expect(pose.lines == shareLines)
        #expect(pose.visibleLines == PointerGuideCaptionSplit.visibleLines(in: label.visibleText))
        #expect(pose.visibleLines.isEmpty)
        #expect(pose.flight.duration > 0)
        let now = began + 0.12
        label.advance(at: now, reduceMotion: false, characterDelay: PointerGuideCaptionSplit.characterDelay)
        let first = try #require(frame.pose(from: origin, at: now, beganAt: began, reduceMotion: false))
        #expect(first.visibleLines == PointerGuideCaptionSplit.visibleLines(in: label.visibleText))
        #expect(first.visibleLines == ["S"])
        #expect(first.flight == CompanionFlight.plan(from: origin, to: frame.bolt, reducedMotion: false))
        #expect(first.bolt == first.flight.sample(at: now - began).position)
        #expect(first.ring == frame.ring)
    }

    @Test func aFlatRingIsNotShown() throws {
        var frame = try loaded(named: "share-menu")
        frame.ring.size.height = 0
        #expect(frame.pose(from: .zero, at: 0, beganAt: 0, reduceMotion: false) == nil)
        frame = try loaded(named: "share-menu")
        frame.bolt.x = .infinity
        #expect(frame.pose(from: .zero, at: 0, beganAt: 0, reduceMotion: true) == nil)
    }
}
