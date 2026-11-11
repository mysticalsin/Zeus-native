import AppKit
import SwiftUI
import ZeusCore

/// The real Chat surface. Controls call the production controller; no canned scene
/// or simulated narration is substituted when a provider/permission is missing.
@MainActor
struct ExplanationPane: View {
    @Bindable var controller: ExplanationController
    let conversationID: UUID
    let submit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("opt.explanation.shortcut") private var shortcut = "Command-Shift-Space"
    @AppStorage("opt.explanation.localOnly") private var localOnly = "false"
    @AppStorage("opt.explanation.voice") private var voiceIdentifier = ""
    @State private var showing3D = false
    @State private var settingsOpen = false
    @State private var installedVoices: [ExplanationSystemVoices.Choice] = []
    @State private var visible = false
    @State private var selectedDisplay: UInt32 = 0
    @State private var snapshotImage: NSImage?
    @State private var diagnosticsJSON: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let scene = controller.scene {
                        if scene.objects.isEmpty { emptyState }
                        else {
                            if scene.objects.values.contains(where: { $0.space == .world }) {
                                Picker("View", selection: $showing3D) {
                                    Text("Diagram").tag(false); Text("3D illustration").tag(true)
                                }.pickerStyle(.segmented)
                            }
                            DisplaySynchronizedView(paused: !controller.wantsDisplayClock) { tick in
                                Group {
                                    if showing3D {
                                        ExplanationSceneView(scene: scene, selection: $controller.selection,
                                            isActive: visible, isInteractive: controller.canInteract && !controller.isBusy && !controller.isReplaying, onEdit: controller.edit)
                                    } else {
                                        ExplanationCanvas(scene: scene, selection: $controller.selection,
                                            captureContext: controller.screenContext.snapshot?.frozenCanvasContext,
                                            isInteractive: controller.canInteract && !controller.isBusy && !controller.isReplaying,
                                            snapshotImage: snapshotImage,
                                            onEdit: controller.edit)
                                    }
                                }
                                .onChange(of: tick.date) { controller.sampleAudioClock() }
                            }
                        }
                    } else if controller.phase == .loading { ProgressView("Opening explanation…") }
                    if !controller.caption.isEmpty {
                        Text(controller.caption).font(.system(size: 14, weight: .medium))
                            .lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Narration: \(controller.caption)")
                    }
                    if controller.isBusy || controller.canReplay || controller.isReplaying { playbackControls.disabled(!controller.canInteract) }
                    if let problem = controller.problem { notice(problem, symbol: "exclamationmark.triangle") }
                    if !controller.canInteract, controller.phase != .loading, !controller.isClosing {
                        notice("This conversation is not ready. Any earlier scene shown here is retained for recovery; sending is disabled.", symbol: "lock")
                        Button("Retry opening this conversation") { Task { await controller.open(conversationID: conversationID) } }.buttonStyle(.borderless)
                    }
                    if let problem = controller.saveProblem {
                        notice(problem, symbol: "externaldrive.badge.exclamationmark")
                        Button("Retry save") {
                            Task { await controller.flushPendingSaves(); await controller.open(conversationID: conversationID) }
                        }.buttonStyle(.borderless)
                    }
                    if controller.screenContext.snapshot != nil {
                        if let image = snapshotImage {
                            Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Selected display snapshot")
                        }
                        Text("Frozen snapshot. Desktop annotations expire after five seconds and disappear when context changes.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Some page changes cannot be detected. Marks refer to the snapshot, not verified live content.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Toggle("Include this snapshot in my next request", isOn: $controller.includeSnapshot)
                            .font(.caption)
                        Text("When included, these pixels are sent to your configured model. Image support depends on that endpoint.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("Remove snapshot") { controller.clearSnapshot() }.buttonStyle(.borderless)
                    }
                    if settingsOpen { inputSettings }
                    if let history = controller.history, !history.messages.isEmpty {
                        DisclosureGroup("Conversation") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(history.messages) { message in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(message.role == .user ? "You" : "Zeus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(message.text).font(.callout).textSelection(.enabled)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.caption)
                    }
                }.padding(14)
            }
            Divider()
            composer.disabled(!controller.canInteract)
        }
        .task(id: conversationID) { await controller.open(conversationID: conversationID) }
        .disabled(controller.isClosing)
        .onAppear { visible = true; controller.reduceMotion = reduceMotion; updateClock(); cacheSnapshot() }
        .onDisappear { visible = false; controller.displayClockActive(false); controller.stop() }
        .onChange(of: reduceMotion) { controller.reduceMotion = reduceMotion; updateClock() }
        .onChange(of: controller.wantsDisplayClock) { updateClock() }
        .onChange(of: controller.screenContext.snapshot?.geometry.captureID) { cacheSnapshot() }
        .onChange(of: controller.scene?.objects.values.contains(where: { $0.space == .world })) {
            showing3D = controller.scene?.objects.values.contains(where: { $0.space == .world }) == true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.circle").foregroundStyle(Theme.bolt)
            VStack(alignment: .leading, spacing: 2) {
                Text("Explain it visually").font(TopBarStyle.label(14, .semibold))
                Text(status).font(TopBarStyle.label(10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                if !settingsOpen { installedVoices = ExplanationSystemVoices.installed() }
                settingsOpen.toggle()
            } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless).accessibilityLabel("Explanation options")
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make an idea visible.").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Ask Zeus to explain a process, compare two ideas, or build a simple 3D illustration. Then refine it by speaking or typing.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Explain a feedback loop") { controller.draft = "Explain a feedback loop with a simple diagram." }
                Button("Show an orbit in 3D") { controller.draft = "Explain an orbit using a simple illustrative 3D scene." }
            }.buttonStyle(.borderless).font(.caption)
            Text("Connect your model in Settings → Connections → Any LLM. Your microphone stays off until you press Speak.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var playbackControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if controller.muted {
                    Button("Next caption", systemImage: "forward.end.fill", action: controller.advanceCaption)
                        .disabled(controller.phase != .captions)
                } else if controller.isBusy {
                    Button(controller.phase == .paused ? "Resume" : "Pause",
                           systemImage: controller.phase == .paused ? "play.fill" : "pause.fill", action: controller.pauseOrResume)
                        .disabled(controller.phase != .paused && controller.phase != .speaking)
                }
                if controller.isReplaying { Button("Return to scene", action: controller.stop) }
                else if controller.isBusy { Button("Stop", systemImage: "stop.fill", action: controller.stop).keyboardShortcut(.escape, modifiers: []) }
                else { Button("Replay completed beats", systemImage: "arrow.counterclockwise", action: controller.replay).disabled(!controller.canReplay) }
                Spacer(minLength: 0)
                Picker("Speed", selection: Binding(get: { controller.rate }, set: { controller.changeRate($0) })) {
                    Text("0.75×").tag(0.75); Text("1×").tag(1.0); Text("1.25×").tag(1.25); Text("1.5×").tag(1.5)
                }.labelsHidden().frame(width: 75)
            }.buttonStyle(.borderless).font(.caption)
            if controller.currentDuration > 0, !controller.muted {
                Slider(value: Binding(get: { min(controller.position, max(0, controller.currentDuration - 0.01)) },
                                      set: { controller.seek($0) }), in: 0...max(0.01, controller.currentDuration - 0.01))
                    .accessibilityLabel("Preview current narration beat")
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if controller.microphone.state != .idle {
                HStack {
                    Image(systemName: "mic.fill").foregroundStyle(Theme.bolt)
                    Text(controller.microphone.partial.isEmpty ? status : controller.microphone.partial).font(.caption).lineLimit(3)
                    Spacer()
                    Button("Cancel", action: controller.stop).buttonStyle(.borderless)
                }.accessibilityElement(children: .combine)
            }
            TextField("Ask, or refine the current scene…", text: $controller.draft, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4).font(.system(size: 13))
                .onSubmit(submit).accessibilityIdentifier("explanation.prompt")
            Text(modelDestination).font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ExplanationTalkButton(attemptID: controller.microphone.state == .transcribing ? nil : controller.inputAttemptID,
                    isListening: controller.microphone.state == .listening,
                    isEnabled: controller.history != nil && controller.microphone.state != .transcribing,
                    begin: controller.beginListening, finish: controller.finishListening, cancel: controller.cancelListening)
                    .frame(width: 112, height: 28)
                Button("Speak") {
                    if controller.microphone.state == .listening { controller.finishListening() }
                    else { controller.beginListening() }
                }.keyboardShortcut(shortcut == "Command-Shift-V" ? "v" : " ", modifiers: [.command, .shift])
                    .accessibilityLabel("Start or finish spoken request").buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!controller.canUndo).accessibilityLabel("Undo scene change")
                Button { controller.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!controller.canRedo).accessibilityLabel("Redo scene change")
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 23)).foregroundStyle(Theme.bolt) }
                    .disabled(controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.history == nil)
                    .accessibilityLabel("Send visual explanation request").accessibilityIdentifier("explanation.send")
            }.buttonStyle(.borderless)
        }.padding(12).background(TopBarStyle.tile)
    }
    private var inputSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(modelDestination).font(.caption.weight(.medium))
            Toggle("Local-only model requests", isOn: Binding(get: { localOnly == "true" }, set: { controller.stop(); localOnly = $0 ? "true" : "false" }))
            Text("Local-only mode refuses remote endpoints. It never substitutes another provider.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle("Caption mode", isOn: Binding(get: { controller.muted }, set: { controller.setMuted($0) }))
            Text("Caption mode never synthesizes audio. Advance each beat yourself.").font(.caption2).foregroundStyle(.secondary)
            Picker("Narration voice", selection: Binding(get: { voiceIdentifier }, set: {
                controller.stop()
                voiceIdentifier = $0
            })) {
                Text("System default").tag("")
                ForEach(installedVoices) { voice in
                    Text("\(voice.name) · \(voice.language)").tag(voice.id)
                }
                if !voiceIdentifier.isEmpty, !installedVoices.contains(where: { $0.id == voiceIdentifier }) {
                    Text("Unavailable voice").tag(voiceIdentifier)
                }
            }.accessibilityIdentifier("explanation.voice")
            if !voiceIdentifier.isEmpty, !installedVoices.contains(where: { $0.id == voiceIdentifier }) {
                Text("This voice is no longer installed. Choose another installed voice or System default.")
                    .foregroundStyle(.secondary)
            }
            Text("Installed voices only. Changing voice stops this explanation and applies to the next narration.")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("Microphone", selection: Binding(get: { controller.deviceUID ?? "" }, set: {
                controller.stop(); controller.deviceUID = $0.isEmpty ? nil : $0
            })) {
                Text("System default").tag("")
                ForEach(Microphones.all(), id: \.uid) { device in Text(device.name).tag(device.uid) }
            }
            Toggle("Use already-loaded WhisperKit", isOn: Binding(get: { controller.useInstalledWhisper }, set: {
                controller.stop(); controller.useInstalledWhisper = $0
            }))
            Text("Requires a verified model already loaded by Zeus. Otherwise use Apple on-device recognition; no model downloads start here.")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("In-app shortcut", selection: $shortcut) {
                Text("⌘⇧Space").tag("Command-Shift-Space"); Text("⌘⇧V").tag("Command-Shift-V")
            }
            Picker("Display for snapshot", selection: $selectedDisplay) {
                Text("Choose display").tag(UInt32(0))
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                    Text(screen.localizedName).tag((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
                }
            }
            Button("Capture selected display") { controller.captureDisplay(selectedDisplay) }
                .disabled(!controller.canInteract || selectedDisplay == 0 || controller.screenContext.isCapturing)
            Text("macOS Screen Recording permission must already be granted by you. This captures one display once.")
                .font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Performance diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timing and counts only, kept in memory. No speech, prompts, images, credentials or conversation identifiers.")
                    Text("Audio timing starts at the player callback. Visual timing measures submitted scene state, not display presentation. Cue lateness uses media time; process CPU and physical memory footprint include all of Zeus. Cancellation measures synchronous cleanup only.")
                        .foregroundStyle(.secondary)
                    Text("Failure counts cover model-provider, narration and response-validation failures after sending. Microphone, renderer and storage failures are not included in these counts.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Refresh measurements", action: refreshDiagnostics)
                        Button("Copy measurements") {
                            guard let diagnosticsJSON else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(diagnosticsJSON, forType: .string)
                        }.disabled(diagnosticsJSON == nil)
                    }.buttonStyle(.borderless)
                    if let diagnosticsJSON {
                        Text(diagnosticsJSON).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 6)
            }
        }.font(.caption).padding(12).background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: 12))
    }
    private func refreshDiagnostics() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        diagnosticsJSON = (try? encoder.encode(controller.diagnosticsReport()))
            .map { String(decoding: $0, as: UTF8.self) }
    }
    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("explanation.notice")
    }
    private var status: String {
        switch controller.microphone.state {
        case .requestingPermission: return "Waiting for your macOS permission"
        case .listening: return "Listening · release to send"
        case .transcribing: return "Transcribing on this Mac"
        case .idle: break
        }
        if controller.isReplaying { return "Playback preview · your saved scene is preserved" }
        return switch controller.phase {
        case .idle: "Ready · microphone off"
        case .loading: "Opening local history"
        case .thinking: "Building an explanation"
        case .preparingSpeech: "Preparing on-device narration"
        case .speaking: "Speaking · visual cues follow playback"
        case .paused: "Paused"
        case .captions: "Captions · advance when ready"
        case .completed: "Complete"
        }
    }
    private var modelDestination: String {
        guard let host = AIConnections.shared.anyLLM.chatURL?.host else { return "Model endpoint is not configured" }
        return AnyLLMEndpointPolicy.isLoopback(host) ? "Model requests stay on this Mac: \(host)" : "Model requests are sent to \(host)"
    }
    private func updateClock() { controller.displayClockActive(visible && controller.wantsDisplayClock) }
    private func cacheSnapshot() { snapshotImage = controller.screenContext.snapshot.flatMap { NSImage(data: $0.jpegData) } }
}
