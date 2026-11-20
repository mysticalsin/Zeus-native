import Foundation

public struct LicenseCardMotion: Equatable, Sendable {
    public var duration: Double
    public var pressScale: Double

    public init(reduceMotion: Bool) {
        duration = reduceMotion ? 0 : MotionTokens.crossfadeDuration
        pressScale = reduceMotion ? 1 : MotionTokens.pressScale
    }
}

public struct LicensePreviewTile: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var badge: String
    public var title: String
    public var detail: String
    public var progress: Double
    public var accessibilityLabel: String

    public var description: String { "LicensePreviewTile(\(badge))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["badge": badge], displayStyle: .struct) }
}

public struct LicenseCardControl: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var accessibilityValue: String
    public var event: LicenseActivationEvent?
    public var enabled: Bool
    public var keyboardReachable: Bool
    public var revealsKey: Bool

    public var description: String { "LicenseCardControl(\(id))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id], displayStyle: .struct) }
}

public struct LicenseCardPresentation: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var phase: LicenseActivationPhase
    public var preview: LicensePreviewTile
    public var controls: [LicenseCardControl]
    public var motion: LicenseCardMotion
    public var panelPadding: Double
    public var cardSpacing: Double
    public var rowHeight: Double
    public var helperLine: Double
    public var loading: Bool
    public var empty: Bool
    public var errorMessage: String?

    public var description: String {
        "LicenseCardPresentation(phase: \(phase.rawValue), controls: \(controls.map(\.id).joined(separator: ",")))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["phase": phase.rawValue], displayStyle: .struct) }

    public static func make(_ state: LicenseActivationState) -> LicenseCardPresentation {
        let secrets = [state.draft.reveal(), state.draft.normalized, state.facts.storedKey.reveal(), state.facts.storedKey.normalized]
        let scrub: (String) -> String = { LicenseKeyPrivacy.scrub($0, secrets: secrets) }
        let preview = tile(for: state, scrub: scrub)
        let loading = state.phase == .activating || state.phase == .releasing
        let controls = rows(for: state, scrub: scrub, loading: loading)
        let empty = state.phase == .unlicensed && state.draft.isEmpty && state.facts.storedKey.isEmpty && state.failure == nil && !loading
        return LicenseCardPresentation(
            phase: state.phase,
            preview: preview,
            controls: controls,
            motion: LicenseCardMotion(reduceMotion: state.reduceMotion),
            panelPadding: GlassSettingsMetrics.panelPadding,
            cardSpacing: GlassSettingsMetrics.cardSpacing,
            rowHeight: GlassSettingsMetrics.controlRow,
            helperLine: GlassSettingsMetrics.helperLine,
            loading: loading,
            empty: empty,
            errorMessage: state.failure.map { scrub($0.message) }
        )
    }
}

private extension LicenseCardPresentation {
    static func tile(for state: LicenseActivationState, scrub: (String) -> String) -> LicensePreviewTile {
        let (badge, title, detail, progress) = copy(for: state)
        let safeDetail = scrub(detail)
        return LicensePreviewTile(
            badge: badge,
            title: scrub(title),
            detail: safeDetail,
            progress: progress,
            accessibilityLabel: scrub("\(badge). \(title). \(safeDetail)")
        )
    }

    static func copy(for state: LicenseActivationState) -> (String, String, String, Double) {
        switch state.phase {
        case .activating:
            return ("Checking", "Checking this key", "Zeus is checking this key with the license server.", underlyingProgress(state.facts.status))
        case .releasing:
            return ("Releasing", "Releasing this Mac", "Zeus is freeing this Mac. The key stays until the release finishes.", underlyingProgress(state.facts.status))
        case .error:
            let message = state.failure?.message ?? "The license change did not finish."
            return ("Error", "License needs attention", message, 0)
        case .unlicensed, .trial, .active:
            return restingCopy(state.facts)
        }
    }

    static func restingCopy(_ facts: LicenseCardFacts) -> (String, String, String, Double) {
        switch facts.status {
        case .trial(let days):
            let title = days <= 1 ? "Trial · last day" : "Trial · \(days) days left"
            let detail = "\(days) of \(Trial.days) days left. \(LicenseActivationMachine.purchaseNote)"
            return ("Trial", title, detail, Double(days) / Double(Trial.days))
        case .licensed(let payload, let daysLeft):
            let title: String
            let progress: Double
            if let daysLeft {
                title = daysLeft <= 1 ? "Zeus is yours · last day" : "Zeus is yours · \(daysLeft) days left"
                progress = min(1, Double(daysLeft) / 365)
            } else {
                title = "Zeus is yours."
                progress = 1
            }
            var detail = "Licensed to \(holder(payload)). Your license is kept across updates."
            if let seat = facts.seatLabel, !seat.isEmpty { detail += " \(seat)." }
            if facts.activationPending { detail += " The seat will be claimed when the license server is reachable." }
            return ("Active", title, detail, progress)
        case .trialEnded:
            return ("Ended", "Your free trial has ended.", "Activate a license key, or use a one-time purchase. Two Macs.", 0)
        case .expired:
            return ("Expired", "This license has expired.", "Renew or activate a new key. The old key stays masked.", 0)
        case .revoked:
            return ("Off", "This license was turned off.", "Use the newest key from your receipt. This one no longer activates this Mac.", 0)
        }
    }

