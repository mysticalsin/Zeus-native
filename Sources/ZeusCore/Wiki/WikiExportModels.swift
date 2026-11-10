import Foundation

public enum WikiExportError: Error, LocalizedError, Equatable, Sendable {
    case destination(String)
    case selection(String)
    case staleDraft
    case needsReview
    case sensitiveReview
    case protocolMismatch
    case invalidResponse
    case conflict
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .destination(let message), .selection(let message): message
        case .staleDraft: "The selected pages, their sources, or the destination changed. Review a new export before sending."
        case .needsReview: "A selected page or its sources need review before export."
        case .sensitiveReview: "Review the sensitive information in this preview before exporting."
        case .protocolMismatch: "The local Memory export helper does not support this export contract. Update Zeus and try again."
        case .invalidResponse: "The export result could not be verified. Check the result before trying again."
        case .conflict: "A note with this export ID already exists with different content. Zeus left it unchanged."
        case .tooLarge: "This selection is too large for one export. Select fewer pages."
        }
    }
}

/// Only an explicitly configured, writable Memory inbox. No discovery or fallback roots.
public struct WikiExportDestination: Codable, Equatable, Sendable {
    public let connection: BrainConnection
    public let rootPath: String
    public let rootIdentity: String
    public let inbox: String

    public init(connection: BrainConnection) throws {
        guard connection.access == .readWrite, [.obsidian, .markdown].contains(connection.source.kind) else {
            throw WikiExportError.destination("Choose a read-and-write Obsidian or Markdown vault in Settings › Memory first.")
        }
        try WikiExportVault.validateInbox(connection.inboxFolder)
        let root = connection.source.url.resolvingSymlinksInPath().standardizedFileURL
        rootIdentity = try WikiExportVault.identity(of: root)
        self.connection = connection
        rootPath = root.path
        inbox = connection.inboxFolder
    }

    public var displayName: String { connection.source.name + " / " + inbox }
    public func relativePath(exportID: UUID) -> String { inbox + "/" + WikiExportVault.fileName(exportID) }

    public func validate(current: BrainConnection?) throws {
        guard current == connection,
              connection.source.url.resolvingSymlinksInPath().standardizedFileURL.path == rootPath,
              try WikiExportVault.identity(of: URL(fileURLWithPath: rootPath)) == rootIdentity else {
            throw WikiExportError.staleDraft
        }
    }
}

/// Current app-owned state, refreshed before the write boundary. Never contains private meeting notes.
public struct WikiExportSnapshot: Sendable {
    public let pages: [WikiPage]
    public let connection: BrainConnection?
    public let availableMeetingIDs: Set<UUID>
    public let forgottenMeetingIDs: Set<UUID>
    public let sourceTitles: [UUID: String]
    public let settingsReadable: Bool

    public init(pages: [WikiPage], connection: BrainConnection?, availableMeetingIDs: Set<UUID>,
                forgottenMeetingIDs: Set<UUID>, sourceTitles: [UUID: String], settingsReadable: Bool) {
        self.pages = pages
        self.connection = connection
        self.availableMeetingIDs = availableMeetingIDs
        self.forgottenMeetingIDs = forgottenMeetingIDs
        self.sourceTitles = sourceTitles
        self.settingsReadable = settingsReadable
    }
}

/// Exact reviewed bytes and source/page revisions. Retrying always retains the same ID and content.
public struct WikiExportDraft: Codable, Equatable, Identifiable, Sendable {
    public static let maxBytes = 512 * 1024
    public static let maxPages = 20
    public let id: UUID
    public let createdAt: Date
    public let destination: WikiExportDestination
    public let pages: [WikiPage]
    public let markdown: String
    public let sensitiveFindingCount: Int
    public let sourceTitles: [UUID: String]

