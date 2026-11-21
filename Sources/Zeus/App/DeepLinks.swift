import AppKit
import ZeusCore

/// Carries out `zeus://` links (see `ZeusDeepLink`).
@MainActor
enum DeepLinks {
    static func handle(_ urls: [URL]) async {
        for url in urls {
            guard let link = ZeusDeepLink.parse(url) else { continue }
            await perform(link, presentedNonce: ZeusDeepLink.presentedNonce(in: url))
        }
    }

    /// Wired by the app: whether dictation is recording right now.
    static var isDictating: () -> Bool = { false }
    /// Wired by the app: opens the Dictation tab with a notice, so capture starts only from an in-app press.
    /// Unset means a link cannot start capture at all.
    static var requestDictationStart: (() -> Void)?
    /// Wired by the app: opens the Settings window on a page (`GSSection` raw value, any case) or the last one.
    static var openSettings: ((String?) -> Void)?
    /// Secret for this launch. A link that presents it may change state. It is not written to disk.
    static let launchNonce = DeepLinkGate.makeNonce()
    /// Inline confirmation in the top bar. Unset means a state change or a text write does not run.
    static var confirm: (@MainActor (DeepLinkPrompt) async -> Bool)?

    static func perform(_ link: ZeusDeepLink, presentedNonce: String? = nil) async {
        await DeepLinkPerformer.run(link, presentedNonce: presentedNonce, launchNonce: launchNonce, isDictating: isDictating(),
                                    confirm: { prompt in
            guard let confirm else { return false }
            return await confirm(prompt)
        }, apply: apply)
    }

    private static func apply(_ link: ZeusDeepLink) {
        let dictation = DictationHub.shared.controller
        switch link {
        // An external link must never start the microphone itself; it only brings Zeus forward.
        case .dictationStart: if !isDictating() { requestDictationStart?() }
        case .dictationStop: dictation?.finish()
        case .dictationToggle:
            if isDictating() { dictation?.toggle() } else { requestDictationStart?() }
        case .dictationCancel: dictation?.cancel()
        case .dictationMode(let key): dictation?.selectMode(key)
        case .chatNew:
            ChatModel.shared.newChat()
            ChatModel.shared.openWindow()
        case .prompter:
            PrompterHub.shared.toggle()
        case .settings(let section):
            openSettings?(section)
        case .stickyNew(let text):
            StickiesController.shared.new(text: text ?? "")
        case .chatOpen(let prefill):
            if let prefill { ChatModel.shared.draft = prefill }
            ChatModel.shared.openWindow()
        }
    }
}
