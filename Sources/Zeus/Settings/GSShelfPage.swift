import SwiftUI
import ZeusCore

/// The Fling card speaks whether it is on, who can see this Mac, and where arrivals go. It does not turn Fling on.
enum FlingVoice {
    static var speakFling: () -> Void = {}
    /// The Receiving card speaks which arrival switches are on. It does not turn Fling on.
    static var speakReceive: () -> Void = {}
}

/// Flick sensitivity speaks Low, Normal, or High. It does not send a file.
enum FlickSetupVoice {
    static var speakFlick: () -> Void = {}
}

/// Settings › Shelf: the Fling switch, who can see this Mac, where arrivals go, and the paired Macs. Every row is a
/// catalog row (`scripts/gen-settings-catalog.py`); Fling does nothing until the first switch is on.
@MainActor
struct ShelfSettingsPage: View {
    private var store: SettingsStore { .shared }
    private var fling: FlingService? { FlingService.current }

    var body: some View {
        GSPageHeading(section: .shelf, subtitle: "Send files to nearby Macs from the Shelf.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Fling") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how Fling is set") { FlingVoice.speakFling() }
            }
            GSToggleRow(symbol: "paperplane", title: "Send and receive with nearby Macs",
                        text: "Drag files from the Shelf onto a nearby Mac running Zeus. Off until you turn it on. Turning it on makes macOS ask once for Local Network access.",
                        isOn: store.boolBinding("fling.enabled"))
            if fling?.localNetworkDenied == true {
                GSDivider()
                GSRow(symbol: "network.slash", title: "Local Network is off for Zeus",
                      text: "macOS is blocking Zeus from finding nearby Macs. Turn Zeus on in System Settings, Privacy and Security, Local Network.") {
                    Button("Open System Settings") { NSWorkspace.shared.open(FlingService.localNetworkSettingsURL) }
                        .buttonStyle(GSButtonStyle())
                }
            }
            GSDivider()
            GSRow(symbol: "eye", title: "Who can see this Mac",
                  text: "Paired only shows this Mac just to Macs you paired. Off hides it and stops receiving.") {
                GSPopup(selection: store.stringBinding("fling.visibility"),
                        options: SettingsCatalog.option("fling.visibility")?.choices ?? [], label: "Who can see this Mac")
            }
            GSDivider()
            GSRow(symbol: "character.cursor.ibeam", title: "Name shown to nearby Macs",
                  text: "Leave empty to use this Mac's name. A paired Mac keeps the name it had when you paired.") {
                GSTextInput(text: store.stringBinding("fling.deviceName"), placeholder: "This Mac's name", label: "Name shown to nearby Macs")
            }
        }
        GSCard("Receiving") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how Fling receiving is set") { FlingVoice.speakReceive() }
            }
            GSToggleRow(symbol: "checkmark.circle", title: "Accept from paired Macs without asking",
                        text: "A Mac that is not paired is never accepted this way.", isOn: store.boolBinding("fling.autoAcceptPaired"))
            GSDivider()
            GSToggleRow(symbol: "moon.zzz", title: "Receive while the notch is closed",
                        text: "Keeps receiving from paired Macs when the notch is not open.", isOn: store.boolBinding("fling.receiveInBackground"))
            GSDivider()
            GSRow(symbol: "folder", title: "Where arrivals go",
                  text: "Downloads/Fling keeps them as files. Clipboard copies them so you can paste in Finder.") {
                GSPopup(selection: store.stringBinding("fling.saveMode"),
                        options: SettingsCatalog.option("fling.saveMode")?.choices ?? [], label: "Where arrivals go")
            }
            GSDivider()
            GSToggleRow(symbol: "link", title: "Open received links in the browser",
                        text: "Only http and https links from a paired Mac.", isOn: store.boolBinding("fling.openLinks"))
            GSDivider()
            GSToggleRow(symbol: "doc.on.doc", title: "Show arrivals as floating papers",
                        text: "Each arrival floats on screen. Closing one never removes it from the Shelf.", isOn: store.boolBinding("fling.papers"))
            GSDivider()
            GSToggleRow(symbol: "bolt.horizontal", title: "Glow when a Fling arrives",
                        text: "A short light on the notch and a cue.", isOn: store.boolBinding("lights.fling"))
        }
        GSCard("Sending") {
            GSRow(symbol: "hand.point.up.left", title: "Flick sensitivity",
                  text: "How fast a drag must be to count as a flick toward a nearby Mac.") {
                HStack(spacing: 8) {
                    GSPopup(selection: store.stringBinding("fling.flickSensitivity"),
                            options: SettingsCatalog.option("fling.flickSensitivity")?.choices ?? [], label: "Flick sensitivity")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the flick sensitivity") { FlickSetupVoice.speakFlick() }
                }
            }
            GSInfo(text: "Zeus never sends on its own. A send needs a click, a drop or a flick from you.")
        }
        GSCard("Paired Macs") {
            let paired = fling?.pairedMacs ?? []
            if paired.isEmpty {
                GSEmptyState(symbol: "laptopcomputer.and.iphone", title: "No paired Macs yet",
                             text: "Pair from Nearby on the Shelf. Both Macs show the same six digits; check they match, then accept.")
            } else {
                ForEach(Array(paired.enumerated()), id: \.element.id) { index, mac in
                    if index > 0 { GSDivider() }
                    GSRow(symbol: "laptopcomputer", title: mac.name, text: "Paired. Last seen \(Self.lastSeen(mac.lastSeen)).") {
                        Button("Remove") { _ = fling?.removePairedMac(id: mac.id) }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Remove \(mac.name)")
                    }
                }
                GSInfo(text: "Remove deletes the key from the Keychain. That Mac must pair again before it can send.")
            }
        }
    }

    static func lastSeen(_ date: Date, now: Date = Date()) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }
}