    public static func make(selectedIDs: Set<String>, snapshot: WikiExportSnapshot,
                            id: UUID = UUID(), now: Date = Date()) throws -> Self {
        guard !selectedIDs.isEmpty, selectedIDs.count <= maxPages else {
            throw WikiExportError.selection("Select between 1 and \(maxPages) Memory pages to export.")
        }
        guard let connection = snapshot.connection else {
            throw WikiExportError.destination("Connect an Obsidian or Markdown vault in Settings › Memory first.")
        }
        let selected = snapshot.pages.filter { selectedIDs.contains($0.id) }.sorted { $0.id < $1.id }
        guard selected.count == selectedIDs.count, Set(selected.map(\.id)).count == selected.count else {
            throw WikiExportError.staleDraft
        }
        try checkSources(selected, in: snapshot)
        let destination = try WikiExportDestination(connection: connection)
        let stamp = ISO8601DateFormatter().string(from: now)
        func quoted(_ value: String) throws -> String {
            // JSON strings are also valid quoted YAML scalars; no unescaped front-matter values.
            String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        }
        let quotedIDs = try selected.map { try quoted($0.id) }.joined(separator: ", ")
        var lines = ["---", "type: zeus-memory-export", "schema: 1", "export_id: \(id.uuidString.lowercased())",
                     "created: \(stamp)", "page_ids: [\(quotedIDs)]", "---", "", "# Zeus Memory", ""]
        for page in selected {
            lines += ["## \(page.title.replacingOccurrences(of: "\n", with: " "))", "",
                      WikiCompiler.strippingMarkers(page.body), "", "### Sources", ""]
            if page.sources.isEmpty { lines.append("- Personal page; no linked source record.") }
            for source in page.sources {
                let label: String
                switch source {
                case .meeting(let sourceID): label = "Meeting: \(snapshot.sourceTitles[sourceID] ?? "Saved meeting")"
                case .preference(let key): label = "Preference: \(key)"
                case .memory: label = "Explicitly remembered item"
                }
                lines.append("- \(label.replacingOccurrences(of: "\n", with: " ")) — `\(source.exportIdentifier)`")
            }
            lines += ["", "_Zeus page: `\(page.id)`; source records open from Memory in Zeus._", ""]
        }
        let text = lines.joined(separator: "\n")
        guard text.utf8.count <= maxBytes else { throw WikiExportError.tooLarge }
        return Self(id: id, createdAt: now, destination: destination, pages: selected, markdown: text,
                    sensitiveFindingCount: SensitiveInfoScanner.scan(text, participantNames: selected.flatMap(\.participantNames)).count,
                    sourceTitles: snapshot.sourceTitles.filter { Set(selected.flatMap(\.meetingIDs)).contains($0.key) })
    }

    public func validate(snapshot: WikiExportSnapshot, acknowledgedSensitive: Bool) throws {
        try destination.validate(current: snapshot.connection)
        guard pages.allSatisfy({ page in snapshot.pages.first(where: { $0.id == page.id }) == page }) else {
            throw WikiExportError.staleDraft
        }
        guard sourceTitles.allSatisfy({ snapshot.sourceTitles[$0.key] == $0.value }) else { throw WikiExportError.staleDraft }
        try Self.checkSources(pages, in: snapshot)
        guard sensitiveFindingCount == 0 || acknowledgedSensitive else { throw WikiExportError.sensitiveReview }
    }

    private static func checkSources(_ pages: [WikiPage], in snapshot: WikiExportSnapshot) throws {
        guard snapshot.settingsReadable else { throw WikiExportError.needsReview }
        for page in pages {
            guard page.exportedMarkdown() != nil, page.forgottenContributors.isEmpty else { throw WikiExportError.needsReview }
            let meetingIDs = Set(page.meetingIDs + page.contributors + page.facts.flatMap { $0.sources.compactMap(\.meetingID) })
            guard meetingIDs.isDisjoint(with: snapshot.forgottenMeetingIDs),
                  meetingIDs.isSubset(of: snapshot.availableMeetingIDs) else { throw WikiExportError.needsReview }
        }
    }
}

extension WikiSource {
    public var exportIdentifier: String {
        switch self {
        case .meeting(let id): "meeting:\(id.uuidString.lowercased())"
        case .memory(let id): "memory:\(id.uuidString.lowercased())"
        case .preference(let key): "preference:\(key.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "\n", with: " "))"
        }
    }
}
