import AppKit
import ApplicationServices
import ZeusCore

/// `Zeus --pointing-selftest --receipt <absolute path> [--live]`
///
/// Runs the pointing slice end to end against Zeus's own fixture windows and writes a receipt.
/// It acts only when started explicitly with the flag, never requests or scripts a permission
/// (a missing one marks the dependent check `blocked` with the System Settings pane), only points
/// at, captures and presses Zeus's own windows, and exits within 120 seconds.
///
/// Evidence labels: key events, pointer samples and the transcript are injected at the
/// `PointingController` boundary (the same entry points the real monitor, timer and overlay call);
/// the capture, the Accessibility probe, the overlay windows and playback are real. Window
/// click-through is checked from window policy and z-order, not from posted OS events.
enum PointingSelfTest {
    static let transcript = "What does this button do?"
    static let hardTimeout: TimeInterval = 120

    @MainActor
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--pointing-selftest") else { return false }
        guard let index = args.firstIndex(of: "--receipt"), args.indices.contains(index + 1),
              args[index + 1].hasPrefix("/") else {
            fputs("--pointing-selftest needs --receipt <absolute path>\n", stderr)
            exit(64)
        }
        let receipt = PointingSelfTestReceipt(path: args[index + 1])
        // Watchdog on a background queue: it still fires if the main thread is wedged.
        DispatchQueue.global().asyncAfter(deadline: .now() + hardTimeout) {
            receipt.write(timedOut: true)
            fputs("pointing self-test: hard timeout after \(Int(hardTimeout)) s\n", stderr)
            exit(124)
        }
        let runner = PointingSelfTestRunner(receipt: receipt, live: args.contains("--live"))
        Task { @MainActor in
            let code = await runner.run()
            exit(code)
        }
        return true
    }
}

@MainActor
final class PointingSelfTestRunner {
    private final class PointerBox { var point = CGPoint.zero }
    private final class Counts { var begins = 0, finishes = 0, cancels = 0 }
    private struct TurnOutcome {
        var states: [String] = []
        var completed = false
        var captureAttempts = 0
        var lagMilliseconds: Double?
        var flights = 0
        var metrics = PointingController.Metrics()
        var failure: String?
    }

    private let receipt: PointingSelfTestReceipt
    private let live: Bool
    private let pointer = PointerBox()
    private let counts = Counts()
    private let fixture = PointingFixture()
    private var notices: [PointingNotice] = []
    private var flights: [(point: CGPoint, label: String)] = []
    private var idleCalls = 0
    private var displays: [PointingDisplay] = []
    private var controller: PointingController!
    private var explanation: ExplanationController!
    private var providers: PointingProviders?
    private var scripted: ScriptedPointingProvider?
    private var heartbeat: Timer?
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var maxGap = 0.0
    private var baselineWindows = 0
    private let screenGranted = CGPreflightScreenCaptureAccess()
    private let accessibilityGranted = AXIsProcessTrusted()
    private let screenPane = "Privacy_ScreenCapture"
    private let accessibilityPane = "Privacy_Accessibility"

    init(receipt: PointingSelfTestReceipt, live: Bool) { self.receipt = receipt; self.live = live }

    // MARK: Setup

