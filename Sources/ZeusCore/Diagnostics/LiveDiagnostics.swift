import Foundation

/// What Zeus is doing right now, for Settings > Diagnostics and a bug report.
/// Pure: the app hands in the numbers, this decides the words, the High marks and the copied text.
/// It holds the player's name and state only, never a title, an artist or a path.
public struct LiveDiagnostics: Equatable, Sendable {
    /// Whether Zeus is capturing system audio to draw the spectrum.
    public enum AudioCapture: Equatable, Sendable {
        case running, off, notAllowed

        /// Running wins; otherwise a refused permission reads Not allowed.
        public init(running: Bool, permission: AudioCapturePermission) {
            if running { self = .running } else if permission == .refused { self = .notAllowed } else { self = .off }
        }

        public var word: String {
            switch self {
            case .running: "Running"
            case .off: "Off"
            case .notAllowed: "Not allowed"
            }
        }
    }

    /// Which line a row is, so the screen can pick its symbol.
    public enum Field: Equatable, Sendable { case cpu, memory, heat, audio, nowPlaying }

    /// How a row reads at a glance. The screen pairs each tone with a symbol and a word, never colour alone.
    public enum Tone: Equatable, Sendable { case ok, neutral, attention }

    public struct Row: Equatable, Sendable {
        public var field: Field
        public var label: String
        public var value: String
        /// True when the number is over the idle budget; the screen writes "High" beside it.
        public var isHigh: Bool
        public var tone: Tone
    }

    /// Percent of one core, nil until a sample exists.
    public var cpuPercent: Double?
    public var memoryBytes: UInt64?
    public var thermal: KeepAwakeRules.Thermal
    public var audio: AudioCapture
    /// The player's name only, such as "Music".
    public var playerName: String?
    public var isPlaying: Bool
    public var appVersion: String
    public var build: String
    public var osVersion: String

    public init(cpuPercent: Double?, memoryBytes: UInt64?, thermal: KeepAwakeRules.Thermal, audio: AudioCapture,
                playerName: String?, isPlaying: Bool, appVersion: String, build: String, osVersion: String) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.thermal = thermal
        self.audio = audio
        self.playerName = playerName
        self.isPlaying = isPlaying
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
    }

    /// Takes the player's name and Playing or Paused from `nowPlaying` and drops the rest.
    public init(cpuPercent: Double?, memoryBytes: UInt64?, thermal: KeepAwakeRules.Thermal, audio: AudioCapture,
                nowPlaying: NowPlaying?, appVersion: String, build: String, osVersion: String) {
        self.init(cpuPercent: cpuPercent, memoryBytes: memoryBytes, thermal: thermal, audio: audio,
                  playerName: nowPlaying?.player.rawValue, isPlaying: nowPlaying?.isPlaying ?? false,
                  appVersion: appVersion, build: build, osVersion: osVersion)
    }

    // MARK: Words and marks

    public static let unknown = "Unknown"

    public static func thermalWord(_ level: KeepAwakeRules.Thermal) -> String {
        switch level {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        }
    }

    /// The largest CPU percent shown. A bad sample can be finite and enormous; clamping keeps the whole-number
    /// conversion safe and the value stays far over the idle budget, so it still reads High.
    static let cpuCeilingPercent = 100_000.0

    /// CPU in tenths of a percent as shown, nil when there is no usable number.
    private static func cpuTenths(_ cpu: Double?) -> Int? {
        guard let cpu, cpu.isFinite else { return nil }
        return Int((min(max(0, cpu), cpuCeilingPercent) * 10).rounded())
    }

    /// Memory in whole megabytes as shown.
    private static func wholeMegabytes(_ bytes: UInt64?) -> Int? {
        guard let bytes else { return nil }
        return Int((Double(bytes) / 1_048_576).rounded())
    }

    /// Over the idle CPU budget. Compares the value as shown, so "1.0%" is never marked High.
    public static func isHigh(cpu: Double?) -> Bool {
        guard let tenths = cpuTenths(cpu) else { return false }
        return tenths > Int((PerformanceBudget.idleCPUPercent * 10).rounded())
    }

    /// Over the idle memory budget. Compares the whole megabytes as shown.
    public static func isHigh(memoryBytes: UInt64?) -> Bool {
        guard let megabytes = wholeMegabytes(memoryBytes) else { return false }
        return Double(megabytes) > PerformanceBudget.idleMemoryMB
    }

    // MARK: Rows

    /// Label and value pairs in display order.
    public var rows: [Row] {
        let cpuHigh = Self.isHigh(cpu: cpuPercent)
        let memoryHigh = Self.isHigh(memoryBytes: memoryBytes)
        let cpuText = Self.cpuTenths(cpuPercent).map { "\($0 / 10).\($0 % 10)%" } ?? Self.unknown
        let memoryText = Self.wholeMegabytes(memoryBytes).map { "\($0) MB" } ?? Self.unknown
        let heatTone: Tone = thermal == .nominal ? .ok : thermal == .fair ? .neutral : .attention
        let audioTone: Tone = audio == .running ? .ok : audio == .off ? .neutral : .attention
        return [
            Row(field: .cpu, label: "CPU", value: cpuText, isHigh: cpuHigh, tone: cpuHigh ? .attention : .neutral),
            Row(field: .memory, label: "Memory", value: memoryText, isHigh: memoryHigh, tone: memoryHigh ? .attention : .neutral),
            Row(field: .heat, label: "Heat", value: Self.thermalWord(thermal), isHigh: false, tone: heatTone),
            Row(field: .audio, label: "System audio capture", value: audio.word, isHigh: false, tone: audioTone),
            Row(field: .nowPlaying, label: "Now playing", value: nowPlayingText, isHigh: false,
                tone: playerName == nil ? .neutral : .ok),
        ]
    }

    private var nowPlayingText: String {
        guard let playerName else { return "None" }
        return "\(Self.oneLine(playerName)), \(isPlaying ? "Playing" : "Paused")"
    }

    // MARK: Summary

    /// The text Copy puts on the clipboard: versions and the rows, nothing the person made or played.
    public var summaryText: String {
        var lines = [
            "Zeus diagnostics",
            "Zeus \(Self.oneLine(appVersion)) (build \(Self.oneLine(build)))",
            "macOS \(Self.oneLine(osVersion))",
        ]
        for row in rows { lines.append("\(row.label): \(row.value)\(row.isHigh ? " (High)" : "")") }
        return lines.joined(separator: "\n")
    }

    /// Keeps a value on one line so it cannot add a line of its own to the summary.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
