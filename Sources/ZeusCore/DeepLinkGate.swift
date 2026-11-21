import Foundation

/// What a person sees before a `zeus://` link is allowed to change state or write text.
public struct DeepLinkPrompt: Equatable, Sendable {
    public var summary: String

    public init(_ link: ZeusDeepLink) {
        switch link {
        case .dictationStop, .dictationToggle:
            summary = "Stop dictation"
        case .dictationCancel:
            summary = "Cancel dictation"
        case .dictationMode(let key):
            summary = "Change dictation mode to \(key)"
        case .chatNew:
            summary = "Start a new chat"
        case .prompter:
            summary = "Show or hide the prompter"
        case .stickyNew(let text):
            summary = "New sticky: \(text ?? "")"
        case .chatOpen(let prefill):
            summary = "Put this in the chat draft: \(prefill ?? "")"
        case .dictationStart:
            summary = "Open dictation"
        case .settings:
            summary = "Open Settings"
        }
    }
}

/// Whether a link ran, and whether the person was asked first.
public struct DeepLinkTrace: Equatable, Sendable {
    public var applied: Bool
    public var asked: Bool
}

/// Opens may run at once. Stopping dictation, changing mode, or writing chat and sticky text
/// needs this launch's nonce or a confirmation in the top bar.
public enum DeepLinkGate {
    public static let textLimit = 2_000

    public enum Decision: Equatable, Sendable {
        case perform
        case needsConfirmation(DeepLinkPrompt)
    }

    public static func makeNonce() -> String { UUID().uuidString }

    public static func requiresConfirmation(_ link: ZeusDeepLink, isDictating: Bool) -> Bool {
        switch link {
        case .dictationStart, .settings:
            return false
        case .dictationToggle:
            return isDictating
        case .chatOpen(let prefill):
            return prefill != nil
        case .dictationStop, .dictationCancel, .dictationMode, .chatNew, .prompter, .stickyNew:
            return true
        }
    }

    public static func decision(for link: ZeusDeepLink, isDictating: Bool, presentedNonce: String?, launchNonce: String, confirmed: Bool) -> Decision {
        guard requiresConfirmation(link, isDictating: isDictating) else { return .perform }
        if confirmed || nonceMatches(presentedNonce, launchNonce: launchNonce) { return .perform }
        return .needsConfirmation(DeepLinkPrompt(link))
    }

    /// Equal-length compare. A missing or differently sized nonce does not match.
    public static func nonceMatches(_ presented: String?, launchNonce: String) -> Bool {
        guard let presented, !launchNonce.isEmpty, presented.utf8.count == launchNonce.utf8.count else { return false }
        var mismatch: UInt8 = 0
        for (left, right) in zip(presented.utf8, launchNonce.utf8) { mismatch |= left ^ right }
        return mismatch == 0
    }

    /// Caps chat and sticky text. Empty text stays empty.
    public static func boundedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(textLimit))
    }
}

/// Applies a link only when `DeepLinkGate` allows it. Tests pass the confirm and apply steps.
@MainActor
public enum DeepLinkPerformer {
    @discardableResult
    public static func run(_ link: ZeusDeepLink, presentedNonce: String?, launchNonce: String, isDictating: Bool,
                           confirm: (DeepLinkPrompt) async -> Bool, apply: (ZeusDeepLink) -> Void) async -> DeepLinkTrace {
        switch DeepLinkGate.decision(for: link, isDictating: isDictating, presentedNonce: presentedNonce, launchNonce: launchNonce, confirmed: false) {
        case .perform:
            apply(link)
            return DeepLinkTrace(applied: true, asked: false)
        case .needsConfirmation(let prompt):
            guard await confirm(prompt) else { return DeepLinkTrace(applied: false, asked: true) }
            apply(link)
            return DeepLinkTrace(applied: true, asked: true)
        }
    }
}