    private func setUp() async {
        displays = PointingDisplay.live()
        let info = Bundle.main.infoDictionary ?? [:]
        receipt.setHeader([
            "app": ["build_stamp": info["ZeusBuildStamp"] as? String ?? "unknown",
                    "git_sha": info["ZeusGitSHA"] as? String ?? ProcessInfo.processInfo.environment["ZEUS_GIT_SHA"] ?? "unknown",
                    "bundle": Bundle.main.bundleIdentifier ?? "unknown"],
            "macos": ProcessInfo.processInfo.operatingSystemVersionString,
            "mode": live ? "live" : "deterministic",
            "inputs": ["keys": "injected", "pointer": "injected", "transcript": "injected (fixed fixture text)",
                       "provider": live ? "live" : "scripted"],
            "permissions": ["screen_recording": screenGranted, "accessibility": accessibilityGranted],
            "displays": displays.map { ["id": Int($0.id), "scale": $0.scale,
                                        "origin": [$0.frame.minX, $0.frame.minY], "size": [$0.frame.width, $0.frame.height]] },
        ])
        fixture.open(on: displays)
        await PointingTimers.wait(0.5)
        baselineWindows = NSApp.windows.count
        if let first = fixture.targets.first { pointer.point = first.center }

        let model: any ExplanationModelProviding, speech: any SpeechOutputProvider
        var prepare: () async -> [PointingProviderPath] = { [.zeusSetup] }
        if live {
            let built = PointingProviders(anyLLM: { (AIConnections.shared.anyLLM, Keychain.get(AnyLLMConfig.keyAccount)) },
                                          localOnly: { false }, anyLLMComplete: { AIConnections.shared.anyLLM.isComplete })
            providers = built; model = built.model; speech = built.speech
            prepare = { await built.prepareTurn() }
        } else {
            let provider = ScriptedPointingProvider()
            scripted = provider; model = provider; speech = ScriptedPointingSpeech()
        }
        let explanation = ExplanationController(provider: model, speechProvider: speech,
            microphone: ExplanationMicrophone(acquire: {}, release: {}), acquireAudio: {}, releaseAudio: {})
        self.explanation = explanation
        var services = PointingController.Services()
        services.mouseLocation = { [pointer] in pointer.point }
        services.enabled = { true }
        if !live { services.sendScreenshot = { false } }
        let counts = self.counts
        let inputs = PointingController.Inputs(
            begin: { counts.begins += 1; return UUID() },
            finish: { [unowned explanation] _ in
                counts.finishes += 1
                explanation.draft = PointingSelfTest.transcript
                explanation.submit()
            },
            cancel: { _ in counts.cancels += 1 })
        let marker = PointingController.Marker(
            listen: {}, think: {},
            idle: { [weak self] in self?.idleCalls += 1 },
            flight: { [weak self] point, label in self?.flights.append((point, label)); return true })
        controller = PointingController(explanation: explanation, services: services, inputs: inputs, marker: marker,
                                        prepare: prepare, recordAudio: { [weak self] seconds in self?.providers?.recordFirstAudio(secondsSinceRelease: seconds) })
        controller.onNotice = { [weak self] notice in self?.notices.append(notice) }
        heartbeat = PointingTimers.repeating(every: 0.01) { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.maxGap = max(self.maxGap, now - self.lastBeat - 0.01)
            self.lastBeat = now
        }
    }

    private func tearDown() {
        heartbeat?.invalidate(); heartbeat = nil
        controller?.stop()
        fixture.close()
    }

    // MARK: Run

    func run() async -> Int32 {
        await setUp()
        let startMemory = ProcessEnergy.sample().residentMB
        var peakMemory = startMemory

        // Turn A is the full, normal turn: it feeds lifecycle, capture, rendering and sync.
        await lifecycle()
        let turn = await normalTurn(label: "A", keepOverlay: true)
        peakMemory = max(peakMemory, ProcessEnergy.sample().residentMB)
        checkCapture(turn)
        await checkRendering()
        checkSync(turn)
        cleanup()

        checkCoordinates()
        await checkTargeting()
        checkProtocol()
        await checkInterruption()
        peakMemory = max(peakMemory, ProcessEnergy.sample().residentMB)
        await checkRepeat()
        peakMemory = max(peakMemory, ProcessEnergy.sample().residentMB)
        checkResources(start: startMemory, peak: peakMemory)

        if live, let providers {
            let stats = providers.book.stats.map { path, stat in
                ["path": path.rawValue, "first_token_s": stat.firstToken ?? NSNull(), "first_audio_s": stat.firstAudio ?? NSNull(),
                 "samples": stat.samples] as [String: Any]
            }
            receipt.setHeader(["provider_path": providers.model.activePath?.rawValue ?? "none", "provider_latency": stats])
        } else {
            receipt.setHeader(["provider_path": "scripted"])
        }
        tearDown()
        let code = receipt.exitCode
        receipt.write()
        return code
    }

    // MARK: Helpers

