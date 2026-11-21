import Foundation

/// One explain turn. A clean Right Option hold, held for `VoiceKey.secondKeyConfirm`, raises the overlay.
/// Release processes the transcript. A tap, another key, a click, or Esc processes nothing.
public struct ExplainTurn: Equatable {
    public static var confirmSeconds: TimeInterval { VoiceKey.secondKeyConfirm }

    public private(set) var phase: ExplainPhase = .idle
    public private(set) var overlay = ExplainOverlay()
    public private(set) var processedTranscripts: [String] = []
    public private(set) var processedOnRelease = false
    public private(set) var waitingForSecondPrompt = false
    public private(set) var openTurns = 0
    public private(set) var openedApps: [String] = []
    public private(set) var closedApps: [String] = []
    public private(set) var approval: ExplainApproval = .none
    public private(set) var speech = ""
    public private(set) var announcements: [String] = []
    public private(set) var talkTurns = 0
    public private(set) var talkSends = 0
    public private(set) var dictationHolds = 0
    public private(set) var dictationSends = 0
    public private(set) var didClick = false
    public private(set) var clocks = ExplainClocks()
    public private(set) var openedWindows = 0
    public private(set) var visibleStepNames: [String] = []

    private var downAt: TimeInterval?
    private var confirmed = false
    private var blocked = false
    private var cancelled = false
    private var listening = false
    private var walkSteps: [ExplainControl] = []
    private var walkIndex: Int?

    public init() {}

    public mutating func handle(_ event: ExplainEvent, screen: ExplainScreen, parse: (String) -> ExplainCommand) {
        switch event {
        case .rightOptionDown(let at):
            rightOptionDown(at: at)
        case .confirm(let at):
            confirm(at: at, screen: screen)
        case .rightOptionUp(let at, let transcript):
            rightOptionUp(at: at, transcript: transcript, screen: screen, parse: parse)
        case .otherKeyDown, .click:
            guard downAt != nil || listening || phase == .holding || phase == .loading else { return }
            blocked = true
            listening = false
            confirmed = false
            tearDown()
            phase = .idle
        case .escape, .voiceOverCancel:
            cancel()
        case .controlOptionDown:
            talkTurns += 1
        case .controlOptionUp:
            talkSends += 1
        case .rightCommandDown:
            break
        case .rightCommandUp(let held):
            guard held >= Self.confirmSeconds else { return }
            dictationHolds += 1
            dictationSends += 1
        case .engineFailed(let message):
            phase = .error(message)
            listening = false
            announcements.append(message)
            tearDown()
        case .stepFinished:
            advanceWalk()
        case .approvalAllowed:
            allowApproval()
        case .approvalDenied:
            didClick = false
            approval = .none
        case .phrase(let id, let at):
            callOut(id: id, at: at, screen: screen)
        case .firstAudio(let at):
            clocks.firstAudioAt = at
        }
    }

    private mutating func rightOptionDown(at: TimeInterval) {
        if walkIndex != nil, !listening {
            downAt = at
            confirmed = false
            blocked = false
            cancelled = false
            return
        }
        if phase == .holding || phase == .loading { return }
        if case .error = phase { phase = .recovery }
        downAt = at
        confirmed = false
        blocked = false
        cancelled = false
        listening = false
        raiseOverlay(captured: false)
    }

    private mutating func confirm(at: TimeInterval, screen: ExplainScreen) {
        guard let downAt, !confirmed, !blocked, !cancelled else { return }
        guard at - downAt >= Self.confirmSeconds else { return }
        if walkIndex != nil { return }
        confirmed = true
        if !screen.engineReady {
            phase = .loading
            overlay.capturedRequest = false
            raiseOverlay(captured: false)
            return
        }
        phase = .holding
        listening = true
        openTurns += 1
        announcements.append("Holding")
        raiseOverlay(captured: true)
    }

    private mutating func rightOptionUp(at: TimeInterval, transcript: String, screen: ExplainScreen, parse: (String) -> ExplainCommand) {
        let wasConfirmed = confirmed
        let wasWalk = walkIndex != nil
        downAt = nil
        confirmed = false
        if wasWalk, !wasConfirmed, !listening {
            advanceWalk()
            return
        }
        guard listening, !blocked, !cancelled else {
            listening = false
            tearDown()
            phase = .idle
            return
        }
        listening = false
        processedOnRelease = true
        processedTranscripts.append(transcript)
        waitingForSecondPrompt = false
        clocks.releaseAt = at
        clocks.actionChosenAt = at
        phase = .processing
        announcements.append("Released")
        apply(parse(transcript), screen: screen, at: at)
    }

