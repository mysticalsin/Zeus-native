import Foundation

/// Phase 4 teaching follow-ups (`docs/POINTING-ASSISTANT-PLAN.md`).
///
/// "show the motor" aims the camera at the existing `motor` and highlights it.
/// "rotate it" rotates that same id. "simpler" and "explain that more simply"
/// speak a shorter line and remove detail ids. "highlight the battery" highlights
/// the existing `battery`. The motor and battery ids stay. This type does not
/// create a part, does not apply an edit, and does not open a connection.
/// The spoken phrase is the one `PointingTeachingFollowUpBox` returns. A zero-width
/// space stays in that phrase.
public enum PointingTeachingFollowUp {
    public static let motorID = "motor"
    public static let batteryID = "battery"
    /// Close view offset from the motor's current position. The target stays that part.
    public static let cameraOffsetX = 1.2
    public static let cameraOffsetY = 0.8
    public static let cameraOffsetZ = 1.4
    /// One right-angle turn about the motor's local z axle, in radians.
    public static let motorRotationRadians = Double.pi / 2
    /// Bounded animation length, in seconds. This type does not schedule it.
    public static let rotationSeconds = 1.0
    public static let simplerSpeech = "The battery sends energy to the motor. The motor turns the wheels."
    /// Spoken command budget, in UTF-8 bytes.
    public static let maxUtteranceBytes = 256
    /// `ExplanationLimits.objects`.
    public static let maxPartIDs = 256
    /// Removals one simpler request may name. Under `ExplanationLimits.operationsPerEvent`.
    public static let maxRemovals = 32
    /// `ExplanationLimits.coordinate`.
    public static let coordinateLimit = 16_384.0
    /// `ExplanationLimits.speech`.
    public static let speechByteLimit = 1_600

    public enum Axis: String, Equatable, Sendable {
        case x, y, z
    }

    public struct Scene: Equatable, Sendable {
        public var partIDs: [String]
        /// Nil means every part except the motor and the battery is detail.
        public var detailIDs: [String]?
        public var motorX: Double?
        public var motorY: Double?
        public var motorZ: Double?

        public init(partIDs: [String], detailIDs: [String]? = nil,
                    motorX: Double? = nil, motorY: Double? = nil, motorZ: Double? = nil) {
            self.partIDs = partIDs
            self.detailIDs = detailIDs
            self.motorX = motorX
            self.motorY = motorY
            self.motorZ = motorZ
        }
    }

    public struct Camera: Equatable, Sendable {
        public var targetID: String
        public var targetX: Double
        public var targetY: Double
        public var targetZ: Double
        public var offsetX: Double
        public var offsetY: Double
        public var offsetZ: Double

        public init(targetID: String, targetX: Double, targetY: Double, targetZ: Double,
                    offsetX: Double, offsetY: Double, offsetZ: Double) {
            self.targetID = targetID
            self.targetX = targetX
            self.targetY = targetY
            self.targetZ = targetZ
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.offsetZ = offsetZ
        }
    }

    public enum Step: Equatable, Sendable {
        case camera(Camera)
        case highlight(id: String, on: Bool)
        case rotate(id: String, radians: Double, axis: Axis, seconds: Double)
        case remove(id: String)
    }

    public enum Kind: String, Equatable, Sendable {
        case showMotor, rotateMotor, simpler, highlightBattery
    }

    public struct Plan: Equatable, Sendable {
        public var kind: Kind
        public var speech: String?
        public var steps: [Step]
        public var keptIDs: [String]

        public init(kind: Kind, speech: String?, steps: [Step], keptIDs: [String]) {
            self.kind = kind
            self.speech = speech
            self.steps = steps
            self.keptIDs = keptIDs
        }
    }

    public enum Refusal: Equatable, Sendable {
        case utterance, phrase, scene, missingMotor, missingBattery, position, budget
    }

    public enum Outcome: Equatable, Sendable {
        case ready(Plan)
        case refused(Refusal)
    }

