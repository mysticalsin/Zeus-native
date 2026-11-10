import Foundation

/// Extractive, pure builder of per-topic pages from saved Scribe meetings. No model is involved.
/// It reads only a meeting's title, id, decisions, action items and participant labels. Private notes, the
/// summary and the transcript text are never read into a page.
public enum WikiCompiler {
    public static let defaultTopic = "meetings"

    // MARK: Topics

    /// One topic per meeting title, ignoring case, accents, punctuation and number-only words (dates, counts),
    /// so "Weekly sync 11/07" and "Weekly sync 11/14" share a page. Always safe as a file name.
    public static func topicID(forTitle title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var words: [String] = []
        var current = ""
        var hasNonASCII = false
        for scalar in folded.unicodeScalars {
            let value = scalar.value
            let isAlnum = (97...122).contains(value) || (48...57).contains(value)
            if isAlnum {
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty { words.append(current); current = "" }
                if !scalar.isASCII && !CharacterSet.whitespacesAndNewlines.contains(scalar) { hasNonASCII = true }
            }
        }
        if !current.isEmpty { words.append(current) }
        words = words.filter { word in !word.unicodeScalars.allSatisfy { (48...57).contains($0.value) } }
        var slug = words.joined(separator: "-")
        if slug.count > 60 { slug = String(slug.prefix(60)) }
        if slug.isEmpty {
            // Titles in other scripts have no ASCII words; a stable hash keeps them apart.
            slug = hasNonASCII ? "t-" + stableHash(folded.trimmingCharacters(in: .whitespacesAndNewlines)) : defaultTopic
        }
        return "topic-" + slug
    }

    private static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private static func stableHash(_ text: String) -> String {
        String(fnv(text), radix: 16)
    }

    // MARK: Line provenance

    // Every rendered line ends with an invisible marker naming the fact it came from: U+2060, 32 bits as
    // U+200B (0) / U+200C (1), U+2060. It survives the person editing the line, so when the fact's source is
    // forgotten the line can still be found.
    private static let markerDelimiter: UInt32 = 0x2060

    static func provenanceToken(for fact: WikiFact) -> UInt32 {
        UInt32(truncatingIfNeeded: fnv(fact.id))
    }

    static func marker(for fact: WikiFact) -> String {
        let token = provenanceToken(for: fact)
        var scalars = String.UnicodeScalarView()
        scalars.append(Unicode.Scalar(markerDelimiter)!)
        for shift in stride(from: 31, through: 0, by: -1) {
            scalars.append(Unicode.Scalar((token >> UInt32(shift)) & 1 == 1 ? 0x200C : 0x200B)!)
        }
        scalars.append(Unicode.Scalar(markerDelimiter)!)
        return String(scalars)
    }

    /// The text without provenance markers, and the fact tokens the markers named.
    static func parseMarkers(_ text: String) -> (visible: String, tokens: Set<UInt32>) {
        let scalars = Array(text.unicodeScalars)
        var visible = String.UnicodeScalarView()
        var tokens = Set<UInt32>()
        var index = 0
        while index < scalars.count {
            if scalars[index].value == markerDelimiter, let (token, next) = decodeMarker(scalars, from: index) {
                tokens.insert(token)
                index = next
                continue
            }
            visible.append(scalars[index])
            index += 1
        }
        return (String(visible), tokens)
    }

    private static func decodeMarker(_ scalars: [Unicode.Scalar], from start: Int) -> (UInt32, Int)? {
        let end = start + 33
        guard end < scalars.count, scalars[end].value == markerDelimiter else { return nil }
        var value: UInt32 = 0
        for index in (start + 1)..<end {
            switch scalars[index].value {
            case 0x200B: value <<= 1
            case 0x200C: value = (value << 1) | 1
            default: return nil
            }
        }
        return (value, end + 1)
    }

    /// Text with provenance markers removed (what an export or a reader should see).
    public static func strippingMarkers(_ text: String) -> String {
        parseMarkers(text).visible
    }

    // MARK: Text

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Case-insensitive, whitespace-collapsed, trailing sentence punctuation removed.
    public static func normalizedKey(_ text: String) -> String {
        var key = clean(text).lowercased()
        while let last = key.last, ".!?;:,".contains(last) { key.removeLast() }
        return key
    }

    public static func line(for fact: WikiFact) -> String {
        switch fact.kind {
        case .decision: return "- \(fact.text)"
        case .action: return "- [\(fact.done ? "x" : " ")] \(fact.text)"
        }
    }

