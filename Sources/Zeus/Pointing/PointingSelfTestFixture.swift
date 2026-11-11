import AppKit
import SwiftUI
import ZeusCore

/// Zeus's own fixture: one window per chosen display holding a native NSButton and a SwiftUI
/// Button at known positions with known accessibility identifiers. The self-test points at,
/// captures and checks only these windows, never another app's.
@MainActor
final class PointingFixture {
    static let nativeID = "zeus.pointing.fixture.native"
    static let swiftUIID = "zeus.pointing.fixture.swiftui"
    static let windowSize = CGSize(width: 420, height: 200)
    /// Offsets inside the window's content (AppKit, bottom-left origin).
    static let nativeFrame = CGRect(x: 40, y: 80, width: 160, height: 32)
    static let swiftUIFrame = CGRect(x: 230, y: 80, width: 160, height: 32)

    final class Counter: @unchecked Sendable { var native = 0; var swiftUI = 0 }
    let counter = Counter()

    struct Target {
        var id: String
        var display: PointingDisplay
        /// The control's frame in AppKit global points, from AppKit itself (no AX permission).
        var frame: CGRect
        var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    }

    private(set) var windows: [NSWindow] = []
    private(set) var targets: [Target] = []
    private var nativeButtons: [NSButton] = []
    private var clickTargets: [FixtureClickTarget] = []

