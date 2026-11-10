import Foundation

/// The same delayed keyboard sequence used by Drive's targeted typing and AXValue fallback.
/// Every irreversible emission rechecks ownership and focus, including the Select All that precedes
/// replacement. The injected steps let interruption be tested without native input or Accessibility.
@MainActor
public enum DriveTypingFlow {
    public enum Outcome: Equatable, Sendable {
        case typed
        case interrupted(piecesTyped: Int)
    }

    public static func run(
        chunks: [String],
        replacing: Bool,
        mayEmit: () -> Bool,
        sleep: (Int) async -> Void,
        selectAll: () -> Void,
        delete: () -> Void,
        type: (String) -> Void
    ) async -> Outcome {
        await sleep(150)
        guard mayEmit() else { return .interrupted(piecesTyped: 0) }
        if replacing {
            selectAll()
            if chunks.isEmpty {
                guard mayEmit() else { return .interrupted(piecesTyped: 0) }
                delete()
            }
        }
        var typed = 0
        for chunk in chunks {
            guard mayEmit() else { return .interrupted(piecesTyped: typed) }
            type(chunk)
            typed += 1
            await sleep(12)
        }
        return .typed
    }
}

/// Tags only Zeus's own CGEvents; an untagged event gives control back to the person.
public enum DriveInputAttribution {
    public static let eventTag: Int64 = 0x5A45555344525645
    public static func isOwnEvent(userData: Int64?) -> Bool { userData == eventTag }
}
