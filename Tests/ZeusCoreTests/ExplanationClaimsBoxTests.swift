import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation claims box")
struct ExplanationClaimsBoxTests {
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

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{0009}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{000A}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{000B}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{000C}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{000D}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{0020}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{0085}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{00A0}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{1680}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2000}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2001}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2002}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2003}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2004}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2005}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2006}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2007}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2008}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2009}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{200A}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2028}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{2029}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{202F}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{205F}"))
        #expect(ExplanationClaimsBox.blankScalars.contains("\u{3000}"))
        #expect(!ExplanationClaimsBox.blankScalars.contains("\u{200B}"))
        #expect(ExplanationClaimsBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(ExplanationClaimsBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(ExplanationClaimsBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceCountsAsClaimText() {
        #expect(ExplanationClaimsBox.hasBody("\u{200B}"))
        #expect(ExplanationClaimsBox.textIsBounded("\u{200B}", maximumScalars: 280))
        #expect(ExplanationClaimsBox.trimmed("\u{200B}") == "\u{200B}")
        let mark = "\u{200B}"
        #expect(ExplanationClaims.review(claim("g", .generic, mark), approvedSourceIDs: [])
                == .admitted(shown("g", .generic, mark)))
        let padded = " \u{200B} "
        #expect(ExplanationClaims.review(claim("g2", .generic, padded), approvedSourceIDs: [])
                == .admitted(shown("g2", .generic, padded)))
        #expect(ExplanationClaims.review(
            claim("b", .brandSpecific, mark, sources: ["manual"]),
            approvedSourceIDs: ["manual"]
        ) == .admitted(shown("b", .brandSpecific, mark, chip: ["manual"])))
    }

    @Test func aBodyOfOnlyNamedBlanksIsRefused() {
        #expect(!ExplanationClaimsBox.hasBody(""))
        #expect(!ExplanationClaimsBox.hasBody(" "))
        #expect(!ExplanationClaimsBox.hasBody("\u{00A0}"))
        #expect(!ExplanationClaimsBox.hasBody("\u{0085}"))
        #expect(!ExplanationClaimsBox.hasBody("\u{3000}"))
        #expect(!ExplanationClaimsBox.hasBody(" \t\n\u{00A0}\u{3000}"))
        #expect(ExplanationClaimsBox.hasBody("\u{00A0}\u{200B}"))
        #expect(ExplanationClaimsBox.trimmed("\u{00A0}\u{200B}\u{3000}") == "\u{200B}")
        for text in ["", "   ", "\n", "\u{00A0}", "\u{0085}", "\u{3000}", " \t\n\u{00A0}\u{3000}"] {
            #expect(!ExplanationClaimsBox.textIsBounded(text, maximumScalars: 280))
            #expect(ExplanationClaims.review(claim("g", .generic, text), approvedSourceIDs: [])
                    == .rejected(.textBounds))
        }
        let kept = "\u{00A0}\u{200B}\u{3000}"
        #expect(ExplanationClaims.review(claim("z", .generic, kept), approvedSourceIDs: [])
                == .admitted(shown("z", .generic, kept)))
    }

    @Test func namedBlanksAroundASentenceStayInTheShownLine() {
        let sentence = " \u{00A0}A battery stores energy.\u{3000} "
        #expect(ExplanationClaimsBox.hasBody(sentence))
        #expect(ExplanationClaimsBox.trimmed(sentence) == "A battery stores energy.")
        #expect(ExplanationClaimsBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(ExplanationClaims.review(claim("g", .generic, sentence), approvedSourceIDs: [])
                == .admitted(shown("g", .generic, sentence)))
        let marked = "\u{200B}"
        #expect(ExplanationClaims.review(claim("z", .generic, marked), approvedSourceIDs: [])
                == .admitted(shown("z", .generic, marked)))
    }

    @Test func aZeroWidthSpaceInsideTheSentenceStays() {
        let interior = "A battery\u{200B}stores energy."
        #expect(ExplanationClaimsBox.trimmed(interior) == interior)
        #expect(ExplanationClaimsBox.trimmed("\u{200B}A battery") == "\u{200B}A battery")
        #expect(ExplanationClaimsBox.trimmed("A battery\u{200B}") == "A battery\u{200B}")
        #expect(ExplanationClaims.review(claim("g", .generic, interior), approvedSourceIDs: [])
                == .admitted(shown("g", .generic, interior)))
        let leading = "\u{200B}A battery stores energy."
        #expect(ExplanationClaims.review(claim("g2", .generic, leading), approvedSourceIDs: [])
                == .admitted(shown("g2", .generic, leading)))
        #expect(ExplanationClaims.review(claim("g3", .generic, "A battery stores energy.\n"), approvedSourceIDs: [])
                == .rejected(.textBounds))
    }
}
