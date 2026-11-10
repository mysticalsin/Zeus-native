import Foundation

public enum WikiLinkDirection: Equatable, Sendable {
    case outgoing
    case incoming
    case both
}

/// A connection backed by identical current source IDs or a person's explicit [[page]] link.
/// It makes no claim that the pages agree or caused one another. Historical contributors aren't evidence.
public struct WikiRelatedPage: Equatable, Identifiable, Sendable {
    public var id: String { pageID }
    public let pageID: String
    public let title: String
    public let sharedSources: [WikiSource]
    public let linkDirection: WikiLinkDirection?
}

public enum WikiRelationships {
    public static func related(
        to pageID: String,
        in pages: [WikiPage],
        availableMeetingIDs: Set<UUID>,
        excluding forgottenMeetingIDs: Set<UUID> = []
    ) -> [WikiRelatedPage] {
        guard let origin = pages.first(where: { $0.id == pageID }) else { return [] }
        func evidence(for page: WikiPage) -> Set<WikiSource> {
            let excluded = forgottenMeetingIDs.union(page.forgottenContributors)
            return Set(page.sources.filter { source in
                guard let id = source.meetingID else { return true }
                return availableMeetingIDs.contains(id) && !excluded.contains(id)
            })
        }
        let originEvidence = evidence(for: origin)
        // IDs are exact; titles match only after case/whitespace normalization and only if unique.
        // Bracket text is never interpreted as a path, URL, query, alias, or inferred topic.
        let ids = Set(pages.map(\.id))
        let titles = Dictionary(grouping: pages, by: { normalizedTitle($0.title) })
        func links(from page: WikiPage) -> Set<String> {
            guard page.userEdited, !page.needsReview, page.forgottenContributors.isEmpty else { return [] }
            var result: Set<String> = []
            for reference in references(in: page.body) {
                if ids.contains(reference) { result.insert(reference); continue }
                let matches = Set((titles[normalizedTitle(reference)] ?? []).map(\.id))
                if matches.count == 1, let id = matches.first { result.insert(id) }
            }
            result.remove(page.id)
            return result
        }
        let outgoing = links(from: origin)
        var seen: Set<String> = [pageID]
        return pages.compactMap { page -> WikiRelatedPage? in
            guard seen.insert(page.id).inserted else { return nil }
            let shared = originEvidence.intersection(evidence(for: page))
            let canLink = !origin.needsReview && !page.needsReview
                && origin.forgottenContributors.isEmpty && page.forgottenContributors.isEmpty
            let forward = canLink && outgoing.contains(page.id)
            let reverse = canLink && links(from: page).contains(origin.id)
            let direction: WikiLinkDirection? = forward ? (reverse ? .both : .outgoing) : (reverse ? .incoming : nil)
            guard !shared.isEmpty || direction != nil else { return nil }
            return WikiRelatedPage(pageID: page.id, title: page.title,
                                   sharedSources: shared.sorted { key($0) < key($1) }, linkDirection: direction)
        }.sorted {
            if ($0.linkDirection != nil) != ($1.linkDirection != nil) { return $0.linkDirection != nil }
            if $0.sharedSources.count != $1.sharedSources.count { return $0.sharedSources.count > $1.sharedSources.count }
            let lhs = $0.title.lowercased(), rhs = $1.title.lowercased()
            return lhs == rhs ? $0.pageID < $1.pageID : lhs < rhs
        }
    }

    private static func normalizedTitle(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// A small, deterministic wiki-link grammar; no regex backtracking or filesystem resolution.
    private static func references(in body: String) -> [String] {
        var remainder = body.prefix(65_536)
        var references: [String] = []
        while references.count < 128, let opening = remainder.range(of: "[[") {
            remainder = remainder[opening.upperBound...]
            guard let closing = remainder.range(of: "]]") else { break }
            let raw = remainder[..<closing.lowerBound]
            if !raw.contains(where: { $0 == "[" || $0 == "]" || $0.isNewline }) {
                let reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reference.isEmpty { references.append(reference) }
            }
            remainder = remainder[closing.upperBound...]
        }
        return references
    }

    private static func key(_ source: WikiSource) -> String {
        switch source {
        case .meeting(let id): return "meeting:\(id.uuidString)"
        case .preference(let key): return "preference:\(key)"
        case .memory(let id): return "memory:\(id.uuidString)"
        }
    }
}
