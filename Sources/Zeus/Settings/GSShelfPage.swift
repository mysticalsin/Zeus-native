import SwiftUI

/// Settings › Shelf. The drop target lives on the notch; this page only names it.
struct ShelfSettingsPage: View {
    var body: some View {
        GSPageHeading(section: .shelf, subtitle: "Drop files on the Shelf in the notch, then drag them out again.")
    }
}
