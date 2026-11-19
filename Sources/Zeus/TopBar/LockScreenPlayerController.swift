import AppKit
import Foundation
import ZeusCore
#if canImport(Darwin)
import Darwin
#endif

/// Shows the current player on a private window-server space above the lock screen.
/// The panel does not activate and ignores input. A missing symbol or a failed call leaves it unavailable.
@MainActor
final class LockScreenPlayerController {
    private let model: TopBarModel
    private let spaceAvailable: () -> Bool
    private let createSpace: () -> Bool
    private let dismissSpace: () -> Void

    init(model: TopBarModel,
         spaceAvailable: @escaping () -> Bool = { LockScreenSpace.symbolsPresent() },
         createSpace: (() -> Bool)? = nil,
         dismissSpace: @escaping () -> Void = { LockScreenSpace.dismiss() }) {
        self.model = model
        self.spaceAvailable = spaceAvailable
        self.createSpace = createSpace ?? { LockScreenSpace.present(title: model.nowPlaying?.title ?? "Nothing playing",
                                                                     artist: model.nowPlaying?.artist ?? "") }
        self.dismissSpace = dismissSpace
    }

    func setEnabled(_ on: Bool) {
        guard on else {
            dismissSpace()
            model.lockScreenPlayer = .off
            return
        }
        let space = spaceAvailable()
        let shown = space && createSpace()
        if !shown { dismissSpace() }
        model.lockScreenPlayer = LockScreenPlayerGate.result(enabled: true, spaceAvailable: space, inputIgnored: shown)
    }

    func stop() { setEnabled(false) }
}

enum LockScreenPlayerText {
    static func line(_ status: LockScreenPlayerStatus) -> String {
        switch status {
        case .off: ""
        case .unavailable: "Lock screen player unavailable"
        case .shown: "On the lock screen"
        }
    }
}

@MainActor
enum LockScreenSpace {
    private static var session: Session?

    private struct Session {
        var panel: NSPanel
        var connection: UInt32
        var space: UInt64
        var destroy: @convention(c) (UInt32, UInt64) -> Void
    }

    private struct API {
        var connection: @convention(c) () -> UInt32
        var create: @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
        var destroy: @convention(c) (UInt32, UInt64) -> Void
        var setLevel: @convention(c) (UInt32, UInt64, Int32) -> Void
        var addWindows: @convention(c) (UInt32, CFArray, CFArray) -> Void
    }

    static func symbolsPresent() -> Bool { loadAPI() != nil }

    static func dismiss() {
        guard let session else { return }
        session.panel.orderOut(nil)
        session.panel.close()
        session.destroy(session.connection, session.space)
        self.session = nil
    }

    static func present(title: String, artist: String) -> Bool {
        dismiss()
        guard let api = loadAPI() else { return false }
        let panel = makePanel(title: title, artist: artist)
        let connection = api.connection()
        guard connection != 0 else { panel.close(); return false }
        let space = api.create(connection, 1, nil)
        guard space != 0 else { panel.close(); return false }
        // Public shield level, one step above the lock cover. There is no lock-screen case on CGWindowLevelKey.
        let level = Int32(CGShieldingWindowLevel()) + 1
        api.setLevel(connection, space, level)
        panel.level = NSWindow.Level(rawValue: Int(level))
        panel.orderFrontRegardless()
        guard panel.windowNumber > 0 else {
            api.destroy(connection, space)
            panel.close()
            return false
        }
        let windows = [NSNumber(value: panel.windowNumber)] as CFArray
        let spaces = [NSNumber(value: space)] as CFArray
        api.addWindows(connection, windows, spaces)
        session = Session(panel: panel, connection: connection, space: space, destroy: api.destroy)
        return true
    }

    private static func makePanel(title: String, artist: String) -> NSPanel {
        let panel = LockScreenPlayerPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
                                           styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.82)
        panel.isOpaque = false
        panel.hasShadow = false
        let text = NSTextField(labelWithString: artist.isEmpty ? title : "\(title): \(artist)")
        text.textColor = .white
        text.font = .systemFont(ofSize: 15, weight: .semibold)
        text.frame = NSRect(x: 16, y: 22, width: 328, height: 28)
        text.lineBreakMode = .byTruncatingTail
        panel.contentView?.addSubview(text)
        if let screen = NSScreen.main {
            var frame = panel.frame
            frame.origin.x = screen.frame.midX - frame.width / 2
            frame.origin.y = screen.frame.maxY - frame.height - 28
            panel.setFrame(frame, display: false)
        }
        return panel
    }

    private static func loadAPI() -> API? {
        #if canImport(Darwin)
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            guard let connection = dlsym(handle, "CGSMainConnectionID"),
                  let create = dlsym(handle, "CGSSpaceCreate"),
                  let destroy = dlsym(handle, "CGSSpaceDestroy"),
                  let setLevel = dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
                  let addWindows = dlsym(handle, "CGSAddWindowsToSpaces") else { continue }
            return API(connection: unsafeBitCast(connection, to: (@convention(c) () -> UInt32).self),
                       create: unsafeBitCast(create, to: (@convention(c) (UInt32, Int32, CFDictionary?) -> UInt64).self),
                       destroy: unsafeBitCast(destroy, to: (@convention(c) (UInt32, UInt64) -> Void).self),
                       setLevel: unsafeBitCast(setLevel, to: (@convention(c) (UInt32, UInt64, Int32) -> Void).self),
                       addWindows: unsafeBitCast(addWindows, to: (@convention(c) (UInt32, CFArray, CFArray) -> Void).self))
        }
        return nil
        #else
        return nil
        #endif
    }
}

private final class LockScreenPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
