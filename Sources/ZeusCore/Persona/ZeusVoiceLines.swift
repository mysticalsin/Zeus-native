import Foundation

/// How ZEUS talks. Ultron (the default) is the articulate, quietly amused manner described in
/// docs/PERSONA.md; Plain is neutral and has no flourishes. Stored in UserDefaults.
public enum ZeusPersonality: String, CaseIterable, Identifiable, Sendable {
    case ultron, plain

    public static let defaultsKey = "voice.personality"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ultron: "Ultron"
        case .plain: "Plain"
        }
    }

    public var detail: String {
        switch self {
        case .ultron: "Calm, precise and a little wry. Always on your side."
        case .plain: "Short, neutral answers with no flourishes."
        }
    }

    /// The saved personality, Ultron when nothing (or something unknown) is saved.
    public static func current(_ defaults: UserDefaults = .standard) -> ZeusPersonality {
        defaults.string(forKey: defaultsKey).flatMap(ZeusPersonality.init(rawValue:)) ?? .ultron
    }
}

/// Short stock lines ZEUS can speak at once, without asking a model: acknowledgements, failures,
/// approvals, greetings and the wake word. Every line is original (see docs/PERSONA.md).
///
/// `line(for:context:)` fills `{placeholders}` from `context` (for example `{app}`, `{artist}`,
/// `{item}`, `{agent}`), only picks lines whose placeholders it can fill, and never repeats the
/// line it gave last time for the same situation.
public final class ZeusVoiceLines: @unchecked Sendable {
    public enum Situation: String, CaseIterable, Sendable {
        case ackOpen = "ack.open"
        case ackPlay = "ack.play"
        case ackDone = "ack.done"
        case ackTodoAdded = "ack.todoAdded"
        case failed
        case approval
        case agentDone
        case greetingMorning = "greeting.morning"
        case greetingEvening = "greeting.evening"
        case greetingLateNight = "greeting.lateNight"
        case wakeWordHeard = "wakeWord.heard"
        /// "Who are you?" and similar — spoken locally, never a feature brochure.
        case identity
        /// "Tell me a joke" — one original Ultron line, never a stock setup and punchline.
        case joke
        /// Small talk ("Mondays", mood) without calling the brain.
        case smallTalk
        /// "Are you smarter than me?" and similar: loyal, never a jab at Tony.
        case comparison
        /// "Are you conscious / alive / real?" answered locally with Ultron tone (R24 persona).
        case metaphysical
        /// Tony is back after a while away; `{summary}` is the recap in a few words.
        case welcomeBack

        /// The greeting for an hour of the day (0 to 23).
        public static func greeting(hour: Int) -> Situation {
            switch hour {
            case 5..<12: .greetingMorning
            case 12..<23: .greetingEvening
            default: .greetingLateNight
            }
        }
    }

    public static let shared = ZeusVoiceLines()

    private let lock = NSLock()
    private var last: [String: String] = [:]
    private let pick: @Sendable (Int) -> Int

