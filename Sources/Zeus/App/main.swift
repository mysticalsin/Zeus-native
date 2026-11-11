import AppKit
import ZeusCore

// Explicit QA startup (`--qa-startup <root>`): decided before anything else runs, and fail closed.
// Without the flag this is `.normal` and nothing below changes. The launcher sets the environment;
// this only checks it, never sets it.
let startupPolicy: StartupPolicy = {
    var userTemp = [CChar](repeating: 0, count: 1024)
    let tempLength = confstr(_CS_DARWIN_USER_TEMP_DIR, &userTemp, userTemp.count)
    let launchTemp = tempLength > 0 ? String(cString: userTemp) : ""
    let realHome = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? ""
    return StartupPolicy.decide(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment,
                                launchTemporaryDirectory: launchTemp, realHome: realHome)
}()
StartupPolicy.current = startupPolicy
switch startupPolicy.mode {
case .normal:
    break
case .invalid(let reason):
    fputs("--qa-startup refused: \(reason)\n", stderr)
    exit(78)
case .qa(let root):
    func refuse(_ reason: String) -> Never {
        fputs("--qa-startup refused: \(reason)\n", stderr)
        exit(78)
    }
    var info = stat()
    let rootStat = lstat(root, &info) == 0
    var marker = stat()
    let markerStat = lstat(root + "/" + StartupPolicy.markerFileName, &marker) == 0
    if let reason = StartupPolicy.verifyRoot(StartupPolicy.RootObservation(
        isDirectory: rootStat && (info.st_mode & S_IFMT) == S_IFDIR,
        ownerMatches: rootStat && info.st_uid == getuid(),
        markerIsRegularFile: markerStat && (marker.st_mode & S_IFMT) == S_IFREG)) {
        refuse(reason)
    }
    let observedPaths = StartupPolicy.PathObservation(
        nsHome: NSHomeDirectory(),
        userHome: FileManager.default.homeDirectoryForCurrentUser.path,
        tildeHome: ("~" as NSString).expandingTildeInPath,
        supportDirectory: ZeusPaths.supportDirectory.path,
        temporaryDirectory: NSTemporaryDirectory())
    if let reason = StartupPolicy.verifyPaths(observedPaths, root: root) { refuse(reason) }
    // Probe boundary, not proof of OS isolation: stop here, before anything reads preferences or starts
    // the app, so QA never reaches the delegate. Full GUI QA is unsupported (StartupPolicy.fullGUIQASupported).
    print(StartupPolicy.probeBoundaryLine)
    exit(StartupPolicy.probeExitCode)
}

if !startupPolicy.isQA {
// `Zeus debug <subcommand>` (the app binary, invoked directly, as QA does): forward to the
// running app over its socket and exit. Must run before anything else ever starts an AppDelegate.
DebugForward.runIfRequested()

// Single instance: a second launch of Zeus.app hands off to the one already running, except for
// the non-interactive process images (snapshots, parity harnesses, the voice self-test).
let ownPID = ProcessInfo.processInfo.processIdentifier
let bundleID = Bundle.main.bundleIdentifier ?? "app.zeus.mac"
let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ownPID }
if InstanceGuard.shouldExit(argv: Array(CommandLine.arguments.dropFirst()), others: otherInstances.map(\.processIdentifier)) {
    otherInstances.first?.activate()
    exit(0)
}
}

let app = NSApplication.shared
let startupMode = ZeusStartupMode.resolve(arguments: CommandLine.arguments, isDebugBuild: _isDebugAssertConfiguration())
if !startupMode.allowsFullAppStartup {
    switch startupMode {
    case .normal:
        break // The normal mode is the only path to AppDelegate and its background services.
    case .unsupportedJevSettingsTest:
        fputs("--jev-settings-test is available only in a debug build.\n", stderr)
        exit(64)
    case .jevSettingsTest:
        #if DEBUG
        GlassFonts.register()
        MainActor.assumeIsolated { JevSettingsTestHarness.show(in: app) }
        app.run()
        exit(0)
        #else
        fputs("--jev-settings-test is available only in a debug build.\n", stderr)
        exit(64)
        #endif
    }
}
if !startupPolicy.isQA {
    KeychainSelfTest.runIfRequested()
    MainActor.assumeIsolated { MacControlSelfTest.runIfRequested() }
    // `--pointing-selftest --receipt <abs path> [--live]`: only when started explicitly.
    if MainActor.assumeIsolated({ PointingSelfTest.runIfRequested() }) { app.setActivationPolicy(.accessory); app.run() }
}
GlassFonts.register()
if !startupPolicy.isQA {
    if MainActor.assumeIsolated({ SnapshotRenderer.runEngineLogosIfRequested() }) { exit(0) }
    if SnapshotRenderer.runIfRequested() { exit(0) }
    if MainActor.assumeIsolated({ FilmRenderer.runIfRequested() }) { exit(0) }
    if DebugCommands.runIfRequested() { app.run() }
    if MainActor.assumeIsolated({ OnboardingParity.runIfRequested() || GSParity.runIfRequested() }) { app.run() }
}
let delegate = AppDelegate(policy: startupPolicy)
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu (LSUIElement is also set in Info.plist).
app.setActivationPolicy(.accessory)
app.run()
