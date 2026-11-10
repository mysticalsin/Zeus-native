import Foundation

enum PersonaArithmetic {
    /// "what is 17 times 23" style questions, answered locally.
    static func answer(for transcript: String) -> String? {
        let key = Utterance(transcript).words.joined(separator: " ")
        guard key.contains("what is") || key.contains("what's") else { return nil }
        let ops: [(String, (Int, Int) -> Int)] = [
            ("times", *), ("multiplied by", *), ("plus", +), ("minus", -),
        ]
        for (word, op) in ops {
            guard key.contains(word) else { continue }
            let parts = key.split(separator: " ").map(String.init)
            guard let left = parts.compactMap({ Int($0) }).first,
                  let right = parts.compactMap({ Int($0) }).last,
                  left != right || parts.filter({ Int($0) != nil }).count >= 2 else { continue }
            return "\(op(left, right))."
        }
        return nil
    }
}
