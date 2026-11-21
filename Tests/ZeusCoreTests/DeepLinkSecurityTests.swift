import Foundation
import Testing
@testable import ZeusCore

@Suite("Deep link confirmation")
@MainActor
struct DeepLinkSecurityTests {
    let launch = "nonce-launch-1"

    final class Box: @unchecked Sendable {
        var applied: [ZeusDeepLink] = []
        var asks: [String] = []
    }

    private func run(_ link: ZeusDeepLink, nonce: String? = nil, dictating: Bool = false, allow: Bool = false, box: Box) async -> DeepLinkTrace {
        await DeepLinkPerformer.run(link, presentedNonce: nonce, launchNonce: launch, isDictating: dictating, confirm: { prompt in
            box.asks.append(prompt.summary)
            return allow
        }, apply: { box.applied.append($0) })
    }

    @Test func stopDoesNothingUntilThePersonConfirms() async {
        let held = Box()
        let waiting = await run(.dictationStop, box: held)
        #expect(held.applied.isEmpty)
        #expect(held.asks.count == 1)
        #expect(waiting.applied == false)
        #expect(waiting.asked == true)

        let sent = Box()
        let done = await run(.dictationStop, allow: true, box: sent)
        #expect(sent.applied == [.dictationStop])
        #expect(done.applied == true)
    }

    @Test func matchingNoncePerformsWithoutAsking() async {
        let box = Box()
        let done = await run(.dictationStop, nonce: launch, box: box)
        #expect(box.applied == [.dictationStop])
        #expect(box.asks.isEmpty)
        #expect(done.asked == false)
    }

    @Test func wrongNonceStillAsks() async {
        let box = Box()
        _ = await run(.dictationCancel, nonce: "other-nonce", box: box)
        #expect(box.applied.isEmpty)
        #expect(box.asks.count == 1)
    }

    @Test func opensStayImmediate() async {
        let box = Box()
        _ = await run(.dictationStart, box: box)
        _ = await run(.settings(section: "permissions"), box: box)
        _ = await run(.chatOpen(prefill: nil), box: box)
        _ = await run(.dictationToggle, dictating: false, box: box)
        #expect(box.asks.isEmpty)
        #expect(box.applied == [.dictationStart, .settings(section: "permissions"), .chatOpen(prefill: nil), .dictationToggle])
    }

    @Test func writesAndStateChangesAsk() async {
        let box = Box()
        _ = await run(.chatOpen(prefill: "Plan my day"), box: box)
        _ = await run(.stickyNew(text: "Buy milk"), box: box)
        _ = await run(.chatNew, box: box)
        _ = await run(.prompter, box: box)
        _ = await run(.dictationMode("email"), box: box)
        _ = await run(.dictationToggle, dictating: true, box: box)
        #expect(box.applied.isEmpty)
        #expect(box.asks.count == 6)
        #expect(box.asks.contains { $0.contains("Plan my day") })
        #expect(box.asks.contains { $0.contains("Buy milk") })
    }

    @Test func confirmedWriteAppliesTheText() async {
        let box = Box()
        _ = await run(.stickyNew(text: "Buy milk"), allow: true, box: box)
        #expect(box.applied == [.stickyNew(text: "Buy milk")])
    }

    @Test func plantedTextIsCapped() throws {
        var sticky = URLComponents()
        sticky.scheme = "zeus"
        sticky.host = "sticky"
        sticky.path = "/new"
        sticky.queryItems = [URLQueryItem(name: "text", value: String(repeating: "b", count: 2_500))]
        let link = try #require(ZeusDeepLink.parse(sticky.url!))
        guard case .stickyNew(let text) = link else {
            Issue.record("expected a sticky")
            return
        }
        #expect(text?.count == 2_000)

        var chat = URLComponents()
        chat.scheme = "zeus"
        chat.host = "chat"
        chat.path = "/open"
        chat.queryItems = [URLQueryItem(name: "text", value: String(repeating: "c", count: 2_500))]
        let opened = try #require(ZeusDeepLink.parse(chat.url!))
        guard case .chatOpen(let prefill) = opened else {
            Issue.record("expected a chat draft")
            return
        }
        #expect(prefill?.count == 2_000)
    }

    @Test func nonceDoesNotChangeTheAction() throws {
        var parts = URLComponents(string: "zeus://dictation/stop")!
        parts.queryItems = [URLQueryItem(name: "nonce", value: launch)]
        let url = try #require(parts.url)
        #expect(ZeusDeepLink.parse(url) == .dictationStop)
        #expect(ZeusDeepLink.presentedNonce(in: url) == launch)
        var junk = URLComponents(string: "zeus://dictation/stop")!
        junk.queryItems = [URLQueryItem(name: "nonce", value: "has space")]
        #expect(ZeusDeepLink.presentedNonce(in: try #require(junk.url)) == nil)
    }
}
