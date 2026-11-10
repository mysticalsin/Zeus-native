import Foundation

/// The System One request and response shape (TypeSafe's `/v1/systemone`), shared by paid Jev and
/// the local Laya server (laya-serve), which accepts the same body. Our own thin client, no SDK.
public struct SystemOneQuestion: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case choice, noul, score }
    public var type: Kind
    public var instructions: String
    /// Choice: option name to description. Unused for Noul and Score.
    public var choices: [String: String]?
    /// Score: ordered level descriptions.
    public var levels: [String]?

    public static func choice(_ instructions: String, _ options: [String: String]) -> Self { .init(type: .choice, instructions: instructions, choices: options) }
    public static func noul(_ instructions: String) -> Self { .init(type: .noul, instructions: instructions) }
    public static func score(_ instructions: String, _ levels: [String]) -> Self { .init(type: .score, instructions: instructions, levels: levels) }

    enum CodingKeys: String, CodingKey { case type, instructions, criteria }
    public init(type: Kind, instructions: String, choices: [String: String]? = nil, levels: [String]? = nil) {
        self.type = type; self.instructions = instructions; self.choices = choices; self.levels = levels
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(instructions, forKey: .instructions)
        switch type {
        case .choice: try c.encode(choices ?? [:], forKey: .criteria)
        case .score: try c.encode(levels ?? [], forKey: .criteria)
        case .noul: break
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(Kind.self, forKey: .type)
        instructions = try c.decode(String.self, forKey: .instructions)
        choices = try? c.decode([String: String].self, forKey: .criteria)
        levels = try? c.decode([String].self, forKey: .criteria)
    }
}

public struct SystemOneRequest: Codable, Equatable, Sendable {
    public var model: String
    public var state: [String: String]
    public var questions: [String: SystemOneQuestion]
    public init(model: String, state: [String: String], questions: [String: SystemOneQuestion]) {
        self.model = model; self.state = state; self.questions = questions
    }

    /// Rough input size for the cost guard before a call: about four characters per token.
    public var estimatedInputTokens: Int {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return max(1, data.count / 4)
    }
}

public struct SystemOneAnswer: Codable, Equatable, Sendable {
    public var type: String
    public var choice: String?
    public var confidence: Double?
    public var probabilities: [String: Double]?
    public var noul: Double?
    public var score: Double?
    public init(type: String, choice: String? = nil, confidence: Double? = nil, probabilities: [String: Double]? = nil, noul: Double? = nil, score: Double? = nil) {
        self.type = type; self.choice = choice; self.confidence = confidence; self.probabilities = probabilities; self.noul = noul; self.score = score
    }
}

public struct SystemOneResponse: Codable, Equatable, Sendable {
    public struct Usage: Codable, Equatable, Sendable {
        public var input_tokens: Int
        public var output_tokens: Int
        public init(input_tokens: Int, output_tokens: Int) { self.input_tokens = input_tokens; self.output_tokens = output_tokens }
    }
    public var model: String
    public var answers: [String: SystemOneAnswer]
    public var usage: Usage
    public init(model: String, answers: [String: SystemOneAnswer], usage: Usage) { self.model = model; self.answers = answers; self.usage = usage }
}
