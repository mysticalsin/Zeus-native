import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A meeting brief built on this Mac. Nothing here is sent away.
public enum MeetingBrief {
    public static let summaryLimit = 280
    public static let retention: TimeInterval = 90 * 24 * 60 * 60

    public struct Settings: Equatable, Sendable {
        public var externalMeetings = true
        public var internalMeetings = false
        /// Exact email domains, compared in lowercase. Empty means the person has not chosen yet.
        public var domains: [String] = []
        public init() {}
    }

    public struct Card: Equatable, Sendable {
        public var name: String
        public var time: String
        public var role: String?
        public var company: String?
        public var summary: String?
        public var collapsed: Bool
    }

    public struct HistoryRecord: Equatable, Codable, Sendable {
        public var emailHash: String
        public var date: Date
        /// At most a short title. Never a note body.
        public var title: String
    }

    public static func plain(_ text: String, limit: Int = summaryLimit) -> String {
        var value = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        value = value.filter { character in
            character.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 && $0.properties.generalCategory != .control }
                || character.isNewline
        }
        let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit))
    }

    public static func domain(of email: String) -> String {
        email.split(separator: "@").last.map { $0.lowercased() } ?? ""
    }

    public static func needsDomainSetup(_ domains: [String]) -> Bool { domains.isEmpty }

    /// Exact domain match. An empty list treats every attendee as external.
    public static func isExternal(email: String, domains: [String]) -> Bool {
        let host = domain(of: email)
        guard !domains.isEmpty else { return true }
        return !domains.contains { $0.lowercased() == host }
    }

    public static func meetingIsExternal(emails: [String], domains: [String]) -> Bool {
        emails.contains { isExternal(email: $0, domains: domains) }
    }

    public static func showsBrief(settings: Settings, emails: [String]) -> Bool {
        let external = meetingIsExternal(emails: emails, domains: settings.domains)
        return external ? settings.externalMeetings : settings.internalMeetings
    }

    /// Shared, recorded, or a meeting app presenting: name and time only.
    /// When capture cannot be detected, the card stays collapsed until it is opened.
    public static func card(name: String, time: String, role: String?, company: String?, summary: String?,
                            shared: Bool, presenting: Bool, captureKnown: Bool, expanded: Bool,
                            contactsAllowed: Bool) -> Card {
        let forced = shared || presenting || !captureKnown
        let collapsed = forced && !expanded || shared || presenting
        let showPeople = contactsAllowed && !collapsed
        return Card(name: name, time: time, role: showPeople ? role : nil, company: showPeople ? company : nil,
                    summary: collapsed ? nil : summary, collapsed: collapsed || summary == nil && !showPeople)
    }

    public static func hash(email: String) -> String {
        let digest = SHA256.hash(data: Data(email.lowercased().utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func historyRecord(email: String, date: Date, title: String) -> HistoryRecord {
        let first = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return HistoryRecord(emailHash: hash(email: email), date: date, title: plain(first, limit: 80))
    }

    public static func keeping(_ records: [HistoryRecord], now: Date) -> [HistoryRecord] {
        records.filter { now.timeIntervalSince($0.date) <= retention }
    }
}

public enum MeetingBriefWindow {
    /// Excluded from screen capture.
    public static let sharingType = "none"
}

public enum MeetingBriefContacts {
    /// Calendar and Contacts are asked only while briefs are on, and only to read.
    public static func shouldRequest(featureOn: Bool, alreadyKnown: Bool) -> Bool {
        featureOn && !alreadyKnown
    }

    /// One email. Never a walk of the address book.
    public static func lookup(email: String, allowed: Bool, found: (role: String?, company: String?)?) -> (role: String?, company: String?) {
        guard allowed, email.contains("@"), let found else { return (nil, nil) }
        return found
    }
}

public enum MeetingBriefLog {
    /// A count only. Never an address, a note, or the brief.
    public static func line(recordCount: Int) -> String { "meeting brief \(recordCount)" }
}

/// Left unbuilt. Off, and it sends nothing.
public enum MeetingBriefOffDevice {
    public static let enabled = false
    public static let sentFields: [String] = []
}

/// Last-meeting memory: a hash, a date, and a title. 0600 file in a 0700 directory.
public final class MeetingBriefStore {
    public static let directoryMode: UInt16 = 0o700
    public static let fileMode: UInt16 = 0o600
    public let directory: URL
    private let fileName = "history.json"

    public init(directory: URL) { self.directory = directory }

    public func load(now: Date) throws -> [MeetingBrief.HistoryRecord] {
        guard let folder = try openDirectory(create: false) else { return [] }
        defer { close(folder) }
        guard let data = try read(folder) else { return [] }
        let records = try JSONDecoder().decode([MeetingBrief.HistoryRecord].self, from: data)
        return MeetingBrief.keeping(records, now: now)
    }

    public func save(_ records: [MeetingBrief.HistoryRecord], now: Date) throws {
        let previous = umask(0o077)
        defer { _ = umask(previous) }
        let kept = MeetingBrief.keeping(records, now: now)
        let data = try JSONEncoder().encode(kept)
        let folder = try openDirectory(create: true)
        guard let folder else { throw CocoaError(.fileWriteUnknown) }
        defer { close(folder) }
        let temporary = ".brief-\(UUID().uuidString).tmp"
        let file = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(Self.fileMode))
        guard file >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(file); _ = unlinkat(folder, temporary, 0) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let wrote = write(file, base.advanced(by: offset), buffer.count - offset)
                if wrote < 0 && errno == EINTR { continue }
                guard wrote > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += wrote
            }
        }
        guard fsync(file) == 0 else { throw CocoaError(.fileWriteUnknown) }
        if linkat(folder, temporary, folder, fileName, 0) != 0 && errno != EEXIST {
            throw CocoaError(.fileWriteUnknown)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    public func clear() throws {
        guard let folder = try openDirectory(create: false) else { return }
        defer { close(folder) }
        _ = unlinkat(folder, fileName, 0)
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        if create, mkdir(directory.path, mode_t(Self.directoryMode)) != 0 && errno != EEXIST {
            throw CocoaError(.fileWriteUnknown)
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if !create && errno == ENOENT { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        return fd
    }

    private func read(_ folder: Int32) throws -> Data? {
        let fd = openat(folder, fileName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, buffer.count)
            #else
            let count = Glibc.read(fd, &buffer, buffer.count)
            #endif
            if count < 0 && errno == EINTR { continue }
            if count == 0 { break }
            guard count > 0 else { throw CocoaError(.fileReadUnknown) }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
