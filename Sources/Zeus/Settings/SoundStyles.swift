import SwiftUI
import ZeusCore

/// Sound style names (Settings > Sounds and the welcome guide's last step). Each one is a distinct
/// sound of Zeus's own, rendered by tools/sounds/make_sounds.py; the table lives in ZeusCore.SoundCatalog.
enum SoundStyles {
    static let runStart = SoundCatalog.styleNames(for: .runStart)
    static let requests = SoundCatalog.styleNames(for: .request)
    static let answer = SoundCatalog.styleNames(for: .answer)
    static let done = SoundCatalog.styleNames(for: .done)

    @MainActor static func preview(_ event: ZeusSound.Event) {
        ZeusSound.play(slot: event.slot, style: event.name)
    }

    /// Previews the style saved under a catalog option such as "sound.startStyle".
    @MainActor static func preview(option id: String) {
        let slot: SoundSlot? = switch id {
        case "sound.startStyle": .runStart
        case "sound.approvalStyle": .request
        case "sound.answerStyle": .answer
        case "sound.doneStyle": .done
        default: nil
        }
        if let slot { ZeusSound.play(slot: slot, style: SettingsStore.shared.string(id)) }
    }
}

extension SettingsStore {
    /// Defaults for options the welcome guide writes before Settings lists them.
    static let guideDefaults: [String: String] = [
        "halo.style": HaloStyle.classic.rawValue, "halo.armWidth": "Medium", "halo.entrance": HaloEntrance.sweep.rawValue, "halo.thickness": "100",
        "appearance.cardStyle": "Glass",
        "sound.startStyle": SoundStyles.runStart[0], "sound.approvalStyle": SoundStyles.requests[0],
        "sound.answerStyle": SoundStyles.answer[0], "sound.doneStyle": SoundStyles.done[0],
    ]

    /// A string binding on the shared store, with the guide's default when nothing is saved.
    @MainActor static func binding(_ id: String) -> Binding<String> {
        Binding(get: {
            let value = shared.string(id)
            if value.isEmpty || (id.hasPrefix("sound.") && id.hasSuffix("Style") && value != "Off" && !isSoundStyle(id, value)) { return guideDefaults[id] ?? value }
            return value
        }, set: { shared.set(id, $0) })
    }

    /// Older Zeus builds saved a system sound name ("Glass") rather than a style.
    private static func isSoundStyle(_ id: String, _ value: String) -> Bool {
        switch id {
        case "sound.startStyle": SoundStyles.runStart.contains(value)
        case "sound.approvalStyle": SoundStyles.requests.contains(value)
        case "sound.answerStyle": SoundStyles.answer.contains(value)
        case "sound.doneStyle": SoundStyles.done.contains(value)
        default: true
        }
    }
}
