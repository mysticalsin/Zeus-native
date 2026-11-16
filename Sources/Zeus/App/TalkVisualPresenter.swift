import AppKit
import Foundation
import ZeusCore

/// What the talk turn asks of the on-screen drawing. The turn calls these on the main actor and never
/// reads anything back, so a fake stands in for the screen in tests.
@MainActor
protocol TalkVisualPresenting: AnyObject {
    /// A draw tag arrived for this capture. Nothing is shown yet.
    func begin(_ draw: TalkDraw, shot: ScreenShot)
    /// The line for this sentence index has started to play: show its marks.
    func reveal(sentence: Int)
    /// The last sentence has finished playing: hide the marks soon.
    func answerFinished()
    /// Hide everything now.
    func clear()
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
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    var isShowing: Bool { overlay.isVisible }

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

    func begin(_ draw: TalkDraw, shot: ScreenShot) {
        clear()
        // The shot carries no display id: the screen whose frame it was taken from is the one to draw on.
        guard let screen = screens().first(where: { Self.sameFrame($0.frame, shot.displayFrame) }),
              let geometry = try? TalkDrawScene.geometry(shot: shot, displayID: screen.id, backingScale: screen.scale,
                                                         captureID: UUID()) else {
            VoiceLog.log("draw", "skipped: no screen matches the capture")
            return
        }
        capture = ExplanationCaptureContext(geometry: geometry, currentDisplay: geometry.display)
        pending = TalkDrawScene.objects(draw, shot: shot, captureID: geometry.captureID)
        watchForStaleScreen()
    }

    func reveal(sentence: Int) {
        guard let capture, let marks = pending.removeValue(forKey: sentence) else { return }
        hideTask?.cancel()
        shown += marks
        let scene = ExplanationScene(sessionID: UUID(), sceneID: UUID(), canvasSize: capture.geometry.imageSize,
                                     captureID: capture.geometry.captureID,
                                     objects: Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { $1 }))
        if !overlay.present(scene: scene, capture: capture, reduceMotion: reduceMotion()) {
            VoiceLog.log("draw", "marks could not be drawn")
        }
    }

    func answerFinished() {
        guard capture != nil else { return }
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
