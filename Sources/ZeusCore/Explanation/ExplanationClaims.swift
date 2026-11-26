import Foundation

/// Phase 4 explanation claims.
///
/// A generic claim is shown as written and carries no source chip. A brand-specific
/// claim must name at least one source id; with none, it is rejected. When every
/// named source sits outside the approved registry, the claim is downgraded: the
/// shown line is "varies by model" and the badge is "needs reference".
///
/// `approvedSourceIDs` is the caller's `ExplanationRegistry.sourceIDs`. This type
/// does not fetch URLs and does not decide which URLs are approved.
public enum ExplanationClaims {
    public static let maximumPerEvent = 8
    public static let maximumSources = 4
    /// JSON Schema `maxLength` counts Unicode code points.
    public static let maximumTextScalars = 280
    public static let variesByModel = "varies by model"
    public static let needsReference = "needs reference"

    public enum Scope: String, Codable, Equatable, Sendable {
        case generic
        case brandSpecific
    }

    public enum Rejection: Equatable, Sendable {
        case identifier
        case textBounds
        case sourceBudget
        case duplicateSource
        case needsSource
        case claimBudget
        case duplicateClaim
        case malformed
    }

    public struct Presented: Equatable, Sendable {
        public var id: String
        public var scope: Scope
        public var text: String
        public var sourceChip: [String]
        public var badge: String?

        public init(id: String, scope: Scope, text: String, sourceChip: [String], badge: String?) {
            self.id = id
            self.scope = scope
            self.text = text
            self.sourceChip = sourceChip
            self.badge = badge
        }
    }

    public enum Outcome: Equatable, Sendable {
        case admitted(Presented)
        case downgraded(Presented)
        case rejected(Rejection)
    }

    public struct Claim: Equatable, Sendable, Codable {
        public var id: String
        public var scope: Scope
        public var text: String
        public var sourceIDs: [String]

        public init(id: String, scope: Scope, text: String, sourceIDs: [String] = []) {
            self.id = id
            self.scope = scope
            self.text = text
            self.sourceIDs = sourceIDs
        }

        private enum CodingKeys: String, CodingKey {
            case id, scope, text, sourceIDs
        }

        private struct JSONKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }
            init?(intValue: Int) {
                self.stringValue = "\(intValue)"
                self.intValue = intValue
            }
        }

        public init(from decoder: Decoder) throws {
            let probe = try decoder.container(keyedBy: JSONKey.self)
            let allowed: Set<String> = ["id", "scope", "text", "sourceIDs"]
            for key in probe.allKeys where !allowed.contains(key.stringValue) {
                throw DecodingError.dataCorruptedError(forKey: key, in: probe, debugDescription: "unknown field")
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.scope = try container.decode(Scope.self, forKey: .scope)
            self.text = try container.decode(String.self, forKey: .text)
            if container.contains(.sourceIDs) {
                self.sourceIDs = try container.decode([String].self, forKey: .sourceIDs)
            } else {
                self.sourceIDs = []
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(scope, forKey: .scope)
            try container.encode(text, forKey: .text)
            try container.encode(sourceIDs, forKey: .sourceIDs)
        }
    }

    public static func review(_ claim: Claim, approvedSourceIDs: Set<String>) -> Outcome {
        guard isIdentifier(claim.id) else { return .rejected(.identifier) }
        guard textIsBounded(claim.text) else { return .rejected(.textBounds) }
        guard claim.sourceIDs.count <= maximumSources else { return .rejected(.sourceBudget) }
        guard Set(claim.sourceIDs).count == claim.sourceIDs.count else { return .rejected(.duplicateSource) }
        guard claim.sourceIDs.allSatisfy(isIdentifier) else { return .rejected(.identifier) }
        switch claim.scope {
        case .generic:
            return .admitted(Presented(id: claim.id, scope: .generic, text: claim.text, sourceChip: [], badge: nil))
        case .brandSpecific:
            guard !claim.sourceIDs.isEmpty else { return .rejected(.needsSource) }
            let chip = claim.sourceIDs.filter { approvedSourceIDs.contains($0) }
            if chip.isEmpty {
                return .downgraded(Presented(
                    id: claim.id, scope: .brandSpecific, text: variesByModel, sourceChip: [], badge: needsReference))
            }
            return .admitted(Presented(
                id: claim.id, scope: .brandSpecific, text: claim.text, sourceChip: chip, badge: nil))
        }
    }

    public static func review(_ claims: [Claim], approvedSourceIDs: Set<String>) -> [Outcome] {
        guard claims.count <= maximumPerEvent else { return [.rejected(.claimBudget)] }
        var seen = Set<String>()
        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(claims.count)
        for claim in claims {
            if !seen.insert(claim.id).inserted {
                outcomes.append(.rejected(.duplicateClaim))
                continue
            }
            outcomes.append(review(claim, approvedSourceIDs: approvedSourceIDs))
        }
        return outcomes
    }

    /// The claims array from one event. A payload that is not that array is rejected whole.
    public static func review(json data: Data, approvedSourceIDs: Set<String>) -> [Outcome] {
        guard let claims = try? JSONDecoder().decode([Claim].self, from: data) else {
            return [.rejected(.malformed)]
        }
        return review(claims, approvedSourceIDs: approvedSourceIDs)
    }

    private static func isIdentifier(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return (1...64).contains(bytes.count) && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func textIsBounded(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard (1...maximumTextScalars).contains(scalars.count) else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return scalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }
}
