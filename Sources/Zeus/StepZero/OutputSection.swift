import Foundation

/// The step-zero sound output section. Pure: it opens no device, starts no browser,
/// and keeps no name.
///
/// The caller feeds transport codes, announcements, and the milliseconds it waited.
/// A code outside the table becomes `other`. A name is counted and dropped. A record
/// key other than the two declared keys is ignored. The browser file, the facts file,
/// the music position section, and the output lint stay out of this file.
public enum OutputSection {
    /// Devices past this count are not read.
    public static let maxDevices = 32
    /// Announcements past this count are not read.
    public static let maxSightings = 128
    /// A record key longer than this is ignored. The value is never taken.
    public static let maxRecordKeyBytes = 64
    /// The browse ends here when the part has not ended sooner.
    public static let browseLimitMilliseconds = 20_000
    /// How long the switched output is watched before the first device is written back.
    public static let switchWindowMilliseconds = 5_000
    /// The gap between output reads during the switch.
    public static let pollMilliseconds = 100
    /// One audio read or write. The restore is still sent once when this expires.
    public static let audioCallLimitMilliseconds = 2_000

    public enum Transport: String, Sendable, Equatable {
        case builtIn
        case wired
        case bluetooth
        case wirelessSpeaker
        case display
        case virtual
        case other
    }

    public enum Service: String, Sendable, Equatable {
        case airplay
        case raop
    }

    /// The two types this section may start. There is no third.
    public static let declaredServices: [Service] = [.airplay, .raop]

    public enum BrowserReport: String, Sendable, Equatable {
        case waiting
        case ready
        case results
        case failed
    }

    public enum BrowseMark: String, Sendable, Equatable {
        case waiting
        case results
        case failed
    }

    public enum PartMark: String, Sendable, Equatable {
        case ran
        case skipped
        case notMeasured
    }

    public enum OwnerAnswer: String, Sendable, Equatable {
        case yes
        case no
        case notTried
    }

    public enum RestoreMark: String, Sendable, Equatable {
        case yes
        case no
        case unknown
    }

    /// One device, already read by the caller. The code is mapped and dropped.
    public struct DeviceSample: Sendable, Equatable {
        public var code: String
        public var connectedOutput: Bool

        public init(code: String, connectedOutput: Bool) {
            self.code = code
            self.connectedOutput = connectedOutput
        }
    }

    /// One announcement. The name is counted and dropped. Key values are not accepted.
    public struct Sighting: Sendable, Equatable {
        public var service: Service
        public var name: String
        public var keys: [String]

        public init(service: Service, name: String, keys: [String]) {
            self.service = service
            self.name = name
            self.keys = keys
        }
    }

    /// A code the table does not name becomes `other`. The characters are not returned.
    public static func transport(code: String) -> Transport {
        switch code {
        case "bltn":
            return .builtIn
        case "usb ", "thun", "1394", "pci ", "eavb":
            return .wired
        case "blue", "blea":
            return .bluetooth
        case "airp":
            return .wirelessSpeaker
        case "hdmi", "dprt":
            return .display
        case "virt", "grup":
            return .virtual
        default:
            return .other
        }
    }

    /// Ready and a results change are the same mark. Waiting and failed stay themselves.
    public static func browseMark(_ report: BrowserReport) -> BrowseMark {
        switch report {
        case .waiting:
            return .waiting
        case .ready, .results:
            return .results
        case .failed:
            return .failed
        }
    }

    /// Twelve to sixteen hex digits, then `@`. Any other shape is not the prefix.
    public static func hasRaopHexPrefix(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        var length = 0
        while length < scalars.count, isHex(scalars[length]) {
            length += 1
            if length > 16 { return false }
        }
        guard length >= 12, length < scalars.count, scalars[length] == "@" else { return false }
        return true
    }

    public enum Step: String, Sendable, Equatable {
        case devices
        case network
        case switchOutput
        case menu
    }

    public static let script: [Step] = [.devices, .network, .switchOutput, .menu]

    public enum Effect: Sendable, Equatable {
        case readDevices
        case startBrowse(Service)
        case cancelBrowse
        case writeDefault
        case readOutput
        case restoreDefault
        case askMenu
    }

