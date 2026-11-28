import Foundation

/// The sources of a research answer, drawn on the talk surface.
///
/// The voice still says the summary. The screen builds the sources: a ring and the word
/// Sources, then an arrow, then one card per site. Only http and https addresses are drawn.
/// A host is shown once. `www.` is dropped. At most three sites are drawn.
public struct ResearchSourceDraw: Equatable, Sendable {
    public static let maxHosts = 3

    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var hosts: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, hosts: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.hosts = hosts
    }

    /// Nil when no http(s) source has a host.
    public static func plan(sources: [String]) -> ResearchSourceDraw? {
        let hosts = hosts(in: sources)
        guard !hosts.isEmpty else { return nil }
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Sources"), at: 0),
            .init(shape: .arrow(from: .init(x: 480, y: 320), to: .init(x: 900, y: 320)), at: 1),
        ]
        for (index, host) in hosts.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: host), at: 2 + index))
        }
        guard let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json) else { return nil }
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ResearchSourceDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), hosts: hosts)
    }

    /// The short line beside the bolt for the beat that is visible at `elapsed`.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 2 else { return "Sources" }
        let index = last - 2
        guard hosts.indices.contains(index) else { return "Sources" }
        return Self.shortLine(hosts[index])
    }

    /// Where the bolt sits: the ring, then the arrow, then the newest source card.
    public func guideBolt(at elapsed: TimeInterval) -> TalkDraw.Point? {
        let shown = Set(schedule.revealed(at: elapsed))
        let marks = draw.marks.filter { shown.contains($0.at) }
        guard let beat = marks.map(\.at).max() else { return nil }
        let placed = marks.filter { $0.at == beat }.compactMap { mark -> (Int, TalkDraw.Point)? in
            guard let point = Self.anchor(of: mark) else { return nil }
            return (Self.preference(mark), point)
        }
        return placed.min { $0.0 < $1.0 }?.1
    }

    /// Distinct site names, in order. A missing host, or a scheme other than http or https, is skipped.
    public static func hosts(in sources: [String]) -> [String] {
        var seen = Set<String>()
        var hosts: [String] = []
        for raw in sources {
            guard let host = site(raw), seen.insert(host).inserted else { continue }
            hosts.append(host)
            if hosts.count == maxHosts { break }
        }
        return hosts
    }

    private static func site(_ raw: String) -> String? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        guard !host.isEmpty else { return nil }
        return String(host.prefix(TalkDraw.maxTextCharacters))
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "Sources" : line
    }

    private static func preference(_ mark: TalkDraw.Mark) -> Int {
        switch mark.shape {
        case .ring: return 0
        case .arrow: return 1
        case .ink: return 2
        case .card: return 3
        }
    }

    private static func anchor(of mark: TalkDraw.Mark) -> TalkDraw.Point? {
        switch mark.shape {
        case .ring(let center, let radius):
            guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else { return nil }
            return center
        case .arrow(let from, let to):
            let point = TalkDraw.Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            guard point.x.isFinite, point.y.isFinite else { return nil }
            return point
        case .ink(let points):
            return points.last
        case .card(let origin, _):
            guard origin.x.isFinite, origin.y.isFinite else { return nil }
            return origin
        }
    }
}
