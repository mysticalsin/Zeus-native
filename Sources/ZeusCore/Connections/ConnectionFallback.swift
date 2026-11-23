import Foundation

/// Which offered connection leads, and the sentence VoiceOver reads for the fallback order.
/// An empty offer list stays empty. A saved name that was turned off is not put back.
public enum ConnectionFallback {
    public static func selection(saved: String?, offered: [String]) -> String? {
        if let saved, offered.contains(saved) { return saved }
        return offered.first
    }

    /// The chosen name first when it is offered, then the other offered names in their order.
    public static func chain(chosen: String, offered: [String]) -> [String] {
        var result: [String] = []
        if offered.contains(chosen) { result.append(chosen) }
        for name in offered where !result.contains(name) { result.append(name) }
        return result
    }

    public static func spokenChain(chosen: String?, offered: [String]) -> String {
        let names = chain(chosen: chosen ?? "", offered: offered)
        guard let first = names.first else { return "No agent is offered for new chats." }
        if names.count == 1 { return "New chats use \(first)." }
        let rest = names.dropFirst().joined(separator: ", then ")
        return "New chats use \(first). If that connection is not ready, \(rest)."
    }
}