    /// Checks run in order: utterance, phrase, scene, then the command's own gap.
    /// A refusal names one reason and carries no plan.
    public static func decide(utterance: String, scene: Scene) -> Outcome {
        if let refusal = utteranceRefusal(utterance) { return .refused(refusal) }
        guard let command = command(in: utterance) else { return .refused(.phrase) }
        guard let resolved = resolve(scene) else { return .refused(.scene) }
        switch command {
        case .showMotor:
            guard resolved.partSet.contains(motorID) else { return .refused(.missingMotor) }
            guard let position = motorPosition(scene) else { return .refused(.position) }
            let camera = Camera(targetID: motorID, targetX: position.0, targetY: position.1, targetZ: position.2,
                                offsetX: cameraOffsetX, offsetY: cameraOffsetY, offsetZ: cameraOffsetZ)
            return .ready(Plan(kind: .showMotor, speech: nil,
                               steps: [.camera(camera), .highlight(id: motorID, on: true)],
                               keptIDs: resolved.parts))
        case .rotateMotor:
            guard resolved.partSet.contains(motorID) else { return .refused(.missingMotor) }
            return .ready(Plan(kind: .rotateMotor, speech: nil,
                               steps: [.rotate(id: motorID, radians: motorRotationRadians, axis: .z, seconds: rotationSeconds)],
                               keptIDs: resolved.parts))
        case .simpler:
            guard let removed = removals(resolved: resolved, details: scene.detailIDs) else { return .refused(.budget) }
            let removedSet = Set(removed)
            let kept = resolved.parts.filter { !removedSet.contains($0) }
            return .ready(Plan(kind: .simpler, speech: simplerSpeech,
                               steps: removed.map { .remove(id: $0) },
                               keptIDs: kept))
        case .highlightBattery:
            guard resolved.partSet.contains(batteryID) else { return .refused(.missingBattery) }
            return .ready(Plan(kind: .highlightBattery, speech: nil,
                               steps: [.highlight(id: batteryID, on: true)],
                               keptIDs: resolved.parts))
        }
    }

    private struct Resolved {
        var parts: [String]
        var partSet: Set<String>
    }

    private static let anchors: Set<String> = [motorID, batteryID]

    private static func utteranceRefusal(_ utterance: String) -> Refusal? {
        if utterance.utf8.count > maxUtteranceBytes { return .utterance }
        let folded = utterance.lowercased()
        if folded.contains("://") || folded.contains("www.") { return .utterance }
        for scalar in utterance.unicodeScalars {
            if scalar == "\t" || scalar == "\n" || scalar == "\r" { continue }
            if scalar.value < 32 || scalar.value == 127 { return .utterance }
        }
        return nil
    }

    private enum Command {
        case showMotor, rotateMotor, simpler, highlightBattery
    }

    private static func command(in utterance: String) -> Command? {
        var text = PointingTeachingFollowUpBox.phrase(utterance)
        let please = "please "
        if text.hasPrefix(please) {
            text = String(text.dropFirst(please.count))
        }
        switch text {
        case "show the motor": return .showMotor
        case "rotate it": return .rotateMotor
        case "simpler", "explain that more simply": return .simpler
        case "highlight the battery": return .highlightBattery
        default: return nil
        }
    }

    /// Identifier shape from `ExplanationSceneReducer.identifier`: 1...64 bytes of
    /// letters, digits, hyphen, and underscore.
    private static func validID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        }
    }

    private static func resolve(_ scene: Scene) -> Resolved? {
        if scene.partIDs.count > maxPartIDs { return nil }
        var set = Set<String>()
        for id in scene.partIDs {
            guard validID(id) else { return nil }
            set.insert(id)
        }
        return Resolved(parts: set.sorted(), partSet: set)
    }

    private static func motorPosition(_ scene: Scene) -> (Double, Double, Double)? {
        guard let x = scene.motorX, let y = scene.motorY, let z = scene.motorZ else { return nil }
        let values = [x, y, z]
        guard values.allSatisfy({ $0.isFinite && abs($0) <= coordinateLimit }) else { return nil }
        return (x, y, z)
    }

    private static func removals(resolved: Resolved, details: [String]?) -> [String]? {
        let source: [String]
        if let details {
            if details.count > maxPartIDs { return nil }
            source = details
        } else {
            source = resolved.parts
        }
        var out = Set<String>()
        for id in source {
            if anchors.contains(id) { continue }
            guard resolved.partSet.contains(id), validID(id) else { continue }
            out.insert(id)
        }
        if out.count > maxRemovals { return nil }
        return out.sorted()
    }
}
