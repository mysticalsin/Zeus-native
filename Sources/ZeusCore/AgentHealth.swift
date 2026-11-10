import Foundation

/// What an agent session is doing, as the notch shows it (halo colour, status word, card).
public enum AgentRunState: Equatable, Sendable {
    case idle, working, needsYou, done
    /// The turn ended in an error (rate limit, auth, API error). Red.
    case failed
    /// Marked working but silent for longer than the stall limit. Amber.
    case stalled
}

/// Reads the reason out of an agent's failure event (Claude Code `StopFailure`, Codex `error`).
public enum AgentFailureParser {
    /// A short sentence for the card: the error kind in plain words, then the agent's own detail.
    public static func reason(from payload: JSONValue) -> String {
        let code = payload["error"]?.stringValue ?? payload["error_type"]?.stringValue
        let detail = payload["error_details"]?.stringValue ?? payload["message"]?.stringValue
            ?? payload["last_assistant_message"]?.stringValue
        return reason(code: code, detail: detail)
    }

    public static func reason(code: String?, detail: String?) -> String {
        let cleaned = detail.map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
        let lead = code.flatMap(friendly)
        switch (lead, cleaned) {
        case (let lead?, let detail?) where !detail.isEmpty && !detail.localizedCaseInsensitiveContains(lead):
            return "\(lead): \(detail.count > 140 ? String(detail.prefix(139)) + "…" : detail)"
        case (let lead?, _): return lead
        case (nil, let detail?) where !detail.isEmpty: return detail.count > 160 ? String(detail.prefix(159)) + "…" : detail
        default: return "The agent stopped with an error"
        }
    }

    /// Claude Code's error kinds in words.
    public static func friendly(_ code: String) -> String? {
        switch code {
        case "rate_limit": "Rate limit reached"
        case "authentication_failed": "Sign-in failed"
        case "billing_error": "Billing problem"
        case "invalid_request": "The request was rejected"
        case "server_error": "The service had an error"
        case "max_output_tokens": "Ran out of output room"
        case "unknown", "": nil
        default: code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// When a working agent counts as stalled: no event for a while. Pure, so a fake clock tests it.
public enum AgentStall {
    public static let defaultMinutes = 5
    public static let choices = ["2 min", "5 min", "10 min", "15 min"]

    public static func minutes(fromLabel label: String) -> Int {
        Int(label.split(separator: " ").first ?? "") ?? defaultMinutes
    }

    public static func threshold(fromLabel label: String) -> TimeInterval { TimeInterval(minutes(fromLabel: label) * 60) }

    /// The state after a stall check: only a working session can stall, and only once it has
    /// been silent for `threshold` seconds. Everything else keeps its state.
    public static func afterCheck(_ state: AgentRunState, lastEvent: Date, now: Date, threshold: TimeInterval) -> AgentRunState {
        guard state == .working, now.timeIntervalSince(lastEvent) >= threshold else { return state }
        return .stalled
    }

    /// "No activity for 5 min".
    public static func reason(silentFor seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 1)
        return "No activity for \(minutes) min"
    }
}
