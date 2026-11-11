import AppKit
import Testing
@testable import Zeus

/// Direct owned native events and inert callbacks; no microphone or permission API.
@MainActor @Suite("Explanation push-to-talk control", .serialized)
struct ExplanationTalkButtonTests {
    private enum Intent: Equatable {
        case begin(UUID), finish(UUID), cancel(UUID)
    }
    @MainActor private final class Fixture {
        let control = ExplanationTalkControl()
        var currentID: UUID?
        var events: [Intent] = []
        func configure(listening: Bool = false, enabled: Bool = true) {
            control.configure(attemptID: currentID, isListening: listening, isEnabled: enabled,
                begin: { [self] in
                    let id = UUID(); currentID = id; events.append(.begin(id)); return id
                }, finish: { [self] id in
                    events.append(.finish(id)); if currentID == id { currentID = nil }
                }, cancel: { [self] id in
                    events.append(.cancel(id)); if currentID == id { currentID = nil }
                })
        }
    }
    private func key(_ type: NSEvent.EventType, code: UInt16 = 49, repeating: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeating, keyCode: code))
    }
    private func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }

    @Test func mouseAndKeyboardHoldEmitOneBeginAndOneFinishWithoutRepeatStarts() throws {
        _ = NSApplication.shared
        let fixture = Fixture(), control = fixture.control
        defer { control.dispose() }
        fixture.configure()
        control.mouseDown(with: try mouse(.leftMouseDown))
        let mouseID = try #require(fixture.currentID)
        #expect(fixture.events == [.begin(mouseID)] && control.title == "Keep holding")
        control.mouseUp(with: try mouse(.leftMouseUp)); control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(fixture.events == [.begin(mouseID), .finish(mouseID)])
        control.keyDown(with: try key(.keyDown)); control.keyDown(with: try key(.keyDown, repeating: true))
        let keyboardID = try #require(fixture.currentID)
        control.keyDown(with: try key(.keyDown)); control.keyUp(with: try key(.keyUp)); control.keyUp(with: try key(.keyUp))
        #expect(fixture.events == [.begin(mouseID), .finish(mouseID), .begin(keyboardID), .finish(keyboardID)])
    }

    @Test func accessibilityToggleAndExternalListeningNeverDuplicateAStart() throws {
        _ = NSApplication.shared
        let fixture = Fixture(), control = fixture.control
        defer { control.dispose() }
        fixture.configure()
        #expect(control.accessibilityPerformPress())
        let id = try #require(fixture.currentID)
        #expect(control.accessibilityPerformPress())
        #expect(fixture.events == [.begin(id), .finish(id)])
        let external = UUID(); fixture.currentID = external; fixture.configure(listening: true)
        #expect(control.accessibilityPerformPress())
        #expect(fixture.events == [.begin(id), .finish(id), .finish(external)])
        let starting = UUID(); fixture.currentID = starting; fixture.configure()
        control.mouseDown(with: try mouse(.leftMouseDown)); control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(fixture.events.last == .finish(starting))
        #expect(fixture.events.count == 4)
    }

    @Test func escapeDisableWindowLossAndRemovalCancelAndIgnoreLateRelease() throws {
        _ = NSApplication.shared
        let fixture = Fixture(), control = fixture.control
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 180, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = control
        defer { control.dispose(); window.contentView = nil; window.close() }
        fixture.configure(); control.keyDown(with: try key(.keyDown))
        let first = try #require(fixture.currentID)
        control.keyDown(with: try key(.keyDown, code: 53)); control.keyUp(with: try key(.keyUp))
        #expect(fixture.events == [.begin(first), .cancel(first)])
        control.mouseDown(with: try mouse(.leftMouseDown))
        let second = try #require(fixture.currentID)
        fixture.configure(enabled: false); control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(fixture.events == [.begin(first), .cancel(first), .begin(second), .cancel(second)])
        #expect(!control.accessibilityPerformPress())
        fixture.configure(); control.keyDown(with: try key(.keyDown))
        let third = try #require(fixture.currentID)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        control.keyUp(with: try key(.keyUp))
        #expect(fixture.events.suffix(2) == [.begin(third), .cancel(third)])
        control.mouseDown(with: try mouse(.leftMouseDown))
        let fourth = try #require(fixture.currentID)
        window.contentView = nil; control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(fixture.events.suffix(2) == [.begin(fourth), .cancel(fourth)] && fixture.events.count == 8)
        control.dispose(); control.dispose()
        #expect(control.disposed && !control.accessibilityPerformPress())
    }

    @Test func failedStartingAttemptThenReplacementIgnoresOldMouseAndKeyboardReleases() throws {
        _ = NSApplication.shared
        let fixture = Fixture(), control = fixture.control
        defer { control.dispose() }
        fixture.configure(); control.mouseDown(with: try mouse(.leftMouseDown))
        let failed = try #require(fixture.currentID)
        // Failure before the listening state was ever reported.
        fixture.currentID = nil; fixture.configure()
        let external = UUID(); fixture.currentID = external; fixture.configure(listening: true)
        control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(fixture.events == [.begin(failed)] && fixture.currentID == external)
        #expect(control.accessibilityPerformPress())
        #expect(fixture.events == [.begin(failed), .finish(external)])
        fixture.configure(); control.keyDown(with: try key(.keyDown))
        let oldKeyboard = try #require(fixture.currentID)
        // Replacement can arrive in one update without an intermediate nil.
        let replacement = UUID(); fixture.currentID = replacement; fixture.configure(listening: true)
        control.keyUp(with: try key(.keyUp))
        #expect(fixture.events.last == .begin(oldKeyboard) && fixture.currentID == replacement)
        #expect(control.accessibilityPerformPress())
        #expect(fixture.events.last == .finish(replacement) && fixture.events.count == 4)
    }

    @Test func holdKeepsItsCallbacksAndRejectedStartNeverCreatesAReleaseAction() throws {
        _ = NSApplication.shared
        let control = ExplanationTalkControl(), id = UUID()
        defer { control.dispose() }
        var original: [UUID] = [], rebound: [UUID] = []
        control.configure(attemptID: nil, isListening: false, isEnabled: true,
            begin: { id }, finish: { original.append($0) }, cancel: { original.append($0) })
        control.mouseDown(with: try mouse(.leftMouseDown))
        control.configure(attemptID: id, isListening: true, isEnabled: true,
            begin: { nil }, finish: { rebound.append($0) }, cancel: { rebound.append($0) })
        control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(original == [id] && rebound.isEmpty)
        control.configure(attemptID: nil, isListening: false, isEnabled: true,
            begin: { nil }, finish: { rebound.append($0) }, cancel: { rebound.append($0) })
        control.mouseDown(with: try mouse(.leftMouseDown)); control.mouseUp(with: try mouse(.leftMouseUp))
        #expect(original == [id] && rebound.isEmpty && control.title == "Hold to talk")
    }

    @Test func externalStartupCancelsOnWindowLossAndDisableButCompletedCaptureDoesNot() throws {
        _ = NSApplication.shared
        let fixture = Fixture(), control = fixture.control
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 180, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = control
        defer { control.dispose(); window.contentView = nil; window.close() }
        let starting = UUID(); fixture.currentID = starting; fixture.configure()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(fixture.events == [.cancel(starting)])
        let another = UUID(); fixture.currentID = another; fixture.configure(enabled: false)
        #expect(fixture.events == [.cancel(starting), .cancel(another)])
        fixture.configure(); control.mouseDown(with: try mouse(.leftMouseDown))
        let captured = try #require(fixture.currentID)
        control.mouseUp(with: try mouse(.leftMouseUp))
        // Pane withdraws the capture ID when transcription starts. Disabling the
        // input control must not cancel that completed capture's transcription.
        fixture.configure(enabled: false)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(fixture.events == [.cancel(starting), .cancel(another), .begin(captured), .finish(captured)])
    }
}
