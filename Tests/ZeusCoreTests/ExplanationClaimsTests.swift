import Foundation
import Testing
@testable import ZeusCore

/// Phase 4 claims (docs/POINTING-ASSISTANT-PLAN.md).
/// A generic fact carries no source chip. A brand-specific claim with no source
/// is rejected. A brand-specific claim whose sources are outside the approved
/// registry is downgraded to "varies by model" with a "needs reference" badge.
@Suite("Explanation claims")
struct ExplanationClaimsTests {
    private let genericSentence = "A battery stores energy."
    private let brandSentence = "Pack capacity is 82 kWh."
    private let approved: Set<String> = ["manual"]

    private func claim(
        _ id: String,
        _ scope: ExplanationClaims.Scope,
        _ text: String,
        sources: [String] = []
    ) -> ExplanationClaims.Claim {
        ExplanationClaims.Claim(id: id, scope: scope, text: text, sourceIDs: sources)
    }

    private func shown(
        _ id: String,
        _ scope: ExplanationClaims.Scope,
        _ text: String,
        chip: [String] = [],
        badge: String? = nil
    ) -> ExplanationClaims.Presented {
        ExplanationClaims.Presented(id: id, scope: scope, text: text, sourceChip: chip, badge: badge)
    }

    @Test func thePlanPhrasesAreExact() {
        #expect(ExplanationClaims.variesByModel == "varies by model")
        #expect(ExplanationClaims.needsReference == "needs reference")
        #expect(ExplanationClaims.maximumPerEvent == 8)
        #expect(ExplanationClaims.maximumSources == 4)
        #expect(ExplanationClaims.maximumTextScalars == 280)
    }

