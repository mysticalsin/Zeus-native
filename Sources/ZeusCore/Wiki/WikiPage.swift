import Foundation

/// Where a page may be seen. Every page starts `personal`; `global` only comes from `WikiPromotion.promote`.
public enum WikiScope: String, Codable, Sendable {
    case personal
    case global
}

/// Zeus-owned data a fact was learned from. Deleting the source deletes the fact.
public enum WikiSource: Codable, Hashable, Sendable {
    case meeting(UUID)
    case preference(String)
    case memory(UUID)

    public var meetingID: UUID? {
        if case .meeting(let id) = self { return id }
        return nil
    }
}

/// One extracted line: a decision or an action item. Facts that read the same (ignoring case and trailing
/// punctuation) within a page are merged, and the merged fact keeps every source that stated it.
public struct WikiFact: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case decision
        case action
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var done: Bool
    public var sources: [WikiSource]
    /// Participant names of the meetings behind this fact, so the sensitive-info check can look for them.
    public var participants: [String]

    public init(kind: Kind, text: String, done: Bool = false, sources: [WikiSource], participants: [String] = []) {
        self.kind = kind
        self.text = text
        self.done = done
        self.sources = sources
        self.participants = participants
        self.id = Self.id(kind: kind, text: text)
    }

    public static func id(kind: Kind, text: String) -> String {
        "\(kind.rawValue):\(WikiCompiler.normalizedKey(text))"
    }
}

public struct WikiPage: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// A file-name-safe slug (`topic-weekly-sync`).
    public var id: String
    public var title: String
    /// Markdown. Rendered from `facts` until the person edits it; after that the person owns it.
    public var body: String
    /// Set by any manual body edit and never cleared automatically. An unedited page is always regenerated from
    /// its remaining sources; an edited one is the person's text and is only flagged for review.
    public var userEdited: Bool
    public var facts: [WikiFact]
    public var sources: [WikiSource]
    public var scope: WikiScope
    public var promotedBy: String?
    public var promotedAt: Date?
    public var updatedAt: Date
    public var pinned: Bool
    /// Every meeting that ever contributed to this page (sorted by id). On an edited page a forgotten meeting
    /// stays here until the person clears the review.
    public var contributors: [UUID]
    /// The contributors that were forgotten or deleted while the page was edited. Removed from `contributors`
    /// when the person clears the review.
    public var forgottenContributors: [UUID]
    /// Set whenever a forgotten or deleted meeting is among the contributors of an edited page, whether or not
    /// any marker or fact is still found: its text may be in the person's own wording. Blocks export and global
    /// promotion until the person clears it.
    public var needsReview: Bool
    public var reviewReason: String?

    public init(
        id: String,
        title: String,
        body: String = "",
        userEdited: Bool = false,
        facts: [WikiFact] = [],
        sources: [WikiSource] = [],
        scope: WikiScope = .personal,
        promotedBy: String? = nil,
        promotedAt: Date? = nil,
        updatedAt: Date,
        pinned: Bool = false,
        contributors: [UUID] = [],
        forgottenContributors: [UUID] = [],
        needsReview: Bool = false,
        reviewReason: String? = nil
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.title = title
        self.body = body
        self.userEdited = userEdited
        self.facts = facts
        self.sources = sources
        self.scope = scope
        self.promotedBy = promotedBy
        self.promotedAt = promotedAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.contributors = contributors
        self.forgottenContributors = forgottenContributors
        self.needsReview = needsReview
        self.reviewReason = reviewReason
    }

    private enum LegacyKeys: String, CodingKey {
        case bodyEdited
    }

    /// Pages saved before provenance review existed have none of the review fields, and the earliest ones call
    /// `userEdited` `bodyEdited`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        if let edited = try container.decodeIfPresent(Bool.self, forKey: .userEdited) {
            userEdited = edited
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            userEdited = try legacy.decode(Bool.self, forKey: .bodyEdited)
        }
        facts = try container.decode([WikiFact].self, forKey: .facts)
        sources = try container.decode([WikiSource].self, forKey: .sources)
        scope = try container.decode(WikiScope.self, forKey: .scope)
        promotedBy = try container.decodeIfPresent(String.self, forKey: .promotedBy)
        promotedAt = try container.decodeIfPresent(Date.self, forKey: .promotedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        contributors = try container.decodeIfPresent([UUID].self, forKey: .contributors) ?? []
        forgottenContributors = try container.decodeIfPresent([UUID].self, forKey: .forgottenContributors) ?? []
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)
    }

    public static let reviewReasonForgottenText =
        "Text from a forgotten or deleted meeting may still be in this page, because you edited it and it can't be traced line by line."

    /// The reason shown for forgotten or deleted meetings, naming each one (`titles` by meeting id).
    public static func reviewReason(forgotten ids: [UUID], titles: [UUID: String]) -> String {
        guard !ids.isEmpty else { return reviewReasonForgottenText }
        let names = ids.sorted { $0.uuidString < $1.uuidString }
            .map { id in titles[id].map { "“\($0)”" } ?? "a meeting that is no longer saved" }
            .joined(separator: ", ")
        return "Text from the forgotten or deleted \(ids.count == 1 ? "meeting" : "meetings") \(names) may still be in this page, because you edited it and it can't be traced line by line."
    }

    /// The person has checked the page. Export and promotion are possible again, and the forgotten meetings
    /// are dropped from `contributors` (unless a meeting is back among the page's sources).
    public mutating func clearReview(now: Date) {
        guard needsReview || !forgottenContributors.isEmpty else { return }
        let live = Set(meetingIDs)
        let dropped = Set(forgottenContributors).subtracting(live)
        contributors.removeAll { dropped.contains($0) }
        forgottenContributors = []
        needsReview = false
        reviewReason = nil
        updatedAt = now
    }

    /// Alias of `userEdited`.
    public var bodyEdited: Bool {
        get { userEdited }
        set { userEdited = newValue }
    }

    public var meetingIDs: [UUID] { sources.compactMap(\.meetingID) }

    /// Names of the people in the meetings behind this page (sorted, unique).
    public var participantNames: [String] {
        Array(Set(facts.flatMap(\.participants))).sorted()
    }

    /// Replaces the body with the person's text. Returns true when that made a global page personal again:
    /// the sensitive-info check ran on the old text, so changed text has to be promoted (and checked) again.
    @discardableResult
    public mutating func applyEdit(body newBody: String, now: Date) -> Bool {
        guard newBody != body else { return false }
        body = newBody
        userEdited = true
        updatedAt = now
        guard scope == .global else { return false }
        scope = .personal
        promotedBy = nil
        promotedAt = nil
        return true
    }

    /// The text of an explicit single-page export.
    public func markdown() -> String {
        "# \(title)\n\n\(WikiCompiler.strippingMarkers(body))\n"
    }

    /// The export text, or nil while the page needs review. Every export path must use this one.
    public func exportedMarkdown() -> String? {
        needsReview ? nil : markdown()
    }
}

public enum WikiSearch {
    /// Pinned first, then newest.
    public static func ordered(_ pages: [WikiPage]) -> [WikiPage] {
        pages.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.id < b.id
        }
    }

    /// Every word of `query` must appear in the title or body (ignoring case). An empty query keeps all pages.
    public static func filter(_ pages: [WikiPage], query: String) -> [WikiPage] {
        let ordered = ordered(pages)
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return ordered }
        return ordered.filter { page in
            let haystack = (page.title + "\n" + page.body).lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}