    private static func markedLine(for fact: WikiFact) -> String {
        line(for: fact) + marker(for: fact)
    }

    public static func render(facts: [WikiFact]) -> String {
        var sections: [String] = []
        let decisions = facts.filter { $0.kind == .decision }
        if !decisions.isEmpty {
            sections.append((["## Decisions"] + decisions.map(markedLine(for:))).joined(separator: "\n"))
        }
        let actions = facts.filter { $0.kind == .action }
        if !actions.isEmpty {
            sections.append((["## Action items"] + actions.map(markedLine(for:))).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Labelled participants of a meeting. Generic labels ("Speaker", "You") are not names.
    public static func participantNames(in record: ScribeMeetingRecord) -> [String] {
        let generic: Set<String> = ["speaker", "you", "unknown", "participant", "me"]
        var seen = Set<String>()
        var names: [String] = []
        for line in record.transcript where line.speakerKind == "participant" {
            guard let label = line.speakerLabel else { continue }
            let name = clean(label)
            let lowered = name.lowercased()
            guard !name.isEmpty, !generic.contains(lowered), !lowered.hasPrefix("speaker "), seen.insert(lowered).inserted else { continue }
            names.append(name)
        }
        return names
    }

    // MARK: Compile

    /// Whether a meeting missing from the store may be taken as deleted. A missing or empty meetings
    /// folder (moved, partial restore) reads as zero records and zero failures, which must not wipe
    /// Memory: it counts as "unknown", the same as an unreadable file.
    public static func mayRemoveMissing(recordCount: Int, failureCount: Int, folderExists: Bool) -> Bool {
        failureCount == 0 && folderExists && recordCount > 0
    }

    /// Reconciles `existing` with the saved meetings and returns the new page list.
    /// - `excluding`: meetings the person forgot. They are never ingested and their facts are removed.
    /// - `removeMissing`: when true, facts of a meeting that is no longer in `meetings` are removed (the source
    ///   was deleted). Pass false when some meeting files could not be read, so an unreadable file is not
    ///   mistaken for a deleted one.
    /// Pages not touched by meeting facts come back unchanged. A page that loses its last source is dropped.
    /// - `ingest`: false (learning paused) only stops NEW ingestion. Forgotten and deleted sources are still
    ///   removed, because pausing must never keep forgotten data alive.
    public static func compile(
        meetings: [ScribeMeetingRecord],
        into existing: [WikiPage],
        excluding: Set<UUID> = [],
        removeMissing: Bool = true,
        ingest: Bool = true,
        now: Date
    ) -> [WikiPage] {
        reconcile(meetings: meetings, into: existing, excluding: excluding, removeMissing: removeMissing, ingest: ingest, now: now).pages
    }

    /// `compile`, plus how many edited body lines were removed because their source is gone.
    public static func reconcile(
        meetings: [ScribeMeetingRecord],
        into existing: [WikiPage],
        excluding: Set<UUID> = [],
        removeMissing: Bool = true,
        ingest: Bool = true,
        now: Date
    ) -> WikiReconcileResult {
        var editedRemoved = 0
        let known = Set(meetings.map(\.id))
        let included = meetings
            .filter { ingest && !excluding.contains($0.id) }
            .sorted { ($0.endedAt, $0.id.uuidString) < ($1.endedAt, $1.id.uuidString) }
        let reingest = Set(included.map(\.id))

        var originals: [String: WikiPage] = [:]
        for page in existing where originals[page.id] == nil { originals[page.id] = page }
        let titles = Dictionary(meetings.map { ($0.id, clean($0.title)) }, uniquingKeysWith: { first, _ in first })
        let isRemoved: (UUID) -> Bool = { excluding.contains($0) || (removeMissing && !known.contains($0)) }

        // Drop what these meetings said before, then say it again from their current content.
        var pages = existing
        for index in pages.indices {
            stripSources(from: &pages[index]) { source in
                guard let id = source.meetingID else { return false }
                return reingest.contains(id) || excluding.contains(id) || (removeMissing && !known.contains(id))
            }
        }

        var indexByID: [String: Int] = [:]
        for (index, page) in pages.enumerated() where indexByID[page.id] == nil { indexByID[page.id] = index }
        for meeting in included {
            let incoming = facts(from: meeting)
            guard !incoming.isEmpty else { continue }
            let id = topicID(forTitle: meeting.title)
            let index: Int
            if let found = indexByID[id] {
                index = found
            } else {
                let title = clean(meeting.title)
                pages.append(WikiPage(id: id, title: title.isEmpty ? "Meeting notes" : title, updatedAt: now))
                index = pages.count - 1
                indexByID[id] = index
            }
            for fact in incoming { merge(fact, into: &pages[index]) }
        }

        var result: [WikiPage] = []
        for var page in pages {
            let original = originals[page.id]
            let nonMeeting = page.sources.filter { $0.meetingID == nil }
            page.sources = unique(nonMeeting + page.facts.flatMap(\.sources))
            if page.sources.isEmpty, let original, !original.sources.isEmpty { continue }
            finish(&page, original: original, isRemoved: isRemoved, titles: titles, now: now, editedRemoved: &editedRemoved)
            result.append(page)
        }
        return WikiReconcileResult(pages: result, editedLinesRemoved: editedRemoved)
    }

    /// Deletes one source everywhere. An unedited page is regenerated from the remaining sources. An edited
    /// page loses the lines its gone facts rendered and, because the person's wording can't be traced, is
    /// flagged `needsReview` when the source was a contributor. A page left with no source is dropped.
    /// `meetingTitle` names the meeting in the review reason.
    public static func removeSource(_ source: WikiSource, from pages: [WikiPage], meetingTitle: String? = nil, now: Date) -> [WikiPage] {
        removeSourceReporting(source, from: pages, meetingTitle: meetingTitle, now: now).pages
    }

    /// `removeSource`, plus how many edited body lines were removed because they came from that source.
    public static func removeSourceReporting(
        _ source: WikiSource, from pages: [WikiPage], meetingTitle: String? = nil, now: Date
    ) -> WikiReconcileResult {
        var editedRemoved = 0
        var result: [WikiPage] = []
        let meetingID = source.meetingID
        let titles: [UUID: String] = meetingID.flatMap { id in meetingTitle.map { [id: clean($0)] } } ?? [:]
        for original in pages {
            // A contributor counts even when none of its facts is on the page any more.
            let touches = original.sources.contains(source)
                || original.facts.contains { $0.sources.contains(source) }
                || (meetingID.map { original.contributors.contains($0) } ?? false)
            guard touches else {
                result.append(original)
                continue
            }
            var page = original
            stripSources(from: &page) { $0 == source }
            if page.sources.isEmpty { continue }
            finish(&page, original: original, isRemoved: { $0 == meetingID }, titles: titles, now: now, editedRemoved: &editedRemoved)
            result.append(page)
        }
        return WikiReconcileResult(pages: result, editedLinesRemoved: editedRemoved)
    }

    // MARK: Internals

    private static func facts(from meeting: ScribeMeetingRecord) -> [WikiFact] {
        let names = participantNames(in: meeting)
        let source = WikiSource.meeting(meeting.id)
        var out: [WikiFact] = []
        for decision in meeting.decisions {
            let text = limited(clean(decision))
            guard !text.isEmpty else { continue }
            out.append(WikiFact(kind: .decision, text: text, sources: [source], participants: names))
        }
        for item in meeting.actionItems {
            let text = limited(clean(item.text))
            guard !text.isEmpty else { continue }
            out.append(WikiFact(kind: .action, text: text, done: item.done, sources: [source], participants: names))
        }
        return out
    }

    private static func limited(_ text: String) -> String {
        text.count > 500 ? String(text.prefix(500)) + "…" : text
    }

    private static func merge(_ fact: WikiFact, into page: inout WikiPage) {
        guard let index = page.facts.firstIndex(where: { $0.id == fact.id }) else {
            page.facts.append(fact)
            return
        }
        for source in fact.sources where !page.facts[index].sources.contains(source) {
            page.facts[index].sources.append(source)
        }
        for name in fact.participants where !page.facts[index].participants.contains(name) {
            page.facts[index].participants.append(name)
        }
        page.facts[index].done = page.facts[index].done || fact.done
    }

    private static func stripSources(from page: inout WikiPage, where remove: (WikiSource) -> Bool) {
        page.sources.removeAll(where: remove)
        var kept: [WikiFact] = []
        for var fact in page.facts {
            fact.sources.removeAll(where: remove)
            if !fact.sources.isEmpty { kept.append(fact) }
        }
        page.facts = kept
    }

    private static func unique(_ sources: [WikiSource]) -> [WikiSource] {
        var seen = Set<WikiSource>()
        return sources.filter { seen.insert($0).inserted }
    }

    /// Brings the page in line with its sources, then stamps `updatedAt` only when something really changed.
    ///
    /// The provenance rule, with nothing to trace:
    /// - An unedited page is always regenerated from the facts that remain, so nothing from a removed source
    ///   can survive in it, and its contributors are exactly the sources that remain.
    /// - An edited page keeps the person's text. `contributors` only grows (until the review is cleared), and a
    ///   removed meeting that is among them flags the page `needsReview`, whether or not any marker or fact
    ///   of it is still found. Lines of facts that are gone are still taken out as a courtesy.
    /// `isRemoved`: meetings that were forgotten or deleted in this pass. `titles` name them in the reason.
    private static func finish(
        _ page: inout WikiPage,
        original: WikiPage?,
        isRemoved: (UUID) -> Bool,
        titles: [UUID: String],
        now: Date,
        editedRemoved: inout Int
    ) {
        let current = Set(page.facts.flatMap { $0.sources.compactMap(\.meetingID) })
        if !page.userEdited {
            page.contributors = current.sorted { $0.uuidString < $1.uuidString }
            page.forgottenContributors = []
            // A page with no facts before or after isn't compiler-managed: its body is left alone.
            if !page.facts.isEmpty || !(original?.facts.isEmpty ?? true) { page.body = render(facts: page.facts) }
        } else {
            var known = Set(page.contributors)
            if let original {
                known.formUnion(original.contributors)
                known.formUnion(original.meetingIDs)
                known.formUnion(original.facts.flatMap { $0.sources.compactMap(\.meetingID) })
            }
            let lost = known.filter(isRemoved).subtracting(page.forgottenContributors)
            page.contributors = known.union(current).sorted { $0.uuidString < $1.uuidString }
            if !lost.isEmpty {
                page.forgottenContributors = Set(page.forgottenContributors).union(lost).sorted { $0.uuidString < $1.uuidString }
                let reason = WikiPage.reviewReason(forgotten: Array(lost), titles: titles)
                page.reviewReason = page.needsReview ? [page.reviewReason, reason].compactMap { $0 }.joined(separator: " ") : reason
                page.needsReview = true
            }
            if let original, original.facts != page.facts {
                // The person owns this text: only the lines of facts that no longer exist are taken out.
                let kept = Set(page.facts.map(\.id))
                let gone = original.facts.filter { !kept.contains($0.id) }
                let trimmed = removingLines(of: gone, from: page.body)
                page.body = trimmed.body
                editedRemoved += trimmed.edited
            }
        }
        if page.needsReview, page.scope == .global { page = WikiPromotion.demote(page) }
        guard let original else { return }
        // New facts or new participant names were never checked. A global page that gains any goes back to
        // personal, so promotion (and its sensitive-info check) has to run again. Removals keep the scope.
        if page.scope == .global {
            let knownFacts = Set(original.facts.map(\.id))
            let knownNames = Set(original.participantNames)
            if page.facts.contains(where: { !knownFacts.contains($0.id) }) || !Set(page.participantNames).isSubset(of: knownNames) {
                page = WikiPromotion.demote(page)
            }
        }
        var probe = page
        probe.updatedAt = original.updatedAt
        page.updatedAt = probe == original ? original.updatedAt : now
    }

    /// Takes out the lines of removed facts. A line is removed entirely when it carries ANY removed fact's
    /// marker or still says a removed fact's text. A marker of a kept fact never keeps such a line, so a line
    /// that joins a forgotten fact with a kept one goes too.
    /// `edited` counts removed lines that were not the untouched original rendering.
    private static func removingLines(of gone: [WikiFact], from body: String) -> (body: String, edited: Int) {
        let goneTokens = Set(gone.map(provenanceToken(for:)))
        let plain = Set(gone.flatMap { ["- \($0.text)", "- [ ] \($0.text)", "- [x] \($0.text)"] })
        let goneKeys = gone.map { normalizedKey($0.text) }.filter { !$0.isEmpty }
        var edited = 0
        var lines: [String] = []
        for line in body.components(separatedBy: "\n") {
            let parsed = parseMarkers(line)
            let visible = parsed.visible.trimmingCharacters(in: .whitespaces)
            if plain.contains(visible) { continue }
            let lowered = clean(visible).lowercased()
            let mentions = !visible.hasPrefix("#") && goneKeys.contains { lowered.contains($0) }
            if !parsed.tokens.isDisjoint(with: goneTokens) || mentions {
                edited += 1
                continue
            }
            lines.append(line)
        }
        return (lines.joined(separator: "\n"), edited)
    }

}

public struct WikiReconcileResult: Sendable {
    public var pages: [WikiPage]
    /// Edited lines taken out because the meeting they came from was forgotten or deleted.
    public var editedLinesRemoved: Int
}
