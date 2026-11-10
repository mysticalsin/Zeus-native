import Foundation

/// Spoken to-do commands, handled on the Mac before any model: "add these to-dos: call Ana
/// tomorrow, send the invoice Friday and book the dentist". English, French and Portuguese.
public enum TodoVoice {
    public enum Command: Equatable, Sendable {
        case add([String])
        case today
        case brief
        case complete(String)
    }

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
    private static let doneLeads = ["mark done", "complete", "i finished", "i did", "done with", "check off", "tick off", "j'ai fini", "terminei", "concluí"]

    public static func parse(_ utterance: String) -> Command? {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".!?")))
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        if briefPhrases.contains(where: { lower.contains($0) }) { return .brief }
        if todayPhrases.contains(where: { lower.contains($0) }) { return .today }
        for lead in doneLeads where lower.hasPrefix(lead + " ") {
            let rest = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !rest.isEmpty { return .complete(rest) }
        }
        for lead in addLeads where lower.hasPrefix(lead) {
            let after = lower.dropFirst(lead.count)
            guard after.isEmpty || after.first == ":" || after.first == " " || after.first == "," else { continue }
            var rest = String(text.dropFirst(lead.count))
            // "add to my list ...", "add to the list ...": drop the filler.
            for filler in [" to my list", " to the list", " to my to-do list", " à ma liste", " na lista", " na minha lista"] where rest.lowercased().hasPrefix(filler) {
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
        for separator in [",", ";", "\n", " and then ", " then ", " and also ", " and ", " et puis ", " et ", " e depois ", " e "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ":.-"))) }
            .map(stripLeadingTo)
            .filter { $0.count > 1 }
    }

    /// "to call Anna" from a bare "call Anna" lead should not keep the filler "to".
    public static func stripLeadingTo(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        if lower.hasPrefix("to ") { result = String(result.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return result
    }
}
