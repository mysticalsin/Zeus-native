import Testing
@testable import ZeusCore

@Suite struct SpokenPointingAskTests {
    private let file = PointingProposalCandidate(id: "t3", isSecure: false, label: "File")
    private let fileMenu = PointingProposalCandidate(id: "t4", isSecure: false, label: "File Menu")
    private let password = PointingProposalCandidate(id: "t5", isSecure: true, label: "Password")

    @Test func aSpokenPointAtFileIsAGuide() {
        let shown = SpokenPointingAsk.show(in: "point at the File menu", candidates: [file, fileMenu, password])
        #expect(shown?.targetID == "t4")
        #expect(shown?.bolt == "Point at File Menu")
        #expect(shown?.spoken == "File Menu is right here.")
        #expect(PointerGuideCaptionSplit.boltText(shown?.bolt ?? "") == shown?.bolt)
    }

    @Test func anExactShortLabelBeatsALongerOne() {
        let shown = SpokenPointingAsk.show(in: "show me File", candidates: [fileMenu, file])
        #expect(shown?.targetID == "t3")
        #expect(shown?.bolt == "Point at File")
    }

    @Test func aSecureFieldIsNotPointed() {
        #expect(SpokenPointingAsk.show(in: "point at Password", candidates: [password]) == nil)
    }

    @Test func anOpenOrALinkIsNotAPointingAsk() {
        let candidates = [file]
        #expect(SpokenPointingAsk.show(in: "open Safari", candidates: candidates) == nil)
        #expect(SpokenPointingAsk.show(in: "point at javascript:alert(1)", candidates: candidates) == nil)
        #expect(SpokenPointingAsk.show(in: "show me https://example.com", candidates: candidates) == nil)
    }

    @Test func anExplainHowStaysOffThisPath() {
        #expect(SpokenPointingAsk.isAsk("show me how a car can fly") == false)
        #expect(SpokenPointingAsk.show(in: "show me how a car can fly", candidates: [file]) == nil)
    }

    @Test func anEmptyAskShowsNothing() {
        #expect(SpokenPointingAsk.show(in: "   ", candidates: [file]) == nil)
        #expect(SpokenPointingAsk.show(in: "show me", candidates: [file]) == nil)
        #expect(SpokenPointingAsk.show(in: "point at File", candidates: []) == nil)
    }

    @Test func aTargetTheGateRefusesIsNotShown() {
        let broken = PointingProposalCandidate(id: "file", isSecure: false, label: "File")
        #expect(SpokenPointingAsk.show(in: "point at File", candidates: [broken]) == nil)
    }
}
