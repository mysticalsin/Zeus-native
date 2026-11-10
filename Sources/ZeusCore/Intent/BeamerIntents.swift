import Foundation

/// Fast-path rules for Beamer (the keyboard-and-mouse sharing app), English only:
///
///     pause Beamer          resume Beamer          start Beamer          open Beamer
///     switch to my iPad     send my keyboard to my MacBook     control my Mac mini
///     bring my keyboard back
///
/// "Switch to X" alone stays an app switch ("switch to Safari"); the Beamer form needs "my".
/// Whether the machine is paired is checked afterwards (`FastActions`); an unknown one goes on
/// to the LLM.
extension FastIntent {
    private static let beamerExact: [String: BeamerCommand] = {
        var map: [String: BeamerCommand] = [:]
        func add(_ phrases: [String], _ command: BeamerCommand) {
            for phrase in phrases { map[Utterance(phrase).words.joined(separator: " ")] = command }
        }
        add(["pause beamer", "pause the beamer", "pause beamer please", "beamer pause", "pause crossing", "pause continuity", "pause keyboard sharing",
             "pause mouse sharing", "stop sharing my keyboard", "pause keyboard and mouse sharing"], .pause)
        add(["resume beamer", "unpause beamer", "resume the beamer", "beamer resume", "resume crossing", "resume continuity", "resume keyboard sharing",
             "resume mouse sharing", "resume keyboard and mouse sharing"], .resume)
        add(["start beamer", "launch beamer", "run beamer", "turn on beamer", "start the beamer", "start continuity", "fire up beamer"], .start)
        add(["open beamer", "show beamer", "open the beamer", "open the beamer window", "show the beamer window", "open beamer settings",
             "open my machines", "show my machines", "open continuity", "show continuity"], .showWindow)
        add(["bring my keyboard back", "bring input back", "bring my input back", "bring my keyboard and mouse back", "bring the keyboard back",
             "come back to this mac", "come back to my mac", "return input to my mac", "return to this mac", "return to my mac",
             "switch back to my mac", "switch back to this mac", "go back to this mac", "go back to my mac", "back to this mac"], .returnHome)
        return map
    }()

    private static let beamerRules = TemplateSet([
        ("switch", [
            "(switch|go|jump|hop|move|cross|change) [over] to my {name}",
            "(send|move|put|throw|push|take) (my|the) (keyboard|mouse|keyboard and mouse|mouse and keyboard|cursor|pointer|input|control) [over] to [my|the] {name}",
            "(control|drive|work on) my {name}",
            "(switch|go|jump|hop|move) [over] to [the] ipad",
        ]),
    ])

    /// The Beamer command in an utterance, or nil.
    static func beamerCommand(_ utterance: Utterance) -> BeamerCommand? {
        if let exact = beamerExact[utterance.words.joined(separator: " ")] { return exact }
        guard let (rule, slots) = beamerRules.first(utterance.words), rule == "switch" else { return nil }
        guard let range = slots["name"] else { return .switchTo("iPad") }
        let words = utterance.words[range]
        guard (1...3).contains(words.count), !words.contains(where: { notAppWords.contains($0) && $0 != "my" }) else { return nil }
        // "control my head" is not a machine: the verbs "control/drive/work on" need a machine-looking name.
        let name = utterance.said(range).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : .switchTo(name)
    }
}
