import Foundation

/// Fast-path rules for the coding and research forms (English, French, Portuguese):
///
///     open a terminal [in <project>]          open <project> in (VS Code|Cursor|Xcode|Finder|terminal)
///     code|build|fix <task> in <project>      ask (claude|codex|gemini|cursor) to <task> [in <project>]
///     research|look up|find out <topic>       deep research <topic>
///
/// The rules only read the words. Whether `<project>` exists is checked afterwards against the
/// project index (`FastActions`), and an unknown project hands the request on to the LLM.
extension FastIntent {
    /// First words of the forms whose text part can be long.
    static let longFormLeads: Set<String> = [
        "code", "build", "fix", "implement", "refactor", "debug", "ask", "tell", "have", "get", "let", "research", "deep", "look", "find",
        "investigate", "do", "run", "make", "give", "lookup", "recherche", "demande", "dis", "pesquisa", "pesquise", "pede", "peca", "diz",
        "codifica", "programme", "corrige", "constroi", "fais", "faz", "faca", "investiga",
    ]

    static let codeRules = TemplateSet([
        ("term", [
            "(open|launch|start|fire up|bring up|get) [a|an|the|my] [new] terminal [window|tab|session]",
            "(open|launch|start|fire up|bring up) [a|an|the|my] [new] terminal (in|at|on|inside|into) {project}",
            "(ouvre|ouvrir|lance|lancer) [un|le|mon] [nouveau] terminal",
            "(ouvre|ouvrir|lance|lancer) [un|le|mon] [nouveau] terminal (dans|sur|pour|a) {project}",
            "(abre|abra|abrir|inicia|inicie) [um|o|meu] [novo] terminal",
            "(abre|abra|abrir|inicia|inicie) [um|o|meu] [novo] terminal (em|no|na|para) {project}",
        ]),
        ("openin", [
            "(open|launch|show|load|pull up) [my|the] {project} (in|with|using|on) {target}",
            "(ouvre|ouvrir|lance|lancer) [le|la|mon|ma] {project} (dans|avec|sur) {target}",
            "(abre|abra|abrir) [o|a|meu|minha] {project} (no|na|em|com|pelo|pela) {target}",
        ]),
        ("agent", [
            "(code|build|fix|implement|refactor|debug) {task} (in|on|for|inside) [the|my] {project}",
            "(programme|construis|corrige|repare|implemente|refactorise|debogue) {task} (dans|sur|pour) [le|la|mon|ma] {project}",
            "(codifica|programa|constroi|corrige|conserta|implementa|refatora|depura) {task} (no|na|em|para) [o|a|meu|minha] {project}",
        ]),
        // The tool is a lazy slot (shortest first), so a task containing "to" ("go to the store") stays whole.
        ("ask", [
            "(ask|tell|have|get|let) {tool~} to {task} (in|on|inside) [the|my] {project}",
            "(ask|tell|have|get|let) {tool~} to {task}",
            "(demande|dis) (a|au) {tool~} (de|d') {task} (dans|sur) [le|la|mon|ma] {project}",
            "(demande|dis) (a|au) {tool~} (de|d') {task}",
            "(pede|peca|diz) (ao|a) {tool~} (para|pra) {task} (no|na|em) [o|a|meu] {project}",
            "(pede|peca|diz) (ao|a) {tool~} (para|pra) {task}",
        ]),
        ("deepresearch", [
            "(deep|in depth|thorough|detailed) research [on|about|into|for|of] {topic}",
            "(do|run|give me) [a|some] (deep|in depth|thorough) research (on|about|into|for) {topic}",
            "(recherche approfondie|recherche poussee|recherche detaillee) [sur|a propos de|autour de] {topic}",
            "(fais|lance) [une] (recherche approfondie|recherche poussee) (sur|a propos de) {topic}",
            "(pesquisa aprofundada|pesquisa profunda|pesquisa detalhada) [sobre|acerca de] {topic}",
            "(faz|faca|fazer) [uma] (pesquisa aprofundada|pesquisa profunda) (sobre) {topic}",
        ]),
        ("research", [
            "(research|look up|lookup|find out|investigate) {topic}",
            "(do|run|give me) [some|a] [quick] research (on|about|into|for) {topic}",
            "(recherche|renseigne-toi sur|renseigne toi sur|informe-toi sur|cherche des infos sur|fais une recherche sur|fais des recherches sur) {topic}",
            "(pesquisa|pesquise|pesquisar|investiga|investigue|descobre|descubra|procura saber) [sobre] {topic}",
        ]),
    ])

    private static let projectLeadArticles: Set<String> = ["the", "my", "le", "la", "les", "l'", "mon", "ma", "mes", "o", "a", "os", "as", "meu", "minha", "um", "uma"]
    private static let projectTrailing: Set<String> = ["project", "repo", "repository", "folder", "directory", "codebase", "app", "projet", "dossier", "projeto", "pasta"]
    private static let projectPrepositions: Set<String> = ["in", "on", "inside", "dans", "sur", "no", "na", "em"]
    private static let notProjects: Set<String> = ["it", "this", "that", "them", "there", "here", "everything", "ce", "ca", "cela", "isso", "isto", "aqui", "la"]
    private static let researchLeads: Set<String> = ["on", "about", "into", "for", "of", "sur", "sobre"]

