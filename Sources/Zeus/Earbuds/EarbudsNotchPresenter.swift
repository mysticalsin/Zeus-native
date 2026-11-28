import Foundation
import ZeusCore

/// Puts an earbud connect or disconnect on the closed notch and says the sentence.
/// A protected cue stays up. A blank device id is dropped.
@MainActor
final class EarbudsNotchPresenter {
    weak var topBar: TopBarModel?
    var say: (String) -> Void = { _ in }
    var hideDetails: () -> Bool = { false }

    func present(_ facts: EarbudsCueFacts, id: String, speak: Bool) {
        let kind: EarbudsCueShow.Kind = facts.connected ? .connected : .disconnected
        let request = EarbudsCueShow(id: id, name: facts.name, kind: kind)
        guard EarbudsCuePolicy.mayShow(request, over: occupant(topBar?.cue)) else { return }
        let line = EarbudsNotchCue.make(facts, hideDetails: hideDetails())
        topBar?.show(.earbuds(text: line.text, connected: line.connected))
        if speak, !line.spoken.isEmpty { say(line.spoken) }
    }

    private func occupant(_ cue: NotchCue?) -> EarbudsCueOccupant {
        switch cue {
        case nil: return .none
        case .hint: return .protected(.hint)
        case .usageAlert: return .protected(.usage)
        case .focusFinished: return .protected(.focus)
        case .keepAwake: return .protected(.keepAwake)
        case .dictation: return .protected(.dictation)
        case .volume: return .protected(.volume)
        case .brightness: return .protected(.brightness)
        case .keyboardBacklight: return .protected(.keyboardLight)
        case .permission: return .protected(.permission)
        case .earbuds: return .earbuds(id: "shown", name: "", connected: true)
        default: return .other
        }
    }
}
