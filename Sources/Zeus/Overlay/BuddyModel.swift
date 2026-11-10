import Foundation
import Observation
import ZeusCore

/// What the overlay draws each frame. Positions are global AppKit coordinates (bottom-left origin).
@MainActor
@Observable
final class BuddyModel {
    enum Mode: Equatable {
        case following
        case listening
        case thinking
        case flying
        case pointing
        case returning
    }

    var mode: Mode = .following {
        didSet { if mode != oldValue { onModeChange?(mode) } }
    }
    /// Told whenever the mode changes (the controller decides when the buddy shows).
    @ObservationIgnored var onModeChange: ((Mode) -> Void)?
    var position: CGPoint = .zero
    /// Degrees, clockwise from pointing up. -15 at rest.
    var rotation: Double = -15
    var scale: Double = 1
    /// Shadow radius while a flight pulses. Rest is 8, peak is 14.
    var glow: Double = 8
    /// Element frame in AppKit global points. Nil once the next click or key clears it.
    var ringFrame: CGRect?
    var hasAppeared = false

    var bubbleText = ""
    /// What ZEUS is saying, shown as text next to the spark (Settings › Show captions).
    var caption = ""
    var captionVisible = false {
        didSet { if captionVisible != oldValue { onCaptionChange?(captionVisible) } }
    }
    @ObservationIgnored var onCaptionChange: ((Bool) -> Void)?
    var bubbleVisible = false

    var strikeCenter: CGPoint = .zero
    /// 0 → 1 while the arrival ring expands; 1 means hidden.
    var strikeProgress: Double = 1

    /// Live mic level 0…1. nil until audio capture lands; the waveform then idles on its own.
    var audioLevel: Double?

    var sparkVisible: Bool {
        mode != .listening && mode != .thinking && !(mode == .following && PointerZone.shared.overNotchPanel)
    }
}

/// Where the pointer is, for the cursor spark: it steps aside while you use the open notch panel
/// (tab row and cards) so it never sits on top of a tab.
@MainActor @Observable
final class PointerZone {
    static let shared = PointerZone()
    var overNotchPanel = false
}

/// Settings > Show Zeus beside the pointer, and the quick toggle in the top bar's ... menu.
@MainActor
@Observable
final class BuddyPreference {
    static let shared = BuddyPreference()

    var show: BuddyShow {
        didSet {
            guard show != oldValue else { return }
            UserDefaults.standard.set(show.rawValue, forKey: BuddyShow.defaultsKey)
            onChange?(show)
        }
    }
    @ObservationIgnored var onChange: ((BuddyShow) -> Void)?

    private init() { show = BuddyShow.stored(UserDefaults.standard.string(forKey: BuddyShow.defaultsKey)) }
}
