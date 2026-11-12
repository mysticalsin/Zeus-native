import Foundation
import os
import ZeusCore

/// `Zeus --keychain-selftest`: loads the one `com.zeus.app` Keychain service exactly as the app
/// does at launch, round-trips a harmless probe item, prints a JSON report with names only (never
/// values) and exits before any window or menu exists, so it never disturbs a running ZEUS.
enum KeychainSelfTest {
    /// Accounts a script may import with `Zeus --keychain-import <account> < file`. The app itself
    /// writes the item, so its own signature owns it and later reads never prompt. The value is
    /// read from stdin and never printed.
    static let importable: Set<String> = [JevKey.account, "worker.url", "worker.token", "elevenlabs.api-key"]
    /// Other spellings scripts may use, mapped to the account the app reads.
    static let aliases = ["elevenlabs-api-key": "elevenlabs.api-key"]

    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--keychain-import"), i + 1 < args.count {
            let account = aliases[args[i + 1]] ?? args[i + 1]
            guard importable.contains(account) else { print("refused: \(account) is not importable"); exit(2) }
            let raw = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { print("refused: empty input"); exit(2) }
            Keychain.store.load()
            let ok = Keychain.store.set(value, for: account)
            let back = SystemKeychain().read(service: KeychainStore.service, account: account) == value
            if back, let legacy = KeychainStore.legacy.first(where: { $0.to == account }) {
                Keychain.store.resolveLegacy("\(legacy.service)/\(legacy.account)")
            }
            print("{\"account\":\"\(account)\",\"length\":\(value.count),\"stored\":\(ok),\"readBack\":\(back)}")
            exit(ok && back ? 0 : 1)
        }
        if args.contains("--jev-smoke") { jevSmoke() }
        VoiceSample.runIfRequested()
        guard CommandLine.arguments.contains("--keychain-selftest") else { return }
        let started = Date()
        let store = Keychain.store
        store.load()
        let probe = "selftest-\(Int(started.timeIntervalSince1970))"
        let wrote = store.set(probe, for: "selftest.probe")
        let fresh = SystemKeychain().read(service: KeychainStore.service, account: "selftest.probe")
        let report: [String: Any] = [
            "service": KeychainStore.service,
            "accounts": SystemKeychain().accounts(service: KeychainStore.service).sorted(),
            "probeWrote": wrote,
            "probeReadBack": fresh == probe,
            "hasJevKey": store.has(JevKey.account),
            "hasWorkerToken": store.has("worker.token"),
            "hasElevenLabsKey": store.has("elevenlabs.api-key"),
            "hasWorkerURL": store.has("worker.url"),
            "keychain": SystemKeychain().location,
            "unreadableLegacy": store.unreadableLegacy,
            "ms": Int(Date().timeIntervalSince(started) * 1000),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        let required = CommandLine.arguments.contains("--require-keys")
        exit(fresh == probe && (!required || (store.has(JevKey.account) && store.has("worker.token"))) ? 0 : 1)
    }

    /// `Zeus --jev-smoke`: one minimal paid Jev call (about 300 input tokens, well under a cent)
    /// through the same budget guard as the app. Prints the engine, intent, confidence, tokens,
    /// cost and latency; never the key.
    static func jevSmoke() -> Never {
        Keychain.store.load()
        let guardian = JevGuard(key: JevKey.load(from: Keychain.store))
        let request = SystemOneRequest(model: "jev-latest", state: ["utterance": "open Safari"], questions: [
            "intent": .choice("What does the person want?", ["app.open": "Open an app", "chat.answer": "Answer a question"]),
        ])
        let done = DispatchSemaphore(value: 0)
        // Only a locked, Sendable value crosses back to the synchronous CLI thread.
        let result = OSAllocatedUnfairLock(initialState: (line: "", ok: false))
        Task.detached {
            let completed: (line: String, ok: Bool)
            do {
                let d = try await guardian.decide(request)
                let intent = d.answers["intent"]?.choice ?? "?"
                let line = "{\"source\":\"\(d.source.rawValue)\",\"intent\":\"\(intent)\",\"confidence\":\(d.confidence),\"inputTokens\":\(d.inputTokens),\"cost\":\(d.cost),\"latencyMs\":\(d.latencyMs)}"
                completed = (line, true)
            } catch {
                completed = ("{\"error\":\"\(String(describing: error).prefix(160))\"}", false)
            }
            result.withLock { $0 = completed }
            done.signal()
        }
        done.wait()
        let completed = result.withLock { $0 }
        print(completed.line)
        exit(completed.ok ? 0 : 1)
    }
}