    static func underlyingProgress(_ status: LicenseStatus) -> Double {
        switch status {
        case .trial(let days): Double(days) / Double(Trial.days)
        case .licensed(_, let days?): min(1, Double(days) / 365)
        case .licensed: 1
        case .trialEnded, .expired, .revoked: 0
        }
    }

    static func holder(_ payload: LicensePayload) -> String {
        if let name = payload.name, !name.isEmpty { return "\(name), \(payload.email)" }
        return payload.email
    }

    static func rows(for state: LicenseActivationState, scrub: (String) -> String, loading: Bool) -> [LicenseCardControl] {
        var controls: [LicenseCardControl] = []
        let preview = tile(for: state, scrub: scrub)
        controls.append(control(id: "glass.license.status", title: preview.title, helper: preview.detail, label: preview.accessibilityLabel, value: preview.badge, event: nil, enabled: !loading, revealsKey: false))
        if showsPurchase(state) {
            controls.append(control(id: "glass.license.purchase", title: "Purchase", helper: LicenseActivationMachine.purchaseNote, label: "Purchase. \(LicenseActivationMachine.purchaseNote)", value: "", event: .purchase, enabled: !loading, revealsKey: false))
        }
        if showsDraft(state) {
            let revealed = state.revealed && state.facts.storedKey.isEmpty
            let value = revealed ? state.draft.reveal() : state.draft.masked
            let helper = keyHelper(state, scrub: scrub, fallback: "Paste the key from your receipt. It is checked on this Mac.")
            let fieldID = showsStoredKey(state) ? "glass.license.draft" : "glass.license.key"
            controls.append(control(id: fieldID, title: "License key", helper: helper, label: "License key", value: value, event: nil, enabled: !loading, revealsKey: revealed))
            let ready = !state.draft.isEmpty && !loading
            controls.append(control(id: "glass.license.activate", title: loading && state.phase == .activating ? "Checking" : "Activate this Mac", helper: "Checks the key and activates this Mac.", label: "Activate this Mac", value: "", event: .activate, enabled: ready, revealsKey: false))
        }
        if showsStoredKey(state) {
            let value = state.revealed ? state.facts.storedKey.reveal() : state.facts.storedKey.masked
            let helper = keyHelper(state, scrub: scrub, fallback: "The license key on this Mac. It stays hidden until you reveal it.")
            controls.append(control(id: "glass.license.key", title: "License key", helper: helper, label: "License key", value: value, event: nil, enabled: !loading, revealsKey: state.revealed))
            controls.append(control(id: "glass.license.reveal", title: state.revealed ? "Hide key" : "Reveal key", helper: "Shows the license key on this Mac. Copy stays a separate action.", label: state.revealed ? "Hide license key" : "Reveal license key", value: "", event: state.revealed ? .conceal : .reveal, enabled: !loading, revealsKey: false))
            controls.append(control(id: "glass.license.copy", title: "Copy key", helper: "Copies the license key when you press Copy.", label: "Copy license key", value: "", event: .copyKey, enabled: !loading, revealsKey: false))
            let releaseTitle = state.releaseArmed ? "Release this Mac" : "Release this Mac"
            let releaseHelper = state.releaseArmed
                ? "Press again to free this Mac. The key stays on this Mac until the release finishes."
                : "Frees this Mac's seat and removes the key from this Mac."
            controls.append(control(id: "glass.license.release", title: releaseTitle, helper: releaseHelper, label: "Release this Mac", value: "", event: state.releaseArmed ? .confirmRelease : .armRelease, enabled: !loading, revealsKey: false))
            if state.releaseArmed {
                controls.append(control(id: "glass.license.releaseCancel", title: "Cancel", helper: "Keeps the license on this Mac.", label: "Cancel release", value: "", event: .cancelRelease, enabled: !loading, revealsKey: false))
            }
        }
        if let failure = state.failure {
            let helper = failure.resume == .active ? "This Mac still holds the license." : "You can edit the key and try again."
            controls.append(control(id: "glass.license.error", title: "Couldn't update the license", helper: scrub(helper + " " + failure.message), label: "License error", value: "", event: .dismissError, enabled: !loading, revealsKey: false))
        }
        return controls
    }

    static func showsPurchase(_ state: LicenseActivationState) -> Bool {
        switch state.phase {
        case .trial, .unlicensed: true
        case .error: state.failure?.resume == .trial || state.failure?.resume == .unlicensed
        case .activating, .active, .releasing: false
        }
    }

    static func showsDraft(_ state: LicenseActivationState) -> Bool {
        if state.enteringReplacement { return true }
        switch state.phase {
        case .unlicensed, .trial, .activating: return true
        case .error: return state.failure?.resume != .active
        case .active, .releasing: return false
        }
    }

    static func showsStoredKey(_ state: LicenseActivationState) -> Bool {
        guard !state.facts.storedKey.isEmpty, !state.enteringReplacement, state.phase != .activating else { return false }
        return true
    }

    static func keyHelper(_ state: LicenseActivationState, scrub: (String) -> String, fallback: String) -> String {
        if let notice = state.facts.notice {
            let cleaned = scrub(notice)
            if !LicenseKeyPrivacy.compact(cleaned).isEmpty { return cleaned }
        }
        return fallback
    }

    static func control(id: String, title: String, helper: String, label: String, value: String, event: LicenseActivationEvent?, enabled: Bool, revealsKey: Bool) -> LicenseCardControl {
        LicenseCardControl(id: id, title: title, helper: helper, accessibilityLabel: label, accessibilityValue: value, event: event, enabled: enabled, keyboardReachable: true, revealsKey: revealsKey)
    }
}
