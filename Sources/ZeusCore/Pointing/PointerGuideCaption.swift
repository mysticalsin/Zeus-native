import CoreGraphics
import Foundation

/// The on-screen helper caption. Three roles, and nothing else, may reach the overlay.
public enum PointerGuideCaptionSplit {
    public static let maxLines = 3
    public static let maxLineCharacters = 40
    /// Same delay the pointing label already uses between characters.
    public static let characterDelay: TimeInterval = 0.04

    /// Lines drawn beside the bolt. At most three short lines: what it is, what to do,
    /// what happens next. A blank role is skipped. A long role, a line break, or a caption
    /// made only of thread detail is not shown. `detail` stays off the overlay.
    public static func overlayLines(whatItIs: String, whatToDo: String, whatHappensNext: String, detail: String) -> [String]? {
        _ = detail
        let roles = [whatItIs, whatToDo, whatHappensNext].map(normalize)
        guard roles.contains(where: { !$0.isEmpty }) else { return nil }
        var lines: [String] = []
        for role in roles {
            guard !role.isEmpty else { continue }
            guard role.count <= maxLineCharacters, !role.contains(where: \.isNewline) else { return nil }
            lines.append(role)
        }
        guard (1...maxLines).contains(lines.count) else { return nil }
        return lines
    }

    public static func visibleLines(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// The caption the bolt may show. One line is the action. Two or three lines are
    /// what it is, what to do, and what happens next. A fourth line, or any line longer
    /// than `maxLineCharacters`, stays off the overlay.
    public static func boltText(_ raw: String) -> String? {
        let pieces = raw.split(whereSeparator: \.isNewline).map { normalize(String($0)) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty, pieces.count <= maxLines else { return nil }
        let what = pieces.count == 1 ? "" : pieces[0]
        let todo = pieces.count == 1 ? pieces[0] : pieces[1]
        let next = pieces.count > 2 ? pieces[2] : ""
        guard let lines = overlayLines(whatItIs: what, whatToDo: todo, whatHappensNext: next, detail: "") else { return nil }
        return lines.joined(separator: "\n")
    }

    /// The first words of a sentence that fit on one caption line.
    public static func oneLine(_ raw: String) -> String? {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > maxLineCharacters { break }
            current = next
        }
        let line = normalize(current)
        guard !line.isEmpty, line.count <= maxLineCharacters else { return nil }
        return line
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Bolt, ring and caption for one moment. Flight and the reveal use Zeus's own motion types.
public struct PointerGuideCaptionPose: Equatable, Sendable {
    public var bolt: CGPoint
    public var ring: CGRect
    public var lines: [String]
    public var visibleLines: [String]
    public var flight: CompanionFlight
}

/// One helper step: Zeus's bolt, the ring on the control, and the caption roles.
public struct PointerGuideCaptionFrame: Equatable, Sendable {
    public var bolt: CGPoint
    public var ring: CGRect
    public var whatItIs: String
    public var whatToDo: String
    public var whatHappensNext: String
    /// Longer note. It belongs in the thread, not on the overlay.
    public var detail: String
    public var reduceMotion: Bool

    public init(bolt: CGPoint, ring: CGRect, whatItIs: String, whatToDo: String,
                whatHappensNext: String, detail: String, reduceMotion: Bool) {
        self.bolt = bolt
        self.ring = ring
        self.whatItIs = whatItIs
        self.whatToDo = whatToDo
        self.whatHappensNext = whatHappensNext
        self.detail = detail
        self.reduceMotion = reduceMotion
    }

    /// Bolt, ring and caption at `now`. Reduce Motion settles the bolt and shows the caption.
    public func pose(from origin: CGPoint, at now: TimeInterval, beganAt: TimeInterval, reduceMotion live: Bool) -> PointerGuideCaptionPose? {
        guard bolt.x.isFinite, bolt.y.isFinite,
              ring.width > 0, ring.height > 0,
              ring.origin.x.isFinite, ring.origin.y.isFinite,
              ring.width.isFinite, ring.height.isFinite else { return nil }
        guard let lines = PointerGuideCaptionSplit.overlayLines(
            whatItIs: whatItIs, whatToDo: whatToDo, whatHappensNext: whatHappensNext, detail: detail
        ) else { return nil }
        let reduced = live || reduceMotion
        let flight = CompanionFlight.plan(from: origin, to: bolt, reducedMotion: reduced)
        let text = lines.joined(separator: "\n")
        var label = CompanionPointingLabel(text: text, beganAt: beganAt, reduceMotion: reduced)
        if !reduced {
            var ticks = 0
            while !label.isComplete, label.nextCharacterAt <= now, ticks < text.count {
                let due = label.nextCharacterAt
                label.advance(at: due, reduceMotion: false, characterDelay: PointerGuideCaptionSplit.characterDelay)
                ticks += 1
                if label.nextCharacterAt <= due { break }
            }
        }
        let elapsed = max(0, now - beganAt)
        return PointerGuideCaptionPose(
            bolt: flight.sample(at: elapsed).position,
            ring: ring,
            lines: lines,
            visibleLines: PointerGuideCaptionSplit.visibleLines(in: label.visibleText),
            flight: flight
        )
    }
}
