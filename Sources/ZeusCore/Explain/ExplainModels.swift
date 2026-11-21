import Foundation

/// The explain turn's named states. There is no tap-to-toggle state.
public enum ExplainPhase: Equatable, Sendable {
    case idle
    case holding
    case processing
    case loading
    case error(String)
    case recovery

    public static let names = ["idle", "holding", "processing", "loading", "error", "recovery"]
}

public enum ExplainCommand: Equatable, Sendable {
    case none
    case openApp(String)
    case quitApp(String)
    case explain
    case describe
    case point(String)
    case walk
    case clickForPerson(String)
}

public enum ExplainApproval: Equatable, Sendable {
    case none
    case close(String)
    case click(String)
}

public struct ExplainFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ExplainControl: Equatable, Sendable {
    public var id: String
    public var name: String
    public var displayID: String
    public var backingScale: Double
    public var frame: ExplainFrame
    public var relevant: Bool

    public init(id: String, name: String, displayID: String, backingScale: Double, frame: ExplainFrame, relevant: Bool) {
        self.id = id
        self.name = name
        self.displayID = displayID
        self.backingScale = backingScale
        self.frame = frame
        self.relevant = relevant
    }
}

public struct ExplainScreen: Equatable, Sendable {
    public var controls: [ExplainControl]
    public var reduceMotion: Bool
    public var engineReady: Bool
    public var unsavedApps: [String]

    public init(controls: [ExplainControl], reduceMotion: Bool, engineReady: Bool, unsavedApps: [String]) {
        self.controls = controls
        self.reduceMotion = reduceMotion
        self.engineReady = engineReady
        self.unsavedApps = unsavedApps
    }
}

public enum ExplainMotion: Equatable, Sendable {
    case fly
    case fade
}

public struct ExplainMark: Equatable, Sendable {
    public var id: String
    public var number: Int
    public var name: String
    public var displayID: String
    public var backingScale: Double
    public var frame: ExplainFrame
    public var relevant: Bool
    public var calledOut: Bool
}

public struct ExplainPointerCue: Equatable, Sendable {
    public var frame: ExplainFrame?
    public var motion: ExplainMotion
    public var highlighted: Bool
}

public struct ExplainOverlay: Equatable, Sendable {
    public var isUp = false
    public var ignoresMouseEvents = false
    public var windowCount = 0
    public var capturedRequest = false
    public var marks: [ExplainMark] = []
    public var pointer: ExplainPointerCue?
}

/// Clock definitions from the explain spec. `measuredMedian` stays empty until a Mac run records one.
public struct ExplainClocks: Equatable, Sendable {
    public var releaseAt: TimeInterval?
    public var firstAudioAt: TimeInterval?
    public var pointCommittedAt: TimeInterval?
    public var highlightAt: TimeInterval?
    public var actionChosenAt: TimeInterval?
    public var actionStartedAt: TimeInterval?
    public var approvalShownAt: TimeInterval?
    public var measuredMedian: TimeInterval? { nil }

    public var firstAudioInterval: TimeInterval? {
        guard let releaseAt, let firstAudioAt else { return nil }
        return firstAudioAt - releaseAt
    }

    public var pointerInterval: TimeInterval? {
        guard let pointCommittedAt, let highlightAt else { return nil }
        return highlightAt - pointCommittedAt
    }

    public var fastActionInterval: TimeInterval? {
        guard let actionChosenAt else { return nil }
        if let actionStartedAt { return actionStartedAt - actionChosenAt }
        if let approvalShownAt { return approvalShownAt - actionChosenAt }
        return nil
    }
}

public enum ExplainEvent: Equatable, Sendable {
    case rightOptionDown(at: TimeInterval)
    case confirm(at: TimeInterval)
    case rightOptionUp(at: TimeInterval, transcript: String)
    case otherKeyDown
    case click
    case escape
    case controlOptionDown
    case controlOptionUp
    case rightCommandDown
    case rightCommandUp(held: TimeInterval)
    case engineFailed(String)
    case stepFinished
    case approvalAllowed
    case approvalDenied
    case phrase(id: String, at: TimeInterval)
    case firstAudio(at: TimeInterval)
    case voiceOverCancel
}
