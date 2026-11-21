import CoreGraphics
import Foundation

/// Which display a talk turn may capture, and whether a shot that is already ready
/// may ride with speech. Pure: no capture session.
public enum TalkCapturePolicy {
    /// Speech starts by this time even when the shot is not ready.
    public static let sttCapMs = 450
    /// A shot with this many milliseconds or fewer left before the cap is late.
    /// 399 ms is in time. 400 ms against a 450 ms cap is the first late millisecond.
    public static let lateWindowMs = 50

    public struct Display: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect

        public init(id: UInt32, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    public struct Decision: Equatable, Sendable {
        public var includeShot: Bool
        public var speechStarts: Bool
        /// True when the shot is ready inside the last `lateWindowMs` of the cap, or after the cap.
        public var lateRelativeToCap: Bool

        public init(includeShot: Bool, speechStarts: Bool, lateRelativeToCap: Bool) {
            self.includeShot = includeShot
            self.speechStarts = speechStarts
            self.lateRelativeToCap = lateRelativeToCap
        }
    }

    /// Seeing off captures nothing. Seeing on returns only the display id under the pointer.
    /// Overlapping displays keep the later one. The shared edge belongs to the display that starts there.
    public static func displayIDs(seeing: Bool, pointer: CGPoint, displays: [Display]) -> [UInt32] {
        guard seeing, let hit = displays.last(where: { $0.frame.contains(pointer) }) else { return [] }
        return [hit.id]
    }

    /// `sttFinalMs` is when the transcript final arrives. Nil means it has not arrived, so speech
    /// starts at the cap. A shot ready at or before that moment may be included, unless it is late
    /// relative to the cap. Speech starts either way.
    public static func decision(shotReadyMs: Int, sttFinalMs: Int?, capMs: Int = sttCapMs) -> Decision {
        let cap = max(capMs, 0)
        let speechAt = min(max(sttFinalMs ?? cap, 0), cap)
        let late = shotReadyMs >= cap - lateWindowMs
        let include = shotReadyMs >= 0 && shotReadyMs <= speechAt && !late
        return Decision(includeShot: include, speechStarts: true, lateRelativeToCap: late)
    }

    /// How long speech may wait for a shot. A shot that is not ready by then is dropped.
    public static var speechWaitBoundMs: Int { max(0, sttCapMs - lateWindowMs) }

    public struct WaitOutcome: Equatable, Sendable {
        public var includeShot: Bool
        public var waitedMs: Int
        public var speechStarts: Bool
        public init(includeShot: Bool, waitedMs: Int, speechStarts: Bool) {
            self.includeShot = includeShot
            self.waitedMs = waitedMs
            self.speechStarts = speechStarts
        }
    }

    /// Speech waits at most until the bound. A shot that is still out then is dropped, and speech starts.
    public static func waitOutcome(shotReadyMs: Int?, sttFinalMs: Int? = nil, capMs: Int = sttCapMs) -> WaitOutcome {
        let bound = max(0, capMs - lateWindowMs)
        guard let shotReadyMs else {
            return WaitOutcome(includeShot: false, waitedMs: bound, speechStarts: true)
        }
        let timing = decision(shotReadyMs: shotReadyMs, sttFinalMs: sttFinalMs, capMs: capMs)
        if !timing.includeShot {
            return WaitOutcome(includeShot: false, waitedMs: min(max(shotReadyMs, 0), bound), speechStarts: true)
        }
        return WaitOutcome(includeShot: true, waitedMs: max(0, shotReadyMs), speechStarts: true)
    }

    /// First result wins. The bound task returns nil, so a slow shot is dropped and the caller continues.
    public static func collect<T: Sendable>(boundMs: Int, shot: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await shot() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(max(0, boundMs)))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// One talk turn's capture. Seeing off, an unplug, or a frame from another turn drops the shot now.
public struct TalkCaptureSession: Equatable, Sendable {
    public struct Offer: Equatable, Sendable {
        public var turnID: UUID
        public var frameID: UUID
        public var displayID: UInt32
        public var shotReadyMs: Int
        public var sttFinalMs: Int?
        public init(turnID: UUID, frameID: UUID, displayID: UInt32, shotReadyMs: Int, sttFinalMs: Int?) {
            self.turnID = turnID
            self.frameID = frameID
            self.displayID = displayID
            self.shotReadyMs = shotReadyMs
            self.sttFinalMs = sttFinalMs
        }
    }

    public private(set) var turnID = UUID()
    public private(set) var seeing = false
    public private(set) var displays: [TalkCapturePolicy.Display] = []
    public private(set) var pointer = CGPoint.zero
    public private(set) var frameID: UUID?
    public private(set) var dropped = false

    public init() {}

    public mutating func begin(turnID: UUID, seeing: Bool, pointer: CGPoint, displays: [TalkCapturePolicy.Display]) {
        self.turnID = turnID
        self.seeing = seeing
        self.pointer = pointer
        self.displays = displays
        if displayIDs().isEmpty {
            dropped = true
            frameID = nil
        } else {
            dropped = false
            frameID = UUID()
        }
    }

    public func displayIDs() -> [UInt32] {
        TalkCapturePolicy.displayIDs(seeing: seeing, pointer: pointer, displays: displays)
    }

    public mutating func setSeeing(_ on: Bool) {
        seeing = on
        if displayIDs().isEmpty { dropFrame() }
    }

    public mutating func unplug(_ id: UInt32) {
        displays.removeAll { $0.id == id }
        if displayIDs().isEmpty { dropFrame() }
    }

    public mutating func sync(displays next: [TalkCapturePolicy.Display], pointer: CGPoint) {
        let armed = displayIDs().first
        self.displays = next
        self.pointer = pointer
        if let armed, !displayIDs().contains(armed) { dropFrame() }
        if displayIDs().isEmpty { dropFrame() }
    }

    public mutating func dropFrame() {
        dropped = true
        frameID = nil
    }

    public func accept(_ offer: Offer) -> TalkCapturePolicy.Decision {
        let timing = TalkCapturePolicy.decision(shotReadyMs: offer.shotReadyMs, sttFinalMs: offer.sttFinalMs)
        let live = !dropped && frameID != nil && offer.turnID == turnID && offer.frameID == frameID
            && displayIDs().contains(offer.displayID)
        return TalkCapturePolicy.Decision(
            includeShot: live && timing.includeShot,
            speechStarts: true,
            lateRelativeToCap: timing.lateRelativeToCap)
    }
}
