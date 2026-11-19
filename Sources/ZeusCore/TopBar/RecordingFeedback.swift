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
        public let reveal: Double
        public let blur: Double
        public let beamOpacity: Double
        public let elapsed: TimeInterval
    }

    public static let completionDuration: TimeInterval = 5

    public enum Motion {
        public static let swapDuration: TimeInterval = 0.15
        public static let swapDistance = 4.0
        public static let swapBlur = 2.0
        public static let revealDuration: TimeInterval = 0.35
        public static let revealBlur = 1.0
        public static let pressDuration: TimeInterval = 0.15
        public static let pressedScale = 0.95

        public static func smoothOut(_ progress: Double) -> Double {
            cubic(progress, x1: 0.22, y1: 1, x2: 0.36, y2: 1)
        }

        public static func easeInOut(_ progress: Double) -> Double {
            cubic(progress, x1: 0.42, y1: 0, x2: 0.58, y2: 1)
        }

        private static func cubic(_ progress: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
            guard progress.isFinite else { return 1 }
            if progress <= 0 { return 0 }
            if progress >= 1 { return 1 }
            func value(_ t: Double, _ a: Double, _ b: Double) -> Double {
                let inverse = 1 - t
                return 3 * inverse * inverse * t * a + 3 * inverse * t * t * b + t * t * t
            }
            var low = 0.0
            var high = 1.0
            for _ in 0..<28 {
                let middle = (low + high) / 2
                if value(middle, x1, x2) < progress { low = middle } else { high = middle }
            }
            return value((low + high) / 2, y1, y2)
        }
    }

    public struct StatusFrame: Equatable, Sendable {
        public let text: String
        public let opacity: Double
        public let offsetY: Double
        public let blur: Double

        public static func settled(_ text: String) -> StatusFrame {
            StatusFrame(text: text, opacity: 1, offsetY: 0, blur: 0)
        }
    }

    public struct BeamTimeline: Equatable, Sendable {
        private var snapshot: Snapshot
        private var origin: TimeInterval

        public init(_ snapshot: Snapshot) {
            self.snapshot = snapshot
            origin = snapshot.beganAt
        }

        public mutating func update(_ next: Snapshot) {
            if next.producer != snapshot.producer || next.sessionKey != snapshot.sessionKey || snapshot.phase == .failed {
                origin = next.beganAt
            }
            snapshot = next
        }

        public func elapsed(at now: TimeInterval) -> TimeInterval {
            let elapsed = now - origin
            return now.isFinite && origin.isFinite && elapsed.isFinite ? max(0, elapsed) : 0
        }
    }

    /// Holds only display state. Replacing a session discards its pending label immediately;
    /// retargeting an outgoing label keeps the existing deadline and selects the newest target.
    public struct StatusTransition: Equatable, Sendable {
        public private(set) var target: Snapshot
        private var outgoing: StatusFrame?
        private var beganAt: TimeInterval = 0

        public init(_ snapshot: Snapshot) { target = snapshot }

        public mutating func update(_ snapshot: Snapshot, at now: TimeInterval, reduceMotion: Bool) {
            guard snapshot.producer == target.producer, snapshot.sessionKey == target.sessionKey,
                  now.isFinite, outgoing == nil || now >= beganAt, !reduceMotion else {
                target = snapshot
                settle()
                return
            }
            guard snapshot.label != target.label else { target = snapshot; return }
            let current = frame(at: now, reduceMotion: false)
            let isExiting = outgoing != nil && now >= beganAt && now < beganAt + Motion.swapDuration
            target = snapshot
            if snapshot.label == current.text {
                settle()
            } else if !isExiting {
                outgoing = current
                beganAt = now
            }
        }

        public mutating func settle() { outgoing = nil }

        public func isAnimating(at now: TimeInterval) -> Bool {
            outgoing != nil && now.isFinite && now >= beganAt && now < beganAt + 2 * Motion.swapDuration
        }

        public func remainingDuration(at now: TimeInterval) -> TimeInterval {
            isAnimating(at: now) ? beganAt + 2 * Motion.swapDuration - now : 0
        }

        public func frame(at now: TimeInterval, reduceMotion: Bool) -> StatusFrame {
            guard !reduceMotion, let outgoing, isAnimating(at: now) else { return .settled(target.label) }
            let elapsed = now - beganAt
            if elapsed < Motion.swapDuration {
                let progress = Motion.easeInOut(elapsed / Motion.swapDuration)
                return StatusFrame(text: outgoing.text, opacity: outgoing.opacity * (1 - progress),
                                   offsetY: outgoing.offsetY + (-Motion.swapDistance - outgoing.offsetY) * progress,
                                   blur: outgoing.blur + (Motion.swapBlur - outgoing.blur) * progress)
            }
            let progress = Motion.easeInOut((elapsed - Motion.swapDuration) / Motion.swapDuration)
            return StatusFrame(text: target.label, opacity: progress,
                               offsetY: Motion.swapDistance * (1 - progress), blur: Motion.swapBlur * (1 - progress))
        }
    }

    public static func transientMotionRemaining(_ snapshot: Snapshot, status: StatusTransition,
                                                at now: TimeInterval, reduceMotion: Bool) -> TimeInterval {
        guard !reduceMotion, now.isFinite else { return 0 }
        let sameSession = snapshot.producer == status.target.producer && snapshot.sessionKey == status.target.sessionKey
        let labelRemaining = sameSession ? status.remainingDuration(at: now) : 0
        guard snapshot.phase == .completed, snapshot.beganAt.isFinite, now >= snapshot.beganAt else { return labelRemaining }
        let elapsed = now - snapshot.beganAt
        guard elapsed.isFinite else { return labelRemaining }
        return max(labelRemaining, max(0, Motion.revealDuration - elapsed))
    }

    public static func frame(_ snapshot: Snapshot, at now: TimeInterval,
                             reduceMotion: Bool, reduceTransparency: Bool) -> Frame {
        // Invalid or backwards timestamps must not produce a success flourish.
        guard now.isFinite, snapshot.beganAt.isFinite, now >= snapshot.beganAt else {
            return Frame(visible: snapshot.phase != .completed, reveal: 1, blur: 0, beamOpacity: 0, elapsed: 0)
        }
        let time = now - snapshot.beganAt
        guard time.isFinite else {
            return Frame(visible: snapshot.phase != .completed, reveal: 1, blur: 0, beamOpacity: 0, elapsed: 0)
        }
        guard snapshot.phase != .completed || time < completionDuration else {
            return Frame(visible: false, reveal: 1, blur: 0, beamOpacity: 0, elapsed: 0)
        }
        if reduceMotion || snapshot.phase == .failed {
            return Frame(visible: true, reveal: 1, blur: 0,
                         beamOpacity: reduceTransparency || snapshot.phase == .failed ? 0 : 0.6, elapsed: 0)
        }
        if snapshot.phase == .completed {
            let reveal = Motion.smoothOut(time / Motion.revealDuration)
            return Frame(visible: true, reveal: reveal, blur: Motion.revealBlur * (1 - reveal),
                         beamOpacity: reduceTransparency ? 0 : 0.6 * (1 - reveal), elapsed: time)
        }
        return Frame(visible: true, reveal: 1, blur: 0, beamOpacity: reduceTransparency ? 0 : 0.6, elapsed: time)
    }
}