    static let projectTargets: [String: ProjectApp] = [
        "vs code": .vscode, "vscode": .vscode, "visual studio code": .vscode, "code": .vscode, "v s code": .vscode, "visual studio": .vscode,
        "cursor": .cursor, "xcode": .xcode, "x code": .xcode, "finder": .finder,
        "terminal": .terminal, "iterm": .terminal, "ghostty": .terminal, "warp": .terminal, "the terminal": .terminal,
    ]

    /// A project name from `range`: articles and "project"/"repo" dropped, 1 to 4 words, no pronouns.
    static func projectName(_ range: Range<Int>?, in utterance: Utterance) -> String? {
        guard let range else { return nil }
        var lower = range.lowerBound, upper = range.upperBound
        let words = utterance.words
        while lower < upper - 1, projectLeadArticles.contains(words[lower]) || projectTrailing.contains(words[lower]) && words[lower] != "app" { lower += 1 }
        // Only drop a trailing "app" when something else is left to name the project.
        while upper - lower > 1, projectTrailing.contains(words[upper - 1]) { upper -= 1 }
        guard upper > lower, upper - lower <= 4 else { return nil }
        if words[lower..<upper].contains(where: { notProjects.contains($0) }) { return nil }
        let name = utterance.said(lower..<upper).trimmingCharacters(in: .whitespaces)
        return name.count >= 2 ? name : nil
    }

    /// "…, with codex" / "using codex" at the end of `range`: the tool, and the range without it.
    private static func splittingTool(_ range: Range<Int>, in utterance: Utterance) -> (CodingTool?, Range<Int>) {
        let words = utterance.words
        for cut in range where cut > range.lowerBound && ["with", "using", "avec", "com", "usando"].contains(words[cut]) {
            if let tool = CodingTool.named(words[(cut + 1)..<range.upperBound].joined(separator: " ")) { return (tool, range.lowerBound..<cut) }
        }
        return (nil, range)
    }

    static func buildCode(rule: String, slots: [String: Range<Int>], in utterance: Utterance) -> FastIntent? {
        let words = utterance.words
        switch rule {
        case "term":
            guard let range = slots["project"] else { return .openTerminal(project: nil) }
            guard let name = projectName(range, in: utterance) else { return nil }
            return .openTerminal(project: name)
        case "openin":
            guard let project = slots["project"], let target = slots["target"], let name = projectName(project, in: utterance) else { return nil }
            var lower = target.lowerBound
            while lower < target.upperBound, ["the", "le", "la", "l'", "o", "a", "no", "na"].contains(words[lower]) { lower += 1 }
            guard lower < target.upperBound, let app = projectTargets[words[lower..<target.upperBound].joined(separator: " ")] else { return nil }
            return .openProject(name, in: app)
        case "agent", "ask":
            guard var task = slots["task"] else { return nil }
            var tool: CodingTool?
            var projectRange = slots["project"]
            // The project comes after the LAST "in": "fix the crash in the parser in zeus" is about zeus.
            if let range = projectRange,
               let cut = ((range.lowerBound + 1)..<range.upperBound).last(where: { projectPrepositions.contains(words[$0]) }) {
                task = task.lowerBound..<cut
                projectRange = (cut + 1)..<range.upperBound
                if projectRange!.isEmpty { return nil }
            }
            if rule == "ask" {
                guard let range = slots["tool"], range.count <= 3, let found = CodingTool.named(words[range].joined(separator: " ")) else { return nil }
                tool = found
            }
            if let range = projectRange {
                let (withTool, trimmed) = splittingTool(range, in: utterance)
                if let withTool { tool = withTool }
                projectRange = trimmed
            } else {
                let (withTool, trimmed) = splittingTool(task, in: utterance)
                if let withTool { tool = withTool; task = trimmed }
            }
            let project: String?
            if projectRange != nil {
                guard let name = projectName(projectRange, in: utterance) else { return nil }
                project = name
            } else {
                project = nil
            }
            // For "fix …" the verb is part of the task ("fix the login bug"); for "ask codex to …" it is not.
            let text = utterance.source(task).trimmingCharacters(in: .whitespacesAndNewlines)
            let verb = rule == "agent" ? (utterance.original.first ?? "") + " " : ""
            guard text.count >= 3 else { return nil }
            // "code" / "build" alone read badly as a task, so they keep their object ("build the settings page").
            return .codeAgent(tool: tool, project: project, task: verb + text)
        case "research", "deepresearch":
            guard var range = slots["topic"] else { return nil }
            while range.count > 1, researchLeads.contains(words[range.lowerBound]) { range = (range.lowerBound + 1)..<range.upperBound }
            let topic = utterance.source(range).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard topic.count >= 3, !["it", "this", "that", "something", "anything"].contains(topic.lowercased()) else { return nil }
            return .research(topic: topic, deep: rule == "deepresearch")
        default:
            return nil
        }
    }
}
