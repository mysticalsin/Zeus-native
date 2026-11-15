import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The Chat hot key's order when it moves (docs/ULTRON-CHORD-PLAN.md): the old key is let go, the talk chord is told so it
/// can yield or take Control-Option-Space back, and only then is the new key registered. The other way round, Chat moving
/// onto Control-Option-Space is refused while the chord still holds it.
@Suite("Chat hot key monitor", .serialized) @MainActor
struct ChatHotkeyMonitorTests {
    private final class Log {
        var events: [String] = []
        /// True while another registration holds the key: a register while it is held fails.
        var held = true
    }

    private func make(_ log: Log, _ hotkey: ChatHotkey) -> ChatHotkeyMonitor {
        let defaults = UserDefaults(suiteName: "ChatHotkeyMonitorTests.\(UUID().uuidString)")!
        return ChatHotkeyMonitor(hotkey: hotkey, defaults: defaults, ops: .init(
            register: { _, _ in log.events.append("register"); return !log.held },
            unregister: { log.events.append("unregister") }))
    }

    @Test func movingChatLetsGoThenTellsTheChordThenRegisters() {
        let log = Log()
        let monitor = make(log, .controlOptionC)
        monitor.onChange = { log.events.append("change"); log.held = false } // the chord yields the key
        log.events = []
        monitor.set(.controlOptionSpace)
        #expect(log.events == ["unregister", "change", "register"], "\(log.events)")
        #expect(monitor.problem == nil, "the chord had yielded when Chat registered")
    }
}