    func open(on displays: [PointingDisplay]) {
        for display in displays {
            let origin = CGPoint(x: display.frame.minX + 120, y: display.frame.minY + display.frame.height - 360)
            let window = NSWindow(contentRect: CGRect(origin: origin, size: Self.windowSize),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Zeus pointing fixture"
            window.isReleasedWhenClosed = false
            let content = NSView(frame: CGRect(origin: .zero, size: Self.windowSize))
            let click = FixtureClickTarget(counter: counter)
            clickTargets.append(click)

            let native = NSButton(title: "Fixture Native", target: click, action: #selector(FixtureClickTarget.nativePressed))
            native.frame = Self.nativeFrame
            native.setAccessibilityIdentifier(Self.nativeID)
            content.addSubview(native)
            nativeButtons.append(native)

            let host = NSHostingView(rootView: Button("Fixture SwiftUI") { [counter] in counter.swiftUI += 1 }
                .accessibilityIdentifier(Self.swiftUIID).frame(width: 160, height: 32))
            host.frame = Self.swiftUIFrame
            content.addSubview(host)

            window.contentView = content
            window.orderFrontRegardless()
            windows.append(window)

            func global(_ rect: CGRect) -> CGRect {
                let inWindow = content.convert(rect, to: nil)
                return window.convertToScreen(inWindow)
            }
            targets.append(Target(id: Self.nativeID, display: display, frame: global(Self.nativeFrame)))
            targets.append(Target(id: Self.swiftUIID, display: display, frame: global(Self.swiftUIFrame)))
        }
    }

    func close() {
        for window in windows { window.orderOut(nil); window.contentView = nil; window.close() }
        windows = []; targets = []; nativeButtons = []; clickTargets = []
    }
}

private final class FixtureClickTarget: NSObject {
    let counter: PointingFixture.Counter
    init(counter: PointingFixture.Counter) { self.counter = counter }
    @objc func nativePressed() { counter.native += 1 }
}

/// A deterministic stand-in for a model: streams a valid v2 scene for the fixture button, in
/// chunks that split mid-token, through the same strict stream the real providers use.
@MainActor
final class ScriptedPointingProvider: ExplanationModelProviding {
    private(set) var requests = 0
    private(set) var chunkBoundaryEventCounts: [Int] = []
    var preferredTargetRole = "AXButton"

    func respond(_ request: ExplanationModelRequest,
                 receive: @escaping @MainActor (ExplanationEvent) async throws -> Void) async throws {
        requests += 1
        guard let context = request.pointing else { throw ExplanationProviderError.invalidRequest }
        var stream = try ExplanationEventStream(sessionID: request.scene.sessionID, turnID: request.turnID,
                                                sceneID: request.scene.sceneID, baseRevision: request.scene.revision,
                                                profile: .v2(candidateIDs: context.candidateIDs))
        // The Accessibility button when Accessibility is on, otherwise the pointer-centered target.
        let target = (context.candidates.first { $0.role == preferredTargetRole && $0.imageRect != nil }
            ?? context.candidates.first { $0.imageRect != nil })?.id
        let bytes = Array(Self.script(request: request, context: context, target: target).utf8)
        // Cut sizes chosen so one boundary falls inside a JSON token.
        let cuts = [41, 7, 233, 19, 311, 64]
        var offset = 0, index = 0
        chunkBoundaryEventCounts = []
        while offset < bytes.count {
            let size = min(cuts[index % cuts.count], bytes.count - offset)
            let events = try stream.append(Data(bytes[offset..<(offset + size)]))
            chunkBoundaryEventCounts.append(events.count)
            for event in events { try await receive(event) }
            offset += size; index += 1
        }
        try stream.finish()
    }

    static func script(request: ExplanationModelRequest, context: PointingContext, target: String?) -> String {
        let ids = "\"sessionID\":\"\(request.scene.sessionID)\",\"turnID\":\"\(request.turnID)\",\"sceneID\":\"\(request.scene.sceneID)\""
        let revision = request.scene.revision
        var cues = "[]"
        if let target, let capture = context.captureID {
            let style = "\"style\":{\"fill\":\"clear\",\"stroke\":\"orange\",\"lineWidth\":3,\"opacity\":1,\"dashed\":false,\"material\":\"matte\"}"
            let ring = "{\"op\":\"create\",\"object\":{\"id\":\"ring-target\",\"space\":\"capture\",\"captureID\":\"\(capture)\",\"targetID\":\"\(target)\",\"geometry\":{\"kind\":\"ring\",\"radius\":20},\(style),\"accessibleDescription\":\"Ring around the fixture button\"}}"
            let label = "{\"op\":\"create\",\"object\":{\"id\":\"label-target\",\"space\":\"capture\",\"captureID\":\"\(capture)\",\"targetID\":\"\(target)\",\"geometry\":{\"kind\":\"label\"},\"text\":\"Fixture button\",\"accessibleDescription\":\"Label for the fixture button\"}}"
            cues = "[{\"id\":\"c0\",\"anchor\":{\"kind\":\"start\"},\"operations\":[\(ring)]},{\"id\":\"c1\",\"anchor\":{\"kind\":\"end\"},\"operations\":[\(label)]}]"
        }
        let first = "{\"version\":2,\(ids),\"sequence\":0,\"baseRevision\":\(revision),\"revision\":\(revision + 1),\"beatID\":\"b0\",\"speech\":{\"chunkID\":\"b0-s\",\"text\":\"That is the fixture button.\"},\"cues\":\(cues),\"isFinal\":false}"
        let second = "{\"version\":2,\(ids),\"sequence\":1,\"baseRevision\":\(revision + 1),\"revision\":\(revision + 2),\"beatID\":\"b1\",\"speech\":{\"chunkID\":\"b1-s\",\"text\":\"It only proves that pointing works.\"},\"cues\":[],\"isFinal\":true}"
        return first + "\n" + second + "\n"
    }
}

/// Silent speech for the deterministic run: a real clip through the real player, so playback
/// callbacks, cue admission and the flight all follow actual playback, with no vendor and no sound.
@MainActor
final class ScriptedPointingSpeech: SpeechOutputProvider {
    private(set) var rendered = 0
    func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
        rendered += 1
        let seconds = 1.2
        return try await PointingPCM.prepare(request, pcm16: Data(count: Int(24_000 * seconds) * 2), sampleRate: 24_000)
    }
}
