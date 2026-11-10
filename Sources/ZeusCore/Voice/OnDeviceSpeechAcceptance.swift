import Foundation

/// Voice capture stays on this Mac when Apple on-device recognition is available (O2).
public enum OnDeviceSpeechPolicy: Equatable, Sendable {
    public static func requiresOnDevice(supportsOnDevice: Bool) -> Bool {
        supportsOnDevice
    }
}

/// Tracks live partial text for the HUD (O2).
public struct LiveWordsHUD: Equatable, Sendable {
    public private(set) var visible = ""
    public private(set) var updates = 0

    public init() {}

    public mutating func applyPartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != visible else { return }
        visible = trimmed
        updates += 1
    }

    public mutating func clear() {
        visible = ""
    }
}

/// Counts tool actions that would run on a partial; revised partials must not add actions (O2).
public struct PartialActionRecorder: Equatable, Sendable {
    public private(set) var actions = 0
    private var gate = PartialActionGate()

    public init() {}

    public mutating func observePartial(_ text: String) {
        gate.observePartial(text)
    }

    public mutating func tryAct(on text: String) {
        guard gate.mayActOnPartial(text) else { return }
        actions += 1
    }

    public mutating func finalize(_ text: String) {
        gate.finalize(text)
    }
}

public enum OnDeviceSpeechAcceptance {
    public static func report() -> (text: String, passed: Bool) {
        var problems: [String] = []

        var hud = LiveWordsHUD()
        hud.applyPartial("open")
        hud.applyPartial("open slack")
        if hud.visible != "open slack" || hud.updates < 2 { problems.append("hud") }
        hud.clear()

        var recorder = PartialActionRecorder()
        recorder.observePartial("open slack")
        recorder.tryAct(on: "open slack")
        recorder.observePartial("open calculator")
        recorder.tryAct(on: "open slack")
        if recorder.actions != 1 { problems.append("partial") }
        recorder.finalize("open calculator")
        recorder.tryAct(on: "open calculator")
        if recorder.actions != 2 { problems.append("finalize") }

        if !OnDeviceSpeechPolicy.requiresOnDevice(supportsOnDevice: true) { problems.append("ondevice") }
        if OnDeviceSpeechPolicy.requiresOnDevice(supportsOnDevice: false) { problems.append("offdevice") }

        let text = problems.isEmpty
            ? "PASS hud=stream partial=0-revised-actions ondevice=required"
            : "FAIL \(problems.joined(separator: ", "))"
        return (text, problems.isEmpty)
    }
}
