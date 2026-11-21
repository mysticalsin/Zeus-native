import AppKit

/// Menu-bar app: no Dock icon and no main menu. `Resources/Info.plist` sets `LSUIElement` to match.
enum ZeusActivation {
    static func configure(_ app: NSApplication) {
        app.setActivationPolicy(.accessory)
    }
}
