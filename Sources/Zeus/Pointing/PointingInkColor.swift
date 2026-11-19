import Foundation
import SwiftUI
import ZeusCore

/// The trail colour: the user's own pointer fill colour from System Settings > Accessibility >
/// Display > Pointer, when they changed it. nil means "use the Zeus accent".
@MainActor
enum PointingInkColor {
    static func current() -> Color? {
        let raw = UserDefaults(suiteName: "com.apple.universalaccess")?.dictionary(forKey: "cursorFill")
        let numbers = raw?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        guard let fill = PointerFillColor.parse(numbers) else { return nil }
        return Color(red: fill.red, green: fill.green, blue: fill.blue)
    }
}
