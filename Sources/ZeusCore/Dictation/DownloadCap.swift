import Foundation

/// The overall limit for one model or voice download. The 45 s, 20 s and 8 s request timeouts
/// stay where they are; this cap does not replace them. Tests pass their own clock.
public enum DownloadKind: Equatable, Sendable {
    case model
    case voice
}

public enum DownloadCap {
    public static let overall: TimeInterval = 10 * 60
    /// Left unchanged. A download is not cut off at these request timeouts.
    public static let requestTimeouts: [TimeInterval] = [45, 20, 8]

    public enum Effect: Equatable, Sendable {
        case cancelAndRemovePartials
        case showTookTooLong
        case restart(DownloadKind)
    }
}

public struct DownloadBarState: Equatable, Sendable {
    public var message: String?
    public var retryTitle: String?
    public static let tookTooLong = "This download took too long."
    public static let retry = "Retry"

    public init(message: String? = nil, retryTitle: String? = nil) {
        self.message = message
        self.retryTitle = retryTitle
    }
}

public struct DownloadTookTooLong: Error, Equatable, LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { DownloadBarState.tookTooLong }
}

/// Idle, running, finished, cancelled, or past the cap. `advance` is how an injected clock moves.
public struct DownloadSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(kind: DownloadKind, startedAt: TimeInterval)
        case tookTooLong(kind: DownloadKind)
        case finished(kind: DownloadKind)
        case cancelled(kind: DownloadKind)
    }

    public private(set) var phase = Phase.idle
    public private(set) var bar = DownloadBarState()

    public init() {}

    public mutating func start(_ kind: DownloadKind, now: TimeInterval) -> [DownloadCap.Effect] {
        guard case .idle = phase else { return [] }
        phase = .running(kind: kind, startedAt: now)
        bar = DownloadBarState()
        return []
    }

    public mutating func advance(to now: TimeInterval) -> [DownloadCap.Effect] {
        guard case .running(let kind, let started) = phase, now >= started + DownloadCap.overall else { return [] }
        phase = .tookTooLong(kind: kind)
        bar = DownloadBarState(message: DownloadBarState.tookTooLong, retryTitle: DownloadBarState.retry)
        return [.cancelAndRemovePartials, .showTookTooLong]
    }

    public mutating func finish(now: TimeInterval) -> [DownloadCap.Effect] {
        _ = now
        guard case .running(let kind, _) = phase else { return [] }
        phase = .finished(kind: kind)
        bar = DownloadBarState()
        return []
    }

    public mutating func cancel(now: TimeInterval) -> [DownloadCap.Effect] {
        _ = now
        guard case .running(let kind, _) = phase else { return [] }
        phase = .cancelled(kind: kind)
        bar = DownloadBarState()
        return [.cancelAndRemovePartials]
    }

    public mutating func retry(now: TimeInterval) -> [DownloadCap.Effect] {
        guard case .tookTooLong(let kind) = phase else { return [] }
        phase = .running(kind: kind, startedAt: now)
        bar = DownloadBarState()
        return [.restart(kind)]
    }
}

/// Files a setup wrote, so a cap or a cancel can delete those and leave older files.
public enum InstallFootprint {
    /// Every file and directory under `root`, as a path relative to `root`. Ancestors are included.
    public static func snapshot(_ root: URL) -> Set<String> {
        let rootPath = root.path
        guard !rootPath.isEmpty else { return [] }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: []) else {
            return []
        }
        var paths = Set<String>()
        for case let url as URL in walker {
            let path = url.path
            guard path.hasPrefix(prefix) else { continue }
            var relative = String(path.dropFirst(prefix.count))
            while !relative.isEmpty {
                paths.insert(relative)
                guard let slash = relative.lastIndex(of: "/") else { break }
                relative = String(relative[..<slash])
            }
        }
        return paths
    }

    /// What to delete after a setup stops.
    /// A root that this run created is removed whole. A virtual environment that this run created is removed whole.
    /// When both were already there, only paths that were not in `before` are removed, and a new directory covers its children.
    public static func removals(root: URL, rootExisted: Bool, tree: URL, treeExisted: Bool, before: Set<String>) -> [URL] {
        if !rootExisted { return [root] }
        if !treeExisted { return [tree] }
        let added = snapshot(tree).subtracting(before)
        let tops = added.filter { relative in
            guard let slash = relative.lastIndex(of: "/") else { return true }
            return !added.contains(String(relative[..<slash]))
        }
        return tops.sorted().map { tree.appendingPathComponent($0) }
    }
}

public enum PartialFiles {
    /// Deletes each file or folder. A path that is already gone is success. Returns paths still present.
    @discardableResult
    public static func remove(_ urls: [URL]) -> [URL] {
        let manager = FileManager.default
        for url in urls where manager.fileExists(atPath: url.path) {
            try? manager.removeItem(at: url)
        }
        return urls.filter { manager.fileExists(atPath: $0.path) }
    }
}

public struct DownloadCapExceeded: Error, Equatable, Sendable {
    public init() {}
}

public enum DownloadRunResult: Equatable, Sendable {
    case finished
    case tookTooLong
    case cancelled
    case capped
    case failed(String)
}

public enum DownloadRunner {
    /// Runs `body` until it finishes, the task is cancelled, or the injected clock passes the cap.
    /// Hitting the cap cancels the work and deletes `partials`.
    public static func run(
        kind: DownloadKind,
        clock: @escaping @Sendable () -> TimeInterval,
        partials: @escaping @Sendable () -> [URL],
        body: @escaping @Sendable () async throws -> Void
    ) async -> DownloadRunResult {
        _ = kind
        let deadline = clock() + DownloadCap.overall
        let outcome: DownloadRunResult = await withTaskGroup(of: DownloadRunResult.self) { group in
            group.addTask {
                do {
                    try await body()
                    return .finished
                } catch is CancellationError {
                    return .cancelled
                } catch is DownloadCapExceeded {
                    return .capped
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            group.addTask {
                while clock() < deadline {
                    if Task.isCancelled { return .cancelled }
                    do { try await Task.sleep(nanoseconds: 5_000_000) } catch { return .cancelled }
                }
                return .tookTooLong
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            while await group.next() != nil {}
            return first
        }
        if outcome == .tookTooLong || outcome == .cancelled || outcome == .capped { _ = PartialFiles.remove(partials()) }
        return outcome
    }
}