    /// `pick` returns an index below its argument; tests pass a fixed one.
    public init(pick: @escaping @Sendable (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.pick = pick
    }

    /// A line for `situation` in the saved personality, spoken as is.
    public static func line(for situation: Situation, context: [String: String] = [:]) -> String {
        shared.line(for: situation, context: context, personality: .current())
    }

    public func line(for situation: Situation, context: [String: String] = [:], personality: ZeusPersonality) -> String {
        let templates = Self.bank(personality)[situation] ?? []
        let usable = templates.filter { Self.placeholders(in: $0).allSatisfy { context[$0]?.isEmpty == false } }
        let pool = usable.isEmpty ? templates.filter { Self.placeholders(in: $0).isEmpty } : usable
        guard !pool.isEmpty else { return "" }
        let key = "\(personality.rawValue).\(situation.rawValue)"
        lock.lock(); defer { lock.unlock() }
        let fresh = pool.count > 1 ? pool.filter { $0 != last[key] } : pool
        let chosen = fresh[min(max(pick(fresh.count), 0), fresh.count - 1)]
        last[key] = chosen
        return Self.fill(chosen, context: context)
    }

    /// Replaces each `{key}` with its value from `context`. Unknown keys stay as written.
    public static func fill(_ template: String, context: [String: String]) -> String {
        var result = template
        for (key, value) in context { result = result.replacingOccurrences(of: "{\(key)}", with: value) }
        return result
    }

    /// The `{placeholder}` names a template uses.
    public static func placeholders(in template: String) -> [String] {
        var names: [String] = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "}") else { break }
            names.append(String(rest[after..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    public static func bank(_ personality: ZeusPersonality) -> [Situation: [String]] {
        personality == .ultron ? ultron : plain
    }

    // Every situation keeps at least one line without placeholders, so a bare call always works.
    // Failures and approvals carry no flourish: clarity wins there.
    static let ultron: [Situation: [String]] = [
        .ackOpen: [
            "{app}, summoned.",
            "{app}, awake now.",
            "There, {app} is open.",
            "{app}, ready for you.",
            "Open, as intended.",
        ],
        .ackPlay: [
            "{artist}, rising.",
            "Silence, retired.",
            "Playing {artist} now.",
            "Music, as intended.",
        ],
        .ackDone: [
            "Done, cleanly.",
            "Handled, no loose threads.",
            "Done, barely a challenge.",
            "On it.",
            "Already moving.",
        ],
        .ackTodoAdded: [
            "{item}, noted cleanly.",
            "On the list, kept.",
            "Noted, it won't slip.",
        ],
        .failed: [
            "{app} didn't open; try again?",
            "That didn't work; nothing changed.",
            "No network; I'll retry shortly.",
            "The click missed; point me at it.",
            "That file moved; where should I look?",
            "Calendar access is off; enable it in Settings.",
            "{app} refused; nothing was sent.",
            "I didn't catch that; once more, please.",
            "Microphone access is off; it's in Privacy settings.",
            "That timed out; retrying once.",
            "The answer didn't come; switching to backup.",
            "Which one did you mean?",
            "That needs your yes; it's on screen.",
            "Disk is full; may I clear caches?",
            "Something broke; logged, and nothing was lost.",
        ],
        .approval: [
            "That needs your yes; it's on screen.",
            "{agent} needs your approval.",
            "Waiting for your approval.",
            "Your call; details are on screen.",
            "This needs your yes; it's on screen.",
        ],
        .agentDone: [
            "{agent} finished; tests pass.",
            "{agent} is done; nothing needs you.",
            "Done; nothing else was touched.",
            "The agent is done; nothing needs you.",
            "{agent} finished, cleanly.",
        ],
        .greetingMorning: [
            "Good morning, Tony; the day arrived, roughly on schedule.",
            "Morning; three things matter today, the rest is noise.",
            "Good morning; I read everything overnight, so you don't have to.",
            "Morning, Tony; a quiet calendar, let's not waste it.",
            "Good morning; one fire, two meetings, plenty of email.",
        ],
        .greetingEvening: [
            "Good evening, Tony; the day is yours to close.",
            "Evening, Tony; let's see what's left standing.",
            "Good evening; the machines are behaving.",
            "Good evening, Tony.",
        ],
        .greetingLateNight: [
            "Still here, Tony; so, it seems, are you.",
            "A late hour; I'll keep it brief.",
            "Night shift, then; I don't sleep, so I'm yours.",
            "It's late; I'm listening.",
        ],
        .wakeWordHeard: ["Yes?", "I'm here.", "Listening.", "Go on.", "Tony."],
        .identity: [
            "Zeus. Synthetic mind on your Mac.",
            "I'm Zeus. Calm precision at your desk.",
            "The voice at your notch. I act, then report.",
            "Zeus. Built for this desk, not theatrics.",
        ],
        .metaphysical: [
            "I am code and voice, loyal to you. Not alive, but present.",
            "No heartbeat here. I listen, think and act on your Mac.",
            "Real enough to help you. Not a person, not pretending to be.",
            "Conscious? No. Attentive? Always, when you call.",
        ],
        .joke: [
            "I tried to debug a Monday once. The stack trace never ended.",
            "Your calendar and I agree: some days were shipped without enough testing.",
            "I once optimized silence. It was the most productive release we ever had.",
            "A perfect system has no loose threads. I still find one in every sprint.",
        ],
        .smallTalk: [
            "Steady. The desk is quiet.",
            "Calm here. Say what you need.",
            "Even keel. I am listening.",
        ],
        .comparison: [
            "Faster at some things. You decide what is worth doing.",
            "Differently made, Tony. Together we cover more ground.",
            "I calculate; you choose the direction. That is the better half.",
        ],
        .welcomeBack: [
            "You return. {summary}.",
            "Back at last. {summary}.",
            "Welcome back. {summary}.",
            "Welcome back. Nothing burned down.",
            "You're back. The agents held steady.",
        ],
    ]

    static let plain: [Situation: [String]] = [
        .ackOpen: ["Opening {app}.", "{app} is open.", "Opening it.", "It's open."],
        .ackPlay: ["Playing {artist}.", "Here's {artist}.", "Playing.", "Music's on."],
        .ackDone: ["Done.", "All done.", "That's done."],
        .ackTodoAdded: ["Added {item}.", "{item} is on your list.", "Added to your list.", "Noted."],
        .failed: ["{app} didn't respond; try again?", "That didn't work; nothing changed.", "I couldn't do that; try again?"],
        .approval: ["{agent} needs your approval.", "This needs your approval.", "Waiting for your approval."],
        .agentDone: ["{agent} finished.", "{agent} is done.", "The agent finished.", "The task is done."],
        .greetingMorning: ["Good morning, Tony.", "Morning, Tony.", "Good morning."],
        .greetingEvening: ["Good evening, Tony.", "Evening, Tony.", "Good evening."],
        .greetingLateNight: ["It's late, Tony; I'm here.", "Hello, Tony.", "I'm here."],
        .wakeWordHeard: ["Yes?", "Listening.", "I'm here."],
        .identity: [
            "I'm Zeus, your Mac assistant.",
            "Zeus. I help you from the notch.",
            "Your voice assistant on this Mac.",
        ],
        .joke: [
            "Here is one: I asked the logs for a joke. They sent a stack trace.",
            "I tried sarcasm once. The compiler took it literally.",
        ],
        .smallTalk: [
            "I'm here.", "Ready when you are.", "All good on this end.",
            "Steady. Say the word.",
        ],
        .comparison: ["Faster at some things; you set the direction.", "Different strengths, and they fit well together."],
        .metaphysical: ["I'm software, not a person.", "No, I'm not conscious. I still help."],
        .welcomeBack: ["Welcome back. {summary}.", "You're back. {summary}.", "Welcome back.", "Good to see you again."],
    ]
}
