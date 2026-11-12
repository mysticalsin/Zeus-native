import AppKit
import Observation
import SwiftUI
import ZeusCore

/// License: trial or licensed status, activate a key, seats on this Mac, deactivate to move.
struct LicenseSettings: View {
    let license: LicenseManager
    let drafts: SecretDrafts
    private let server = LicenseServerDraft.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Glass.gap) {
            statusCard
            GlassCard(title: license.isLicensed ? "Change key" : "Activate") {
                GlassRow(title: "License key", note: license.deactivationError == nil ? (license.lastError ?? keyNote) : keyNote) {
                    HStack(spacing: 6) {
                        GlassSecureField(placeholder: "ZEUS1.…", text: Binding(get: { drafts.licenseKey }, set: { drafts.licenseKey = $0 }), width: 210)
                        Button(license.busy ? "Checking" : "Activate") {
                            let key = drafts.licenseKey
                            Task { if await license.activate(key) == nil { drafts.licenseKey = "" } }
                        }
                        .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                        .fixedSize()
                        .disabled(drafts.licenseKey.isEmpty || license.busy)
                    }
                }
            }
            GlassCard(title: "This Mac") {
                GlassRow(title: "Device", note: "A hash of the hardware id, nothing personal. Seats are counted per Mac.") {
                    Text(license.deviceID).font(Glass.font(11.5, .semibold).monospaced()).foregroundStyle(Glass.secondary).textSelection(.enabled)
                }
                if let payload = license.status.payload {
                    GlassDivider()
                    GlassRow(title: "Seat", note: seatNote(payload)) {
                        GlassStatus(ok: license.activation != nil || license.serverURL == nil, text: seatLabel(payload))
                    }
                }
                if license.status.payload != nil || license.deactivationError != nil {
                    GlassDivider()
                    // A partial cleanup still exposes its reason and retry after the key is gone.
                    GlassRow(title: "Deactivate or move to another Mac", note: license.deactivationError ?? "Frees this Mac's seat and removes the key from its Keychain. Activate the same key on the new Mac.") {
                        Button(drafts.confirmDeactivate ? "Press again" : license.deactivationError == nil ? "Deactivate" : "Try again") {
                            if drafts.confirmDeactivate {
                                drafts.confirmDeactivate = false
                                Task { await license.deactivate() }
                            } else {
                                drafts.confirmDeactivate = true
                            }
                        }
                        .buttonStyle(GlassButtonStyle(kind: .danger, compact: true))
                        .disabled(license.busy)
                    }
                }
            }
            GlassCard(title: "License server") {
                GlassRow(title: "Server", note: license.serverURL == nil
                         ? "Not set: keys are checked on this Mac only and nothing goes over the network."
                         : "Claims a seat when you activate and checks once a day for keys that were turned off.") {
                    HStack(spacing: 6) {
                        GlassField(placeholder: "https://licenses.example.com", text: Binding(get: { server.text }, set: { server.text = $0 }), width: 220, onSubmit: { license.setServer(server.text) })
                        Button("Save") { license.setServer(server.text) }
                            .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                            .fixedSize()
                    }
                }
            }
            GlassCard(title: "How ZEUS is sold") {
                Text("Lifetime licenses are yours to keep, annual licenses run a year, and every Mac starts with a \(Trial.days) day free trial. Bring your own AI keys, so there is no subscription for the basics.\(Entitlements.gatingEnabled ? " When a trial or term ends, the notch keeps working and the assistant waits for a key." : " Every feature is unlocked today.")")
                    .font(Glass.caption).foregroundStyle(Glass.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var keyNote: String {
        license.serverURL == nil ? "Paste the key from your receipt email. It is checked on this Mac, offline."
                                 : "Paste the key from your receipt email. It is checked here, then this Mac takes a seat."
    }

    private func seatLabel(_ payload: LicensePayload) -> String {
        if let proof = license.activation { return "Mac \(proof.seat) of \(proof.seats)" }
        if license.activationPending { return "Pending" }
        return payload.seatCount == 1 ? "1 Mac" : "\(payload.seatCount) Macs"
    }

    private func seatNote(_ payload: LicensePayload) -> String {
        if license.activation != nil { return "This Mac holds a seat on the license server." }
        if license.activationPending { return "The server was out of reach. ZEUS claims the seat next time it can." }
        return "This key covers \(payload.seatCount == 1 ? "one Mac" : "\(payload.seatCount) Macs")."
    }

    private static let day = Date.FormatStyle.dateTime.day().month(.abbreviated).year()

    private var statusCard: some View {
        let (title, detail, tint, progress, badge): (String, String, Color, Double, String) = {
            switch license.status {
            case .trial(let left):
                return ("Free trial", "\(left) of \(Trial.days) days left", Glass.accent, Double(left) / Double(Trial.days), "Trial")
            case .trialEnded:
                return ("Trial ended", Entitlements.gatingEnabled ? "The notch keeps working. Activate a license for the assistant." : "Activate a license to keep going", Glass.warn, 0, "Ended")
            case .licensed(let payload, let left):
                let who = payload.name.map { "\($0), \(payload.email)" } ?? payload.email
                guard let left, let end = payload.expiryDate else {
                    return ("ZEUS \(payload.kind.title)", "Licensed to \(who) · never expires", Glass.ok, 1, "Active")
                }
                let span = payload.kind == .trial ? Double(Trial.days) : 365
                return ("ZEUS \(payload.kind.title)", "Licensed to \(who) · \(left) days left, until \(end.formatted(Self.day))", Glass.ok, min(1, Double(left) / span), "Active")
            case .expired(let payload):
                let end = payload.expiryDate.map { " on \($0.formatted(Self.day))" } ?? ""
                return ("\(payload.kind.title) license ended", "It ran out\(end). Renew or activate a new key.", Glass.warn, 0, "Expired")
            case .revoked:
                return ("License turned off", "This key was refunded or replaced. Use the newest key from your email.", Glass.bad, 0, "Off")
            }
        }()
        return GlassCard(title: "Status") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Glass.fillRaised, lineWidth: 5)
                    Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: license.isLicensed ? "checkmark.seal.fill" : "hourglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Glass.title).foregroundStyle(Glass.text)
                    Text(detail).font(Glass.caption).foregroundStyle(Glass.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                GlassStatus(ok: license.isLicensed || { if case .trial = license.status { true } else { false } }(), text: badge)
            }
        }
    }
}

/// The license server address being typed, saved only on Save or Return.
@MainActor
@Observable
final class LicenseServerDraft {
    static let shared = LicenseServerDraft()
    var text = UserDefaults.standard.string(forKey: "license.server") ?? ""
}