    private func name(_ state: PointingSession.State) -> String {
        switch state {
        case .idle: "idle"; case .listening: "listening"; case .drawing: "drawing"; case .processing: "processing"
        case .speaking: "speaking"; case .guiding: "guiding"; case .interrupted: "interrupted"
        case .cancelled: "cancelled"; case .failed: "failed"
        }
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            await PointingTimers.wait(0.02)
        }
        return condition()
    }

    /// Leaks once an in-flight system capture has returned (it keeps its admission until it does).
    private func settledLeaks() async -> [String] {
        _ = await waitUntil(3) { controller.leaks.isEmpty }
        return controller.leaks
    }

    private func cleanup() {
        explanation.stop()
        explanation.screenContext.clear()
        MarkOverlay.shared.hide()
    }

    /// Holds, rests on the native fixture button (a dwell), draws a short stroke, releases, and
    /// follows the state machine until it is idle again.
    private func normalTurn(label: String, keepOverlay: Bool = false) async -> TurnOutcome {
        var outcome = TurnOutcome()
        let attemptsBefore = controller.metrics.captureAttempts
        let flightsBefore = flights.count
        var last = name(controller.state)
        outcome.states = [last]
        func note() { let now = name(controller.state); if now != last { outcome.states.append(now); last = now } }

        controller.handle(.began); note()
        let center = fixture.targets.first?.center ?? .zero
        pointer.point = center
        for _ in 0..<9 { controller.sample(at: center); await PointingTimers.wait(0.05) }
        controller.ink(.leftMouseDown, center)
        for step in 1...3 { controller.ink(.leftMouseDragged, CGPoint(x: center.x + Double(step) * 6, y: center.y + Double(step) * 3)) }
        controller.ink(.leftMouseUp, CGPoint(x: center.x + 18, y: center.y + 9))
        controller.handle(.ended); note()
        let finished = await waitUntil(25) { note(); return controller.state == .idle && explanation.phase != .thinking
            && explanation.phase != .preparingSpeech && explanation.phase != .speaking }
        note()
        outcome.completed = finished && explanation.phase == .completed
        outcome.captureAttempts = controller.metrics.captureAttempts - attemptsBefore
        outcome.lagMilliseconds = controller.metrics.flightLagMilliseconds
        outcome.flights = flights.count - flightsBefore
        outcome.metrics = controller.metrics
        outcome.failure = controller.metrics.lastFailure ?? explanation.problem
        if keepOverlay { turnAScene = explanation.scene; turnACapture = explanation.screenContext.annotationContext }
        else { cleanup() }
        return outcome
    }

    private func isSubsequence(_ wanted: [String], of states: [String]) -> Bool {
        var index = 0
        for state in states where index < wanted.count && state == wanted[index] { index += 1 }
        return index == wanted.count
    }

    // MARK: 1 lifecycle

    private func lifecycle() async {
        var problems: [String] = []
        var metrics: [String: Any] = [:]
        if controller.state != .idle { problems.append("not idle at start") }
        // Double hold is idempotent.
        controller.handle(.began); controller.handle(.began)
        metrics["input_begins_after_double_hold"] = counts.begins
        if counts.begins != 1 { problems.append("a second hold started a second session") }
        // Spoil cancels with no request.
        let requestsBefore = controller.metrics.requestsSent
        controller.handle(.cancelled)
        let sent = controller.metrics.requestsSent - requestsBefore
        metrics["requests_after_spoil"] = sent
        metrics["finishes_after_spoil"] = counts.finishes
        if controller.state != .idle { problems.append("spoil did not return to idle") }
        if sent != 0 || counts.finishes != 0 || (scripted?.requests ?? 0) != 0 { problems.append("spoil sent a request") }
        let spoilLeaks = await settledLeaks()
        if !spoilLeaks.isEmpty { problems.append("spoil leaked: \(spoilLeaks.joined(separator: ", "))") }
        // The normal order is checked on turn A, run next; record that order here.
        let turn = await normalTurn(label: "lifecycle", keepOverlay: false)
        metrics["states"] = turn.states.joined(separator: ">")
        if !isSubsequence(["idle", "listening", "processing", "speaking", "idle"], of: turn.states) {
            problems.append("states were \(turn.states.joined(separator: ">"))")
        }
        if !turn.completed { problems.append("turn did not complete: \(turn.failure ?? "no reason")") }
        receipt.set("lifecycle", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "), metrics: metrics)
    }

    // MARK: 2 capture

    private func checkCapture(_ turn: TurnOutcome) {
        var metrics: [String: Any] = ["screen_recording_granted": screenGranted, "capture_attempts_in_turn": turn.captureAttempts]
        let permissionNotices = notices.filter { if case .permission(_, let pane) = $0 { return pane == screenPane } else { return false } }
        metrics["permission_notices"] = permissionNotices.count
        if !screenGranted {
            let ok = turn.captureAttempts == 0 && permissionNotices.count == 1
            receipt.set("capture", ok ? .blocked : .failed,
                        reason: ok ? "Screen Recording is not granted to this process. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording. The clear message was shown once and no prompt was raised."
                            : "without permission expected 0 captures and exactly 1 notice, got \(turn.captureAttempts) and \(permissionNotices.count)",
                        pane: screenPane, metrics: metrics)
            return
        }
        if let size = explanation.screenContext.snapshot?.geometry.imageSize {
            metrics["image_width"] = size.width; metrics["image_height"] = size.height
        }
        let ok = turn.captureAttempts == 1 && permissionNotices.isEmpty
        receipt.set("capture", ok ? .passed : .failed,
                    reason: ok ? "" : "expected exactly 1 capture and no permission notice, got \(turn.captureAttempts) and \(permissionNotices.count)",
                    metrics: metrics)
    }

    // MARK: 3 coordinates

    private func checkCoordinates() {
        let mapper = ScreenCoordinateMapper(displays: displays.map { DisplayMap(id: Int($0.id), frame: $0.frame, scale: $0.scale) })
        var rows: [[String: Any]] = []
        var worst = 0.0
        var problems: [String] = []
        for display in displays {
            let native = CGSize(width: display.frame.width * display.scale, height: display.frame.height * display.scale)
            let factor = min(1, Double(ExplanationScreenContext.maximumImageEdge) / max(native.width, native.height))
            let delivered = ExplanationSize2(width: max(1, (native.width * factor).rounded(.down)), height: max(1, (native.height * factor).rounded(.down)))
            guard let context = try? ExplanationDisplayContext(displayID: display.id,
                    frame: .init(x: display.frame.minX, y: display.frame.minY, width: display.frame.width, height: display.frame.height),
                    backingScale: display.scale),
                  let geometry = try? ExplanationCaptureGeometry(display: context, fullImageSize: .init(width: native.width, height: native.height),
                    crop: .init(x: 0, y: 0, width: native.width, height: native.height), imageSize: delivered) else {
                problems.append("display \(display.id): geometry"); continue
            }
            var displayWorst = 0.0
            for target in fixture.targets where target.display.id == display.id {
                guard let quartz = mapper.convert(target.frame, from: .screen, to: .ax, context: MapContext()),
                      let rect = PointingGeometry.imageRect(fromAX: quartz, mapper: mapper, geometry: geometry, display: context),
                      let topLeft = geometry.globalPoint(fromImage: .init(x: rect.x, y: rect.y), current: context),
                      let bottomRight = geometry.globalPoint(fromImage: .init(x: rect.x + rect.width, y: rect.y + rect.height), current: context) else {
                    problems.append("display \(display.id): \(target.id) did not convert"); continue
                }
                let errors = [abs(topLeft.x - target.frame.minX), abs(topLeft.y - target.frame.maxY),
                              abs(bottomRight.x - target.frame.maxX), abs(bottomRight.y - target.frame.minY)]
                displayWorst = max(displayWorst, errors.max() ?? 0)
            }
            worst = max(worst, displayWorst)
            rows.append(["display_id": Int(display.id), "scale": display.scale, "origin": [display.frame.minX, display.frame.minY],
                         "delivered_px": [delivered.width, delivered.height], "max_error_pt": displayWorst])
            if displayWorst > 1 { problems.append("display \(display.id): round trip off by \(displayWorst) pt") }
        }
        if fixture.targets.isEmpty { problems.append("no fixture targets") }
        receipt.set("coordinates", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "),
                    metrics: ["per_display": rows, "max_error_pt": worst, "displays": displays.count])
    }

    // MARK: 4 targeting

    private func checkTargeting() async {
        guard accessibilityGranted else {
            receipt.set("targeting", .blocked,
                        reason: "Accessibility is not granted to this process. Turn it on in System Settings > Privacy & Security > Accessibility; the self-test never prompts.",
                        pane: accessibilityPane, metrics: ["accessibility_granted": false])
            return
        }
        let mapper = ScreenCoordinateMapper(displays: displays.map { DisplayMap(id: Int($0.id), frame: $0.frame, scale: $0.scale) })
        var problems: [String] = []
        var rows: [[String: Any]] = []
        for target in fixture.targets.prefix(2) {
            guard let quartz = mapper.convert(target.center, from: .screen, to: .ax, context: MapContext()) else { continue }
            let raw = PointingTargetProbe.hitTest(atQuartzPoint: quartz) // main actor, like the app
            guard let raw else { problems.append("\(target.id): no element"); continue }
            let screenFrame = mapper.convert(raw.axFrame, from: .ax, to: .screen, context: MapContext()) ?? .zero
            let centerError = hypot(screenFrame.midX - target.frame.midX, screenFrame.midY - target.frame.midY)
            rows.append(["expected": target.id, "found": raw.identifier ?? "none", "role": raw.role, "center_error_pt": centerError])
            if raw.identifier != target.id { problems.append("\(target.id): found \(raw.identifier ?? "no identifier")") }
            if centerError > 20 { problems.append("\(target.id): frame center off by \(Int(centerError)) pt") }
        }
        receipt.set("targeting", problems.isEmpty && rows.count == 2 ? .passed : .failed,
                    reason: problems.isEmpty && rows.count < 2 ? "fixture targets missing" : problems.joined(separator: "; "),
                    metrics: ["probes": rows])
    }

    // MARK: 5 protocol

    private func checkProtocol() {
        let session = UUID(), turn = UUID(), scene = UUID(), capture = UUID()
        let profile = ExplanationWireProfile.v2(candidateIDs: ["t0"])
        func line(position: String = "{\"x\":10,\"y\":10,\"z\":0}", op: String = "create", target: String = ",\"targetID\":\"t0\"") -> Data {
            let object = "{\"id\":\"ring\",\"space\":\"capture\",\"captureID\":\"\(capture)\"\(target),\"transform\":{\"position\":\(position),\"rotation\":{\"x\":0,\"y\":0,\"z\":0},\"scale\":{\"x\":1,\"y\":1,\"z\":1}},\"geometry\":{\"kind\":\"ring\",\"radius\":20},\"accessibleDescription\":\"Ring\"}"
            let text = "{\"version\":2,\"sessionID\":\"\(session)\",\"turnID\":\"\(turn)\",\"sceneID\":\"\(scene)\",\"sequence\":0,\"baseRevision\":0,\"revision\":1,\"beatID\":\"b0\",\"speech\":{\"chunkID\":\"b0-s\",\"text\":\"Hi.\"},\"cues\":[{\"id\":\"c0\",\"anchor\":{\"kind\":\"start\"},\"operations\":[{\"op\":\"\(op)\",\"object\":\(object)}]}],\"isFinal\":true}\n"
            return Data(text.utf8)
        }
        func stream() -> ExplanationEventStream? {
            try? ExplanationEventStream(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0, profile: profile)
        }
        var problems: [String] = []
        var metrics: [String: Any] = [:]

        // Split chunks never render a partial op: nothing is emitted before the newline, at any cut.
        let good = line()
        var rendered = 0, cuts = 0
        for cut in stride(from: 1, to: good.count - 1, by: 11) {
            guard var s = stream() else { problems.append("stream"); break }
            rendered += (try? s.append(good.prefix(cut)))?.count ?? 0; cuts += 1
            if (try? s.append(good.suffix(from: cut)))?.count != 1 { problems.append("split at \(cut) lost the event") }
        }
        metrics["split_cuts"] = cuts; metrics["partial_events_rendered"] = rendered
        if rendered != 0 { problems.append("a partial line rendered") }
        if let counts = scripted?.chunkBoundaryEventCounts, !counts.isEmpty {
            metrics["scripted_events_per_chunk"] = counts
        }

        // A malformed op and an off-image coordinate are rejected, not clamped.
        if var s = stream() { if (try? s.append(line(op: "bogus"))) != nil { problems.append("malformed op accepted") } }
        metrics["malformed_op_rejected"] = problems.allSatisfy { $0 != "malformed op accepted" }
        if var s = stream() {
            if (try? s.append(line(position: "{\"x\":20000,\"y\":10,\"z\":0}"))) != nil { problems.append("out-of-range coordinate accepted") }
        }
        let farLine = line(position: "{\"x\":5000,\"y\":5000,\"z\":0}", target: "")
        if let event = try? ExplanationWire.decode(farLine.dropLast(), profile: profile) {
            let context = PointingContext(captureID: capture, imageSize: .init(width: 1440, height: 900),
                candidates: [.init(id: "t0", role: "AXButton", imageRect: .init(x: 100, y: 100, width: 100, height: 40))])
            let resolution = PointingSceneResolver.resolve(event, context: context)
            metrics["off_image_marks_dropped"] = resolution.droppedObjects
            if resolution.droppedObjects != 1 || !resolution.event.cues.isEmpty { problems.append("off-image mark was not dropped") }
        } else { problems.append("far mark did not decode") }
        if let display = displays.first,
           let context = try? ExplanationDisplayContext(displayID: display.id,
                frame: .init(x: display.frame.minX, y: display.frame.minY, width: display.frame.width, height: display.frame.height), backingScale: display.scale),
           let geometry = try? ExplanationCaptureGeometry(display: context, fullImageSize: .init(width: 100, height: 100),
                crop: .init(x: 0, y: 0, width: 100, height: 100), imageSize: .init(width: 100, height: 100)) {
            let outside = geometry.imagePoint(fromGlobal: .init(x: display.frame.maxX + 50, y: display.frame.maxY + 50), current: context)
            metrics["outside_point_returns_nil"] = outside == nil
            if outside != nil { problems.append("an outside point was clamped into the image") }
        }
        receipt.set("protocol", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "), metrics: metrics)
    }

    // MARK: 6 rendering

    private func topmostAccepting(at point: CGPoint) -> NSWindow? {
        NSApp.orderedWindows.first { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(point) }
    }

    private func checkRendering() async {
        var problems: [String] = []
        var metrics: [String: Any] = [:]
        let fixtureWindows = Set(fixture.windows.map { ObjectIdentifier($0) })
        guard let target = fixture.targets.first else { receipt.set("rendering", .failed, reason: "no fixture"); return }

        // Click-through when not drawing: every annotation window ignores the mouse, and the
        // topmost window that accepts mouse events at the button is the fixture window.
        let overlays = explanation.overlayWindows
        metrics["overlay_windows"] = overlays.count
        if let level = overlays.map(\.level.rawValue).min() { metrics["overlay_level"] = level }
        let accepting = topmostAccepting(at: target.center)
        let passesThrough = overlays.allSatisfy(\.ignoresMouseEvents) && accepting.map { fixtureWindows.contains(ObjectIdentifier($0)) } == true
        metrics["clicks_pass_through"] = passesThrough
        if !passesThrough { problems.append("annotation overlay would take clicks") }

        // While held the overlay stays click-through (the pointer path is the ink); strokes come from motion.
        controller.handle(.began)
        let holdTop = topmostAccepting(at: target.center)
        let heldCaptures = holdTop.map { !fixtureWindows.contains(ObjectIdentifier($0)) } ?? false
        controller.ink(.leftMouseDown, target.center)
        controller.ink(.leftMouseDragged, CGPoint(x: target.center.x + 10, y: target.center.y))
        controller.ink(.leftMouseUp, CGPoint(x: target.center.x + 10, y: target.center.y))
        let strokes = controller.trace.strokes.count
        metrics["held_overlay_takes_mouse"] = heldCaptures
        metrics["strokes_while_held"] = strokes
        metrics["fixture_clicks_while_held"] = fixture.counter.native + fixture.counter.swiftUI
        if heldCaptures || MarkOverlay.shared.capturesMouse { problems.append("overlay took the mouse while held") }
        if strokes != 1 { problems.append("expected 1 stroke while held, got \(strokes)") }
        if fixture.counter.native + fixture.counter.swiftUI != 0 { problems.append("a click reached the fixture") }
        controller.handle(.cancelled)
        if MarkOverlay.shared.capturesMouse { problems.append("ink overlay stayed after release") }
        let afterRelease = topmostAccepting(at: target.center)
        if afterRelease.map({ fixtureWindows.contains(ObjectIdentifier($0)) }) != true { problems.append("clicks did not return to normal after release") }

        guard screenGranted else {
            receipt.set("rendering", .blocked,
                        reason: "Ring placement and the overlay level need a capture, which needs Screen Recording. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording. Pass-through and ink checks above still ran." + (problems.isEmpty ? "" : " Problems: " + problems.joined(separator: "; ")),
                        pane: screenPane, metrics: metrics)
            return
        }
        guard accessibilityGranted else {
            receipt.set("rendering", .blocked,
                        reason: "The ring is placed from the button's Accessibility frame. Turn on Accessibility in System Settings > Privacy & Security > Accessibility." + (problems.isEmpty ? "" : " Problems: " + problems.joined(separator: "; ")),
                        pane: accessibilityPane, metrics: metrics)
            return
        }
        // Above menus, and the ring hugs the control. (The earlier lease ended with the hold above,
        // so this reads the scene and window state kept from turn A.)
        if let level = overlays.map(\.level.rawValue).min(), level <= NSWindow.Level.popUpMenu.rawValue { problems.append("overlay is not above menus") }
        if overlays.isEmpty { problems.append("no annotation overlay was shown") }
        if let ring = turnARing {
            metrics["ring_center_error_pt"] = ring.centerError; metrics["ring_margin_pt"] = ring.margin
            if ring.centerError > 4 { problems.append("ring center is \(ring.centerError) pt from the button") }
            if ring.margin < 0 || ring.margin > 12 { problems.append("ring margin \(ring.margin) pt") }
        } else { problems.append(live ? "the model did not ring the fixture" : "no ring was rendered") }
        receipt.set("rendering", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "), metrics: metrics)
    }

    /// Ring geometry read from the scene after turn A, against the fixture's own frame.
    private var turnARing: (centerError: Double, margin: Double)? {
        guard let scene = turnAScene, let capture = turnACapture, let target = fixture.targets.first,
              let ring = scene.objects.values.first(where: { $0.geometry.kind == .ring && $0.space == .capture }),
              let center = capture.geometry.globalPoint(fromImage: .init(x: ring.transform.position.x, y: ring.transform.position.y), current: capture.currentDisplay)
        else { return nil }
        let points = capture.currentDisplay.frame.width / capture.geometry.imageSize.width
        let radius = (ring.geometry.radius ?? 0) * points
        return (hypot(center.x - target.frame.midX, center.y - target.frame.midY), radius - max(target.frame.width, target.frame.height) / 2)
    }
    private var turnAScene: ExplanationScene?
    private var turnACapture: ExplanationCaptureContext?

    // MARK: 7 sync

    private func checkSync(_ turn: TurnOutcome) {
        var metrics: [String: Any] = ["flights": turn.flights]
        if let lag = turn.lagMilliseconds { metrics["flight_start_minus_first_audio_ms"] = lag }
        metrics["flight_used_fallback"] = turn.metrics.flightUsedFallback
        if let first = turn.metrics.firstAudioAt, let release = turn.metrics.releaseAt {
            metrics["release_to_first_audio_ms"] = (first - release) * 1000
        }
        guard screenGranted else {
            receipt.set("sync", .blocked,
                        reason: "There is no ring to fly to without a capture, which needs Screen Recording. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording.",
                        pane: screenPane, metrics: metrics)
            return
        }
        guard let lag = turn.lagMilliseconds else {
            receipt.set("sync", .failed, reason: live ? "the model produced no ring, so no flight started" : "no flight started", metrics: metrics)
            return
        }
        let ok = lag >= 0 && !turn.metrics.flightUsedFallback
        receipt.set("sync", ok ? .passed : .failed, reason: ok ? "" : "flight left \(lag) ms relative to first audio (fallback \(turn.metrics.flightUsedFallback))", metrics: metrics)
    }

    // MARK: 8 interruption

    private func startSpeaking() async -> Bool {
        controller.handle(.began)
        let center = fixture.targets.first?.center ?? .zero
        for _ in 0..<4 { controller.sample(at: center); await PointingTimers.wait(0.05) }
        controller.handle(.ended)
        return await waitUntil(25) { controller.state == .speaking }
    }

    private func checkInterruption() async {
        var problems: [String] = []
        var metrics: [String: Any] = [:]

        // Esc mid-speech.
        if await startSpeaking() {
            let began = ProcessInfo.processInfo.systemUptime
            controller.handle(.escape)
            let elapsed = (ProcessInfo.processInfo.systemUptime - began) * 1000
            metrics["esc_to_stopped_ms"] = elapsed
            metrics["esc_stop_call_ms"] = (controller.metrics.stopLatency ?? 0) * 1000
            if elapsed > 150 { problems.append("Esc took \(Int(elapsed)) ms") }
            if explanation.phase != .idle { problems.append("speech still active after Esc (\(explanation.phase))") }
            if controller.state != .idle { problems.append("state \(name(controller.state)) after Esc") }
            let leaks = await settledLeaks()
            metrics["leaks_after_esc"] = leaks
            if !leaks.isEmpty { problems.append("after Esc: \(leaks.joined(separator: ", "))") }
        } else { problems.append("never reached speaking for the Esc case") }
        cleanup()

        // A second hold mid-speech (barge-in).
        if await startSpeaking() {
            let began = ProcessInfo.processInfo.systemUptime
            controller.handle(.began)
            let elapsed = (ProcessInfo.processInfo.systemUptime - began) * 1000
            metrics["second_hold_to_stopped_ms"] = elapsed
            if elapsed > 150 { problems.append("second hold took \(Int(elapsed)) ms") }
            if explanation.phase != .idle || explanation.overlayVisible { problems.append("speech or animation survived the second hold") }
            if controller.state != .listening { problems.append("second hold did not start listening") }
            controller.handle(.cancelled)
            let leaks = await settledLeaks()
            metrics["leaks_after_second_hold"] = leaks
            if !leaks.isEmpty { problems.append("after second hold: \(leaks.joined(separator: ", "))") }
        } else { problems.append("never reached speaking for the second-hold case") }
        cleanup()
        metrics["microphone_idle"] = explanation.microphone.state == .idle
        if explanation.microphone.state != .idle { problems.append("microphone not released") }

        // The next turn works.
        let next = await normalTurn(label: "after-interrupt")
        metrics["next_turn_completed"] = next.completed
        if !next.completed { problems.append("the next turn did not complete") }
        receipt.set("interruption", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "), metrics: metrics)
    }

    // MARK: 9 repeat

    private func checkRepeat() async {
        var problems: [String] = []
        var completed = 0
        cleanup()
        let before = NSApp.windows.count
        for index in 0..<3 {
            let turn = await normalTurn(label: "repeat-\(index)")
            if turn.completed { completed += 1 } else { problems.append("turn \(index + 1) did not complete") }
            let leaks = await settledLeaks()
            if !leaks.isEmpty { problems.append("turn \(index + 1) leaked \(leaks.joined(separator: ", "))") }
            if NSApp.windows.count != before { problems.append("turn \(index + 1) changed the window count to \(NSApp.windows.count)") }
        }
        receipt.set("repeat", problems.isEmpty ? .passed : .failed, reason: problems.joined(separator: "; "),
                    metrics: ["turns": 3, "completed": completed, "windows_before": before, "windows_after": NSApp.windows.count,
                              "baseline_windows_with_fixture": baselineWindows])
    }

    // MARK: 10 resources

    private func checkResources(start: Double, peak: Double) {
        var metrics: [String: Any] = ["max_main_thread_gap_ms": maxGap * 1000]
        guard start > 0, peak > 0 else {
            receipt.set("resources", .notMeasured, reason: "the process sampler returned no resident size", metrics: metrics)
            return
        }
        metrics["resident_start_mb"] = start; metrics["resident_peak_mb"] = peak; metrics["resident_delta_mb"] = peak - start
        // The gap is measured by a 10 ms main-run-loop heartbeat. It is a hitch indicator, not a frame-rate proof.
        let ok = maxGap < 0.5
        receipt.set("resources", ok ? .passed : .failed, reason: ok ? "" : "the main thread stalled for \(Int(maxGap * 1000)) ms", metrics: metrics)
    }
}
