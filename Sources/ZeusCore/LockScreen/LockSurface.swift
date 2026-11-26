import Foundation

/// The lock-screen window's life, as one value. A controller runs the effects and reports what happened.
///
/// The session flag arrives as `LockPresenceInput`. The rows arrive as `LockLayoutScene`. This reducer
/// stores both, then opens one generation when the feature is armed, the session allows the surface,
/// the scene has something to draw, and the layout has a frame. Every other path ends with no window.
public enum LockSurface {
    public enum Phase: Equatable, Sendable {
        case off
        case unavailable(LockUnavailable)
        case stopped(LockStop)
        case ready
        case opening(Int)
        case open(Int)
        case closing(Int)
    }

    public struct State: Equatable, Sendable {
        public private(set) var phase: Phase
        public private(set) var enabled: Bool
        public private(set) var osMajor: Int
        public private(set) var osBuild: String
        public private(set) var bootID: String
        public private(set) var lastPresence: LockPresenceInput
        public private(set) var lastScene: LockLayoutScene
        public private(set) var lastDisplay: LockDisplay?
        /// Rises when a window is asked for. A close and a switch off leave it where it is.
        public private(set) var nextGeneration: Int
        public private(set) var awaitingSymbols: Bool
        /// The frame and scene handed to the open that is still in flight.
        var openingFrame: LockRect?
        var openingScene: LockLayoutScene?

        public init() {
            phase = .off
            enabled = false
            osMajor = 0
            osBuild = ""
            bootID = ""
            lastPresence = LockPresenceInput(lockSurfaceMayShow: false)
            lastScene = .empty
            lastDisplay = nil
            nextGeneration = 1
            awaitingSymbols = false
            openingFrame = nil
            openingScene = nil
        }
    }

    public enum Event: Equatable, Sendable {
        case launched(enabled: Bool, marker: LockMarker?, osMajor: Int, bootID: String, osBuild: String)
        case enabled(Bool)
        case symbolsLoaded(missing: [String])
        case presence(LockPresenceInput)
        case scene(LockLayoutScene)
        case display(LockDisplay?)
        case opened(Int, failedStep: String?)
        case closed(Int, failedStep: String?)
        case turnOnAgain
        case willQuit
    }

    public enum Effect: Equatable, Sendable {
        case loadSymbols
        case writeMarker(LockMarker)
        case clearMarker
        case open(generation: Int, frame: LockRect, scene: LockLayoutScene)
        case redraw(LockLayoutScene)
        case move(LockRect)
        case close(generation: Int)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var state = state
        let effects = state.apply(event)
        return (state, effects)
    }
}

extension LockSurface.State {
    fileprivate mutating func apply(_ event: LockSurface.Event) -> [LockSurface.Effect] {
        switch event {
        case .launched(let enabled, let marker, let osMajor, let bootID, let osBuild):
            return launch(enabled: enabled, marker: marker, osMajor: osMajor, bootID: bootID, osBuild: osBuild)
        case .enabled(let on):
            return setEnabled(on)
        case .symbolsLoaded(let missing):
            return symbolsLoaded(missing)
        case .presence(let presence):
            guard enabled else { return [] }
            lastPresence = presence
            return reconcile(sceneChanged: false, frameChanged: false)
        case .scene(let scene):
            guard enabled else { return [] }
            let before = currentFrame()
            let changed = scene != lastScene
            lastScene = scene
            return reconcile(sceneChanged: changed, frameChanged: before != currentFrame())
        case .display(let display):
            guard enabled else { return [] }
            let before = currentFrame()
            lastDisplay = display
            return reconcile(sceneChanged: false, frameChanged: before != currentFrame())
        case .opened(let generation, let failedStep):
            return opened(generation, failedStep: failedStep)
        case .closed(let generation, let failedStep):
            return closed(generation, failedStep: failedStep)
        case .turnOnAgain:
            return turnOnAgain()
        case .willQuit:
            return quit()
        }
    }

    private mutating func launch(enabled on: Bool, marker: LockMarker?, osMajor: Int, bootID: String, osBuild: String) -> [LockSurface.Effect] {
        enabled = on
        self.osMajor = osMajor
        self.bootID = bootID
        self.osBuild = osBuild
        awaitingSymbols = false
        openingFrame = nil
        openingScene = nil
        guard on else {
            phase = .off
            return []
        }
        if let marker {
            phase = stop(for: marker, bootID: bootID)
            return []
        }
        phase = .off
        return arm()
    }

    private mutating func setEnabled(_ on: Bool) -> [LockSurface.Effect] {
        guard on else {
            enabled = false
            awaitingSymbols = false
            switch phase {
            case .opening(let generation), .open(let generation):
                phase = .closing(generation)
                openingFrame = nil
                openingScene = nil
                return [.close(generation: generation)]
            default:
                phase = .off
                return []
            }
        }
        if case .stopped = phase { return [] }
        if awaitingSymbols { return [] }
        if enabled, phase != .off { return [] }
        enabled = true
        return arm()
    }

    private mutating func symbolsLoaded(_ missing: [String]) -> [LockSurface.Effect] {
        guard awaitingSymbols else { return [] }
        awaitingSymbols = false
        if missing.isEmpty {
            phase = .ready
            guard let frame = wantedFrame() else { return [] }
            return beginOpen(frame)
        }
        phase = .unavailable(.missingSymbols(missing))
        return []
    }

