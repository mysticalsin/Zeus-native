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

    @Test func theHostAllowsOneOriginAndTheSocketIsOwnerOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let installer = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Chrome/ChromeInstaller.swift"), encoding: .utf8)
        let socket = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/UnixSocket.swift"), encoding: .utf8)
        #expect(installer.contains("\"allowed_origins\": [\"chrome-extension://\\(ZeusPaths.extensionID)/\"]"))
        #expect(socket.contains("chmod(path, 0o600)"))
    }
}
