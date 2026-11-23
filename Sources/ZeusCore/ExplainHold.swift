import Foundation

/// One Right Option hold for an explain turn. The clock is the caller's synthetic stream.
/// A hold past `VoiceKey.secondKeyConfirm` raises the overlay. The release returns the
/// transcript for the existing `FastIntent.parse`. This type does not recognize speech.
public struct ExplainHold: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case holding
        case processing
        case loading
        case error
    }

    public enum Engine: Equatable, Sendable {
        case ready
        case loading
        case failed
    }

    /// `.process` is the transcript the release hands to `FastIntent.parse`.
    public enum Release: Equatable, Sendable {
        case process(String)
        case nothing
    }

    public static let confirm = VoiceKey.secondKeyConfirm

    public private(set) var phase: Phase
    public private(set) var overlayUp: Bool
    public private(set) var walkStep: Int?
    public private(set) var engine: Engine

    private var walkCount: Int
    private var armedDown: TimeInterval?
    private var confirmed: Bool
    private var spoiled: Bool
    private var otherDown: Bool

    public init(engine: Engine = .ready) {
        self.engine = engine
        phase = engine == .loading ? .loading : .idle
        overlayUp = false
        walkStep = nil
        walkCount = 0
        armedDown = nil
        confirmed = false
        spoiled = false
        otherDown = false
    }

    /// Right Option has been down since `down`. The overlay rises only after a clean confirm.
    public mutating func advance(from down: TimeInterval, to now: TimeInterval) {
        if phase == .holding || phase == .processing {
            return
        }
        if engine != .ready || otherDown {
            armedDown = down
            spoiled = true
            overlayUp = false
            return
        }
        if armedDown != down {
            armedDown = down
            confirmed = false
            spoiled = false
        }
        guard armedDown != nil, !spoiled, now - down >= Self.confirm else { return }
        confirmed = true
        phase = .holding
        overlayUp = true
    }

    public mutating func otherKeyDown() {
        otherDown = true
        spoiled = true
        if phase == .holding {
            phase = .idle
            overlayUp = false
        }
    }

    public mutating func click() {
        otherKeyDown()
    }

    public mutating func escape() {
        spoiled = true
        overlayUp = false
        walkStep = nil
        walkCount = 0
        if phase == .holding || phase == .processing {
            phase = .idle
        }
    }

    /// Control-Option stays the existing talk hold. It does not open an explain turn.
    public mutating func controlOptionHeld(from: TimeInterval, to: TimeInterval) {}

    /// Right Command stays dictation. A hold or a tap does not open an explain turn.
    public mutating func rightCommandHeld(from: TimeInterval, to: TimeInterval) {}

    public mutating func tapRightCommand() {}

    public mutating func release(at now: TimeInterval, transcript: String, steps: Int = 0) -> Release {
        let down = armedDown
        let clean = engine == .ready && confirmed && !spoiled && !otherDown && phase != .error
        armedDown = nil
        confirmed = false
        spoiled = false
        otherDown = false
        guard let down, clean, now - down >= Self.confirm else {
            if engine == .loading {
                phase = .loading
            } else if engine == .failed {
                phase = .error
            } else if phase != .processing {
                phase = .idle
            }
            if walkStep == nil {
                overlayUp = false
            }
            return .nothing
        }
        phase = .processing
        overlayUp = true
        if steps > 0 {
            walkCount = steps
            walkStep = 1
        }
        return .process(transcript)
    }

    public mutating func tap() {
        moveWalk()
    }

    public mutating func finishCurrentStep() {
        moveWalk()
    }

    public mutating func failEngine() {
        engine = .failed
        phase = .error
        overlayUp = false
        spoiled = true
    }

    public mutating func engineReady() {
        engine = .ready
        if phase == .loading || phase == .error {
            phase = .idle
            spoiled = false
            overlayUp = false
            armedDown = nil
            confirmed = false
        }
    }

    private mutating func moveWalk() {
        guard phase == .processing, let step = walkStep, walkCount > 0 else { return }
        if step >= walkCount {
            walkStep = nil
            walkCount = 0
            overlayUp = false
            phase = .idle
        } else {
            walkStep = step + 1
        }
    }
}
