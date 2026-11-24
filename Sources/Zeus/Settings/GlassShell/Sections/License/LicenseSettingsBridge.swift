import ZeusCore

/// Reads the license the app already stores. It does not open a new store or a new endpoint.
@MainActor
enum LicenseSettingsBridge {
    static func facts(from license: LicenseManager) -> LicenseCardFacts {
        LicenseCardFacts(
            status: license.status,
            storedKey: LicenseKeyDraft(license.storedLicenseKey() ?? ""),
            activationPending: license.activationPending,
            serverNeedsReentry: license.serverNeedsReentry,
            serverConfigured: license.serverURL != nil,
            seatLabel: license.activation.map { "Mac \($0.seat) of \($0.seats)" },
            deactivationError: license.deactivationError,
            notice: license.lastError
        )
    }

    static func publish(phase: LicenseActivationPhase) {
        let value = LicenseStatusRecord.sanitized(phase.rawValue)
        SettingsStore.shared.set(LicenseStatusRecord.activationState.id, value)
    }
}
