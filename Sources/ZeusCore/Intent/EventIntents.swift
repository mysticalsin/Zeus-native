import Foundation

extension FastIntent {
    /// "add lunch with Ana tomorrow at 1 pm", "schedule a meeting with Sam on friday", "ajoute déjeuner demain à 13h",
    /// "agenda almoço amanhã às 13h". Strict: a command verb, a title and a day or a time. Without a day or time ("add
    /// lunch with Ana") it is not sure, so the next stage decides. To-dos ("add X to my list") match their own rule first.
    static func eventIntent(_ utterance: Utterance) -> FastIntent? {
        let words = utterance.words
        guard words.count >= 3, CalendarQuickAdd.leadVerbs.contains(words[0]), words[0] != "set", words[0] != "new" else { return nil }
        // "book me a flight tomorrow", "add it tomorrow", "create a project called x at 5": not a calendar event.
        var next = 1
        while next < words.count, ["a", "an", "the", "un", "une", "o", "um", "uma", "new", "novo", "nova"].contains(words[next]) { next += 1 }
        guard next < words.count else { return nil }
        let blocked: Set<String> = ["me", "it", "this", "that", "them", "these", "those", "todo", "todos", "timer", "reminder", "note", "tab", "project",
                                    "file", "folder", "task", "alarm", "volume", "song", "playlist", "window", "page", "rappel", "minuteur", "lembrete"]
        guard !blocked.contains(words[next]) else { return nil }
        // To-do and reminder lists keep theirs.
        if words.contains(where: { ["todo", "todos", "reminders", "list", "liste", "lista", "tarefas", "taches"].contains($0) }) { return nil }
        let text = utterance.source(0..<words.count)
        guard let parsed = CalendarQuickAdd.parse(text), parsed.hadDate, parsed.title.count >= 2 else { return nil }
        return .addEvent(text)
    }
}
