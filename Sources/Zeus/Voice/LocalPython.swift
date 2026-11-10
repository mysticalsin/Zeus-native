import Foundation

/// A private Python environment under Application Support/Zeus/Python, shared by the local
/// speech tools (faster-whisper, Kokoro). Zeus creates it once when the person asks, and never
/// touches the system Python.
enum LocalPython {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/Python", isDirectory: true)
    }
    static var venv: URL { root.appendingPathComponent("venv", isDirectory: true) }
    static var python: URL { venv.appendingPathComponent("bin/python3") }
    static var exists: Bool { FileManager.default.isExecutableFile(atPath: python.path) }

    /// A system python3 to build the environment from.
    static var systemPython: String? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Whether the environment can import `module`.
    static func canImport(_ module: String) -> Bool {
        guard exists else { return false }
        return run(python.path, ["-I", "-c", "import \(module)"]).status == 0
    }

    @discardableResult
    static func run(_ launch: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval = 600) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe = Pipe()
        process.standardInput = inPipe
        var collected = (Data(), Data())
        let group = DispatchGroup()
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        group.enter(); group.enter()
        DispatchQueue.global().async { collected.0 = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        DispatchQueue.global().async { collected.1 = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if let input { inPipe.fileHandleForWriting.write(input) }
        try? inPipe.fileHandleForWriting.close()
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        process.waitUntilExit()
        killer.cancel()
        group.wait()
        return (process.terminationStatus, String(decoding: collected.0, as: UTF8.self), String(decoding: collected.1, as: UTF8.self))
    }

    /// Creates the environment and installs `packages` into it. Blocking; call off the main thread.
    static func install(_ packages: [String]) -> String? {
        guard let system = systemPython else { return "Python 3 is not installed on this Mac." }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if !exists {
            let made = run(system, ["-m", "venv", venv.path])
            guard made.status == 0 else { return "Could not create the Python environment." }
        }
        let installed = run(python.path, ["-m", "pip", "install", "--disable-pip-version-check", "--quiet"] + packages)
        guard installed.status == 0 else {
            let line = installed.error.split(separator: "\n").last.map(String.init) ?? "pip failed."
            return "Setup failed: \(line)"
        }
        return nil
    }
}
