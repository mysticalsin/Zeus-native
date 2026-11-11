import Foundation

/// The self-test receipt (schema_version 1). Thread-safe, because the hard-timeout watchdog may
/// write it from a background queue while the main actor is stuck. It holds the fixed fixture
/// transcript, dimensions and numbers only: no keys, no screenshots, no model output.
final class PointingSelfTestReceipt: @unchecked Sendable {
    enum Status: String { case passed, failed, blocked, notMeasured = "not-measured" }

    struct CheckSpec { var id: String; var title: String; var required: Bool }
    static let checks: [CheckSpec] = [
        .init(id: "lifecycle", title: "Session lifecycle, spoil and double hold", required: true),
        .init(id: "capture", title: "One event-driven capture per turn, only with consent", required: true),
        .init(id: "coordinates", title: "AX frame to image pixels and back, every display", required: true),
        .init(id: "targeting", title: "AX element at the pointer is the fixture button", required: true),
        .init(id: "protocol", title: "Strict protocol: split chunks, malformed and off-image", required: true),
        .init(id: "rendering", title: "Ring hugs the button, overlay level, click-through, ink", required: true),
        .init(id: "sync", title: "Marker flight starts at or after first audio", required: true),
        .init(id: "interruption", title: "Second hold or Esc stops speech within 150 ms", required: true),
        .init(id: "repeat", title: "Three consecutive turns leak nothing", required: true),
        .init(id: "resources", title: "Memory delta and main-thread gaps", required: false),
    ]

    private let lock = NSLock()
    private var entries: [String: [String: Any]] = [:]
    private var header: [String: Any] = [:]
    private let started = Date()
    private let path: String

    init(path: String) {
        self.path = path
        for spec in Self.checks {
            entries[spec.id] = ["id": spec.id, "title": spec.title, "required": spec.required,
                                "status": Status.failed.rawValue, "reason": "check did not run", "metrics": [String: Any]()]
        }
    }

    /// JSON has no NaN or infinity, and a lone bad number would otherwise drop the whole receipt.
    private static func clean(_ value: Any) -> Any {
        switch value {
        case let d as Double: return d.isFinite ? d : NSNull()
        case let f as Float: return f.isFinite ? f : NSNull()
        case let a as [Any]: return a.map(clean)
        case let m as [String: Any]: return m.mapValues(clean)
        default: return value
        }
    }

    func setHeader(_ values: [String: Any]) { lock.withLock { for (k, v) in values { header[k] = Self.clean(v) } } }

    func set(_ id: String, _ status: Status, reason: String = "", pane: String? = nil, metrics: [String: Any] = [:]) {
        lock.withLock {
            guard var entry = entries[id] else { return }
            entry["status"] = status.rawValue; entry["reason"] = reason; entry["metrics"] = Self.clean(metrics)
            if let pane { entry["permission_pane"] = pane } else { entry.removeValue(forKey: "permission_pane") }
            entries[id] = entry
        }
    }

    func status(_ id: String) -> Status? {
        lock.withLock { (entries[id]?["status"] as? String).flatMap(Status.init(rawValue:)) }
    }

    /// 0 only when every required check passed; 3 when the only gaps are permission blocks; 1 otherwise.
    var exitCode: Int32 {
        lock.withLock {
            var blocked = false
            for spec in Self.checks where spec.required {
                switch (entries[spec.id]?["status"] as? String).flatMap(Status.init(rawValue:)) {
                case .passed?: continue
                case .blocked?: blocked = true
                default: return 1
                }
            }
            return blocked ? 3 : 0
        }
    }

    func render(finished: Date = Date(), timedOut: Bool = false) -> Data {
        lock.withLock {
            var root = header
            root["schema_version"] = 1
            root["started_at"] = ISO8601DateFormatter().string(from: started)
            root["finished_at"] = ISO8601DateFormatter().string(from: finished)
            root["timed_out"] = timedOut
            root["checks"] = Self.checks.compactMap { entries[$0.id] }
            let data = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
            return data
        }
    }

    @discardableResult
    func write(timedOut: Bool = false) -> Bool {
        let data = render(timedOut: timedOut)
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch { return false }
    }
}
