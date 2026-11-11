import SwiftUI
import ZeusCore

/// Settings for command mode (Stage B): double-tap talk key → Zeus drives the Mac.
/// DriveController performs the moves listed in `actions`, preferring Accessibility over the pointer.
struct CommandModeSettingsPage: View {
    @AppStorage(DriveAutonomy.settingsKey) private var autonomy = DriveAutonomy.default.rawValue

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Command mode") {
                GlassRow(title: "How to talk", note: Preferences.shared.talkKeyHint) {
                    GlassStatus(ok: true, text: Preferences.shared.pushToTalk.title)
                }
                GlassDivider()
                GlassRow(title: "When Zeus may drive", note: (DriveAutonomy(rawValue: autonomy) ?? .default).explanation) {
                    Picker("Autonomy", selection: $autonomy) {
                        ForEach(DriveAutonomy.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Theme.accent)
                }
            }
            GlassCard(title: "What Zeus can do") {
                ForEach(Array(Self.actions.enumerated()), id: \.offset) { index, row in
                    if index > 0 { GlassDivider() }
                    GlassRow(title: row.0, note: row.1, icon: (row.2, Theme.accent)) {
                        GlassStatus(ok: true, text: "Live")
                    }
                }
            }
            GlassCard(title: "Show me") {
                GlassRow(title: "Hold left Command and circle", note: "Marks a spot; Zeus answers about what you circled.") {
                    GlassStatus(ok: true, text: "Annotation live")
                }
            }
        }
    }

    /// Every move DriveController runs. Most act through Accessibility without moving the pointer.
    private static let actions: [(String, String, String)] = [
        ("Read the window", "Lists the front window's controls so steps aim at them directly.", "list.bullet.rectangle"),
        ("Open an app", "Finds it by name or bundle id and brings it forward.", "app.fill"),
        ("Switch windows", "Brings an open app forward, and one of its windows by title.", "macwindow.on.rectangle"),
        ("Move the pointer", "Glides to a labelled control or a point on screen.", "cursorarrow.click"),
        ("Click or double-click", "Accessibility press without moving the pointer; a visible click only when there's none.", "hand.tap.fill"),
        ("Type text", "Focuses a field when needed, then types, so Undo takes it back.", "keyboard"),
        ("Fill a field", "Puts text straight into a field. Never into a password field.", "character.cursor.ibeam"),
        ("Choose from a menu", "Picks an option in a pop-up button, menu, tab or list.", "filemenu.and.selection"),
        ("Turn on or off", "Sets a checkbox or switch; leaves it alone when it's already set.", "switch.2"),
        ("Expand", "Opens disclosure triangles, outline rows and menus.", "chevron.down.circle"),
        ("Press a shortcut", "Sends a key combo (copy, paste, undo…).", "command"),
        ("Scroll", "Scrolls the focused view by line count.", "arrow.up.arrow.down"),
        ("Wait", "Pauses between steps so the UI can settle.", "clock"),
        ("Clipboard", "Reads it for a later step, or replaces it. Replacing always asks.", "doc.on.clipboard"),
        ("Point and click", "Bolt trail follows the cursor whenever a step has to move it.", "scope"),
    ]
}
