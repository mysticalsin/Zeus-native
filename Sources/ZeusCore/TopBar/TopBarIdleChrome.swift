import Foundation

/// One sRGB colour. Components are 0...1.
public struct TopBarSRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// The idle top-bar fill. One value, so the bar cannot drift off pure black.
public enum TopBarIdleBlack {
    /// sRGB #000000, alpha 1.
    public static let sRGB = TopBarSRGB(red: 0, green: 0, blue: 0, alpha: 1)
}

/// Who is drawn on the quiet bar. Classic is Zeus. The orb persona is Jarvis.
public enum TopBarCharacterChoice: Equatable, Sendable {
    case zeus
    case jarvis

    public static func resolved(mascotKind: MascotKind) -> TopBarCharacterChoice {
        switch mascotKind {
        case .classic: .zeus
        case .orb: .jarvis
        }
    }
}

/// Idle is the quiet bar. Hover is the pointer on that bar. Active is open, peeking, calibrating, or live attention.
public enum TopBarChromeState: Equatable, Sendable {
    case idle
    case hover
    case active
}

/// Pitch black is the idle fill. Existing keeps the body paint already used for hover, peek and the open panel.
public enum TopBarBodyTreatment: Equatable, Sendable {
    case pitchBlack
    case existing
}

/// What the bar is allowed to show.
public enum TopBarChromeContent: Equatable, Sendable {
    /// The selected character and nothing else.
    case characterOnly(TopBarCharacterChoice)
    /// The body the bar already draws, plus every live attention mark that is on.
    case existing(attention: [TopBarChromeMark])
}

/// Something the closed bar already draws while the pointer is away. Idle keeps these.
public enum TopBarChromeMark: Equatable, Sendable {
    case approval
    case recording
    case dictation
    case recordingFeedback
    case cue
    case avatarActivity
    case focusTimer
    case music
    case alerts
    case lights
}

/// The open and close motion the bar already uses. Reduce Motion is that same motion with the spring removed.
public enum TopBarChromeTransition: Equatable, Sendable {
    case existingOpenClose(reduceMotion: Bool)
}

/// The facts the chrome decision reads. Defaults are a quiet bar showing Zeus.
public struct TopBarChromeFacts: Equatable, Sendable {
    public var pointerOverBar: Bool
    public var expanded: Bool
    public var peek: Bool
    public var reduceMotion: Bool
    public var calibrating: Bool
    public var character: TopBarCharacterChoice
    public var approval: Bool
    public var recording: Bool
    public var music: Bool
    public var dictation: Bool
    public var cue: Bool
    public var focusTimer: Bool
    public var recordingFeedback: Bool
    public var alerts: Bool
    public var lights: Bool
    public var avatarActivity: Bool

    public init(
        pointerOverBar: Bool = false,
        expanded: Bool = false,
        peek: Bool = false,
        reduceMotion: Bool = false,
        calibrating: Bool = false,
        character: TopBarCharacterChoice = .zeus,
        approval: Bool = false,
        recording: Bool = false,
        music: Bool = false,
        dictation: Bool = false,
        cue: Bool = false,
        focusTimer: Bool = false,
        recordingFeedback: Bool = false,
        alerts: Bool = false,
        lights: Bool = false,
        avatarActivity: Bool = false
    ) {
        self.pointerOverBar = pointerOverBar
        self.expanded = expanded
        self.peek = peek
        self.reduceMotion = reduceMotion
        self.calibrating = calibrating
        self.character = character
        self.approval = approval
        self.recording = recording
        self.music = music
        self.dictation = dictation
        self.cue = cue
        self.focusTimer = focusTimer
        self.recordingFeedback = recordingFeedback
        self.alerts = alerts
        self.lights = lights
        self.avatarActivity = avatarActivity
    }
}

/// One resolved frame of the top bar.
public struct TopBarChromeFrame: Equatable, Sendable {
    public var state: TopBarChromeState
    public var treatment: TopBarBodyTreatment
    /// Forced sRGB fill. Nil keeps the paint the bar already uses.
    public var background: TopBarSRGB?
    public var allowsMaterial: Bool
    public var allowsBlur: Bool
    public var allowsVibrancy: Bool
    public var allowsGradient: Bool
    public var allowsTint: Bool
    public var allowsTranslucency: Bool
    public var allowsShadow: Bool
    public var content: TopBarChromeContent
    public var transition: TopBarChromeTransition

    public init(
        state: TopBarChromeState,
        treatment: TopBarBodyTreatment,
        background: TopBarSRGB?,
        allowsMaterial: Bool,
        allowsBlur: Bool,
        allowsVibrancy: Bool,
        allowsGradient: Bool,
        allowsTint: Bool,
        allowsTranslucency: Bool,
        allowsShadow: Bool,
        content: TopBarChromeContent,
        transition: TopBarChromeTransition
    ) {
        self.state = state
        self.treatment = treatment
        self.background = background
        self.allowsMaterial = allowsMaterial
        self.allowsBlur = allowsBlur
        self.allowsVibrancy = allowsVibrancy
        self.allowsGradient = allowsGradient
        self.allowsTint = allowsTint
        self.allowsTranslucency = allowsTranslucency
        self.allowsShadow = allowsShadow
        self.content = content
        self.transition = transition
    }
}

/// Idle versus hover versus active, and what each one shows.
public enum TopBarIdleChrome {
    public static func resolve(_ facts: TopBarChromeFacts) -> TopBarChromeFrame {
        let attention = attentionMarks(facts)
        let state: TopBarChromeState
        if facts.expanded || facts.peek || facts.calibrating || !attention.isEmpty {
            state = .active
        } else if facts.pointerOverBar {
            state = .hover
        } else {
            state = .idle
        }
        let transition = TopBarChromeTransition.existingOpenClose(reduceMotion: facts.reduceMotion)
        switch state {
        case .idle:
            return TopBarChromeFrame(
                state: .idle,
                treatment: .pitchBlack,
                background: TopBarIdleBlack.sRGB,
                allowsMaterial: false,
                allowsBlur: false,
                allowsVibrancy: false,
                allowsGradient: false,
                allowsTint: false,
                allowsTranslucency: false,
                allowsShadow: false,
                content: .characterOnly(facts.character),
                transition: transition
            )
        case .hover, .active:
            return TopBarChromeFrame(
                state: state,
                treatment: .existing,
                background: nil,
                allowsMaterial: true,
                allowsBlur: true,
                allowsVibrancy: true,
                allowsGradient: true,
                allowsTint: true,
                allowsTranslucency: true,
                allowsShadow: true,
                content: .existing(attention: attention),
                transition: transition
            )
        }
    }

    /// Attention the closed bar already shows. The quiet bar keeps every one that is on.
    public static func attentionMarks(_ facts: TopBarChromeFacts) -> [TopBarChromeMark] {
        var marks: [TopBarChromeMark] = []
        if facts.approval { marks.append(.approval) }
        if facts.recording { marks.append(.recording) }
        if facts.dictation { marks.append(.dictation) }
        if facts.recordingFeedback { marks.append(.recordingFeedback) }
        if facts.cue { marks.append(.cue) }
        if facts.avatarActivity { marks.append(.avatarActivity) }
        if facts.focusTimer { marks.append(.focusTimer) }
        if facts.music { marks.append(.music) }
        if facts.alerts { marks.append(.alerts) }
        if facts.lights { marks.append(.lights) }
        return marks
    }
}
