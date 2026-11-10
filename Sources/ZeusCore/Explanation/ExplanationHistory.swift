import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Local, editable history. Replay checkpoints are observations of applied work, never queued model operations.
/// Text is deliberately limited to visible user/assistant conversation. No credentials, prompts, audio,
/// screenshots, file paths, or resource bytes have dedicated storage fields here.
public struct ExplanationHistory: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let maxMessages = 32
    public static let maxConversationBytes = 65_536
    public static let maxUndoStates = 16
    public static let maxCheckpoints = 64
    public static let maxSceneBytes = 262_144
    public static let maxRecordBytes = 8 * 1024 * 1024

    public enum HistoryError: Error, Equatable, LocalizedError, Sendable {
        case unsupportedVersion(Int), invalidHistory, invalidDate, wrongIdentity
        case staleRevision, revisionExhausted, invalidAdmission, alreadyStarted, notStarted, cueOutOfOrder
        case nothingToUndo, nothingToRedo, checkpointMissing, limitExceeded
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This explanation uses an unsupported history version."
            case .invalidHistory: "The explanation history is inconsistent or unreadable."
            case .invalidDate: "The explanation timestamp is invalid or earlier than the last change."
            case .wrongIdentity: "This scene belongs to a different explanation."
            case .staleRevision: "The explanation changed while this response was being prepared."
            case .revisionExhausted: "This explanation reached its revision limit. Start a new explanation."
            case .invalidAdmission: "This playback is no longer active."
            case .alreadyStarted: "This explanation beat already started."
            case .notStarted: "This explanation beat has not started playing."
            case .cueOutOfOrder: "The explanation cue is missing, repeated, or out of order."
            case .nothingToUndo: "There is no scene change to undo."
            case .nothingToRedo: "There is no scene change to redo."
            case .checkpointMissing: "That replay checkpoint is no longer retained."
            case .limitExceeded: "This explanation exceeds the local history size limit."
            }
        }
    }

    public struct Message: Codable, Equatable, Sendable, Identifiable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        public let id: UUID
        public let role: Role
        public let text: String
        public let createdAt: Date
    }

    /// Identity only: future speech, operations, audio references and provider payloads are not persisted.
    public struct ModelEventKey: Codable, Equatable, Sendable {
        public let sessionID: UUID
        public let turnID: UUID
        public let sceneID: UUID
        public let sequence: Int
        public let baseRevision: Int
        public let revision: Int
        public let beatID: String
        public init(sessionID: UUID, turnID: UUID, sceneID: UUID, sequence: Int,
                    baseRevision: Int, revision: Int, beatID: String) {
            self.sessionID = sessionID; self.turnID = turnID; self.sceneID = sceneID
            self.sequence = sequence; self.baseRevision = baseRevision; self.revision = revision; self.beatID = beatID
        }
        public init(_ event: ExplanationEvent) {
            self.init(sessionID: event.sessionID, turnID: event.turnID, sceneID: event.sceneID,
                      sequence: event.sequence, baseRevision: event.baseRevision,
                      revision: event.revision, beatID: event.beatID)
        }
    }

    public struct Checkpoint: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable { case created, turn, message, modelStart, cue, edit, interruption, undo, redo }
        public let id: UUID
        /// Strictly increasing independently of scene revision; several actual cues may share a reserved revision.
        public let ordinal: Int
        public let kind: Kind
        public let createdAt: Date
        public let scene: ExplanationScene
        public let event: ModelEventKey?
        public let cueIndex: Int?
    }

    public private(set) var version: Int
    public let id: UUID
    public private(set) var title: String
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var canonicalScene: ExplanationScene
    public private(set) var activeTurnID: UUID?
    public private(set) var messages: [Message]
    public private(set) var checkpoints: [Checkpoint]
    public private(set) var discardedMessages: Int
    public private(set) var discardedCheckpoints: Int
    public private(set) var discardedUndoStates: Int
    private var undoScenes: [ExplanationScene]
    private var redoScenes: [ExplanationScene]

    /// Never encoded. Reopening a record cannot resume or admit old playback callbacks.
    private var admission: Admission? = nil
    private struct Admission: Equatable, Sendable {
        var id: UUID
        var key: ModelEventKey
        var cueCount: Int
        var nextCue = 0
        var started = false
        var pushedUndo = false
        var before: ExplanationScene
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, title, createdAt, updatedAt, canonicalScene, activeTurnID, messages, checkpoints
        case discardedMessages, discardedCheckpoints, discardedUndoStates, undoScenes, redoScenes
    }

    public var revision: Int { canonicalScene.revision }
    public var canUndo: Bool { !undoScenes.isEmpty }
    public var canRedo: Bool { !redoScenes.isEmpty }
    public var lastCheckpointID: UUID { checkpoints[checkpoints.count - 1].id }

    public init(scene: ExplanationScene, title: String, at date: Date,
                registry: ExplanationRegistry = .empty) throws {
        version = Self.formatVersion; id = UUID(); self.title = title
        createdAt = date; updatedAt = date; canonicalScene = scene; activeTurnID = nil
        messages = []; undoScenes = []; redoScenes = []
        discardedMessages = 0; discardedCheckpoints = 0; discardedUndoStates = 0
        checkpoints = [.init(id: UUID(), ordinal: 0, kind: .created, createdAt: date,
                             scene: scene, event: nil, cueIndex: nil)]
        try validate(registry: registry)
        try enforceEncodedLimit()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else { throw HistoryError.unsupportedVersion(version) }
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt); updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        canonicalScene = try c.decode(ExplanationScene.self, forKey: .canonicalScene)
        activeTurnID = try c.decodeIfPresent(UUID.self, forKey: .activeTurnID)
        messages = try c.decode([Message].self, forKey: .messages)
        checkpoints = try c.decode([Checkpoint].self, forKey: .checkpoints)
        discardedMessages = try c.decode(Int.self, forKey: .discardedMessages)
        discardedCheckpoints = try c.decode(Int.self, forKey: .discardedCheckpoints)
        discardedUndoStates = try c.decode(Int.self, forKey: .discardedUndoStates)
        undoScenes = try c.decode([ExplanationScene].self, forKey: .undoScenes)
        redoScenes = try c.decode([ExplanationScene].self, forKey: .redoScenes)
        admission = nil
        // Asset/source authority is injected by load()/decoded(), never recovered from JSON.
        try validateStructure()
    }

    public static func decoded(_ data: Data, registry: ExplanationRegistry = .empty) throws -> Self {
        guard data.count <= maxRecordBytes else { throw HistoryError.limitExceeded }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(registry: registry)
        return value
    }

    public func encoded(registry: ExplanationRegistry = .empty) throws -> Data {
        try validate(registry: registry)
        let data = try Self.encoder().encode(self)
        guard data.count <= Self.maxRecordBytes else { throw HistoryError.limitExceeded }
        return data
    }

    public func validate(registry: ExplanationRegistry = .empty) throws {
        try validateStructure()
        for scene in [canonicalScene] + undoScenes + redoScenes + checkpoints.map(\.scene) {
            try validateScene(scene, registry: registry)
        }
    }

    @discardableResult
    public mutating func beginTurn(_ turnID: UUID, at date: Date,
                                   registry: ExplanationRegistry = .empty) throws -> Int {
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(canonicalScene, atRevision: nextRevision(), registry: registry)
        next.activeTurnID = turnID; next.admission = nil
        try next.record(.turn, at: date)
        try next.enforceEncodedLimit(); self = next
        return revision
    }

    public mutating func appendMessage(role: Message.Role, text: String, at date: Date) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 16_384, !text.utf8.contains(0) else { throw HistoryError.limitExceeded }
        var next = self
        next.messages.append(.init(id: UUID(), role: role, text: text, createdAt: date))
        while next.messages.count > Self.maxMessages || next.messages.reduce(0, { $0 + $1.text.utf8.count }) > Self.maxConversationBytes {
            next.messages.removeFirst(); next.discardedMessages = try increment(next.discardedMessages)
        }
        try next.record(.message, at: date)
        try next.enforceEncodedLimit(); self = next
    }

    /// Staging grants no revision and stores no future operation. The app calls start only on actual audio start
    /// or an explicit manual caption advance, including a beat with zero cues.
    public mutating func stageModelEvent(key: ModelEventKey, cueCount: Int) throws -> UUID {
        try validateKey(key)
        guard admission == nil, key.turnID == activeTurnID else { throw HistoryError.invalidAdmission }
        guard key.baseRevision == revision, key.revision == (try nextRevision()) else { throw HistoryError.staleRevision }
        guard (0...ExplanationLimits.cuesPerEvent).contains(cueCount) else { throw HistoryError.limitExceeded }
        let id = UUID()
        admission = Admission(id: id, key: key, cueCount: cueCount, before: canonicalScene)
        return id
    }

    public mutating func startModelEvent(admissionID: UUID, key: ModelEventKey, at date: Date,
                                        registry: ExplanationRegistry = .empty) throws {
        var active = try admitted(admissionID, key: key)
        guard !active.started else { throw HistoryError.alreadyStarted }
        guard revision == key.baseRevision else { throw HistoryError.staleRevision }
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(canonicalScene, atRevision: key.revision, registry: registry)
        active.started = true; next.admission = active
        try next.record(.modelStart, at: date, event: key)
        try next.enforceEncodedLimit(); self = next
    }

    public mutating func admitCue(admissionID: UUID, key: ModelEventKey, cueIndex: Int,
                                  scene: ExplanationScene, at date: Date,
                                  registry: ExplanationRegistry = .empty) throws {
        var active = try admitted(admissionID, key: key)
        guard active.started else { throw HistoryError.notStarted }
        guard cueIndex == active.nextCue, cueIndex < active.cueCount else { throw HistoryError.cueOutOfOrder }
        guard revision == key.revision, scene.revision == key.revision else { throw HistoryError.staleRevision }
        try validateScene(scene, registry: registry)
        var next = self
        if scene != canonicalScene, !active.pushedUndo {
            try next.pushUndo(active.before); next.redoScenes.removeAll(); active.pushedUndo = true
        }
        next.canonicalScene = scene; active.nextCue += 1; next.admission = active
        try next.record(.cue, at: date, event: key, cueIndex: cueIndex)
        try next.enforceEncodedLimit(); self = next
    }

    public mutating func finishModelEvent(admissionID: UUID, key: ModelEventKey) throws {
        let active = try admitted(admissionID, key: key)
        guard active.started else { throw HistoryError.notStarted }
        guard active.nextCue == active.cueCount else { throw HistoryError.cueOutOfOrder }
        admission = nil
    }

    public mutating func cancelModelEvent(admissionID: UUID, key: ModelEventKey) throws {
        _ = try admitted(admissionID, key: key)
        admission = nil
    }

    public mutating func applyUserScene(_ scene: ExplanationScene, baseRevision: Int, at date: Date,
                                       registry: ExplanationRegistry = .empty) throws {
        guard baseRevision == revision else { throw HistoryError.staleRevision }
        try validateScene(scene, registry: registry)
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(scene, atRevision: nextRevision(), registry: registry)
        try next.pushUndo(canonicalScene); next.redoScenes.removeAll(); next.admission = nil
        try next.record(.edit, at: date)
        try next.enforceEncodedLimit(); self = next
    }

    /// Commits the actually sampled interruption pose, never the queued animation's future target.
    /// Preserve existing undo/redo: pushing the old semantic target here would let Undo revive a pose
    /// the user never saw. The controller samples its own presentation clock before calling this.
    public mutating func freezePlayback(scene: ExplanationScene, baseRevision: Int, at date: Date,
                                        registry: ExplanationRegistry = .empty) throws {
        guard baseRevision == revision, scene.revision == revision else { throw HistoryError.staleRevision }
        try validateScene(scene, registry: registry)
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(scene, atRevision: nextRevision(), registry: registry)
        next.admission = nil
        try next.record(.interruption, at: date)
        try next.enforceEncodedLimit(); self = next
    }

    public mutating func undo(at date: Date, registry: ExplanationRegistry = .empty) throws {
        guard let scene = undoScenes.last else { throw HistoryError.nothingToUndo }
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(scene, atRevision: nextRevision(), registry: registry)
        next.undoScenes.removeLast(); next.redoScenes.append(canonicalScene); next.admission = nil
        if next.redoScenes.count > Self.maxUndoStates { next.redoScenes.removeFirst() }
        try next.record(.undo, at: date)
        try next.enforceEncodedLimit(); self = next
    }

    public mutating func redo(at date: Date, registry: ExplanationRegistry = .empty) throws {
        guard let scene = redoScenes.last else { throw HistoryError.nothingToRedo }
        var next = self
        next.canonicalScene = try ExplanationSceneReducer.restoring(scene, atRevision: nextRevision(), registry: registry)
        next.redoScenes.removeLast(); try next.pushUndo(canonicalScene); next.admission = nil
        try next.record(.redo, at: date)
        try next.enforceEncodedLimit(); self = next
    }

    /// Returns an immutable historical observation. It neither edits the scene nor grants capture/asset authority.
    public func replay(checkpointID: UUID, registry: ExplanationRegistry = .empty) throws -> Checkpoint {
        guard let checkpoint = checkpoints.first(where: { $0.id == checkpointID }) else { throw HistoryError.checkpointMissing }
        try validateScene(checkpoint.scene, registry: registry)
        return checkpoint
    }

    private func admitted(_ id: UUID, key: ModelEventKey) throws -> Admission {
        guard let admission, admission.id == id, admission.key == key,
              activeTurnID == key.turnID else { throw HistoryError.invalidAdmission }
        return admission
    }
    private func nextRevision() throws -> Int {
        guard revision >= 0, revision < ExplanationLimits.revision else { throw HistoryError.revisionExhausted }
        return revision + 1
    }
    private func increment(_ value: Int) throws -> Int {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw HistoryError.limitExceeded }
        return next
    }
    private mutating func pushUndo(_ scene: ExplanationScene) throws {
        undoScenes.append(scene)
        if undoScenes.count > Self.maxUndoStates {
            undoScenes.removeFirst(); discardedUndoStates = try increment(discardedUndoStates)
        }
    }
    private mutating func record(_ kind: Checkpoint.Kind, at date: Date,
                                 event: ModelEventKey? = nil, cueIndex: Int? = nil) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite, date >= updatedAt else { throw HistoryError.invalidDate }
        let ordinal = try increment(checkpoints.last?.ordinal ?? -1)
        checkpoints.append(.init(id: UUID(), ordinal: ordinal, kind: kind, createdAt: date,
                                 scene: canonicalScene, event: event, cueIndex: cueIndex))
        if checkpoints.count > Self.maxCheckpoints {
            checkpoints.removeFirst(); discardedCheckpoints = try increment(discardedCheckpoints)
        }
        updatedAt = date
    }
    private func validateKey(_ key: ModelEventKey) throws {
        guard key.sessionID == canonicalScene.sessionID, key.sceneID == canonicalScene.sceneID else { throw HistoryError.wrongIdentity }
        guard key.sequence >= 0, key.sequence < ExplanationLimits.events,
              key.baseRevision >= 0, key.baseRevision < ExplanationLimits.revision,
              key.revision == key.baseRevision + 1,
              !key.beatID.isEmpty, key.beatID.utf8.count <= 128,
              !key.beatID.contains(where: { $0.isNewline }), !key.beatID.utf8.contains(0) else { throw HistoryError.invalidHistory }
    }
    private func validateScene(_ scene: ExplanationScene, registry: ExplanationRegistry) throws {
        guard scene.sessionID == canonicalScene.sessionID, scene.sceneID == canonicalScene.sceneID else { throw HistoryError.wrongIdentity }
        try ExplanationSceneReducer.validate(scene, registry: registry)
        guard try Self.encoder().encode(scene).count <= Self.maxSceneBytes else { throw HistoryError.limitExceeded }
    }
    private func validateStructure() throws {
        guard version == Self.formatVersion else { throw HistoryError.unsupportedVersion(version) }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt <= updatedAt, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 512, !title.utf8.contains(0),
              (0...ExplanationLimits.revision).contains(revision),
              messages.count <= Self.maxMessages, messages.reduce(0, { $0 + $1.text.utf8.count }) <= Self.maxConversationBytes,
              (1...Self.maxCheckpoints).contains(checkpoints.count),
              undoScenes.count <= Self.maxUndoStates, redoScenes.count <= Self.maxUndoStates,
              discardedMessages >= 0, discardedCheckpoints >= 0, discardedUndoStates >= 0,
              checkpoints.last?.scene == canonicalScene, checkpoints.last?.createdAt == updatedAt,
              checkpoints.first?.ordinal == discardedCheckpoints,
              Set(messages.map(\.id)).count == messages.count,
              Set(checkpoints.map(\.id)).count == checkpoints.count else { throw HistoryError.invalidHistory }
        var previousDate = createdAt
        for message in messages {
            guard message.createdAt.timeIntervalSinceReferenceDate.isFinite, message.createdAt >= previousDate,
                  message.createdAt <= updatedAt, !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  message.text.utf8.count <= 16_384, !message.text.utf8.contains(0) else { throw HistoryError.invalidHistory }
            previousDate = message.createdAt
        }
        var previousOrdinal = checkpoints[0].ordinal - 1
        var previousRevision: Int?
        var priorEvent: ModelEventKey?
        var priorCue: Int?
        // A retained suffix may begin after its start checkpoint was discarded.
        var permitsRetainedEvent = discardedCheckpoints > 0
        previousDate = createdAt
        for checkpoint in checkpoints {
            guard checkpoint.ordinal >= 0, previousOrdinal < Int.max, checkpoint.ordinal == previousOrdinal + 1,
                  checkpoint.scene.revision >= 0, checkpoint.scene.revision <= revision,
                  checkpoint.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  checkpoint.createdAt >= previousDate, checkpoint.createdAt <= updatedAt,
                  checkpoint.scene.sessionID == canonicalScene.sessionID,
                  checkpoint.scene.sceneID == canonicalScene.sceneID else { throw HistoryError.invalidHistory }
            switch checkpoint.kind {
            case .modelStart, .cue:
                guard let event = checkpoint.event else { throw HistoryError.invalidHistory }
                try validateKey(event)
                guard event.revision == checkpoint.scene.revision else { throw HistoryError.invalidHistory }
                if checkpoint.kind == .cue {
                    guard let cue = checkpoint.cueIndex, (0..<ExplanationLimits.cuesPerEvent).contains(cue) else { throw HistoryError.invalidHistory }
                    if let priorEvent {
                        guard event == priorEvent, cue == (priorCue.map { $0 + 1 } ?? 0) else { throw HistoryError.invalidHistory }
                    } else {
                        guard permitsRetainedEvent else { throw HistoryError.invalidHistory }
                    }
                    if let previousRevision { guard checkpoint.scene.revision == previousRevision else { throw HistoryError.invalidHistory } }
                    priorEvent = event; priorCue = cue; permitsRetainedEvent = false
                } else {
                    guard checkpoint.cueIndex == nil else { throw HistoryError.invalidHistory }
                    if let previousRevision { guard event.baseRevision == previousRevision else { throw HistoryError.invalidHistory } }
                    priorEvent = event; priorCue = nil; permitsRetainedEvent = false
                }
            default:
                guard checkpoint.event == nil, checkpoint.cueIndex == nil else { throw HistoryError.invalidHistory }
                if checkpoint.kind == .message {
                    if let previousRevision { guard checkpoint.scene.revision == previousRevision else { throw HistoryError.invalidHistory } }
                } else if checkpoint.kind == .created {
                    guard checkpoint.ordinal == 0, checkpoint.createdAt == createdAt else { throw HistoryError.invalidHistory }
                    priorEvent = nil; priorCue = nil; permitsRetainedEvent = false
                } else {
                    if let previousRevision {
                        guard previousRevision < ExplanationLimits.revision,
                              checkpoint.scene.revision == previousRevision + 1 else { throw HistoryError.invalidHistory }
                    }
                    priorEvent = nil; priorCue = nil; permitsRetainedEvent = false
                }
            }
            previousOrdinal = checkpoint.ordinal; previousRevision = checkpoint.scene.revision; previousDate = checkpoint.createdAt
        }
        for scene in undoScenes + redoScenes {
            guard scene.revision <= revision, scene.sessionID == canonicalScene.sessionID,
                  scene.sceneID == canonicalScene.sceneID else { throw HistoryError.invalidHistory }
        }
    }
    private static func encoder() -> JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder }
    private func enforceEncodedLimit() throws {
        guard try Self.encoder().encode(self).count <= Self.maxRecordBytes else { throw HistoryError.limitExceeded }
    }
}

