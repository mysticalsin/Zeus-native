import Foundation

public enum LockScreenCopy {
    public static let loading = "Loading lock screen settings."
    public static let empty = "Nothing shows on the lock screen until you turn a control on."
    public static let unavailable = "The lock screen card is not available on this Mac."
    public static let previewPlaying = "Preview. Playing. Read only."
    public static let previewPaused = "Preview. Paused. Read only."
    public static let nothingPlaying = "Nothing is playing."
    public static let soundMissing = "That sound is missing, so nothing plays."
    public static let playerHelper = "Shows Playing or Paused on the lock screen, with no buttons. Off shows nothing."
    public static let lockHelper = "Plays when the screen finishes locking. Off plays nothing."
    public static let unlockHelper = "Plays when the screen finishes unlocking. Off plays nothing."
    public static let levelHelper = "Quiet is softer. Loud is full. Off plays nothing."
}

public enum LockScreenLayout {
    public static let rowHeight = 52.0
    public static let panelPadding = 32.0
    public static let cardGap = 28.0
    public static let motionDuration = 0.22
}

public struct LockScreenControl: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var label: String
    public var value: String
    public var keyboardReachable: Bool
}

public struct LockScreenPreviewTile: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case loading
        case empty(String)
        case unavailable(String)
        case card(word: String)
    }

    public var body: Body
    public var accessibilityLabel: String
    public var controlCount: Int
}

/// The settings page: loading, empty, unavailable, and a read-only preview.
public struct LockScreenPageModel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case empty
        case unavailable(String)
        case ready
    }

    public var phase: Phase
    public var settings: LockScreenSettings
    public var controls: [LockScreenControl]
    public var preview: LockScreenPreviewTile
    public var soundNote: String?
    public var animationDuration: Double
    public var rowHeight: Double
    public var panelPadding: Double
    public var cardGap: Double

    public static func make(
        settings: LockScreenSettings,
        playback: LockScreenPlayback,
        space: LockScreenSpaceAnswer?,
        reduceMotion: Bool,
        soundFileExists: (String) -> Bool,
        loaded: Bool
    ) -> LockScreenPageModel {
        let duration = reduceMotion ? 0 : LockScreenLayout.motionDuration
        guard loaded else {
            return LockScreenPageModel(
                phase: .loading,
                settings: settings,
                controls: [],
                preview: LockScreenPreviewTile(body: .loading, accessibilityLabel: LockScreenCopy.loading, controlCount: 0),
                soundNote: nil,
                animationDuration: duration,
                rowHeight: LockScreenLayout.rowHeight,
                panelPadding: LockScreenLayout.panelPadding,
                cardGap: LockScreenLayout.cardGap
            )
        }
        let unavailable = settings.playerCard && (space == .symbolMissing || space == .callFailed)
        let phase: Phase
        if unavailable {
            phase = .unavailable(LockScreenCopy.unavailable)
        } else if settings == .off {
            phase = .empty
        } else {
            phase = .ready
        }
        return LockScreenPageModel(
            phase: phase,
            settings: settings,
            controls: controls(settings),
            preview: preview(settings: settings, playback: playback, unavailable: unavailable),
            soundNote: missingSound(settings, soundFileExists: soundFileExists),
            animationDuration: duration,
            rowHeight: LockScreenLayout.rowHeight,
            panelPadding: LockScreenLayout.panelPadding,
            cardGap: LockScreenLayout.cardGap
        )
    }

    private static func controls(_ settings: LockScreenSettings) -> [LockScreenControl] {
        [
            LockScreenControl(
                id: "playerCard", title: "Player card", helper: LockScreenCopy.playerHelper, label: "Player card",
                value: settings.playerCard ? "On" : "Off", keyboardReachable: true
            ),
            LockScreenControl(
                id: "lockSound", title: "Lock sound", helper: LockScreenCopy.lockHelper, label: "Lock sound",
                value: settings.lockSound.title, keyboardReachable: true
            ),
            LockScreenControl(
                id: "unlockSound", title: "Unlock sound", helper: LockScreenCopy.unlockHelper, label: "Unlock sound",
                value: settings.unlockSound.title, keyboardReachable: true
            ),
            LockScreenControl(
                id: "soundLevel", title: "Sound level", helper: LockScreenCopy.levelHelper, label: "Sound level",
                value: settings.soundLevel.rawValue, keyboardReachable: true
            ),
        ]
    }

    private static func preview(settings: LockScreenSettings, playback: LockScreenPlayback, unavailable: Bool) -> LockScreenPreviewTile {
        if unavailable {
            return LockScreenPreviewTile(body: .unavailable(LockScreenCopy.unavailable), accessibilityLabel: LockScreenCopy.unavailable, controlCount: 0)
        }
        guard settings.playerCard else {
            return LockScreenPreviewTile(body: .empty(LockScreenCopy.empty), accessibilityLabel: LockScreenCopy.empty, controlCount: 0)
        }
        switch playback {
        case .playing:
            return LockScreenPreviewTile(body: .card(word: "Playing"), accessibilityLabel: LockScreenCopy.previewPlaying, controlCount: 0)
        case .paused:
            return LockScreenPreviewTile(body: .card(word: "Paused"), accessibilityLabel: LockScreenCopy.previewPaused, controlCount: 0)
        case .none:
            return LockScreenPreviewTile(body: .empty(LockScreenCopy.nothingPlaying), accessibilityLabel: LockScreenCopy.nothingPlaying, controlCount: 0)
        }
    }

    private static func missingSound(_ settings: LockScreenSettings, soundFileExists: (String) -> Bool) -> String? {
        let chosen = [settings.lockSound, settings.unlockSound].compactMap(\.fileName)
        guard chosen.contains(where: { !soundFileExists($0) }) else { return nil }
        return LockScreenCopy.soundMissing
    }
}
