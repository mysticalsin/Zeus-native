import Foundation
import Testing
@testable import ZeusCore

@Suite("Deck URL predicate")
struct DeckURLPredicateTests {
    @Test func hostileURLsAreRejected() {
        let hostile = [
            "http://docs.google.com/presentation/d/abc",
            "https://docs.google.com:444/presentation/d/abc",
            "https://user:pw@docs.google.com/presentation/d/abc",
            "https://docs.google.com:80/presentation/d/abc",
            "https://docs.google.com/presentation/d/abc/../../../etc",
        ]
        for url in hostile {
            #expect(!DeckURL.isPresentation(url), "\(url)")
        }
        #expect(DeckURL.isPresentation("https://docs.google.com/presentation/d/abc/edit"))
        #expect(DeckURL.isPresentation("https://docs.google.com:443/presentation/d/abc"))
    }
}
