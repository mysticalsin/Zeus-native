import AppKit
import AVFoundation
import IOKit.pwr_mgt
import SwiftUI
import ZeusCore

/// Runs the notch teleprompter: countdown, scrolling, voice follow from the mic level,
/// and keeping the notch out of screen shares and screenshots while you read.
@MainActor
final class TeleprompterController {
    private let topBar: TopBarModel
    private var engine: AVAudioEngine?
    private var timer: Timer?
    private var lastTick = Date()
    private var editor: NSWindow?
    /// Hides the notch window from screen capture while true.
    var setPrivate: (Bool) -> Void = { _ in }

    init(topBar: TopBarModel) { self.topBar = topBar }

    func start() {
        topBar.startPrompter = { [weak self] in self?.begin() }
        topBar.stopPrompter = { [weak self] in self?.end() }
        topBar.editScript = { [weak self] in self?.openEditor() }
        topBar.setPrompterVoice = { [weak self] on in self?.setVoice(on) }
    }

    func begin() {
        guard !topBar.prompterActive else { return }
        topBar.prompterNotice = nil
        topBar.restoreSavedVoiceFollow()
        topBar.roll.start()
        setPrivate(true)
        if topBar.roll.voiceFollow { startMic() }
        lastTick = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func end() {
        timer?.invalidate()
        timer = nil
        stopMic()
        topBar.roll.stop()
        topBar.prompterLevel = 0
        setPrivate(false)
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.2)
        lastTick = now
        let maxOffset = max(0, topBar.prompterContentHeight - TopBarModel.prompterReadingLine - 24)
        topBar.roll.tick(dt, at: now, hovered: topBar.prompterHovered, maxOffset: maxOffset)
    }

    private func setVoice(_ on: Bool) {
        topBar.roll.voiceFollow = on
        guard topBar.prompterActive else { return }
        on ? startMic() : stopMic()
    }

    // MARK: Mic level (no speech recognition, nothing recorded or stored)

    private func startMic() {
        guard engine == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            // Asked only in setup or Settings > Permissions, never mid-show.
            voiceUnavailable()
            return
        default:
            voiceUnavailable()
            return
        }
        // No input device (a Mac mini with nothing plugged in) makes the input node's format invalid, and
        // installTap on it raises an Objective-C exception that Swift cannot catch.
        guard AVCaptureDevice.default(for: .audio) != nil else {
            voiceUnavailable()
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            voiceUnavailable()
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let level = Double(min(max((sqrt(sum / Float(buffer.frameLength)) - 0.008) * 10.2, 0), 1))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.topBar.prompterLevel = level
                    self.topBar.roll.hear(level: level)
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
            voiceUnavailable()
        }
    }

    private func stopMic() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func voiceUnavailable() {
        topBar.fallBackFromVoiceFollow()
        topBar.prompterNotice = "Mic is off, so the script scrolls at a steady pace."
    }

    // MARK: Editor

    private func openEditor() {
        if let editor {
            editor.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Teleprompter Script"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScriptEditorView(topBar: topBar))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        editor = window
    }
}

private struct ScriptEditorView: View {
    let topBar: TopBarModel

    var body: some View {
        let script = PrompterScript(topBar.script)
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: Binding(get: { topBar.script }, set: { topBar.script = $0 }))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Start a line with # to make a cue you can jump to. Blank lines split paragraphs.")
                Spacer()
                Text("\(script.wordCount) words · about \(PrompterTiming.minutes(script.readingTime()))")
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 420, minHeight: 320)
    }
}

enum PrompterTiming {
    static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(max(1, Int(seconds.rounded()))) s" : "\(Int((seconds / 60).rounded())) min"
    }
}

/// Keeps the display awake while on (Home strip cup). Not saved, so the Mac never stays awake by surprise after a restart.
@MainActor
final class KeepAwake {
    /// display keeps the screen on; system only blocks idle sleep (the screen can still lock).
    enum Kind { case display, system }
    private let kind: Kind
    private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false

    init(kind: Kind = .display) { self.kind = kind }

    func set(_ on: Bool) {
        if on, !isOn {
            var id = IOPMAssertionID(0)
            let type = kind == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
            let result = IOPMAssertionCreateWithName(type as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), "ZEUS keep awake" as CFString, &id)
            if result == kIOReturnSuccess { assertion = id; isOn = true }
        } else if !on, isOn {
            IOPMAssertionRelease(assertion)
            isOn = false
        }
    }
}
