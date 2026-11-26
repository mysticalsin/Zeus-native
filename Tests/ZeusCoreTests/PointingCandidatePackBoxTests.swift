import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing candidate pack box")
struct PointingCandidatePackBoxTests {
    private func rect(_ width: Double = 40, _ height: Double = 18) -> PointingCandidatePack.Rect {
        PointingCandidatePack.Rect(x: 12, y: 40, width: width, height: height)
    }

    private func draft(id: String = "share", role: String = "AXButton", label: String? = "Share", secure: Bool = false) -> PointingCandidatePack.Draft {
        PointingCandidatePack.Draft(id: id, role: role, label: label, rect: rect(), isSecure: secure)
    }

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{0009}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{000A}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{000B}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{000C}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{000D}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{0020}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{0085}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{00A0}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{1680}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2000}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2001}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2002}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2003}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2004}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2005}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2006}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2007}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2008}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2009}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{200A}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2028}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{2029}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{202F}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{205F}"))
        #expect(PointingCandidatePackBox.blankScalars.contains("\u{3000}"))
        #expect(!PointingCandidatePackBox.blankScalars.contains("\u{200B}"))
        #expect(PointingCandidatePackBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(PointingCandidatePackBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(PointingCandidatePackBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceStaysInTheRole() {
        #expect(PointingCandidatePackBox.role("\u{200B}AXButton") == "\u{200B}AXButton")
        let pack = PointingCandidatePack(displayID: 7, candidates: [draft(role: "\u{200B}AXButton")])
        #expect(pack?.candidates.first?.role == "\u{200B}AXButton")
        let only = PointingCandidatePack(displayID: 7, candidates: [draft(role: "\u{200B}")])
        #expect(only?.candidates.first?.role == "\u{200B}")
        #expect(only?.candidates.first?.id == "share")
    }

    @Test func namedBlanksAroundARoleAreRemoved() {
        #expect(PointingCandidatePackBox.role(" \tAXButton\n") == "AXButton")
        #expect(PointingCandidatePackBox.role("\u{00A0}AXButton\u{3000}") == "AXButton")
        #expect(PointingCandidatePackBox.role(" \u{200B}AXButton\t") == "\u{200B}AXButton")
        let pack = PointingCandidatePack(displayID: 7, candidates: [draft(role: " \tAXButton\n")])
        #expect(pack?.candidates.first?.role == "AXButton")
        #expect(PointingCandidatePack(displayID: 7, candidates: [draft(role: "   ")]) == nil)
        #expect(PointingCandidatePack(displayID: 7, candidates: [draft(role: "\u{00A0}\u{3000}")]) == nil)
        #expect(PointingCandidatePackBox.role("   ") == "")
        #expect(PointingCandidatePackBox.role("\u{00A0}\u{3000}") == "")
    }

    @Test func aRoleOfOnlyTheZeroWidthSpaceIsKept() {
        #expect(PointingCandidatePackBox.role("\u{200B}") == "\u{200B}")
        #expect(PointingCandidatePackBox.role("\n\u{200B}\t") == "\u{200B}")
        #expect(PointingCandidatePackBox.role("") == "")
        let pack = PointingCandidatePack(displayID: 4, candidates: [draft(id: "mark", role: "\n\u{200B}\t", label: "\u{200B}")])
        #expect(pack?.candidates.first?.role == "\u{200B}")
        #expect(pack?.candidates.first?.label == "\u{200B}")
        #expect(PointingCandidatePack(displayID: 4, candidates: [draft(role: "")]) == nil)
    }

    @Test func thePackReadsTheBoxForLimits() throws {
        let eight = (0..<8).map { draft(id: "c\($0)") }
        let built = try #require(PointingCandidatePackBox.assemble(displayID: 7, drafts: eight))
        #expect(built.candidates.count == 8)
        #expect(built.image == nil)
        #expect(built.sendScreenshot == false)
        let pack = try #require(PointingCandidatePack(displayID: 7, candidates: eight))
        #expect(pack.candidates.count == 8)
        #expect(PointingCandidatePackBox.assemble(displayID: 7, drafts: eight + [draft(id: "c8")]) == nil)
        #expect(PointingCandidatePack(displayID: 7, candidates: eight + [draft(id: "c8")]) == nil)

        let pixels = Data([0x01, 0x02, 0x03])
        #expect(PointingCandidatePackBox.assemble(displayID: 7, sendScreenshot: false, image: pixels, drafts: [draft()]) == nil)
        let kept = try #require(PointingCandidatePackBox.assemble(displayID: 4, sendScreenshot: true, image: pixels, drafts: [draft()]))
        #expect(kept.image == pixels)
        #expect(kept.displayID == 4)
        let empty = try #require(PointingCandidatePackBox.assemble(displayID: 7, sendScreenshot: true, image: Data(), drafts: []))
        #expect(empty.image == nil)
        let huge = Data(count: PointingCandidatePack.maxImageBytes + 1)
        #expect(PointingCandidatePackBox.assemble(displayID: 4, sendScreenshot: true, image: huge, drafts: []) == nil)

        #expect(PointingCandidatePackBox.assemble(displayID: 7, drafts: [draft(), draft()]) == nil)
        #expect(PointingCandidatePackBox.assemble(displayID: 7, drafts: [draft(id: "has space")]) == nil)
        #expect(PointingCandidatePackBox.assemble(displayID: 0, drafts: [draft()]) == nil)
        let flat = PointingCandidatePack.Draft(id: "share", role: "AXButton", rect: rect(0, 18))
        #expect(PointingCandidatePackBox.assemble(displayID: 7, drafts: [flat]) == nil)
        let left = PointingCandidatePack.Draft(
            id: "share", role: "AXButton",
            rect: PointingCandidatePack.Rect(x: -1200, y: 20, width: 40, height: 18))
        let shifted = try #require(PointingCandidatePackBox.assemble(displayID: 3, drafts: [left]))
        #expect(shifted.candidates.first?.rect.x == -1200)

        let secure = try #require(PointingCandidatePackBox.assemble(displayID: 7, drafts: [draft(role: " \u{200B}AXButton ", label: "hunter2", secure: true)]))
        #expect(secure.candidates.first?.isSecure == true)
        #expect(secure.candidates.first?.label == nil)
        #expect(secure.candidates.first?.role == "\u{200B}AXButton")
        let agreed = try #require(PointingCandidatePack(displayID: 7, candidates: [draft(role: " \u{200B}AXButton ", label: "hunter2", secure: true)]))
        #expect(agreed.candidates.first?.role == "\u{200B}AXButton")
        #expect(agreed.candidates.first?.label == nil)
    }
}
