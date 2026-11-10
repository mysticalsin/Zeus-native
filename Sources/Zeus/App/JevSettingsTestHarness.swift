#if DEBUG
import AppKit
import SwiftUI
import ZeusCore

/// A narrowly scoped window for visually exercising the real Engine page without AppDelegate.
/// The page receives an in-memory, credential-free center and a fresh, non-persistent draft state.
@MainActor
enum JevSettingsTestHarness {
    private static var controller: Controller?

    static func show(in app: NSApplication) {
        let center = IntelligenceCenter.isolatedSettingsTestCenter()
        let page = EnginePageState()
        let root = JevSettingsTestRoot(center: center, page: page)
        let controller = Controller(root: root)
        self.controller = controller
        app.setActivationPolicy(.regular)
        controller.show()
        app.activate(ignoringOtherApps: true)
    }

    private struct JevSettingsTestRoot: View {
        let center: IntelligenceCenter
        let page: EnginePageState

        var body: some View {
            ScrollView {
                EnginePage(center: center, page: page, testMode: true)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 980, height: 850)
            .background(GS.window)
            .preferredColorScheme(.dark)
        }
    }

    @MainActor
    private final class Controller: NSObject, NSWindowDelegate {
        private let root: JevSettingsTestRoot
        private var window: NSWindow?

        init(root: JevSettingsTestRoot) { self.root = root }

        func show() {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 850),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "ZEUS Jev Settings — TEST MODE"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: root)
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }

        func windowWillClose(_ notification: Notification) {
            NSApp.terminate(nil)
        }
    }
}
#endif
