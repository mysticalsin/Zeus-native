import Foundation

/// Zeus's own sound set (rendered by tools/sounds/make_sounds.py, bundled as AAC in Sources/Zeus/Sounds;
/// the Crystal dictation cues come from scripts/gen-dictation-sounds.py and stay uncompressed WAV).
/// Each slot is one thing that makes a sound; a slot with several styles gets a picker in Settings.
public enum SoundSlot: String, CaseIterable, Sendable {
    case runStart, request, answer, done, failure, dictationBegin, dictationEnd, dictationCancel
    case listenStart, listenStop, voiceDone, voiceError, todo, timer, runningLoop
}

public struct SoundSpec: Equatable, Sendable {
    public let style: String
    /// File name without extension; the file is `<file>.<fileExtension>` in the Sounds resource folder.
    public let file: String
    /// The rendered length, which the tests hold the bundled files to.
    public let seconds: Double
    /// AAC (`m4a`) for most sounds; the short dictation cues are WAV so they start with no decoder delay.
    public var fileExtension: String = SoundCatalog.fileExtension

    /// The bundled file's name, such as `dictation_crystal_start.wav`.
    public var fileName: String { "\(file).\(fileExtension)" }
}

public enum SoundCatalog {
    public static let fileExtension = "m4a"

    public static let runStart: [SoundSpec] = [
        .init(style: "Classic", file: "running_classic", seconds: 1.96),
        .init(style: "Spaceship Futuristic", file: "running_spaceship", seconds: 1.96),
        .init(style: "Mystery Game", file: "running_mystery", seconds: 0.96),
        .init(style: "Tap", file: "running_tap", seconds: 1.96),
    ]
    public static let request: [SoundSpec] = [
        .init(style: "Classic", file: "permission_classic", seconds: 1.96),
        .init(style: "Notebook", file: "permission_notebook", seconds: 1.96),
        .init(style: "Game Alert", file: "permission_gamealert", seconds: 1.96),
        .init(style: "Weard Permission", file: "permission_weard", seconds: 1.96),
        .init(style: "Weard 2 Permission", file: "permission_weard2", seconds: 1.96),
        .init(style: "Short Warning", file: "permission_shortwarning", seconds: 2.96),
    ]
    public static let answer: [SoundSpec] = [
        .init(style: "Futuristic 1", file: "respond_futuristic1", seconds: 0.96),
        .init(style: "Futuristic 2", file: "respond_futuristic2", seconds: 0.96),
    ]
    public static let done: [SoundSpec] = [
        .init(style: "Success", file: "success", seconds: 2.96),
        .init(style: "Gentle", file: "success_gentle", seconds: 1.96),
        .init(style: "Spark", file: "success_spark", seconds: 0.96),
    ]
    /// Dictation start and stop: the original click first (what a nil style means), then the Crystal
    /// chimes that Settings > Dictation uses by default (DictationCueStyle.crystal).
    public static let dictationBegin: [SoundSpec] = [
        .init(style: "Dictation begin", file: "dictation_begin", seconds: 0.50),
        .init(style: DictationCueStyle.crystal.rawValue, file: "dictation_crystal_start", seconds: 0.26, fileExtension: "wav"),
    ]
    public static let dictationEnd: [SoundSpec] = [
        .init(style: "Dictation end", file: "dictation_end", seconds: 0.46),
        .init(style: DictationCueStyle.crystal.rawValue, file: "dictation_crystal_stop", seconds: 0.26, fileExtension: "wav"),
    ]
    /// Slots with a single sound.
    private static let single: [SoundSlot: SoundSpec] = [
        .failure: .init(style: "Failure", file: "failure", seconds: 1.46),
        .dictationCancel: .init(style: "Dictation cancel", file: "dictation_cancel", seconds: 0.18, fileExtension: "wav"),
        .listenStart: .init(style: "Listening", file: "listen_start", seconds: 0.40),
        .listenStop: .init(style: "Stopped listening", file: "listen_stop", seconds: 0.40),
        .voiceDone: .init(style: "Answer done", file: "answer_done", seconds: 0.80),
        .voiceError: .init(style: "Voice error", file: "voice_error", seconds: 0.70),
        .todo: .init(style: "To-do", file: "todo_check", seconds: 0.35),
        .timer: .init(style: "Timer", file: "timer_alarm", seconds: 2.00),
        .runningLoop: .init(style: "Running loop", file: "running_loop", seconds: 4.00),
    ]

    public static func styles(for slot: SoundSlot) -> [SoundSpec] {
        switch slot {
        case .runStart: runStart
        case .request: request
        case .answer: answer
        case .done: done
        case .dictationBegin: dictationBegin
        case .dictationEnd: dictationEnd
        default: single[slot].map { [$0] } ?? []
        }
    }

    /// The sound for a slot and style. An unknown style (a system sound name an older build saved)
    /// falls back to the slot's first sound; "Off" is silence (nil).
    public static func spec(_ slot: SoundSlot, style: String?) -> SoundSpec? {
        if style == "Off" { return nil }
        let all = styles(for: slot)
        return all.first { $0.style == style } ?? all.first
    }

    public static func styleNames(for slot: SoundSlot) -> [String] { styles(for: slot).map(\.style) }

    public static var everySpec: [SoundSpec] { SoundSlot.allCases.flatMap(styles(for:)) }
}

/// Every sound the reference app ships, and the Zeus slot and style that answers it.
public enum SoundParity {
    public struct Entry: Equatable, Sendable {
        public let reference: String
        public let seconds: Double
        public let slot: SoundSlot
        public let style: String
    }
    public static let entries: [Entry] = [
        .init(reference: "running.wav", seconds: 1.96, slot: .runStart, style: "Classic"),
        .init(reference: "runningspaceship.wav", seconds: 1.96, slot: .runStart, style: "Spaceship Futuristic"),
        .init(reference: "runningmisterygame.wav", seconds: 0.96, slot: .runStart, style: "Mystery Game"),
        .init(reference: "runningtap.wav", seconds: 1.96, slot: .runStart, style: "Tap"),
        .init(reference: "permission.wav", seconds: 1.96, slot: .request, style: "Classic"),
        .init(reference: "permission2noteboo.wav", seconds: 1.96, slot: .request, style: "Notebook"),
        .init(reference: "permissiongamealert.wav", seconds: 1.96, slot: .request, style: "Game Alert"),
        .init(reference: "weardpermission.wav", seconds: 1.96, slot: .request, style: "Weard Permission"),
        .init(reference: "weard2permission.wav", seconds: 1.96, slot: .request, style: "Weard 2 Permission"),
        .init(reference: "permissionshortwarning.wav", seconds: 2.96, slot: .request, style: "Short Warning"),
        .init(reference: "respondfuturistic1.wav", seconds: 0.96, slot: .answer, style: "Futuristic 1"),
        .init(reference: "respondfuturistic2.wav", seconds: 0.96, slot: .answer, style: "Futuristic 2"),
        .init(reference: "succes.wav", seconds: 2.96, slot: .done, style: "Success"),
        .init(reference: "dictation-begin.wav", seconds: 0.50, slot: .dictationBegin, style: "Dictation begin"),
        .init(reference: "dictation-end.wav", seconds: 0.46, slot: .dictationEnd, style: "Dictation end"),
    ]
    /// Zeus-only slots the task also wants wired (failure, ambient loop).
    public static let zeusExtras: [SoundSlot] = [.failure, .runningLoop]
}