    private mutating func apply(_ command: ExplainCommand, screen: ExplainScreen, at: TimeInterval) {
        switch command {
        case .none:
            tearDown()
            phase = .idle
        case .openApp(let name):
            openedApps.append(name)
            clocks.actionStartedAt = at
            speech = "Opened \(name)."
            raiseOverlay(captured: true)
        case .quitApp(let name):
            if screen.unsavedApps.contains(name) {
                approval = .close(name)
                clocks.approvalShownAt = at
                speech = "\(name) has unsaved work."
            } else {
                closedApps.append(name)
                clocks.actionStartedAt = at
                speech = "Closed \(name)."
            }
            raiseOverlay(captured: true)
        case .explain:
            speech = "Here are the relevant controls."
            overlay.marks = marks(for: screen.controls.filter(\.relevant))
            clocks.actionStartedAt = at
            raiseOverlay(captured: true)
        case .describe:
            if screen.controls.isEmpty {
                speech = "There is nothing on screen to mark."
                overlay.marks = []
            } else {
                speech = screen.controls.map(\.name).joined(separator: ", ")
                overlay.marks = marks(for: screen.controls)
            }
            clocks.actionStartedAt = at
            raiseOverlay(captured: true)
        case .point(let name):
            point(at: name, screen: screen, at: at)
        case .walk:
            beginWalk(screen: screen)
        case .clickForPerson(let name):
            approval = .click(name)
            clocks.approvalShownAt = at
            didClick = false
            if let control = screen.controls.first(where: { $0.name == name }) {
                overlay.pointer = ExplainPointerCue(frame: control.frame, motion: motion(screen), highlighted: true)
            }
            speech = "Waiting for approval before clicking \(name)."
            raiseOverlay(captured: true)
        }
    }

    private mutating func point(at name: String, screen: ExplainScreen, at: TimeInterval) {
        clocks.actionStartedAt = at
        guard let control = screen.controls.first(where: { $0.name == name }) else {
            overlay.pointer = ExplainPointerCue(frame: nil, motion: motion(screen), highlighted: false)
            speech = "I cannot see that control."
            didClick = false
            raiseOverlay(captured: true)
            return
        }
        overlay.pointer = ExplainPointerCue(frame: control.frame, motion: motion(screen), highlighted: true)
        speech = control.name
        didClick = false
        clocks.pointCommittedAt = at
        clocks.highlightAt = at
        raiseOverlay(captured: true)
    }

    private mutating func beginWalk(screen: ExplainScreen) {
        guard !screen.controls.isEmpty else {
            walkSteps = []
            walkIndex = nil
            visibleStepNames = []
            tearDown()
            phase = .idle
            return
        }
        walkSteps = screen.controls
        walkIndex = 0
        showWalkStep()
    }

    private mutating func showWalkStep() {
        guard let walkIndex, walkSteps.indices.contains(walkIndex) else { return }
        let control = walkSteps[walkIndex]
        visibleStepNames = [control.name]
        overlay.marks = marks(for: [control])
        overlay.pointer = ExplainPointerCue(frame: control.frame, motion: .fly, highlighted: true)
        phase = .processing
        raiseOverlay(captured: true)
    }

    private mutating func advanceWalk() {
        guard var index = walkIndex else { return }
        index += 1
        if index >= walkSteps.count {
            endWalk()
        } else {
            walkIndex = index
            showWalkStep()
        }
    }

    private mutating func endWalk() {
        walkIndex = nil
        walkSteps = []
        visibleStepNames = []
        tearDown()
        phase = .idle
    }

    private mutating func callOut(id: String, at: TimeInterval, screen: ExplainScreen) {
        guard let index = overlay.marks.firstIndex(where: { $0.id == id }) else { return }
        for markIndex in overlay.marks.indices {
            overlay.marks[markIndex].calledOut = markIndex == index
        }
        let mark = overlay.marks[index]
        overlay.pointer = ExplainPointerCue(frame: mark.frame, motion: motion(screen), highlighted: true)
        clocks.pointCommittedAt = at
        clocks.highlightAt = at
        announcements.append("Mark \(mark.number), \(mark.name)")
    }

    private mutating func allowApproval() {
        switch approval {
        case .close(let name):
            closedApps.append(name)
            clocks.actionStartedAt = clocks.approvalShownAt
            approval = .none
        case .click:
            didClick = true
            clocks.actionStartedAt = clocks.approvalShownAt
            approval = .none
        case .none:
            break
        }
    }

    private mutating func cancel() {
        cancelled = true
        listening = false
        walkIndex = nil
        walkSteps = []
        visibleStepNames = []
        announcements.append("Cancelled")
        tearDown()
        phase = .idle
    }

    private mutating func raiseOverlay(captured: Bool) {
        if overlay.windowCount == 0 { openedWindows += 1 }
        overlay.isUp = true
        overlay.ignoresMouseEvents = true
        overlay.windowCount = 1
        overlay.capturedRequest = captured
    }

    private mutating func tearDown() {
        overlay.isUp = false
        overlay.ignoresMouseEvents = false
        overlay.windowCount = 0
        overlay.capturedRequest = false
        overlay.marks = []
        overlay.pointer = nil
    }

    private func motion(_ screen: ExplainScreen) -> ExplainMotion {
        screen.reduceMotion ? .fade : .fly
    }

    private func marks(for controls: [ExplainControl]) -> [ExplainMark] {
        controls.enumerated().map { offset, control in
            ExplainMark(
                id: control.id,
                number: offset + 1,
                name: control.name,
                displayID: control.displayID,
                backingScale: control.backingScale,
                frame: control.frame,
                relevant: control.relevant,
                calledOut: false
            )
        }
    }
}
