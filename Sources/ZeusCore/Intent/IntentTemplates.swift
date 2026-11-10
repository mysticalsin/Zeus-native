import Foundation

/// A tiny sentence-template matcher in the style of Home Assistant's hassil (Apache-2.0; ideas
/// only, no code taken): `(open|launch) [the] {app}` means one of the alternatives, an optional
/// word, then a slot of one or more words. Templates are expanded once into flat word sequences,
/// so matching is plain array comparison with a little backtracking for slots.
struct IntentTemplate: Sendable {
    enum Element: Equatable, Sendable {
        case word(String)
        case slot(String)
    }

    let rule: String
    let elements: [Element]

    /// Expands `pattern` into every concrete sequence it allows, all tagged with `rule`.
    static func expand(_ pattern: String, rule: String) -> [IntentTemplate] {
        var sequences: [[Element]] = [[]]
        var index = pattern.startIndex
        func readGroup(close: Character) -> [String] {
            var body = ""
            while index < pattern.endIndex, pattern[index] != close {
                body.append(pattern[index]); index = pattern.index(after: index)
            }
            if index < pattern.endIndex { index = pattern.index(after: index) }
            return body.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        func words(_ text: String) -> [Element] {
            text.split(separator: " ").map { part in
                let s = String(part)
                if s.hasPrefix("{"), s.hasSuffix("}") { return .slot(String(s.dropFirst().dropLast())) }
                return .word(Utterance.normalize(s))
            }
        }
        while index < pattern.endIndex {
            let c = pattern[index]
            if c == " " { index = pattern.index(after: index); continue }
            if c == "(" || c == "[" {
                index = pattern.index(after: index)
                var options = readGroup(close: c == "(" ? ")" : "]")
                if c == "[" { options.append("") }
                sequences = sequences.flatMap { seq in options.map { seq + words($0) } }
            } else {
                var word = ""
                while index < pattern.endIndex, pattern[index] != " ", pattern[index] != "(", pattern[index] != "[" {
                    word.append(pattern[index]); index = pattern.index(after: index)
                }
                sequences = sequences.map { $0 + words(word) }
            }
        }
        return sequences.map { IntentTemplate(rule: rule, elements: $0) }
    }

    /// Slot name to word range, when the whole utterance matches.
    func match(_ words: [String]) -> [String: Range<Int>]? {
        var captures: [String: Range<Int>] = [:]
        return Self.match(elements[...], words, from: 0, &captures) ? captures : nil
    }

    private static func match(_ elements: ArraySlice<Element>, _ words: [String], from start: Int,
                              _ captures: inout [String: Range<Int>]) -> Bool {
        guard let first = elements.first else { return start == words.count }
        switch first {
        case .word(let w):
            guard start < words.count, words[start] == w else { return false }
            return match(elements.dropFirst(), words, from: start + 1, &captures)
        case .slot(let rawName):
            // `{name~}` is lazy: the shortest slot first ("ask claude code to ..." names its tool before "to").
            let lazy = rawName.hasSuffix("~")
            let name = lazy ? String(rawName.dropLast()) : rawName
            // Every later element needs at least one word, so the slot can't take those.
            let longest = words.count - start - (elements.count - 1)
            guard longest >= 1 else { return false }
            // Greedy by default: the longest slot first, so "add X to my list to my to-do" keeps X whole.
            let lengths: [Int] = lazy ? Array(1...longest) : Array(stride(from: longest, through: 1, by: -1))
            for length in lengths {
                captures[name] = start..<(start + length)
                if match(elements.dropFirst(), words, from: start + length, &captures) { return true }
            }
            captures[name] = nil
            return false
        }
    }
}

/// A set of templates tried in order; the first rule that matches wins.
struct TemplateSet: Sendable {
    let templates: [IntentTemplate]
    /// Templates by their first word, so a lookup only tries the ones that can match (a set with
    /// thousands of expansions stays well under a millisecond). Templates opening with a slot are
    /// tried after, in order.
    private let byFirstWord: [String: [IntentTemplate]]
    private let slotFirst: [IntentTemplate]

    init(_ rules: [(rule: String, patterns: [String])]) {
        let all = rules.flatMap { entry in entry.patterns.flatMap { IntentTemplate.expand($0, rule: entry.rule) } }
        templates = all
        var buckets: [String: [IntentTemplate]] = [:]
        var open: [IntentTemplate] = []
        for template in all {
            if let first = template.elements.first, case .word(let w) = first { buckets[w, default: []].append(template) } else { open.append(template) }
        }
        byFirstWord = buckets
        slotFirst = open
    }

    func first(_ words: [String]) -> (rule: String, slots: [String: Range<Int>])? {
        if let first = words.first, let bucket = byFirstWord[first] {
            for template in bucket {
                if let slots = template.match(words) { return (template.rule, slots) }
            }
        }
        for template in slotFirst {
            if let slots = template.match(words) { return (template.rule, slots) }
        }
        return nil
    }
}
