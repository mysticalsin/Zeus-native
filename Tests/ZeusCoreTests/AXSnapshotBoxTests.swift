import Testing
@testable import ZeusCore

@Suite("AX snapshot box") struct AXSnapshotBoxTests {
    @Test func lookupReadsAtSignBracketsAndALowercasedRef() {
        #expect(AXSnapshotBox.lookup("@s4:e1", snapshot: 4, count: 2) == .found(0))
        #expect(AXSnapshotBox.lookup("  [S12:E40] ", snapshot: 12, count: 40) == .found(39))
        #expect(AXSnapshotBox.lookup("s4:e2", snapshot: 4, count: 2) == .found(1))
    }

    @Test func lookupRejectsAZeroSnapshotAMissingPrefixAndAnEmptyIndex() {
        #expect(AXSnapshotBox.lookup("s0:e1", snapshot: 0, count: 1) == .malformed)
        #expect(AXSnapshotBox.lookup("e1:s2", snapshot: 2, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("button 2", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("s4:e", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("s4:e0", snapshot: 4, count: 2) == .malformed)
        #expect(AXSnapshotBox.lookup("", snapshot: 4, count: 2) == .malformed)
    }

    @Test func staleRefUsesTheCanonicalFormAndTheCurrentSnapshot() {
        #expect(AXSnapshotBox.lookup("@s4:e2", snapshot: 5, count: 3) == .stale(ref: "s4:e2", current: 5))
    }

    @Test func unknownRefWhenTheIndexIsPastTheElements() {
        #expect(AXSnapshotBox.lookup("s5:e9", snapshot: 5, count: 2) == .unknown(ref: "s5:e9"))
        #expect(AXSnapshotBox.lookup("s5:e1", snapshot: 5, count: 0) == .unknown(ref: "s5:e1"))
    }

    @Test func theLastElementIsFoundAndTheNextOneIsUnknown() {
        #expect(AXSnapshotBox.lookup("s12:e40", snapshot: 12, count: 40) == .found(39))
        #expect(AXSnapshotBox.lookup("s12:e41", snapshot: 12, count: 40) == .unknown(ref: "s12:e41"))
    }

    @Test func aMissingOrBlankLabelIsNotRelocated() {
        let old = AXSnapshotBox.Spot(role: "AXButton", label: nil, midX: 0, midY: 0)
        let blank = AXSnapshotBox.Spot(role: "AXButton", label: "", midX: 0, midY: 0)
        let share = AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 10, midY: 0)
        #expect(AXSnapshotBox.relocateIndex(old: old, among: [share]) == nil)
        #expect(AXSnapshotBox.relocateIndex(old: blank, among: [share]) == nil)
    }

    @Test func theNearestSameRoleAndLabelWins() {
        let old = AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 120, midY: 20)
        let spots = [
            AXSnapshotBox.Spot(role: "AXStaticText", label: "Share", midX: 120, midY: 20),
            AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 620, midY: 20),
            AXSnapshotBox.Spot(role: "AXButton", label: "share", midX: 140, midY: 20),
            AXSnapshotBox.Spot(role: "axbutton", label: "Share", midX: 120, midY: 20),
            AXSnapshotBox.Spot(role: "AXButton", label: "Tags", midX: 140, midY: 20),
        ]
        #expect(AXSnapshotBox.relocateIndex(old: old, among: spots) == 2)
    }

    @Test func anEqualDistanceKeepsTheEarlierElement() {
        let old = AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 0, midY: 0)
        let spots = [
            AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 10, midY: 0),
            AXSnapshotBox.Spot(role: "AXButton", label: "Share", midX: 10, midY: 0),
        ]
        #expect(AXSnapshotBox.relocateIndex(old: old, among: spots) == 0)
    }

    @Test func distanceIsTheHypotenuseBetweenTheMids() {
        #expect(AXSnapshotBox.distance(midX: 0, midY: 0, x: 3, y: 4) == 5)
        #expect(AXSnapshotBox.distance(midX: 8, midY: 2, x: 8, y: 2) == 0)
    }

    @Test func rankedPutsEnabledControlsFirstAndDropsAnEmptyContainer() {
        let rows = [
            AXSnapshotBox.Row(interactive: false, enabled: true, hasLabel: true, hasValue: false),
            AXSnapshotBox.Row(interactive: true, enabled: false, hasLabel: true, hasValue: false),
            AXSnapshotBox.Row(interactive: true, enabled: true, hasLabel: true, hasValue: false),
            AXSnapshotBox.Row(interactive: false, enabled: true, hasLabel: false, hasValue: false),
            AXSnapshotBox.Row(interactive: false, enabled: true, hasLabel: false, hasValue: true),
            AXSnapshotBox.Row(interactive: true, enabled: true, hasLabel: false, hasValue: false),
        ]
        #expect(AXSnapshotBox.rankedIndexes(rows) == [2, 5, 0, 1, 4])
    }

    @Test func renderCapsTheBodyAndSaysTheWalkStopped() {
        let body = (0..<12).map { "L\($0)" }
        let text = AXSnapshotBox.render(app: "Notes", window: "Groceries", snapshot: 9, body: body, limit: 10, truncated: true)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 12)
        #expect(lines.first == "Controls in Notes, window \"Groceries\" (snapshot s9; use a ref like {\"ref\":\"s9:e1\"} to target one):")
        #expect(lines.dropFirst().first == "- L0")
        #expect(lines.dropFirst(10).first == "- L9")
        #expect(lines.last == "- ... 2 more not listed; the walk stopped early")
    }

    @Test func renderOmitsTheMoreLineWhenEverythingFits() {
        let text = AXSnapshotBox.render(app: "Notes", window: nil, snapshot: 1, body: ["button \"OK\" [s1:e1]"], limit: 40, truncated: false)
        #expect(text == "Controls in Notes (snapshot s1; use a ref like {\"ref\":\"s1:e1\"} to target one):\n- button \"OK\" [s1:e1]")
        #expect(!text.contains("more not listed"))
    }

    @Test func renderKeepsAMoreLineWhenTheWalkStoppedWithNothingHidden() {
        let text = AXSnapshotBox.render(app: "Notes", window: nil, snapshot: 9, body: ["button \"OK\""], limit: 40, truncated: true)
        #expect(text.hasSuffix("\n- ... 0 more not listed; the walk stopped early"))
    }

    @Test func renderClipsALongWindowAndFlattensANewline() {
        let long = String(repeating: "a", count: 61)
        let clipped = AXSnapshotBox.render(app: "Notes", window: long, snapshot: 3, body: [], limit: 10, truncated: false)
        #expect(clipped.contains("window \"\(String(repeating: "a", count: 60))...\""))
        let broken = AXSnapshotBox.render(app: "Notes", window: "Gro\nceries", snapshot: 3, body: [], limit: 10, truncated: false)
        #expect(broken.contains("window \"Gro ceries\""))
        #expect(!broken.contains("\nceries"))
    }

    @Test func aNegativeLimitShowsTheHeaderAndCountsEveryRowAsHidden() {
        let text = AXSnapshotBox.render(app: "Mail", window: nil, snapshot: 2, body: ["one", "two"], limit: -1, truncated: false)
        #expect(text == "Controls in Mail (snapshot s2; use a ref like {\"ref\":\"s2:e1\"} to target one):\n- ... 2 more not listed")
    }
}
