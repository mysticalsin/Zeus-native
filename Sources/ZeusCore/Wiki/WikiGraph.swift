import Foundation

public enum WikiGraphFilter: String, CaseIterable, Identifiable, Sendable {
    case all, authoredLinks, sharedSources
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "All connections"
        case .authoredLinks: "Authored links"
        case .sharedSources: "Shared sources"
        }
    }
}

public struct WikiGraphNode: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let isFocus: Bool
    /// Stable normalized coordinates; the renderer performs only a size transform.
    public let x: Double
    public let y: Double
}

public struct WikiGraphEdge: Equatable, Identifiable, Sendable {
    public var id: String { targetID }
    public let sourceID: String
    public let targetID: String
    public let sharedSources: [WikiSource]
    public let linkDirection: WikiLinkDirection?
}

/// A bounded visual projection of the same evidenced relationships used by the accessible list.
/// This adds no links, reads no records, and infers no relationship from wording or proximity.
public struct WikiGraphSnapshot: Equatable, Sendable {
    public static let maximumNeighbors = 8
    public let focusID: String?
    public let nodes: [WikiGraphNode]
    public let edges: [WikiGraphEdge]
    /// Every matching connection, including visual overflow, stays available to the list.
    public let relationships: [WikiRelatedPage]
    public let totalRelationshipCount: Int
    public var hiddenCount: Int { max(0, relationships.count - edges.count) }

    public static func make(focus: WikiPage?, relationships: [WikiRelatedPage],
                            filter: WikiGraphFilter = .all, query: String = "",
                            neighborLimit: Int = maximumNeighbors) -> Self {
        guard let focus else {
            return Self(focusID: nil, nodes: [], edges: [], relationships: [], totalRelationshipCount: 0)
        }
        // Identical duplicates collapse; conflicting values for one ID fail closed.
        let grouped = Dictionary(grouping: relationships.filter { $0.pageID != focus.id && !$0.pageID.isEmpty }, by: \.pageID)
        let unique = grouped.values.compactMap { values -> WikiRelatedPage? in
            guard let first = values.first, values.allSatisfy({ $0 == first }),
                  first.linkDirection != nil || !first.sharedSources.isEmpty else { return nil }
            return first
        }.sorted {
            if ($0.linkDirection != nil) != ($1.linkDirection != nil) { return $0.linkDirection != nil }
            if $0.sharedSources.count != $1.sharedSources.count { return $0.sharedSources.count > $1.sharedSources.count }
            let lhs = $0.title.lowercased(), rhs = $1.title.lowercased()
            return lhs == rhs ? $0.pageID < $1.pageID : lhs < rhs
        }
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        let matching = unique.filter { relation in
            let kindMatches: Bool
            switch filter {
            case .all: kindMatches = true
            case .authoredLinks: kindMatches = relation.linkDirection != nil
            case .sharedSources: kindMatches = !relation.sharedSources.isEmpty
            }
            let searchable = relation.title.lowercased() + " " + relation.pageID.lowercased()
            return kindMatches && terms.allSatisfy { searchable.contains($0) }
        }
        let visible = Array(matching.prefix(min(maximumNeighbors, max(0, neighborLimit))))
            .sorted { $0.pageID < $1.pageID }
        var nodes = [WikiGraphNode(id: focus.id, title: focus.title, isFocus: true, x: 0.5, y: 0.5)]
        for (index, relation) in visible.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(visible.count)
            nodes.append(WikiGraphNode(id: relation.pageID, title: relation.title, isFocus: false,
                                       x: 0.5 + 0.38 * cos(angle), y: 0.5 + 0.36 * sin(angle)))
        }
        let edges = visible.map {
            WikiGraphEdge(sourceID: focus.id, targetID: $0.pageID, sharedSources: $0.sharedSources, linkDirection: $0.linkDirection)
        }
        return Self(focusID: focus.id, nodes: nodes, edges: edges, relationships: matching, totalRelationshipCount: unique.count)
    }
}
