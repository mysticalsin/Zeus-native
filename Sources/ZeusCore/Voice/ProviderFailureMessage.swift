import Foundation

/// What a cloud voice's refusal means to the person, so the notice tells them what to do. ElevenLabs
/// answers 401 both for a bad key (`invalid_api_key`) and for used-up credits (`quota_exceeded`), so the
/// body's status word is read before the HTTP code. Reads only the status code and that word; never a key.
public enum ProviderFailureMessage {
    public enum Kind: Equatable, Sendable {
        case badKey
        case creditsUsedUp
        case rateLimited
        case other
    }

    /// `detail` is the provider's own status word (for example `quota_exceeded`), empty when unknown.
    public static func kind(status: Int, detail: String) -> Kind {
        let word = detail.lowercased()
        if word.contains("quota") || word.contains("credit") || status == 402 { return .creditsUsedUp }
        switch status {
        case 429: return .rateLimited
        case 401, 403: return .badKey
        default: return .other
        }
    }

    /// The notice for `kind`. Rate limits and other failures are worded by the caller.
    public static func message(label: String, kind: Kind) -> String? {
        switch kind {
        case .badKey:
            "\(label) rejected the key. Paste a new key in Settings. Zeus uses the next voice meanwhile."
        case .creditsUsedUp:
            "\(label) credits are used up. Zeus uses the next voice until the pause ends."
        case .rateLimited, .other:
            nil
        }
    }
}