    public enum Phase: String, Sendable, Equatable {
        case idle
        case gate
        case awaitDevices
        case browsing
        case switching
        case restoring
        case awaitMenu
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin
        case continueAsked
        case skip
        case devices([DeviceSample])
        case sightings([Sighting])
        case browse(BrowserReport)
        case networkAnswered
        case endNetwork
        case waited(milliseconds: Int)
        case callExceeded
        case readBack(onTarget: Bool, onOriginal: Bool)
        case menu(OwnerAnswer)
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var cursor: Int
        public var transports: [Transport]
        public var airpSeen: Bool
        public var bluetoothConnected: Bool
        public var marks: [Step: PartMark]
        public var browseMarks: [BrowseMark]
        public var waitingBeforeAnswer: Bool
        public var networkAnswered: Bool
        public var airplayCount: Int
        public var raopCount: Int
        public var hexPrefixCount: Int
        public var modelKey: Bool
        public var amKey: Bool
        public var sightingsTaken: Int
        public var browseCancelled: Bool
        public var clockMs: Int
        public var inFlightMs: Int
        public var awaitingRead: Bool
        public var lastReadMs: Int
        public var sawTarget: Bool
        public var msToReadBack: Int?
        public var movedBack: Bool?
        public var wrote: Bool
        public var restoreSent: Bool
        public var restored: RestoreMark?
        public var menu: OwnerAnswer?

        public init() {
            phase = .idle
            cursor = 0
            transports = []
            airpSeen = false
            bluetoothConnected = false
            marks = [:]
            browseMarks = []
            waitingBeforeAnswer = false
            networkAnswered = false
            airplayCount = 0
            raopCount = 0
            hexPrefixCount = 0
            modelKey = false
            amKey = false
            sightingsTaken = 0
            browseCancelled = false
            clockMs = 0
            inFlightMs = 0
            awaitingRead = false
            lastReadMs = 0
            sawTarget = false
            msToReadBack = nil
            movedBack = nil
            wrote = false
            restoreSent = false
            restored = nil
            menu = nil
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            begin(&state)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .skip:
            skip(&state)
        case .devices(let samples):
            takeDevices(samples, &state)
        case .sightings(let rows):
            takeSightings(rows, &state)
        case .browse(let report):
            noteBrowse(report, &state)
        case .networkAnswered:
            noteAnswer(&state)
        case .endNetwork:
            endNetwork(&state, &effects)
        case .waited(let milliseconds):
            waited(milliseconds, &state, &effects)
        case .callExceeded:
            callExceeded(&state, &effects)
        case .readBack(let onTarget, let onOriginal):
            readBack(onTarget, onOriginal, &state, &effects)
        case .menu(let answer):
            menu(answer, &state)
        }
        return (state, effects)
    }

