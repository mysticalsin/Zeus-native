import Foundation
import Testing
@testable import ZeusCore

@Suite("To-do connection blob")
struct TodoConnectionBlobTests {
    @Test func aTruncatedBlobIsCorruptAndTheBytesAreTheSameValue() throws {
        let bytes = Data("{}".utf8)
        guard case .corrupt(let kept) = TodoConnectionBlob.load(bytes) else {
            Issue.record("expected a corrupt blob")
            return
        }
        #expect(kept == bytes)
    }

    @Test func aRoundTripKeepsTheVaultPath() throws {
        let connection = BrainConnection(source: BrainSource(kind: .markdown, name: "Notes", path: "/tmp/zeus-notes"))
        let data = try TodoConnectionBlob.encode(connection)
        guard case .connected(let loaded) = TodoConnectionBlob.load(data) else {
            Issue.record("expected a connection")
            return
        }
        #expect(loaded.source.path == connection.source.path)
        #expect(loaded.access == connection.access)
    }

    @Test func encodeFailureWouldNotBeRepresentedAsRemoval() throws {
        let existing = Data("{\"keep\":true}".utf8)
        let connection = BrainConnection(source: BrainSource(kind: .markdown, name: "Notes", path: "/tmp/zeus-notes"))
        let stored = try TodoConnectionBlob.persisted(existing: existing, connection: connection)
        #expect(stored != nil)
        let removed = try TodoConnectionBlob.persisted(existing: existing, connection: nil)
        #expect(removed == nil)
    }
}
