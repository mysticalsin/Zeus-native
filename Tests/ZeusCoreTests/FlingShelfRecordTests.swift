import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling Shelf record")
struct FlingShelfRecordTests {
    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fling-shelf-\(UUID().uuidString)", isDirectory: true)
    }
    private func record(_ n: Int, origin: ShelfOrigin = .fling(peer: "Mac")) -> FlingShelfRecord {
        FlingShelfRecord(path: "/tmp/f\(n).png", origin: origin, stackID: UUID(), verified: true, addedAt: Date(timeIntervalSince1970: Double(n)), link: nil)
    }

    @Test func originsRoundTripThroughJSON() throws {
        for origin in [ShelfOrigin.local, .airDrop, .fling(peer: "Tony's Mac")] {
            let data = try JSONEncoder().encode(origin)
            #expect(try JSONDecoder().decode(ShelfOrigin.self, from: data) == origin)
        }
    }

    /// REG-678: records survive a relaunch, newest 500 only, with owner-only permissions.
    @Test func recordsPersistWithOwnerOnlyPermissionsAndAreCappedAtFiveHundred() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Shelf/shelf.json")
        let store = FlingShelfPersistence(url: url)
        var records = (0..<510).map { record($0) }
        records.append(FlingShelfRecord(path: "/tmp/link.webloc", origin: .fling(peer: "Mac"), stackID: nil, verified: true, addedAt: Date(timeIntervalSince1970: 999), link: "https://example.com"))
        #expect(store.save(records) == .saved)
        let loaded = store.load()
        #expect(loaded.records.count == 500)
        #expect(loaded.records.first == records[records.count - 500])
        #expect(loaded.records.last?.link == "https://example.com")
        #expect(!loaded.unreadable)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func aMissingFileIsEmptyAndNotUnreadable() {
        let loaded = FlingShelfPersistence(url: temp().appendingPathComponent("none.json")).load()
        #expect(loaded.records.isEmpty && !loaded.unreadable)
    }

    /// REG-678: a file that cannot be read is never overwritten.
    @Test func anUnreadableFileIsNeverOverwritten() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shelf.json")
        try Data("not json at all".utf8).write(to: url)
        let store = FlingShelfPersistence(url: url)
        let loaded = store.load()
        #expect(loaded.unreadable && loaded.records.isEmpty)
        #expect(store.save([record(1)]) == .refusedUnreadable)
        #expect(try Data(contentsOf: url) == Data("not json at all".utf8))
    }

    @Test func aNewerFileVersionIsUnreadableToThisBuild() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shelf.json")
        try Data(#"{"version":99,"records":[]}"#.utf8).write(to: url)
        #expect(FlingShelfPersistence(url: url).load().unreadable)
    }
}
