import Foundation

/// Spoken to-do commands. A blank edge is a named scalar. U+200B is not a member.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so this type does not ask that set.
/// This type does not read a vault, a clock, or a network.
public enum TodoVoiceBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member.
    public static let blankScalars: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}",
        "\u{0020}",
        "\u{0085}",
        "\u{00A0}",
        "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    private static let addLeads = [
        "add these to-dos", "add these todos", "add these tasks", "add the following to-dos", "add the following tasks",
        "add to-dos", "add todos", "add tasks", "add to-do", "add todo", "add a to-do", "add a todo", "add a task", "add task",
        "new to-do", "new todo", "new task", "to-do", "todo", "remind me to",
        "ajoute ces tâches", "ajoute ces taches", "ajoute les tâches", "ajoute une tâche", "ajoute la tâche", "ajoute",
        "adiciona essas tarefas", "adiciona as tarefas", "adicione as tarefas", "adiciona tarefa", "adiciona uma tarefa", "adiciona", "adicione",
    ]
    private static let todayPhrases = [
        "what do i have today", "what's on today", "whats on today", "what is on today", "what have i got today",
        "what's on my plate", "my day", "today's tasks", "qu'est-ce que j'ai aujourd'hui", "j'ai quoi aujourd'hui",
        "o que eu tenho hoje", "o que tenho hoje",
    ]
    private static let briefPhrases = [
        "daily brief", "morning brief", "brief me", "give me my brief", "give me the brief", "brief of the day",
        "résumé du jour", "resume du jour", "fais-moi le point", "resumo do dia", "meu resumo",
    ]
    private static let doneLeads = [
        "mark done", "complete", "i finished", "i did", "done with", "check off", "tick off", "j'ai fini", "terminei", "concluí",
    ]
    private static let fillers = [
        " to my list", " to the list", " to my to-do list", " à ma liste", " na lista", " na minha lista",
    ]
    private static let separators = [
        ",", ";", "\n", " and then ", " then ", " and also ", " and ", " et puis ", " et ", " e depois ", " e ",
    ]

    /// Leading and trailing members of `blankScalars`, plus `also`. A zero-width space stays.
    public static func trimmed(_ text: String, also: Set<Unicode.Scalar> = []) -> String {
        cut(text) { blankScalars.contains($0) || also.contains($0) }
    }

    /// Blanks and punctuation at the edges. U+200B stays, even when a punctuation set would be asked next.
    public static func trimmedRemainder(_ text: String) -> String {
        cut(text) { scalar in
            if blankScalars.contains(scalar) { return true }
            if scalar == "\u{200B}" { return false }
            return CharacterSet.punctuationCharacters.contains(scalar)
        }
    }

    public static func parse(_ utterance: String) -> TodoVoice.Command? {
        let text = trimmed(utterance, also: [".", "!", "?"])
        let lower = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if briefPhrases.contains(where: { lower.contains($0) }) { return .brief }
        if todayPhrases.contains(where: { lower.contains($0) }) { return .today }
        for lead in doneLeads where lower.hasPrefix(lead + " ") {
            let rest = trimmedRemainder(String(text.dropFirst(lead.count)))
            if !rest.isEmpty { return .complete(rest) }
        }
        for lead in addLeads where lower.hasPrefix(lead) {
            let after = lower.dropFirst(lead.count)
            guard after.isEmpty || after.first == ":" || after.first == " " || after.first == "," else { continue }
            var rest = String(text.dropFirst(lead.count))
            for filler in fillers where rest.lowercased().hasPrefix(filler) {
                rest = String(rest.dropFirst(filler.count))
            }
            let items = split(rest)
            return items.isEmpty ? nil : .add(items)
        }
        return nil
    }

    /// One phrase, many to-dos: commas, semicolons, new lines, "and", "then", "et", "e".
    public static func split(_ text: String) -> [String] {
        var parts = [text]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts
            .map { trimmed($0, also: [":", ".", "-"]) }
            .map(stripLeadingTo)
            .filter { $0.count > 1 }
    }

    /// "to call Anna" from a bare "call Anna" lead should not keep the filler "to".
    public static func stripLeadingTo(_ text: String) -> String {
        var result = trimmed(text)
        if result.lowercased().hasPrefix("to ") {
            result = trimmed(String(result.dropFirst(3)))
        }
        return result
    }

    private static func cut(_ text: String, dropping: (Unicode.Scalar) -> Bool) -> String {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, dropping(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let previous = scalars.index(before: end)
            if dropping(scalars[previous]) {
                end = previous
            } else {
                break
            }
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }
}
