import Foundation

/// The line the closed notch shows for one earbud cue, and the sentence to speak.
///
/// Hide details keeps the notch on "Connected" or "Disconnected" and the voice on
/// "Earbuds connected." A shown charge uses the same words as the cue list.
/// The notch keeps the cue for the earbud policy's connect or disconnect time.
public struct EarbudsNotchCue: Equatable, Sendable {
    public var text: String
    public var connected: Bool
    public var spoken: String
    public var duration: TimeInterval

    public init(text: String, connected: Bool, spoken: String, duration: TimeInterval) {
        self.text = text
        self.connected = connected
        self.spoken = spoken
        self.duration = duration
    }

    public static func make(_ facts: EarbudsCueFacts, hideDetails: Bool) -> EarbudsNotchCue {
        let lines = EarbudsWords.cueStatus(facts, hideDetails: hideDetails).map(\.text).filter { !$0.isEmpty }
        let text = lines.isEmpty ? (facts.connected ? "Connected" : "Disconnected") : lines.joined(separator: " · ")
        let kind: EarbudsCueShow.Kind = facts.connected ? .connected : .disconnected
        return EarbudsNotchCue(
            text: text,
            connected: facts.connected,
            spoken: EarbudsWords.spoken(facts, hideDetails: hideDetails),
            duration: EarbudsCuePolicy.duration(kind)
        )
    }
}
