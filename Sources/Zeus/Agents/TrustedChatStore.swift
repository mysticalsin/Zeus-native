import Observation
import ZeusCore

/// Chats the person trusted from an approval card. Memory only: quitting ZEUS clears them.
@MainActor
@Observable
final class TrustedChatStore {
    static let shared = TrustedChatStore()
    private(set) var chats = TrustedChats()

    var entries: [TrustedChats.Entry] { chats.entries }

    func trust(session: String, agent: String, project: String) { chats.trust(session, agent: agent, project: project) }
    func revoke(session: String) { chats.revoke(session) }
    func clear() { chats.clear() }

    func autoApproves(session: String?, tool: String?, input: JSONValue?, risk: HookEvent.Risk?) -> Bool {
        chats.autoApproves(session: session, tool: tool, input: input, risk: risk)
    }

    var summary: String {
        switch entries.count {
        case 0: "None"
        case 1: "1 chat"
        default: "\(entries.count) chats"
        }
    }
}
