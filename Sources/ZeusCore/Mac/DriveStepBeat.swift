import Foundation

/// What the spark and the voice do for one Mac drive step.
///
/// The notch card already lists the plan. Each step is spoken as it runs, and the spark
/// keeps a short line. Typing or setting a password field is shown as "Secret" and is not spoken,
/// so the value is not read aloud.
public enum DriveStepBeat {
    public static let boltLimit = 40

    public struct Shown: Equatable, Sendable {
        public var spoken: String?
        public var bolt: String

        public init(spoken: String?, bolt: String) {
            self.spoken = spoken
            self.bolt = bolt
        }
    }

    public static func make(index: Int, count: Int, step: DriveStep) -> Shown {
        if hidesValue(step) {
            return Shown(spoken: nil, bolt: "Secret")
        }
        let number = max(index, 1)
        let total = max(count, number)
        let summary = step.summary
        return Shown(spoken: "Step \(number) of \(total). \(sentence(summary))", bolt: short(summary))
    }

    private static func hidesValue(_ step: DriveStep) -> Bool {
        switch step {
        case .type(_, let into?): return DriveStep.looksSecret(into)
        case .setValue(let target, _): return DriveStep.looksSecret(target)
        default: return false
        }
    }

    private static func sentence(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        if last == "." || last == "?" || last == "!" { return trimmed }
        return trimmed + "."
    }

    private static func short(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > boltLimit { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { return line }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Here" : String(trimmed.prefix(boltLimit))
    }
}