    private static func isHex(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9", "a"..."f", "A"..."F":
            return true
        default:
            return false
        }
    }

    private static func begin(_ state: inout State) {
        guard state.phase == .idle else { return }
        state.cursor = 0
        state.phase = .gate
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .gate, state.cursor < script.count else { return }
        switch script[state.cursor] {
        case .devices:
            state.phase = .awaitDevices
            effects.append(.readDevices)
        case .network:
            state.phase = .browsing
            state.clockMs = 0
            state.browseCancelled = false
            for service in declaredServices {
                effects.append(.startBrowse(service))
            }
        case .switchOutput:
            guard state.bluetoothConnected else {
                state.marks[.switchOutput] = .notMeasured
                advance(&state)
                return
            }
            state.phase = .switching
            state.clockMs = 0
            state.inFlightMs = 0
            state.lastReadMs = 0
            state.awaitingRead = true
            state.wrote = true
            effects.append(.writeDefault)
            effects.append(.readOutput)
        case .menu:
            state.phase = .awaitMenu
            effects.append(.askMenu)
        }
    }

    private static func skip(_ state: inout State) {
        guard state.phase == .gate, state.cursor < script.count else { return }
        state.marks[script[state.cursor]] = .skipped
        advance(&state)
    }

    private static func takeDevices(_ samples: [DeviceSample], _ state: inout State) {
        guard state.phase == .awaitDevices else { return }
        var transports: [Transport] = []
        var connected = false
        for sample in samples {
            if transports.count == maxDevices { break }
            let mapped = transport(code: sample.code)
            transports.append(mapped)
            if mapped == .bluetooth, sample.connectedOutput {
                connected = true
            }
        }
        state.transports = transports
        state.airpSeen = transports.contains(.wirelessSpeaker)
        state.bluetoothConnected = connected
        state.marks[.devices] = .ran
        advance(&state)
    }

    private static func takeSightings(_ rows: [Sighting], _ state: inout State) {
        guard state.phase == .browsing else { return }
        for row in rows {
            if state.sightingsTaken == maxSightings { return }
            state.sightingsTaken += 1
            switch row.service {
            case .airplay:
                state.airplayCount += 1
            case .raop:
                state.raopCount += 1
                if hasRaopHexPrefix(row.name) {
                    state.hexPrefixCount += 1
                }
            }
            for key in row.keys {
                guard key.utf8.count <= maxRecordKeyBytes else { continue }
                if key == "model" {
                    state.modelKey = true
                } else if key == "am" {
                    state.amKey = true
                }
            }
        }
    }

    private static func noteBrowse(_ report: BrowserReport, _ state: inout State) {
        guard state.phase == .browsing else { return }
        let mark = browseMark(report)
        if state.browseMarks.contains(mark) == false {
            state.browseMarks.append(mark)
        }
        if mark == .waiting, state.networkAnswered == false {
            state.waitingBeforeAnswer = true
        }
    }

    private static func noteAnswer(_ state: inout State) {
        guard state.phase == .browsing else { return }
        state.networkAnswered = true
    }

    private static func endNetwork(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .browsing else { return }
        finishBrowse(&state, &effects)
    }

    private static func finishBrowse(_ state: inout State, _ effects: inout [Effect]) {
        cancel(&state, &effects)
        state.marks[.network] = .ran
        advance(&state)
    }

    private static func cancel(_ state: inout State, _ effects: inout [Effect]) {
        guard state.browseCancelled == false else { return }
        state.browseCancelled = true
        effects.append(.cancelBrowse)
    }

    private static func waited(_ milliseconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard milliseconds > 0 else { return }
        switch state.phase {
        case .browsing:
            state.clockMs += milliseconds
            if state.clockMs >= browseLimitMilliseconds {
                finishBrowse(&state, &effects)
            }
        case .switching:
            state.clockMs += milliseconds
            if state.awaitingRead {
                state.inFlightMs += milliseconds
                if state.inFlightMs >= audioCallLimitMilliseconds {
                    failCall(&state, &effects)
                }
                return
            }
            if state.clockMs >= switchWindowMilliseconds {
                beginRestore(&state, &effects)
                return
            }
            if state.clockMs - state.lastReadMs >= pollMilliseconds {
                issueRead(&state, &effects)
            }
        case .restoring:
            guard state.awaitingRead else { return }
            state.inFlightMs += milliseconds
            if state.inFlightMs >= audioCallLimitMilliseconds {
                state.restored = .unknown
                state.awaitingRead = false
                state.marks[.switchOutput] = .ran
                advance(&state)
            }
        default:
            break
        }
    }

    private static func callExceeded(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .switching || state.phase == .restoring else { return }
        failCall(&state, &effects)
    }

    private static func failCall(_ state: inout State, _ effects: inout [Effect]) {
        state.awaitingRead = false
        state.inFlightMs = 0
        if state.phase == .restoring {
            state.restored = .unknown
            state.marks[.switchOutput] = .ran
            advance(&state)
            return
        }
        beginRestore(&state, &effects)
    }

    private static func issueRead(_ state: inout State, _ effects: inout [Effect]) {
        state.lastReadMs = state.clockMs
        state.awaitingRead = true
        state.inFlightMs = 0
        effects.append(.readOutput)
    }

    private static func beginRestore(_ state: inout State, _ effects: inout [Effect]) {
        guard state.restoreSent == false else { return }
        if state.movedBack == nil {
            state.movedBack = false
        }
        state.phase = .restoring
        state.restoreSent = true
        state.awaitingRead = true
        state.inFlightMs = 0
        effects.append(.restoreDefault)
        effects.append(.readOutput)
    }

    private static func readBack(
        _ onTarget: Bool,
        _ onOriginal: Bool,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.awaitingRead else { return }
        state.awaitingRead = false
        state.inFlightMs = 0
        switch state.phase {
        case .switching:
            if onTarget, state.msToReadBack == nil {
                state.msToReadBack = state.clockMs
            }
            if onTarget {
                state.sawTarget = true
            }
            if state.sawTarget, onTarget == false {
                state.movedBack = true
            }
            if state.clockMs >= switchWindowMilliseconds {
                beginRestore(&state, &effects)
            }
        case .restoring:
            state.restored = onOriginal ? .yes : .no
            if state.movedBack == nil {
                state.movedBack = false
            }
            state.marks[.switchOutput] = .ran
            advance(&state)
        default:
            break
        }
    }

    private static func menu(_ answer: OwnerAnswer, _ state: inout State) {
        guard state.phase == .awaitMenu else { return }
        state.menu = answer
        state.marks[.menu] = .ran
        advance(&state)
    }

    private static func advance(_ state: inout State) {
        state.cursor += 1
        state.clockMs = 0
        state.inFlightMs = 0
        state.awaitingRead = false
        if state.cursor >= script.count {
            state.phase = .done
        } else {
            state.phase = .gate
        }
    }
}
