import AppKit
import ZeusCore

/// Carries out `zeus://` links (see `ZeusDeepLink`).
@MainActor
enum DeepLinks {
    static func handle(_ urls: [URL]) {
        for url in urls {
            guard let link = ZeusDeepLink.parse(url) else { continue }
            perform(link)
        }
    }

    /// Wired by the app: whether dictation is recording right now.
    static var isDictating: () -> Bool = { false }
    /// Wired by the app: opens the Dictation tab with a notice, so capture starts only from an in-app press.
    /// Unset means a link cannot start capture at all.
    static var requestDictationStart: (() -> Void)?

    static func perform(_ link: ZeusDeepLink) {
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
        case .stickyNew(let text):
            StickiesController.shared.new(text: text ?? "")
        case .chatOpen(let prefill):
            if let prefill { ChatModel.shared.draft = prefill }
            ChatModel.shared.openWindow()
        }
    }
}
