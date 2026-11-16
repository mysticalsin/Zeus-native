import Foundation

/// Why a turn carries no screenshot, so the prompt can say the truth about it.
public enum ScreenSightReason: String, Sendable, Equatable {
    case permissionOff
    case notCaptured
}

/// What the model is told about the screen. It is told it can see only when pixels are really attached.
public enum ScreenSightNote {
    /// The screen section of a turn's text block, for a provider that sends images.
    public static func line(labels: [String], reason: ScreenSightReason?) -> String {
        guard labels.isEmpty else {
            return (["Screenshots attached, in order:"] + labels.map { "- \($0)" }).joined(separator: "\n")
        }
        switch reason {
        case .permissionOff:
            return "No screenshots this turn: Screen Recording permission is off, so you cannot see the screen. "
                + "Say so plainly if Tony asks about it. Use [POINT:none]."
        case .notCaptured, nil:
            return "No screenshots this turn: none were captured, so you cannot see the screen right now. "
                + "Do not guess what is on it. Use [POINT:none]."
        }
    }

    /// For an engine that never receives images.
    public static let textOnlyLine = "No screenshot reaches you on this turn, so you cannot see the screen. "
        + "Say so plainly if Tony asks about it, and never guess what is on it."

    /// The system prompt for an engine that takes text only. A screen-aware (spoken or screenshot) turn ends with
    /// the honest line; a plain chat or routine request is left as written.
    public static func textOnlySystemPrompt(for request: BrainRequest) -> String {
        let screenAware = request.firstTextBudget != nil || !request.screenshots.isEmpty || request.screenReason != nil
        guard screenAware else { return request.systemPrompt }
        return request.systemPrompt + "\n\n" + textOnlyLine
    }
}

/// Which captures a talk turn keeps, sends and draws on. Seeing the screen (sending images to the brain) is one
/// consent, drawing marks on it another.
public enum TalkSightPolicy {
    public struct Plan: Sendable {
        /// Every capture the turn keeps, for POINT tags and the drive and walkthrough actions.
        public var kept: [ScreenShot]
        /// What the brain request carries: every kept capture, or only the cursor display while drawing.
        public var request: [ScreenShot]
        public var drawing: Bool
        /// The turn goes to the image-capable provider.
        public var sendsImages: Bool

        public var keptCount: Int { kept.count }
        public var requestLabels: [String] { request.map(\.label) }
    }

    /// `textAnswersIt`: window or page text already answers the question, which used to drop the pixels.
    /// `restricted` and `pageRoute` turns never carry an image.
    public static func plan(seeScreen: Bool, drawConsent: Bool, restricted: Bool, pageRoute: Bool, textAnswersIt: Bool,
                            captured: [ScreenShot]) -> Plan {
        let kept = (restricted || pageRoute || (textAnswersIt && !seeScreen)) ? [] : captured
        let drawing = TalkDrawPolicy.wantsImages(consent: drawConsent, shots: kept.count)
        let request = TalkDrawPolicy.requestShots(consent: drawing, shots: kept)
        return Plan(kept: kept, request: request, drawing: drawing,
                    sendsImages: !request.isEmpty && (seeScreen || drawing))
    }
}

/// Tells the owner once per launch that Zeus cannot see the screen.
public struct ScreenSightNotice: Sendable {
    public static let message = "I can't see your screen yet. Turn on Screen Recording for Zeus in System Settings, under Privacy and Security."

    private var told = false

    public init() {}

    /// The notice to give now, or nil. A granted permission never uses the notice up.
    public mutating func take(permissionGranted: Bool) -> String? {
        guard !permissionGranted, !told else { return nil }
        told = true
        return Self.message
    }
}