    private mutating func opened(_ generation: Int, failedStep: String?) -> [LockSurface.Effect] {
        guard case .opening(let current) = phase, current == generation else { return [] }
        if let failedStep, !failedStep.isEmpty {
            return fail(step: failedStep, generation: generation)
        }
        let previousScene = openingScene
        let previousFrame = openingFrame
        phase = .open(generation)
        openingScene = nil
        openingFrame = nil
        var effects: [LockSurface.Effect] = []
        if let previousScene, previousScene != lastScene {
            effects.append(.redraw(lastScene))
        }
        if let frame = currentFrame(), frame != previousFrame {
            effects.append(.move(frame))
        }
        return effects
    }

    private mutating func closed(_ generation: Int, failedStep: String?) -> [LockSurface.Effect] {
        guard case .closing(let current) = phase, current == generation else { return [] }
        if let failedStep, !failedStep.isEmpty {
            return fail(step: failedStep, generation: generation)
        }
        openingFrame = nil
        openingScene = nil
        var effects: [LockSurface.Effect] = [.clearMarker]
        guard enabled else {
            phase = .off
            return effects
        }
        phase = .ready
        if let frame = wantedFrame() {
            effects += beginOpen(frame)
        }
        return effects
    }

    private mutating func turnOnAgain() -> [LockSurface.Effect] {
        guard case .stopped = phase else { return [] }
        let armed = arm()
        if awaitingSymbols { phase = .off }
        return [.clearMarker] + armed
    }

    private mutating func quit() -> [LockSurface.Effect] {
        let generation = liveGeneration
        if generation == nil, phase == .off, !enabled { return [] }
        var effects: [LockSurface.Effect] = []
        if let generation {
            effects.append(.close(generation: generation))
        }
        effects.append(.clearMarker)
        phase = .off
        enabled = false
        awaitingSymbols = false
        openingFrame = nil
        openingScene = nil
        return effects
    }

    private mutating func reconcile(sceneChanged: Bool, frameChanged: Bool) -> [LockSurface.Effect] {
        guard let frame = wantedFrame() else { return closeIfShown() }
        switch phase {
        case .ready:
            return beginOpen(frame)
        case .open:
            var effects: [LockSurface.Effect] = []
            if sceneChanged { effects.append(.redraw(lastScene)) }
            if frameChanged { effects.append(.move(frame)) }
            return effects
        case .off, .unavailable, .stopped, .opening, .closing:
            return []
        }
    }

    private mutating func beginOpen(_ frame: LockRect) -> [LockSurface.Effect] {
        let generation = nextGeneration
        nextGeneration += 1
        phase = .opening(generation)
        openingFrame = frame
        openingScene = lastScene
        let marker = LockMarker(bootID: bootID, osBuild: osBuild, failedStep: nil)
        return [
            .writeMarker(marker),
            .open(generation: generation, frame: frame, scene: lastScene),
        ]
    }

    private mutating func closeIfShown() -> [LockSurface.Effect] {
        switch phase {
        case .opening(let generation), .open(let generation):
            phase = .closing(generation)
            openingFrame = nil
            openingScene = nil
            return [.close(generation: generation)]
        case .off, .unavailable, .stopped, .ready, .closing:
            return []
        }
    }

    private mutating func fail(step: String, generation: Int) -> [LockSurface.Effect] {
        phase = .stopped(.callFailed(step: step))
        awaitingSymbols = false
        openingFrame = nil
        openingScene = nil
        let marker = LockMarker(bootID: bootID, osBuild: osBuild, failedStep: step)
        return [.close(generation: generation), .writeMarker(marker)]
    }

    private mutating func arm() -> [LockSurface.Effect] {
        guard LockSupport.checkedMajors.contains(osMajor) else {
            phase = .unavailable(.untestedSystem(osMajor))
            awaitingSymbols = false
            return []
        }
        awaitingSymbols = true
        return [.loadSymbols]
    }

    private func wantedFrame() -> LockRect? {
        guard enabled, isReadyOrLater, lastPresence.lockSurfaceMayShow, lastScene.draws else { return nil }
        guard let display = lastDisplay else { return nil }
        return LockLayout.frame(display: display, scene: lastScene)
    }

    private var isReadyOrLater: Bool {
        switch phase {
        case .ready, .opening, .open, .closing: true
        case .off, .unavailable, .stopped: false
        }
    }

    private func currentFrame() -> LockRect? {
        guard lastScene.draws, let display = lastDisplay else { return nil }
        return LockLayout.frame(display: display, scene: lastScene)
    }

    private var liveGeneration: Int? {
        switch phase {
        case .opening(let generation), .open(let generation), .closing(let generation):
            generation
        case .off, .unavailable, .stopped, .ready:
            nil
        }
    }

    private func stop(for marker: LockMarker, bootID: String) -> LockSurface.Phase {
        if let step = marker.failedStep, !step.isEmpty {
            return .stopped(.callFailed(step: step))
        }
        if marker.bootID.isEmpty || marker.bootID == bootID {
            return .stopped(.problemLastTime)
        }
        return .stopped(.restartLastTime)
    }
}
