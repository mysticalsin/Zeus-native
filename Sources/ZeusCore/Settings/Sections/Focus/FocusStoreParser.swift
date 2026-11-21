import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A pure read of the two Focus store documents. It never opens a file. A bad document is unreadable, never a guessed name.
public enum FocusStoreParser {
    public static let maxBytes = 4 * 1024 * 1024
    public static let maxModes = 64
    public static let maxRecords = 256
    public static let maxIdentifierLength = 200

    public enum Reason: Equatable, Sendable {
        case malformed
        case tooLarge
        case denied
        case missing
        case notAFile
        case refused
        case other
    }

    public enum Read: Equatable, Sendable {
        case off
        case on(name: String?, symbol: String?)
        case unreadable(Reason)
    }

    public enum Place: Equatable, Sendable {
        case folder
        case assertions
        case configurations
    }

    public static func parse(assertions: Data, configurations: Data?) -> Read {
        guard assertions.count <= maxBytes else { return .unreadable(.tooLarge) }
        guard let root = jsonObject(assertions) as? [String: Any] else { return .unreadable(.malformed) }
        guard let data = root["data"] as? [Any], !data.isEmpty else { return .unreadable(.malformed) }

        guard let entry = data.compactMap({ $0 as? [String: Any] }).first(where: { $0.keys.contains("storeAssertionRecords") }) else {
            return .off
        }
        guard let records = entry["storeAssertionRecords"] as? [Any] else { return .unreadable(.malformed) }
        if records.isEmpty { return .off }

        let usable = usableRecords(in: records)
        if usable.isEmpty { return .on(name: nil, symbol: nil) }
        guard let chosen = choose(usable) else { return .on(name: nil, symbol: nil) }

        var modes = modeMap(in: root)
        if modes[chosen.id] == nil, let configurations, configurations.count <= maxBytes, let extraRoot = jsonObject(configurations) {
            let extra = modeMap(in: extraRoot)
            if let found = extra[chosen.id] { modes[chosen.id] = found }
        }
        guard let mode = modes[chosen.id] else { return .on(name: nil, symbol: nil) }
        let name = (mode["name"] as? String).flatMap(FocusNameText.cleanName)
        let symbol = (mode["symbolImageName"] as? String).flatMap(FocusNameText.cleanSymbol)
        return .on(name: name, symbol: symbol)
    }

    /// Maps a failed open onto a read. The configurations file never fails the whole read: a missing one only drops the name.
    public static func mapErrno(_ code: Int32, place: Place) -> Read {
        switch place {
        case .configurations:
            return .on(name: nil, symbol: nil)
        case .folder:
            if code == EPERM || code == EACCES { return .unreadable(.denied) }
            if code == ENOENT { return .unreadable(.missing) }
            if code == ENOTDIR || code == ELOOP { return .unreadable(.notAFile) }
            return .unreadable(.other)
        case .assertions:
            if code == EPERM || code == EACCES { return .unreadable(.denied) }
            if code == ENOENT { return .off }
            if code == ELOOP { return .unreadable(.notAFile) }
            return .unreadable(.other)
        }
    }

    private struct Candidate {
        var index: Int
        var id: String
        var time: Double?
    }

    private static func usableRecords(in records: [Any]) -> [Candidate] {
        records.prefix(maxRecords).enumerated().compactMap { index, item in
            guard let record = item as? [String: Any],
                  let details = record["assertionDetails"] as? [String: Any],
                  let id = details["assertionDetailsModeIdentifier"] as? String,
                  !id.isEmpty, id.count <= maxIdentifierLength else { return nil }
            return Candidate(index: index, id: id, time: double(record["assertionStartDateTimestamp"]))
        }
    }

    private static func choose(_ records: [Candidate]) -> Candidate? {
        records.max { lhs, rhs in
            let left = lhs.time ?? -.infinity
            let right = rhs.time ?? -.infinity
            if left != right { return left < right }
            return lhs.index > rhs.index
        }
    }

    private static func modeMap(in root: Any) -> [String: [String: Any]] {
        var found: [String: [String: Any]] = [:]
        if let root = root as? [String: Any] {
            if let data = root["data"] as? [Any] {
                for entry in data {
                    guard let dict = entry as? [String: Any], let modes = dict["modeConfigurations"] as? [String: Any] else { continue }
                    collect(modes, into: &found)
                }
            }
            if let modes = root["modeConfigurations"] as? [String: Any] {
                collect(modes, into: &found)
            }
        }
        if found.count <= maxModes { return found }
        let kept = found.keys.sorted().prefix(maxModes)
        return found.filter { kept.contains($0.key) }
    }

    private static func collect(_ modes: [String: Any], into found: inout [String: [String: Any]]) {
        for (id, value) in modes {
            guard let wrapper = value as? [String: Any] else { continue }
            if let mode = wrapper["mode"] as? [String: Any] {
                found[id] = mode
            } else if wrapper["name"] != nil || wrapper["symbolImageName"] != nil {
                found[id] = wrapper
            }
        }
    }

    private static func jsonObject(_ data: Data) -> Any? {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    private static func double(_ value: Any?) -> Double? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }
}
