import AppKit
import SwiftUI
import ZeusCore

/// Settings › Beamer: install and open Beamer, see its machines, pause crossing, and decide how
/// Zeus shows it. Beamer (uk.co.kalkman.beamer) shares one keyboard and mouse across Macs and PCs;
/// docs/BEAMER.md says what Zeus can and cannot steer.
@MainActor
struct BeamerSettingsPage: View {
    let context: GSContext
    private var beamer: BeamerModel { .shared }
    private var store: SettingsStore { .shared }

    var body: some View {
        let status = beamer.status
        GSPageHeading(section: .beamer, subtitle: "One keyboard and mouse across your Macs and PCs.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Beamer") {
            GSRow(symbol: "rectangle.connected.to.line.below", title: status.headline,
                  text: status.version.map { "Beamer \($0)" } ?? (status.availability == .notInstalled ? installNote : "Pair machines inside Beamer, once.")) {
                HStack(spacing: 10) {
                    switch status.availability {
                    case .notInstalled:
                        // QA7 round 11 (report-11.md hang): no `beamer.downloadedImage` read
                        // here -- see `installNote` below for why.
                        Button("Install Beamer") { Task { await beamer.install() } }
                            .buttonStyle(GSButtonStyle(prominent: true)).disabled(beamer.busy)
                    case .notRunning:
                        Button("Start Beamer") { Task { await beamer.perform(.start) } }.buttonStyle(GSButtonStyle(prominent: true)).disabled(beamer.busy)
                        Button("Open window") { Task { await beamer.perform(.showWindow) } }.buttonStyle(GSButtonStyle()).disabled(beamer.busy)
                    case .needsPermission, .ready:
                        Button("Machines panel") { Task { await beamer.perform(.showWindow) } }.buttonStyle(GSButtonStyle(prominent: true)).disabled(beamer.busy)
                    }
                }
            }
            if let message = beamer.message { GSInfo(text: message) }
        }
        GSCard("Sharing") {
            GSRow(symbol: status.paused == true ? "play.circle" : "pause.circle", title: status.paused == true ? "Crossing is paused" : "Pause crossing",
                  text: status.availability == .ready ? status.link.summary : "Needs Beamer running and Accessibility for Zeus.") {
                Button(status.paused == true ? "Resume" : "Pause") { Task { await beamer.perform(status.paused == true ? .resume : .pause) } }
                    .buttonStyle(GSButtonStyle()).disabled(status.availability != .ready || beamer.busy)
            }
            GSDivider()
            GSRow(symbol: "house", title: "Bring input back to this Mac", text: "When your keyboard and mouse are on another machine.") {
                Button("Bring back") { Task { await beamer.perform(.returnHome) } }
                    .buttonStyle(GSButtonStyle()).disabled(status.availability != .ready || !status.isCrossed || beamer.busy)
            }
            if status.availability == .needsPermission {
                GSDivider()
                GSRow(symbol: "accessibility", title: "Accessibility", text: "Beamer has no remote control, so Zeus presses its menu bar menu. macOS also asks once to let Zeus control System Events.") {
                    Button("Allow") { context.permissions.request(.accessibility) }.buttonStyle(GSButtonStyle(prominent: true))
                }
            }
        }
        GSCard("Paired machines") {
            if status.machines.isEmpty {
                GSRow(symbol: "display", title: "None yet", text: status.availability == .notInstalled
                      ? "Install Beamer, open it, and pair a Mac or PC with the code it shows." : "Open Beamer and pair a Mac or PC. Pairing happens in Beamer; Zeus never touches it.")
            }
            ForEach(Array(status.machines.enumerated()), id: \.element.id) { index, machine in
                if index > 0 { GSDivider() }
                GSRow(symbol: machine.platform.symbol, title: machine.name,
                      text: "\(machine.platform.title)\(machine.inUse ? "" : " · not in use on this Mac")") {
                    if status.link.machine == machine.name {
                        GSStatus(ok: true, text: status.link == .driving(machine.name) ? "Has your keyboard" : "Driving this Mac")
                    } else if status.availability == .ready, machine.inUse {
                        Button("Switch to") { Task { await beamer.perform(.switchTo(machine.name)) } }.buttonStyle(GSButtonStyle()).disabled(beamer.busy)
                    }
                }
            }
            GSInfo(text: "Beamer pairs Macs, Windows, Linux, iPhone and Android machines. An iPad uses Apple\u{2019}s Universal Control (System Settings \u{203A} Displays), which no app can steer. Zeus shows Continuity for the machines Beamer has.")
        }
        GSCard("Zeus and Beamer") {
            GSToggleRow(symbol: "power", title: "Start Beamer when Zeus starts", text: "Opens it hidden in the menu bar. Beamer\u{2019}s own \u{201C}Start at login\u{201D} switch is in Beamer\u{2019}s settings.", isOn: store.boolBinding("beamer.autoStart"))
            GSDivider()
            GSToggleRow(symbol: "light.max", title: "Light the notch when control crosses", text: "A cue from Zeus when your keyboard and mouse move to another machine, and when they come back. Needs Accessibility to read Beamer.", isOn: store.boolBinding("beamer.cue"))
            GSDivider()
            GSToggleRow(symbol: "rectangle.connected.to.line.below", title: "Show the Continuity tab", text: "A tab in the notch with where your keyboard is, Pause, and a button per machine.",
                        isOn: Binding(get: { context.continuityTabShown() }, set: { context.setContinuityTabShown($0) }))
            GSInfo(text: "Beamer draws its own light at the notch while you cross. It has no switch for that from outside. To let only Zeus show it, open Beamer \u{203A} Crossing and set \u{201C}Show at\u{201D} to the screen edge.")
        }
        .task { beamer.watch(); await beamer.refresh() }
        .onDisappear { beamer.unwatch() }
    }

    // QA7 round 11 (report-11.md): this used to read `beamer.downloadedImage` (lists the real
    // Downloads folder) just to word this label -- a TCC-protected folder's *first* ever listing
    // blocks the caller in `open()` until the user answers a one-time system consent dialog,
    // same bug and same fix as `FolderAccess.status(for:)` above: a passive body read must never
    // be able to trigger that probe. `beamer.install()` (a direct response to the "Install
    // Beamer" tap, a deliberate action) already re-checks `downloadedImage` itself and reports
    // "No Beamer disk image in Downloads" there if it's missing -- no need to also probe here
    // just to pre-word this static instruction.
    private var installNote: String { "Download the Beamer disk image, then tap Install Beamer." }
}
