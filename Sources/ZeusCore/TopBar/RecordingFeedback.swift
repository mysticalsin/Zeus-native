import Foundation

/// Shared, time-driven presentation for real Recordly and Meetings work. Producers own state and
/// persistence; a clock can animate a phase but can never declare that recording or saving succeeded.
public enum RecordingFeedback {
    public enum Producer: String, Equatable, Sendable { case recordly, meetings }
    public enum Phase: String, Equatable, Sendable { case starting, finishing, writing, exporting, completed, failed }
    public enum ExportDisposition: Equatable, Sendable { case failed, partial, saved }

    /// One successful format does not make the whole requested export a success.
    public static func exportDisposition(completedFiles: Int, failedFormats: Int) -> ExportDisposition {
        guard completedFiles > 0 else { return .failed }
        return failedFormats == 0 ? .saved : .partial
    }

    public struct Snapshot: Equatable, Sendable {
        public let producer: Producer
        public let phase: Phase
        public let sessionKey: String
        public let beganAt: TimeInterval
        public let label: String

        public init(producer: Producer, phase: Phase, sessionKey: String, beganAt: TimeInterval, label: String) {
            self.producer = producer
            self.phase = phase
            self.sessionKey = sessionKey
            self.beganAt = beganAt
            self.label = label
        }
    }

    public struct Completion: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let sessionKey: String
        public let beganAt: Date
        public let label: String

        public init(sessionKey: String, beganAt: Date = Date(), label: String) {
            id = UUID()
            self.sessionKey = sessionKey
            self.beganAt = beganAt
            self.label = label
        }

        /// A restored/replaced project cannot inherit the previous project's success animation.
        public func snapshot(for producer: Producer, currentSessionKey: String, now: Date) -> Snapshot? {
            guard currentSessionKey == sessionKey,
                  now.timeIntervalSince(beganAt) >= 0,
                  now.timeIntervalSince(beganAt) < completionDuration else { return nil }
            return Snapshot(producer: producer, phase: .completed, sessionKey: sessionKey,
                            beganAt: beganAt.timeIntervalSinceReferenceDate, label: label)
        }
    }

    public struct Frame: Equatable, Sendable {
        public let visible: Bool
        public let glow: Double
        public let frost: Double
        public let reveal: Double
        public let sweep: Double
    }

    public static let completionDuration: TimeInterval = 5

    public static func frame(_ snapshot: Snapshot, at now: TimeInterval,
                             reduceMotion: Bool, reduceTransparency: Bool) -> Frame {
        // Invalid or backwards timestamps must not produce a success flourish.
        guard now.isFinite, snapshot.beganAt.isFinite, now >= snapshot.beganAt else {
            return Frame(visible: snapshot.phase != .completed, glow: 0, frost: 0, reveal: 1, sweep: 0.5)
        }
        let time = now - snapshot.beganAt
        guard time.isFinite else {
            return Frame(visible: snapshot.phase != .completed, glow: 0, frost: 0, reveal: 1, sweep: 0.5)
        }
        guard snapshot.phase != .completed || time < completionDuration else {
            return Frame(visible: false, glow: 0, frost: 0, reveal: 1, sweep: 0.5)
        }
        if reduceMotion || snapshot.phase == .failed {
            return Frame(visible: true, glow: 0.15, frost: reduceTransparency ? 0 : 0.08, reveal: 1, sweep: 0.5)
        }
        if snapshot.phase == .completed {
            let wash = ScribeGlow.glowOpacity(stage: .reveal, t: time, reduceMotion: false)
            return Frame(visible: true, glow: wash, frost: reduceTransparency ? 0 : 0.2 * wash,
                         reveal: ScribeGlow.contentOpacity(t: time, reduceMotion: false), sweep: min(1, time / 0.4))
        }
        let cycle = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        let breathe = 0.5 + 0.5 * cos(2 * Double.pi * cycle)
        return Frame(visible: true, glow: 0.3 + 0.2 * breathe,
                     frost: reduceTransparency ? 0 : 0.06 + 0.06 * breathe,
                     reveal: 1, sweep: cycle)
    }
}
