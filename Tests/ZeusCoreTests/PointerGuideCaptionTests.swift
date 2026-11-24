import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointer guide caption lines")
struct PointerGuideCaptionTests {
    private struct FixtureFile: Decodable {
        var captions: [Fixture]
    }

    private struct FixturePoint: Decodable {
        var x: Double
        var y: Double
    }

    private struct FixtureRect: Decodable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private struct Fixture: Decodable {
        var name: String
        var reduceMotion: Bool
        var bolt: FixturePoint
        var ring: FixtureRect
        var whatItIs: String
        var whatToDo: String
        var whatHappensNext: String
        var detail: String
    }

    private enum FixtureError: Error { case missing, invalid }

    private func fixture(named name: String) throws -> Fixture {
        guard let url = Bundle.module.url(forResource: "pointer-caption-lines", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing
        }
        let file = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
        guard let fixture = file.captions.first(where: { $0.name == name }) else { throw FixtureError.invalid }
        return fixture
    }

    private func loaded(named name: String) throws -> PointerGuideCaptionFrame {
        let fixture = try fixture(named: name)
        return PointerGuideCaptionFrame(
            bolt: CGPoint(x: fixture.bolt.x, y: fixture.bolt.y),
            ring: CGRect(x: fixture.ring.x, y: fixture.ring.y, width: fixture.ring.width, height: fixture.ring.height),
            whatItIs: fixture.whatItIs,
            whatToDo: fixture.whatToDo,
            whatHappensNext: fixture.whatHappensNext,
            detail: fixture.detail,
            reduceMotion: fixture.reduceMotion
        )
    }

    private let shareLines = ["Share button", "Click Share", "The share menu opens"]

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
