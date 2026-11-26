import Foundation

/// The words the step-zero window may show.
///
/// Seven rows, one result word each, Continue and Skip. A hosted view holds no
/// prose outside the fixed list. The digest, when present, is 16 lowercase hex
/// digits and is not prose. Reduce Motion: nothing moves. A control's VoiceOver
/// label is its visible word.
public enum StepZeroView {
    public enum Word: String, Sendable, Equatable, CaseIterable {
        case notRun = "Not run"
        case running = "Running"
        case yourTurn = "Your turn"
        case done = "Done"
        case partial = "Partly done"
        case skipped = "Skipped"
        case stopped = "Stopped"

        public var symbol: String {
            switch self {
            case .notRun: "circle"
            case .running: "arrow.triangle.2.circlepath"
            case .yourTurn: "hand.point.up.left"
            case .done: "checkmark.circle"
            case .partial: "circle.lefthalf.filled"
            case .skipped: "forward"
            case .stopped: "exclamationmark.triangle"
            }
        }
    }

    public enum Motion: String, Sendable, Equatable {
        case still
    }

    public static let motion = Motion.still

    public static let rows = [
        "System source",
        "Lock screen",
        "Kill test",
        "Earbuds",
        "Focus",
        "Sound output",
        "Music position",
    ]

    public static let putBack = "Put back"
    public static let showReport = "Show report"
    public static let continueTitle = "Continue"
    public static let skipTitle = "Skip"
    public static let handDone = "Done"
    public static let handStart = "Start"
    public static let handYes = "Yes"
    public static let handNo = "No"
    public static let handNotTried = "Not tried"
    public static let lockInstruction = "Lock the Mac. Unlock it when the card has shown."
    public static let trashLine = "Move this build to the Trash"

    public static let needs = ["Earbuds", "Second display", "Phone"]
    public static let grants = ["Bluetooth", "Automation", "Full Disk Access", "Local Network"]
    public static let restoreItems = ["Listening mode", "Default output", "Helper process"]

    public enum Sentence: String, Sendable, Equatable, CaseIterable {
        case putBack = "The last run ended early. This puts your earbuds' listening mode back and stops one helper process."
        case systemSource = "This reads what any app on this Mac is playing, pauses it, moves the position, and shows the word Zeus in the Mac's own now-playing display for up to three seconds. Each is put back."
        case systemSourceSkip = "This skips to the next track and back in your music player. The player may count one skip."
        case lockScreen = "This puts a small test card on your lock screen while you lock and unlock the Mac. It also asks you to switch user, start the screensaver and sleep the display."
        case lockPlayer = "Next, macOS may ask to let ZEUS control Music and Spotify, so the probe can play, pause and skip from the lock screen. The player may count one skip."
        case killTest = "This ends the probe on purpose while the test card and the helper are up. You then start it again."
        case earbudsPaired = "Next, macOS may ask to let ZEUS use Bluetooth. The probe lists the devices paired with this Mac to see whether that needs your permission."
        case earbudsManager = "Next, macOS will ask to let ZEUS use Bluetooth, so the probe can see your earbuds connect and read their battery."
        case earbudsMode = "This changes your earbuds' listening mode for a few seconds and puts it back."
        case focus = "This reads the two Focus files and keeps yes or no answers only. It asks you to turn a Focus on and off, and to switch Full Disk Access for ZEUS off and on."
        case focusTool = "This starts a small system tool that tries to list one protected folder, and keeps only whether it could."
        case soundSwitch = "This moves the Mac's sound to your earbuds for five seconds and puts it back."
        case soundNetwork = "Next, macOS will ask to let ZEUS find devices on your network, so the probe can see how wireless speakers announce themselves."
        case music = "This watches the notices Music posts while you play, pause, skip and scrub."
    }

    private static let knownSymbols: Set<String> = [
        "circle",
        "arrow.triangle.2.circlepath",
        "hand.point.up.left",
        "checkmark.circle",
        "circle.lefthalf.filled",
        "forward",
        "exclamationmark.triangle",
        "airpodspro",
        "display",
        "iphone",
    ]

    public static func symbolResolves(_ name: String) -> Bool {
        knownSymbols.contains(name)
    }

    public static func needSymbol(_ name: String) -> String? {
        switch name {
        case "Earbuds": "airpodspro"
        case "Second display": "display"
        case "Phone": "iphone"
        default: nil
        }
    }

    /// The label a person hears is the word they can see.
    public static func voiceOverLabel(for visible: String) -> String {
        visible
    }

    public static func showReportEnabled(_ words: [Word], putBack: Word?) -> Bool {
        guard words.count == rows.count else { return false }
        guard words.allSatisfy({ $0 == .done || $0 == .skipped }) else { return false }
        guard let putBack else { return true }
        return putBack == .done || putBack == .skipped
    }

    public struct Hosted: Equatable, Sendable {
        public var prose: [String]
        public var digest: String?

        public init(prose: [String], digest: String?) {
            self.prose = prose
            self.digest = digest
        }
    }

    public static let fixed: Set<String> = makeFixed()

    public static func isScreenDigest(_ text: String) -> Bool {
        guard text.utf8.count == 16 else { return false }
        return text.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
        }
    }

    /// Prose must be taken from the fixed list. A digest must be 16 lowercase hex digits.
    public static func holdsOnlyFixed(_ hosted: Hosted) -> Bool {
        guard hosted.prose.allSatisfy({ fixed.contains($0) }) else { return false }
        if let digest = hosted.digest { return isScreenDigest(digest) }
        return true
    }

    public static func hosted(
        words: [Word],
        line: Sentence?,
        showNeeds: Bool,
        owesRestore: Bool,
        putBackWord: Word?,
        grantsOn: [String],
        grantsBack: [String],
        notPutBack: [String],
        digest: String?
    ) -> Hosted {
        var prose: [String] = []
        if owesRestore {
            prose.append(putBack)
            if let putBackWord { prose.append(putBackWord.rawValue) }
        }
        for (index, name) in rows.enumerated() {
            prose.append(name)
            if words.indices.contains(index) { prose.append(words[index].rawValue) }
        }
        if let line { prose.append(line.rawValue) }
        if showNeeds { prose.append(contentsOf: needs) }
        if words.contains(.yourTurn) {
            prose.append(contentsOf: [handDone, handStart, handYes, handNo, handNotTried, lockInstruction])
        }
        prose.append(contentsOf: [continueTitle, skipTitle, showReport, trashLine])
        prose.append(contentsOf: grantsOn.filter { grants.contains($0) })
        prose.append(contentsOf: grantsBack.filter { grants.contains($0) })
        prose.append(contentsOf: notPutBack.filter { restoreItems.contains($0) })
        let shownDigest = digest.flatMap { isScreenDigest($0) ? $0 : nil }
        return Hosted(prose: prose, digest: shownDigest)
    }

    private static func makeFixed() -> Set<String> {
        var list = Set(rows)
        list.insert(putBack)
        list.insert(showReport)
        list.insert(continueTitle)
        list.insert(skipTitle)
        list.insert(handDone)
        list.insert(handStart)
        list.insert(handYes)
        list.insert(handNo)
        list.insert(handNotTried)
        list.insert(lockInstruction)
        list.insert(trashLine)
        list.formUnion(needs)
        list.formUnion(grants)
        list.formUnion(restoreItems)
        list.formUnion(Word.allCases.map(\.rawValue))
        list.formUnion(Sentence.allCases.map(\.rawValue))
        return list
    }
}
