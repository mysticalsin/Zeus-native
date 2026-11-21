import Foundation

/// WAV engines and the temp files they play. Finishing a clip drops that engine and returns the file to delete.
public struct ProviderEngineBook: Equatable, Sendable {
    public private(set) var engines = 0
    public private(set) var files: [URL] = []

    public init() {}

    public mutating func started(_ file: URL) {
        engines += 1
        files.append(file)
    }

    public mutating func finished(_ file: URL) -> URL? {
        guard let index = files.lastIndex(of: file) else { return nil }
        files.remove(at: index)
        engines = max(0, engines - 1)
        return file
    }

    public mutating func stopAll() -> [URL] {
        let gone = files
        files = []
        engines = 0
        return gone
    }
}

public final class ProviderEngineTracker: @unchecked Sendable {
    public static let shared = ProviderEngineTracker()
    private let lock = NSLock()
    private var book = ProviderEngineBook()

    public init() {}

    public func started(_ file: URL) {
        lock.lock(); book.started(file); lock.unlock()
    }

    public func finished(_ file: URL) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return book.finished(file)
    }

    public func stopAll() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return book.stopAll()
    }
}
