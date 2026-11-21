import AppKit
import Foundation
import ZeusCore

/// What the talk turn asks of the on-screen drawing. The turn calls these on the main actor and never
/// reads anything back, so a fake stands in for the screen in tests.
@MainActor
protocol TalkVisualPresenting: AnyObject {
    /// A draw tag arrived for this capture. Nothing is shown yet.
    /// `token` names the turn; later calls with another token (a late callback of an earlier turn) are ignored.
    func begin(_ draw: TalkDraw, shot: ScreenShot, token: UUID)
    /// The line for this sentence index has started to play: show its marks.
    func reveal(sentence: Int, token: UUID)
    /// The last sentence has finished playing: hide the marks soon.
    func answerFinished(token: UUID)
    /// Hide everything now.
    func clear()
    /// A barge-in stops marks that are still waiting for their audio time.
    func cancelScheduledMarks()
}

/// Draws the marks of one talk answer on the display it was captured from. The marks of a sentence appear
/// when that sentence starts to play, and go a few seconds after the last one, or at once when the screen
/// layout or the frontmost app changes (the marks would then sit on the wrong thing).
@MainActor
final class TalkVisualPresenter: TalkVisualPresenting {
    struct Screen { var id: UInt32; var frame: CGRect; var scale: Double }

    static let autoHideSeconds = 4.0

    private let overlay = ExplanationOverlay()
    private let screens: @MainActor () -> [Screen]
    private let reduceMotion: @MainActor () -> Bool
    private var capture: ExplanationCaptureContext?
    private var pending: [Int: [ExplanationObject]] = [:]
    private var shown: [ExplanationObject] = []
    private var hideTask: Task<Void, Never>?
    private var token: UUID?
    private var identity: (session: UUID, scene: UUID, revision: Int)?
    private var markSchedule = SpeechMarkSchedule(marks: [])
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    var isShowing: Bool { overlay.isVisible }
    var hideIsArmed: Bool { hideTask != nil }
    /// One scene per turn: its marks keep their identity while later sentences add to it.
    var sceneIdentity: (session: UUID, scene: UUID, revision: Int)? { identity }

    init(screens: @escaping @MainActor () -> [Screen] = TalkVisualPresenter.currentScreens,
         reduceMotion: @escaping @MainActor () -> Bool = { Motion.reduced }) {
        self.screens = screens
        self.reduceMotion = reduceMotion
    }

    static func currentScreens() -> [Screen] {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
                Screen(id: $0.uint32Value, frame: screen.frame, scale: Double(screen.backingScaleFactor))
            }
        }
    }

    func begin(_ draw: TalkDraw, shot: ScreenShot, token: UUID) {
        clear()
        // The shot carries no display id: the screen whose frame it was taken from is the one to draw on.
        guard let screen = screens().first(where: { Self.sameFrame($0.frame, shot.displayFrame) }),
              let geometry = try? TalkDrawScene.geometry(shot: shot, displayID: screen.id, backingScale: screen.scale,
                                                         captureID: UUID()) else {
            VoiceLog.log("draw", "skipped: no screen matches the capture")
            return
        }
        capture = ExplanationCaptureContext(geometry: geometry, currentDisplay: geometry.display)
        self.token = token
        identity = (UUID(), UUID(), 0)
        markSchedule = SpeechMarkSchedule(marks: draw.marks.enumerated().map {
            .init(id: "td\($0.offset)", sentenceIndex: $0.element.at)
        })
        pending = TalkDrawScene.objects(draw, shot: shot, captureID: geometry.captureID)
        watchForStaleScreen()
    }

    func cancelScheduledMarks() {
        markSchedule.bargeIn()
    }

    func reveal(sentence: Int, token: UUID) {
        guard !markSchedule.isCancelled else { return }
        guard token == self.token, let capture, var identity, let marks = pending.removeValue(forKey: sentence) else { return }
        hideTask?.cancel()
        hideTask = nil
        shown += marks
        identity.revision += 1
        self.identity = identity
        let scene = ExplanationScene(sessionID: identity.session, sceneID: identity.scene, revision: identity.revision,
                                     canvasSize: capture.geometry.imageSize,
                                     captureID: capture.geometry.captureID,
                                     objects: Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { $1 }))
        if !overlay.present(scene: scene, capture: capture, reduceMotion: reduceMotion()) {
            VoiceLog.log("draw", "marks could not be drawn")
        }
    }

    func answerFinished(token: UUID) {
        guard capture != nil, token == self.token else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoHideSeconds))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func clear() {
        hideTask?.cancel()
        hideTask = nil
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers = []
        overlay.hide()
        capture = nil
        token = nil
        identity = nil
        pending = [:]
        shown = []
    }

    private func watchForStaleScreen() {
        let names: [(NotificationCenter, Notification.Name)] = [
            (.default, NSApplication.didChangeScreenParametersNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification),
        ]
        observers = names.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clear() }
            })
        }
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
