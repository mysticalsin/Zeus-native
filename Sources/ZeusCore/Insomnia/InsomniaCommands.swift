import Foundation

/// What a command printed and how it exited.
public struct InsomniaCommandResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String = "", stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var ok: Bool { status == 0 }
    public static let notFound = InsomniaCommandResult(status: 127, stderr: "not found")
}

/// Runs one program with arguments, never through a shell. Injected everywhere a lid-closed
/// session touches the system, so tests use a fake and never run sudo, pmset or osascript.
public protocol InsomniaCommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult
}

/// The real runner: Process with a timeout, so a hung pmset or tmux never hangs Zeus.
public struct ProcessCommandRunner: InsomniaCommandRunner {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 20) {
        self.timeout = timeout
    }

    public func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return .notFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            return InsomniaCommandResult(status: 126, stderr: error.localizedDescription)
        }
        // Read while it runs so a full pipe cannot block the child.
        let outBox = DataBox(), errBox = DataBox()
        let readers = DispatchGroup()
        DispatchQueue.global().async(group: readers) { outBox.data = out.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: readers) { errBox.data = err.fileHandleForReading.readDataToEndOfFile() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 3)
            _ = readers.wait(timeout: .now() + 1)
            return InsomniaCommandResult(status: 124, stdout: outBox.string, stderr: "timed out after \(Int(timeout)) s")
        }
        _ = readers.wait(timeout: .now() + 2)
        return InsomniaCommandResult(status: process.terminationStatus, stdout: outBox.string, stderr: errBox.string)
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
        var string: String { String(decoding: data, as: UTF8.self) }
    }
}

/// The exact command lines a lid-closed session runs. Pure, so tests can check every one.
public enum InsomniaCommand {
    public static let sudo = "/usr/bin/sudo"
    public static let pmset = "/usr/bin/pmset"
    public static let osascript = "/usr/bin/osascript"
    public static let launchctl = "/bin/launchctl"
    public static let visudo = "/usr/sbin/visudo"

    /// `sudo -n pmset -a disablesleep 1|0`: never prompts; fails fast without the rule.
    public static func disableSleep(_ on: Bool) -> (String, [String]) {
        (sudo, ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
    }

    /// `sudo -n pmset -a lowpowermode 1|0`.
    public static func lowPowerMode(_ on: Bool) -> (String, [String]) {
        (sudo, ["-n", pmset, "-a", "lowpowermode", on ? "1" : "0"])
    }

    /// `pmset -g`: SleepDisabled and lowpowermode, no sudo.
    public static let readPower = (pmset, ["-g"])
    /// `pmset displaysleepnow`: the screen off, no sudo.
    public static let displaySleepNow = (pmset, ["displaysleepnow"])

    /// `sudo -n -l <command>`: exits 0 only when the rule lets this user run it without a password.
    public static func sudoAllows(_ on: Bool = true) -> (String, [String]) {
        (sudo, ["-n", "-l", pmset, "-a", "disablesleep", on ? "1" : "0"])
    }

    public static let readVolume = (osascript, ["-e", "get volume settings"])
    public static let mute = (osascript, ["-e", "set volume with output muted"])

    /// Puts the volume and mute state back.
    public static func restoreVolume(_ volume: Int, muted: Bool) -> (String, [String]) {
        (osascript, ["-e", "set volume output volume \(min(max(volume, 0), 100))",
                     "-e", muted ? "set volume with output muted" : "set volume without output muted"])
    }
}

/// Reads what `pmset -g` and `get volume settings` print.
public enum InsomniaParse {
    /// `SleepDisabled 1` in `pmset -g`. pmset prints the line only when it is set, so no line is false.
    public static func sleepDisabled(_ pmsetG: String) -> Bool {
        value(of: "SleepDisabled", in: pmsetG) == "1"
    }

    /// `lowpowermode 0|1`, or `powermode 1` (Low Power) where macOS prints that instead.
    /// Nil when neither line is there or the value is not 0 or 1 (High Power is not "off").
    public static func lowPowerMode(_ pmsetG: String) -> Bool? {
        if let value = value(of: "lowpowermode", in: pmsetG) {
            return value == "1" ? true : value == "0" ? false : nil
        }
        switch value(of: "powermode", in: pmsetG) {
        case "1"?: return true
        case "0"?: return false
        default: return nil
        }
    }

    /// `output volume:50, input volume:75, alert volume:100, output muted:false`.
    public static func volume(_ settings: String) -> (volume: Int, muted: Bool)? {
        var volume: Int?
        var muted: Bool?
        for part in settings.split(separator: ",") {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pair.count == 2 else { continue }
            if pair[0] == "output volume" { volume = Int(pair[1]) }
            if pair[0] == "output muted" { muted = pair[1] == "true" }
        }
        guard let volume, let muted else { return nil }
        return (volume, muted)
    }

    private static func value(of key: String, in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == key { return String(parts[1]) }
        }
        return nil
    }
}
