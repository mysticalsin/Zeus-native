import Foundation
import SQLite3

/// Recent notifications from other apps, read from macOS's local Notification Center store
/// (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`). Read-only (the database is
/// opened with SQLITE_OPEN_READONLY), needs Full Disk Access, never leaves the Mac.
public struct MirroredNotification: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var app: String
    public var title: String
    public var subtitle: String?
    public var body: String
    public var date: Date

    public init(id: Int64, app: String, title: String, subtitle: String?, body: String, date: Date) {
        self.id = id; self.app = app; self.title = title; self.subtitle = subtitle; self.body = body; self.date = date
    }
}

public enum NotificationMirror {
    public static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    public enum Failure: Error, Equatable { case noAccess, unreadable }

    /// The newest modification time of the store and its write-ahead log: unchanged means nothing new
    /// was delivered, so a poller can skip opening the database (a `stat` instead of an `open` + query).
    /// nil when the store cannot be statted (no access, or Notification Center never ran).
    public static func changeStamp(url: URL = databaseURL) -> Date? {
        let manager = FileManager.default
        let dates = [url.path, url.path + "-wal"].compactMap { path in
            (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
        return dates.max()
    }

    /// Newest first. `muted` holds bundle ids to hide.
    public static func recent(limit: Int = 30, muted: Set<String> = [], url: URL = databaseURL) -> Result<[MirroredNotification], Failure> {
        var handle: OpaquePointer?
        let path = "file:\(url.path)?mode=ro&immutable=0"
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return .failure(.noAccess)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let sql = """
            SELECT record.rec_id, app.identifier, record.data, record.delivered_date
            FROM record JOIN app ON app.app_id = record.app_id
            ORDER BY record.delivered_date DESC LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
            // A database we can open but not read is the Full Disk Access case.
            return .failure(sqlite3_errcode(db) == SQLITE_AUTH || sqlite3_errcode(db) == SQLITE_CANTOPEN ? .noAccess : .unreadable)
        }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int(query, 1, Int32(limit * 2))
        var out: [MirroredNotification] = []
        while sqlite3_step(query) == SQLITE_ROW, out.count < limit {
            let id = sqlite3_column_int64(query, 0)
            let app = sqlite3_column_text(query, 1).map { String(cString: $0) } ?? ""
            guard !muted.contains(app) else { continue }
            let bytes = sqlite3_column_bytes(query, 2)
            guard bytes > 0, let blob = sqlite3_column_blob(query, 2) else { continue }
            let data = Data(bytes: blob, count: Int(bytes))
            let delivered = sqlite3_column_double(query, 3)
            if var note = parse(data, app: app) {
                note.id = id
                note.date = Date(timeIntervalSinceReferenceDate: delivered)
                out.append(note)
            }
        }
        return .success(out)
    }

    /// The record's binary plist: `req` holds `titl`, `subt`, `body`.
    public static func parse(_ data: Data, app: String) -> MirroredNotification? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let request = root["req"] as? [String: Any] else { return nil }
        let title = (request["titl"] as? String) ?? ""
        let body = (request["body"] as? String) ?? ""
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return MirroredNotification(id: 0, app: (root["app"] as? String) ?? app, title: title,
                                    subtitle: request["subt"] as? String, body: body, date: Date(timeIntervalSince1970: 0))
    }

    /// "com.apple.MobileSMS" → "MobileSMS" when the app's name is not known.
    public static func shortName(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