/// An app-owned local capability. Files are UUID leaves under one injected root, never model paths.
/// The actor serializes callers; a nonblocking advisory lock also refuses competing cooperating stores.
/// Each commit is atomic. Directory-sync/retention failures AFTER commit are explicit receipt warnings.
public actor ExplanationHistoryStore {
    public struct Policy: Equatable, Sendable {
        public var maxRecords: Int
        public var maxTotalBytes: Int
        public var maxAge: TimeInterval
        public var maxDirectoryEntries: Int
        public init(maxRecords: Int = 50, maxTotalBytes: Int = 64 * 1024 * 1024,
                    maxAge: TimeInterval = 30 * 24 * 60 * 60, maxDirectoryEntries: Int = 512) {
            self.maxRecords = maxRecords; self.maxTotalBytes = maxTotalBytes
            self.maxAge = maxAge; self.maxDirectoryEntries = maxDirectoryEntries
        }
    }
    public enum StoreError: Error, Equatable, LocalizedError, Sendable {
        case invalidRoot, invalidPolicy, unsafePath, unsafeFile, insecureFolder, notFound, tooLarge
        case busy, conflict, directoryLimit, corrupt, filesystem(operation: String, code: Int32)
        case cleanupFailed(code: Int32)
        public var errorDescription: String? {
            switch self {
            case .invalidRoot: "Choose a clean, absolute local explanation-history folder."
            case .invalidPolicy: "The explanation retention limits are invalid."
            case .unsafePath: "The explanation folder contains a symbolic link or a non-folder."
            case .unsafeFile: "The explanation record is not a private, singly linked regular file."
            case .insecureFolder: "The explanation folder must be owned by this user and private."
            case .notFound: "The saved explanation is unavailable."
            case .tooLarge: "The saved explanation exceeds the local size limit."
            case .busy: "Another explanation-history operation is in progress. Try again."
            case .conflict: "The saved explanation changed. Reopen it before saving again."
            case .directoryLimit: "The explanation folder has too many entries to inspect safely."
            case .corrupt: "The saved explanation is unreadable. It was left in place."
            case .filesystem(let operation, let code): "Explanation history could not \(operation) (errno \(code))."
            case .cleanupFailed(let code): "The explanation was not committed and its temporary file could not be removed (errno \(code))."
            }
        }
    }
    public enum FaultStage: Equatable, Sendable { case afterTempCreate, afterTempWrite, beforeCommit, beforeDelete, beforeDirectorySync }
    public enum SaveExpectation: Sendable { case absent, checkpoint(UUID) }
    public struct Summary: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let sessionID: UUID
        public let title: String
        public let revision: Int
        public let createdAt: Date
        public let updatedAt: Date
        public let bytes: Int
        public let checkpointID: UUID
    }
    public struct Failure: Equatable, Sendable {
        public let id: UUID?
        public let message: String
    }
    public struct Listing: Equatable, Sendable {
        public var records: [Summary]
        public var failures: [Failure]
        public var ignoredEntries: Int
    }
    public struct RetentionReport: Equatable, Sendable {
        public var deletedIDs: [UUID]
        public var failures: [Failure]
        public var remainingRecords: Int
        public var remainingBytes: Int
    }
    public struct SaveReceipt: Equatable, Sendable {
        public let id: UUID
        public let checkpointID: UUID
        public let directorySynced: Bool
        public let retention: RetentionReport
        public let warnings: [Failure]
    }

    public let root: URL
    public let policy: Policy
    private let parts: [String]
    private let faultHook: (@Sendable (FaultStage) throws -> Void)?
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    public init(root: URL, policy: Policy = .init(),
                faultHook: (@Sendable (FaultStage) throws -> Void)? = nil) throws {
        guard root.isFileURL, let parts = Self.components(root.path) else { throw StoreError.invalidRoot }
        guard (1...100).contains(policy.maxRecords), (1...128 * 1024 * 1024).contains(policy.maxTotalBytes),
              policy.maxAge.isFinite, policy.maxAge > 0, policy.maxAge <= 365 * 24 * 60 * 60,
              (policy.maxRecords + 1...2048).contains(policy.maxDirectoryEntries) else { throw StoreError.invalidPolicy }
        self.root = root; self.parts = parts; self.policy = policy; self.faultHook = faultHook
    }

    public nonisolated static func productionRootURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Zeus/Explanations", isDirectory: true)
    }
    public nonisolated static func fileName(_ id: UUID) -> String { "explanation-\(id.uuidString.lowercased()).json" }

    public func load(id: UUID, registry: ExplanationRegistry = .empty) throws -> ExplanationHistory {
        try withFolder(create: false) { folder in
            guard let data = try read(id: id, folder: folder) else { throw StoreError.notFound }
            return try decode(data, id: id, registry: registry)
        }
    }

    public func list(registry: ExplanationRegistry = .empty) throws -> Listing {
        do { return try withFolder(create: false) { try scan(folder: $0, registry: registry) } }
        catch StoreError.notFound { return Listing(records: [], failures: [], ignoredEntries: 0) }
    }

    @discardableResult
    public func save(_ history: ExplanationHistory, expecting: SaveExpectation = .absent,
                     registry: ExplanationRegistry = .empty, now: Date = Date()) throws -> SaveReceipt {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw ExplanationHistory.HistoryError.invalidDate }
        let data = try history.encoded(registry: registry)
        guard data.count <= policy.maxTotalBytes else { throw StoreError.tooLarge }
        return try withFolder(create: true) { folder in
            // Preflight the bounded directory before any record mutation.
            let entries = try entryNames(folder)
            let existing = try read(id: history.id, folder: folder)
            if existing == nil, entries.count >= policy.maxDirectoryEntries { throw StoreError.directoryLimit }
            switch (expecting, existing) {
            case (.absent, nil): break
            case (.checkpoint(let checkpoint), .some(let bytes)):
                let prior = try decode(bytes, id: history.id, registry: registry)
                guard prior.lastCheckpointID == checkpoint,
                      prior.canonicalScene.sessionID == history.canonicalScene.sessionID,
                      prior.canonicalScene.sceneID == history.canonicalScene.sceneID,
                      prior.revision <= history.revision,
                      prior.checkpoints.last!.ordinal <= history.checkpoints.last!.ordinal,
                      prior.lastCheckpointID != history.lastCheckpointID || bytes == data else { throw StoreError.conflict }
            default: throw StoreError.conflict
            }
            try commit(data, id: history.id, folder: folder)
            var warnings: [Failure] = []
            let directorySynced: Bool
            do {
                try faultHook?(.beforeDirectorySync)
                guard fsync(folder) == 0 else { throw Self.system("sync the history folder") }
                directorySynced = true
            } catch {
                directorySynced = false
                warnings.append(.init(id: history.id, message: "The explanation was saved, but folder durability could not be confirmed. \(error.localizedDescription)"))
            }
            let retention: RetentionReport
            do { retention = try retain(folder: folder, protecting: history.id, registry: registry, now: now) }
            catch {
                retention = .init(deletedIDs: [], failures: [.init(id: nil, message: error.localizedDescription)],
                                  remainingRecords: -1, remainingBytes: -1)
            }
            return SaveReceipt(id: history.id, checkpointID: history.lastCheckpointID,
                               directorySynced: directorySynced, retention: retention, warnings: warnings)
        }
    }

    /// Explicit user deletion also permits a corrupt/oversize record, but never follows links or removes folders.
    public func delete(id: UUID) throws {
        try withFolder(create: false) { folder in
            try deleteFile(id: id, folder: folder)
            guard fsync(folder) == 0 else { throw Self.system("confirm deletion durability") }
        }
    }

    public func enforceRetention(registry: ExplanationRegistry = .empty, now: Date = Date()) throws -> RetentionReport {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw ExplanationHistory.HistoryError.invalidDate }
        do { return try withFolder(create: false) { try retain(folder: $0, protecting: nil, registry: registry, now: now) } }
        catch StoreError.notFound { return .init(deletedIDs: [], failures: [], remainingRecords: 0, remainingBytes: 0) }
    }

    private func decode(_ data: Data, id: UUID, registry: ExplanationRegistry) throws -> ExplanationHistory {
        let history = try ExplanationHistory.decoded(data, registry: registry)
        guard history.id == id else { throw StoreError.corrupt }
        return history
    }

    private func scan(folder: Int32, registry: ExplanationRegistry) throws -> Listing {
        var listing = Listing(records: [], failures: [], ignoredEntries: 0)
        for name in try entryNames(folder) {
            guard let id = Self.recordID(name) else { listing.ignoredEntries += 1; continue }
            do {
                guard let data = try read(id: id, folder: folder) else { throw StoreError.notFound }
                let history = try decode(data, id: id, registry: registry)
                listing.records.append(.init(id: id, sessionID: history.canonicalScene.sessionID,
                                             title: history.title, revision: history.revision,
                                             createdAt: history.createdAt, updatedAt: history.updatedAt,
                                             bytes: data.count, checkpointID: history.lastCheckpointID))
            } catch { listing.failures.append(.init(id: id, message: error.localizedDescription)) }
        }
        listing.records.sort {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id.uuidString < $1.id.uuidString
        }
        return listing
    }

    private func retain(folder: Int32, protecting: UUID?, registry: ExplanationRegistry, now: Date) throws -> RetentionReport {
        let listing = try scan(folder: folder, registry: registry)
        var report = RetentionReport(deletedIDs: [], failures: listing.failures,
                                     remainingRecords: listing.records.count,
                                     remainingBytes: listing.records.reduce(0, { $0 + $1.bytes }))
        for record in listing.records.reversed() where record.id != protecting {
            let expired = now.timeIntervalSince(record.updatedAt) > policy.maxAge
            guard expired || report.remainingRecords > policy.maxRecords || report.remainingBytes > policy.maxTotalBytes else { continue }
            do {
                try deleteFile(id: record.id, folder: folder)
                report.deletedIDs.append(record.id); report.remainingRecords -= 1; report.remainingBytes -= record.bytes
            } catch { report.failures.append(.init(id: record.id, message: error.localizedDescription)) }
        }
        if !report.deletedIDs.isEmpty, fsync(folder) != 0 {
            report.failures.append(.init(id: nil, message: "History was removed, but deletion durability could not be confirmed (errno \(errno))."))
        }
        return report
    }

    private func commit(_ data: Data, id: UUID, folder: Int32) throws {
        let temporary = ".explanation-\(UUID().uuidString.lowercased()).tmp"
        let file = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw Self.system("create the temporary record") }
        var opened = true
        do {
            try faultHook?(.afterTempCreate)
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { throw StoreError.corrupt }
                var offset = 0
                while offset < buffer.count {
                    let amount = write(file, base.advanced(by: offset), buffer.count - offset)
                    if amount < 0, errno == EINTR { continue }
                    guard amount > 0 else { throw Self.system("write the temporary record") }
                    offset += amount
                }
            }
            try faultHook?(.afterTempWrite)
            guard fsync(file) == 0 else { throw Self.system("sync the temporary record") }
            let result = close(file); opened = false
            guard result == 0 else { throw Self.system("close the temporary record") }
            try faultHook?(.beforeCommit)
            guard renameat(folder, temporary, folder, Self.fileName(id)) == 0 else { throw Self.system("commit the record") }
        } catch {
            if opened { _ = close(file) }
            if unlinkat(folder, temporary, 0) != 0, errno != ENOENT { throw StoreError.cleanupFailed(code: errno) }
            throw error
        }
    }

    private func read(id: UUID, folder: Int32) throws -> Data? {
        let file = openat(folder, Self.fileName(id), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw StoreError.unsafeFile }
            throw Self.system("open the record")
        }
        defer { _ = close(file) }
        var before = stat()
        guard fstat(file, &before) == 0 else { throw Self.system("inspect the record") }
        try Self.validateFile(before)
        guard before.st_size >= 0, before.st_size <= ExplanationHistory.maxRecordBytes else { throw StoreError.tooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let amount = buffer.withUnsafeMutableBytes { raw in
                #if canImport(Darwin)
                Darwin.read(file, raw.baseAddress, raw.count)
                #else
                Glibc.read(file, raw.baseAddress, raw.count)
                #endif
            }
            if amount < 0, errno == EINTR { continue }
            guard amount >= 0 else { throw Self.system("read the record") }
            if amount == 0 { break }
            guard data.count <= ExplanationHistory.maxRecordBytes - amount else { throw StoreError.tooLarge }
            data.append(contentsOf: buffer.prefix(amount))
        }
        var after = stat()
        guard fstat(file, &after) == 0 else { throw Self.system("recheck the record") }
        try Self.validateFile(after)
        guard before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, data.count == after.st_size else { throw StoreError.conflict }
        #if canImport(Darwin)
        guard before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw StoreError.conflict }
        #else
        guard before.st_mtim.tv_sec == after.st_mtim.tv_sec, before.st_mtim.tv_nsec == after.st_mtim.tv_nsec,
              before.st_ctim.tv_sec == after.st_ctim.tv_sec, before.st_ctim.tv_nsec == after.st_ctim.tv_nsec else { throw StoreError.conflict }
        #endif
        return data
    }

    private func deleteFile(id: UUID, folder: Int32) throws {
        var info = stat()
        guard fstatat(folder, Self.fileName(id), &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { throw StoreError.notFound }
            throw Self.system("inspect the record for deletion")
        }
        try Self.validateFile(info)
        try faultHook?(.beforeDelete)
        guard unlinkat(folder, Self.fileName(id), 0) == 0 else { throw Self.system("delete the record") }
    }

    private static func validateFile(_ info: stat) throws {
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw StoreError.unsafeFile }
    }

    private func withFolder<T>(create: Bool, _ body: (Int32) throws -> T) throws -> T {
        let folder = try openFolder(create: create)
        defer { _ = close(folder) }
        let lock = openat(folder, ".history.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, mode_t(0o600))
        guard lock >= 0 else { throw Self.system("open the history lock") }
        defer { _ = close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0 else { throw Self.system("inspect the history lock") }
        try Self.validateFile(info)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw StoreError.busy }
            throw Self.system("lock the history")
        }
        defer { _ = flock(lock, LOCK_UN) }
        return try body(folder)
    }

    private func openFolder(create: Bool) throws -> Int32 {
        var folder = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folder >= 0 else { throw Self.system("open the filesystem root") }
        do {
            for component in parts {
                if create, mkdirat(folder, component, mode_t(0o700)) != 0, errno != EEXIST { throw Self.system("create the history folder") }
                let next = openat(folder, component, Self.directoryFlags)
                guard next >= 0 else {
                    if errno == ENOENT { throw StoreError.notFound }
                    if errno == ELOOP || errno == ENOTDIR { throw StoreError.unsafePath }
                    throw Self.system("open the history folder")
                }
                _ = close(folder); folder = next
            }
            var info = stat()
            guard fstat(folder, &info) == 0 else { throw Self.system("inspect the history folder") }
            guard info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw StoreError.insecureFolder }
            return folder
        } catch { _ = close(folder); throw error }
    }

    private func entryNames(_ folder: Int32) throws -> [String] {
        // Opening '.' creates an independent directory offset; dup alone would share readdir's offset.
        let scanFD = openat(folder, ".", Self.directoryFlags)
        guard scanFD >= 0 else { throw Self.system("open the history listing") }
        guard let directory = fdopendir(scanFD) else { _ = close(scanFD); throw Self.system("list history") }
        defer { _ = closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw Self.system("read the history listing") }
                return names
            }
            var bytes = entry.pointee.d_name
            let size = MemoryLayout.size(ofValue: bytes)
            let name = withUnsafePointer(to: &bytes) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: size) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard names.count < policy.maxDirectoryEntries else { throw StoreError.directoryLimit }
            names.append(name)
        }
    }
    private static func recordID(_ name: String) -> UUID? {
        guard name.hasPrefix("explanation-"), name.hasSuffix(".json") else { return nil }
        let value = String(name.dropFirst("explanation-".count).dropLast(".json".count))
        guard let id = UUID(uuidString: value), fileName(id) == name else { return nil }
        return id
    }
    private static func components(_ path: String) -> [String]? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        parts.removeFirst(); if parts.last == "" { parts.removeLast() }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }
    private static func system(_ operation: String) -> StoreError { .filesystem(operation: operation, code: errno) }
}