    @Test func aBrandSpecificClaimWithoutASourceIsRejectedOrDowngraded() {
        let json = """
        [\
        {"id":"g","scope":"generic","text":"\(genericSentence)"},\
        {"id":"b","scope":"brandSpecific","text":"\(brandSentence)","sourceIDs":["manual"]},\
        {"id":"u","scope":"brandSpecific","text":"\(brandSentence)","sourceIDs":["rumor"]},\
        {"id":"n","scope":"brandSpecific","text":"\(brandSentence)"}\
        ]
        """
        let outcomes = ExplanationClaims.review(json: Data(json.utf8), approvedSourceIDs: approved)
        #expect(outcomes == [
            .admitted(shown("g", .generic, genericSentence)),
            .admitted(shown("b", .brandSpecific, brandSentence, chip: ["manual"])),
            .downgraded(shown("u", .brandSpecific, "varies by model", badge: "needs reference")),
            .rejected(.needsSource),
        ])
        let missing = claim("n", .brandSpecific, brandSentence)
        #expect(ExplanationClaims.review(missing, approvedSourceIDs: approved) == .rejected(.needsSource))
        let unapproved = claim("u", .brandSpecific, brandSentence, sources: ["rumor"])
        let downgraded = ExplanationClaims.review(unapproved, approvedSourceIDs: approved)
        guard case .downgraded(let presented) = downgraded else {
            Issue.record("expected a downgrade")
            return
        }
        #expect(presented.text == "varies by model")
        #expect(presented.text != brandSentence)
        #expect(presented.badge == "needs reference")
        #expect(presented.sourceChip.isEmpty)
        #expect(presented.scope == .brandSpecific)
        #expect(downgraded == ExplanationClaims.review(unapproved, approvedSourceIDs: approved))
    }

    @Test func genericFactsCarryNoSourceChip() {
        let plain = claim("g", .generic, genericSentence)
        let cited = claim("g2", .generic, genericSentence, sources: ["manual"])
        let punctuated = claim("g3", .generic, "A battery stores energy, then a motor turns the wheels.")
        #expect(ExplanationClaims.review(plain, approvedSourceIDs: approved) == .admitted(shown("g", .generic, genericSentence)))
        #expect(ExplanationClaims.review(cited, approvedSourceIDs: approved) == .admitted(shown("g2", .generic, genericSentence)))
        #expect(ExplanationClaims.review(punctuated, approvedSourceIDs: []) == .admitted(
            shown("g3", .generic, "A battery stores energy, then a motor turns the wheels.")))
        let mixed = ExplanationClaims.review(
            [plain, claim("b", .brandSpecific, brandSentence, sources: ["rumor"])],
            approvedSourceIDs: approved)
        #expect(mixed.count == 2)
        guard case .admitted(let generic) = mixed[0], case .downgraded = mixed[1] else {
            Issue.record("generic stays admitted while the unsourced brand claim is downgraded")
            return
        }
        #expect(generic.sourceChip.isEmpty)
        #expect(generic.badge == nil)
    }

    @Test func anApprovedSourceKeepsTheBrandSentenceAndDropsUnapprovedIds() {
        let ordered = claim("b", .brandSpecific, brandSentence, sources: ["zeta", "rumor", "manual"])
        let outcome = ExplanationClaims.review(ordered, approvedSourceIDs: ["manual", "zeta"])
        #expect(outcome == .admitted(shown("b", .brandSpecific, brandSentence, chip: ["zeta", "manual"])))
        let reversed = claim("b2", .brandSpecific, brandSentence, sources: ["manual", "zeta"])
        #expect(ExplanationClaims.review(reversed, approvedSourceIDs: ["zeta", "manual"])
                == .admitted(shown("b2", .brandSpecific, brandSentence, chip: ["manual", "zeta"])))
        let four = claim("b4", .brandSpecific, brandSentence, sources: ["s0", "s1", "s2", "s3"])
        #expect(ExplanationClaims.review(four, approvedSourceIDs: []) == .downgraded(
            shown("b4", .brandSpecific, "varies by model", badge: "needs reference")))
        let five = claim("b5", .brandSpecific, brandSentence, sources: ["manual", "s1", "s2", "s3", "s4"])
        #expect(ExplanationClaims.review(five, approvedSourceIDs: approved) == .rejected(.sourceBudget))
    }

    @Test func anEmptyRegistryDowngradesACitedBrandClaim() {
        let cited = claim("u", .brandSpecific, brandSentence, sources: ["manual"])
        #expect(ExplanationClaims.review(cited, approvedSourceIDs: []) == .downgraded(
            shown("u", .brandSpecific, "varies by model", badge: "needs reference")))
        let missing = claim("n", .brandSpecific, brandSentence)
        #expect(ExplanationClaims.review(missing, approvedSourceIDs: []) == .rejected(.needsSource))
    }

    @Test func nineClaimsAreRejectedAsABudget() {
        var claims = (0..<8).map { claim("c\($0)", .generic, genericSentence) }
        claims.append(claim("bad id", .brandSpecific, ""))
        #expect(ExplanationClaims.review(claims, approvedSourceIDs: approved) == [.rejected(.claimBudget)])
        #expect(ExplanationClaims.review(Array(claims.prefix(8)), approvedSourceIDs: approved).count == 8)
    }

    @Test func duplicateClaimIdsAndDuplicateSourcesAreRejected() {
        let first = claim("g", .generic, genericSentence)
        let second = claim("g", .generic, "A motor turns a shaft.")
        let outcomes = ExplanationClaims.review([first, second], approvedSourceIDs: approved)
        #expect(outcomes == [
            .admitted(shown("g", .generic, genericSentence)),
            .rejected(.duplicateClaim),
        ])
        let duplicates = claim("b", .brandSpecific, brandSentence, sources: ["manual", "manual"])
        #expect(ExplanationClaims.review(duplicates, approvedSourceIDs: approved) == .rejected(.duplicateSource))
        let copies = claim("b2", .brandSpecific, brandSentence, sources: ["manual", "manual", "manual", "manual", "manual"])
        #expect(ExplanationClaims.review(copies, approvedSourceIDs: approved) == .rejected(.sourceBudget))
    }

    @Test func identifierAndTextBounds() {
        #expect(ExplanationClaims.review(claim("ok_id-1", .generic, genericSentence), approvedSourceIDs: [])
                == .admitted(shown("ok_id-1", .generic, genericSentence)))
        #expect(ExplanationClaims.review(claim(String(repeating: "a", count: 64), .generic, genericSentence), approvedSourceIDs: [])
                == .admitted(shown(String(repeating: "a", count: 64), .generic, genericSentence)))
        for id in ["", " ", "a b", "a.b", "a/b", String(repeating: "a", count: 65)] {
            #expect(ExplanationClaims.review(claim(id, .generic, genericSentence), approvedSourceIDs: []) == .rejected(.identifier))
        }
        #expect(ExplanationClaims.review(claim("-a", .generic, genericSentence), approvedSourceIDs: [])
                == .admitted(shown("-a", .generic, genericSentence)))
        #expect(ExplanationClaims.review(claim("b", .brandSpecific, brandSentence, sources: ["bad id"]), approvedSourceIDs: [])
                == .rejected(.identifier))
        let exact = String(repeating: "a", count: 280)
        #expect(ExplanationClaims.review(claim("g", .generic, exact), approvedSourceIDs: [])
                == .admitted(shown("g", .generic, exact)))
        #expect(ExplanationClaims.review(claim("g", .generic, exact + "a"), approvedSourceIDs: []) == .rejected(.textBounds))
        let pair = "e\u{0301}"
        let within = String(repeating: pair, count: 140)
        #expect(within.unicodeScalars.count == 280)
        #expect(within.count == 140)
        #expect(within.utf8.count == 420)
        #expect(ExplanationClaims.review(claim("g", .generic, within), approvedSourceIDs: [])
                == .admitted(shown("g", .generic, within)))
        let over = String(repeating: pair, count: 141)
        #expect(over.unicodeScalars.count == 282)
        #expect(ExplanationClaims.review(claim("g", .generic, over), approvedSourceIDs: []) == .rejected(.textBounds))
        for text in ["", "   ", "\n", "A battery stores energy.\n", "A battery\u{0001}stores energy."] {
            #expect(ExplanationClaims.review(claim("g", .generic, text), approvedSourceIDs: []) == .rejected(.textBounds))
        }
    }

    @Test func closedJSONRejectsUnknownFieldsAndTheWrongShape() {
        let bad = [
            #"[{"id":"g","scope":"generic","text":"A battery stores energy.","url":"https://example.com"}]"#,
            #"{"id":"g","scope":"generic","text":"A battery stores energy."}"#,
            #"[{"id":"b","scope":"brandSpecific","text":"Pack capacity is 82 kWh.","sourceIDs":"manual"}]"#,
            #"[{"id":"b","scope":"brand","text":"Pack capacity is 82 kWh.","sourceIDs":["manual"]}]"#,
            "",
            #"{"claims":[]}"#,
            #"[{"id":1,"scope":"generic","text":"A battery stores energy."}]"#,
            #"[{"id":"g","scope":"generic","text":"A battery stores energy.","sourceIDs":null}]"#,
        ]
        for payload in bad {
            #expect(ExplanationClaims.review(json: Data(payload.utf8), approvedSourceIDs: approved) == [.rejected(.malformed)])
        }
        #expect(ExplanationClaims.review(json: Data("[]".utf8), approvedSourceIDs: approved) == [])
    }

    @Test func aClaimRoundTrips() throws {
        let brand = claim("b", .brandSpecific, brandSentence, sources: ["manual", "press"])
        let brandData = try JSONEncoder().encode(brand)
        #expect(try JSONDecoder().decode(ExplanationClaims.Claim.self, from: brandData) == brand)
        let generic = claim("g", .generic, genericSentence)
        let genericData = try JSONEncoder().encode(generic)
        #expect(try JSONDecoder().decode(ExplanationClaims.Claim.self, from: genericData) == generic)
        let reviewed = ExplanationClaims.review(json: brandData, approvedSourceIDs: [])
        #expect(reviewed == [.rejected(.malformed)])
    }
}
