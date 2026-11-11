// human-qa.swift
//
// Human-style end-to-end QA driver for the packaged Zeus.app. Run it through scripts/human-qa.sh, which compiles
// it with plain swiftc (no macros, no swift build) and supplies the process id and the evidence folder.
//
// It behaves like a person at the keyboard: it hovers the notch, presses buttons through the Accessibility API
// (AXPress, AXIncrement, set value, focus), types with real key events and cancels with the Esc key. After every
// action it waits for a visible effect and records how long that took.
//
// Rules this file keeps:
//   - It never requests a permission (AXIsProcessTrusted never prompts) and never touches another app.
//   - It never starts a recording and never uses the microphone, unless --allow-mic is given (Scribe Start only).
//     The Record countdown is always cancelled before it reaches zero.
//   - A step waiting more than 2 s starts `sample <pid> 3` into the evidence folder (freeze evidence).
//   - Plain Swift only: no @Observable, no #Preview, no Testing, so swiftc compiles it directly.
//
// Output: <evidence>/results-<phase>.json (one record per step: PASS, FAIL with a reason, or MANUAL with a reason)
// plus <evidence>/driver-<phase>.log. Exit: 0 no FAIL, 1 at least one FAIL, 2 not trusted, 3 setup error.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Options

struct Options {
    var pid: pid_t = 0
    var appPath = ""
    var bundleID = "app.zeus.mac"
    var phase = "main"            // main, persist
    var evidence = ""
    var only: String?
    var allowMic = false
    var screenshots = false
    var launchedAt: Double = 0    // epoch seconds when the script launched the app
    var checkTrust = false
}

func parseOptions() -> Options {
    var o = Options()
    let a = Array(CommandLine.arguments.dropFirst())
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < a.count else {
            FileHandle.standardError.write(Data("human-qa: \(flag) needs a value\n".utf8))
            exit(3)
        }
        return a[i]
    }
    while i < a.count {
        switch a[i] {
        case "--pid": o.pid = pid_t(Int32(value("--pid")) ?? 0)
        case "--app": o.appPath = value("--app")
        case "--bundle-id": o.bundleID = value("--bundle-id")
        case "--phase": o.phase = value("--phase")
        case "--evidence": o.evidence = value("--evidence")
        case "--only": o.only = value("--only")
        case "--launched-at": o.launchedAt = Double(value("--launched-at")) ?? 0
        case "--allow-mic": o.allowMic = true
        case "--screenshots": o.screenshots = true
        case "--check-trust": o.checkTrust = true
        default:
            FileHandle.standardError.write(Data("human-qa: unknown argument \(a[i])\n".utf8))
            exit(3)
        }
        i += 1
    }
    return o
}

let opts = parseOptions()

// MARK: - Time, logging

func nowEpoch() -> Double { Date().timeIntervalSince1970 }
func mono() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

var logHandle: FileHandle?

func log(_ message: String) {
    let line = String(format: "%.3f %@\n", nowEpoch(), message)
    FileHandle.standardError.write(Data(line.utf8))
    logHandle?.write(Data(line.utf8))
}

// MARK: - Accessibility helpers

func axCopy(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &ref)
    return err == .success ? ref : nil
}

func axString(_ el: AXUIElement, _ name: String) -> String {
    guard let r = axCopy(el, name) else { return "" }
    if let s = r as? String { return s }
    if let n = r as? NSNumber { return n.stringValue }
    return ""
}

func axBool(_ el: AXUIElement, _ name: String) -> Bool {
    (axCopy(el, name) as? NSNumber)?.boolValue ?? false
}

/// One element, with attributes read on demand (every read is an IPC call, so walks stay cheap).
final class AXN {
    let el: AXUIElement
    init(_ el: AXUIElement) { self.el = el }
    lazy var role: String = axString(el, "AXRole")
    lazy var title: String = axString(el, "AXTitle")
    lazy var desc: String = axString(el, "AXDescription")
    lazy var value: String = axString(el, "AXValue")
    lazy var ident: String = axString(el, "AXIdentifier")
    lazy var help: String = axString(el, "AXHelp")
    lazy var kids: [AXN] = ((axCopy(el, "AXChildren") as? [AXUIElement]) ?? []).map { AXN($0) }

    var selected: Bool { axBool(el, "AXSelected") }
    var enabled: Bool { axCopy(el, "AXEnabled") == nil ? true : axBool(el, "AXEnabled") }

    func mentions(_ needle: String) -> Bool {
        let n = needle.lowercased()
        return [title, desc, value].contains { $0.lowercased().contains(n) }
    }

    func actions() -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    var frame: CGRect? {
        guard let r = axCopy(el, "AXFrame"), CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue((r as! AXValue), .cgRect, &rect) else { return nil }
        return rect
    }

    var parent: AXN? {
        guard let r = axCopy(el, "AXParent"), CFGetTypeID(r) == AXUIElementGetTypeID() else { return nil }
        return AXN(r as! AXUIElement)
    }

    /// AXPress. A button that opens a menu blocks in the app until the menu closes, so a timeout is not a failure.
    @discardableResult
    func press(patient: Bool = false) -> Bool {
        AXUIElementSetMessagingTimeout(el, patient ? 1.0 : 3.0)
        let err = AXUIElementPerformAction(el, "AXPress" as CFString)
        return err == .success || (patient && err == .cannotComplete)
    }

    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    func setValue(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(el, "AXValue" as CFString, text as CFString) == .success
    }

    func focus() -> Bool {
        AXUIElementSetAttributeValue(el, "AXFocused" as CFString, kCFBooleanTrue) == .success
    }
}

struct Hit {
    let node: AXN
    let inButton: Bool
}

/// Depth-first search under `roots`. `inButton` tells the predicate the element sits inside a button.
func search(_ roots: [AXN], limit: Int = 6000, maxDepth: Int = 30, all: Bool = false,
            _ pred: @escaping (AXN, Bool) -> Bool) -> [Hit] {
    var out: [Hit] = []
    var budget = limit
    func go(_ n: AXN, _ depth: Int, _ inBtn: Bool) -> Bool {
        if budget <= 0 || depth > maxDepth { return false }
        budget -= 1
        if pred(n, inBtn) {
            out.append(Hit(node: n, inButton: inBtn))
            if !all { return true }
        }
        let btn = inBtn || n.role == "AXButton"
        for k in n.kids {
            if go(k, depth + 1, btn) { return true }
        }
        return false
    }
    for r in roots {
        if go(r, 0, false) { break }
    }
    return out
}

func first(_ roots: [AXN], _ pred: @escaping (AXN) -> Bool) -> AXN? {
    search(roots, all: false) { n, _ in pred(n) }.first?.node
}

func allMatching(_ roots: [AXN], _ pred: @escaping (AXN) -> Bool) -> [AXN] {
    search(roots, all: true) { n, _ in pred(n) }.map { $0.node }
}

let appEl: AXUIElement = AXUIElementCreateApplication(max(opts.pid, 1))

func appRoots() -> [AXN] {
    let app = AXN(appEl)
    var roots = app.kids
    if let windows = axCopy(appEl, "AXWindows") as? [AXUIElement] {
        for w in windows where !roots.contains(where: { CFEqual($0.el, w) }) { roots.append(AXN(w)) }
    }
    return roots
}

func window(titleContaining text: String) -> AXN? {
    appRoots().first { $0.role == "AXWindow" && $0.title.lowercased().contains(text.lowercased()) }
}

func alive() -> Bool {
    guard let running = NSRunningApplication(processIdentifier: opts.pid) else { return false }
    return !running.isTerminated
}

func activateApp() {
    NSRunningApplication(processIdentifier: opts.pid)?.activate(options: [])
}

func numberIn(_ text: String) -> Int? {
    let digits = text.filter { "0123456789".contains($0) }
    return digits.isEmpty ? nil : Int(digits)
}

// MARK: - Synthetic input (the same events a person makes)

func screenForNotch() -> NSScreen? {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
}

func moveMouse(to p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
}

/// A person hovers the top edge of the screen to open the notch.
func hoverNotch() {
    guard let screen = screenForNotch(), let primary = NSScreen.screens.first else { return }
    let top = primary.frame.height - screen.frame.maxY   // top edge in CG coordinates
    let x = screen.frame.midX
    for dx in [-24.0, 0.0, 12.0, 0.0] {
        moveMouse(to: CGPoint(x: x + dx, y: top + 3))
        pause(0.04)
    }
}

func pressKey(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    pause(0.02)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}

func pressEscape() { pressKey(53) }

func typeString(_ text: String) {
    for unit in text.utf16 {
        var c = unit
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        up?.post(tap: .cghidEventTap)
        pause(0.015)
    }
}

func frontmostIsZeus() -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == opts.pid
}

// MARK: - Steps, waits, freeze evidence

let PASS = "PASS", FAIL = "FAIL", MANUAL = "MANUAL"

struct Outcome {
    let status: String
    let reason: String
}
func pass(_ note: String = "") -> Outcome { Outcome(status: PASS, reason: note) }
func fail(_ reason: String) -> Outcome { Outcome(status: FAIL, reason: reason) }
func manual(_ reason: String) -> Outcome { Outcome(status: MANUAL, reason: reason) }

final class StepCtx {
    let journey: String
    let id: String
    let name: String
    let startMono = mono()
    let startEpoch = nowEpoch()
    var maxWait = 0.0
    var latency: Double?
    var evidence: [String] = []
    var notes: [String] = []
    var sampled = false
    init(_ journey: String, _ id: String, _ name: String) {
        self.journey = journey
        self.id = id
        self.name = name
    }
    /// Call after the visible effect appeared: milliseconds since `since` (default: step start).
    func stamp(since: Double? = nil) { latency = (mono() - (since ?? startMono)) * 1000 }
}

var records: [[String: Any]] = []
var samplers: [Process] = []
var anyFail = false

func startFreezeSample(_ ctx: StepCtx) {
    guard !ctx.sampled, alive() else { return }
    ctx.sampled = true
    let file = opts.evidence + "/freeze-\(opts.phase)-\(ctx.id).sample.txt"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
    p.arguments = [String(opts.pid), "3", "-file", file]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        samplers.append(p)
        ctx.evidence.append(file)
        ctx.notes.append("waited over 2 s: sample 3 started")
        log("freeze evidence started for \(ctx.id)")
    } catch {
        ctx.notes.append("sample could not start: \(error)")
    }
}

/// Polls `probe` until it returns a value or `timeout` passes. Updates the step's longest wait and starts the
/// freeze sample the first time a wait passes 2 s.
func waitFor<T>(_ ctx: StepCtx, _ timeout: Double, poll: Double = 0.05, _ probe: () -> T?) -> T? {
    let t0 = mono()
    while true {
        let found = probe()
        let elapsed = mono() - t0
        if elapsed > ctx.maxWait { ctx.maxWait = elapsed }
        if elapsed > 2.0 { startFreezeSample(ctx) }
        if let found { return found }
        if elapsed >= timeout { return nil }
        pause(poll)
    }
}

func takeScreenshot(_ ctx: StepCtx, _ tag: String) {
    guard opts.screenshots else { return }
    let file = opts.evidence + "/shot-\(opts.phase)-\(ctx.id)-\(tag).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", file]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    if (try? p.run()) != nil {
        p.waitUntilExit()
        if FileManager.default.fileExists(atPath: file) { ctx.evidence.append(file) }
    }
}

func wants(_ journey: String) -> Bool {
    guard let only = opts.only else { return true }
    return only == journey
}

func runStep(_ journey: String, _ id: String, _ name: String, _ body: (StepCtx) -> Outcome) {
    let ctx = StepCtx(journey, id, name)
    let outcome: Outcome
    if !alive() {
        outcome = fail("Zeus is not running (it quit or crashed earlier in this run)")
    } else {
        outcome = body(ctx)
    }
    if outcome.status == FAIL {
        anyFail = true
        takeScreenshot(ctx, "fail")
    }
    var rec: [String: Any] = [
        "journey": journey, "id": id, "name": name, "status": outcome.status, "reason": outcome.reason,
        "max_wait_ms": (ctx.maxWait * 1000).rounded(), "started_at": ctx.startEpoch, "ended_at": nowEpoch(),
        "evidence": ctx.evidence, "notes": ctx.notes,
    ]
    if let l = ctx.latency { rec["latency_ms"] = l.rounded() }
    records.append(rec)
    let lat = ctx.latency.map { String(format: " %.0f ms", $0) } ?? ""
    log("[\(outcome.status)] \(id)\(lat) \(outcome.reason)")
    writeResults()
}

func writeResults() {
    let doc: [String: Any] = [
        "schema_version": 1, "phase": opts.phase, "pid": Int(opts.pid), "written_at": nowEpoch(), "steps": records,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: opts.evidence + "/results-\(opts.phase).json"), options: .atomic)
}

// MARK: - Preferences (read from the app's defaults domain, never written)

let screenShareKey = "opt.general.showInScreenSharing"
let topBarKey = "appearance.topBarOffset"

func prefText(_ key: String) -> String {
    CFPreferencesAppSynchronize(opts.bundleID as CFString)
    guard let v = CFPreferencesCopyAppValue(key as CFString, opts.bundleID as CFString) else { return "unset" }
    return "\(v)"
}

// MARK: - Top bar and menus

func findMore() -> AXN? { first(appRoots()) { $0.ident == "notch.more" } }

/// Hovers the notch (as a person would) until the top bar's More button is in the accessibility tree.
func openTopBar(_ ctx: StepCtx, timeout: Double = 4.0) -> AXN? {
    if let m = findMore() { return m }
    activateApp()
    return waitFor(ctx, timeout, poll: 0.2) { () -> AXN? in
        hoverNotch()
        return findMore()
    }
}

func menuItems() -> [AXN] { allMatching(appRoots()) { $0.role == "AXMenuItem" } }

func closeOpenMenu() {
    guard let item = menuItems().first else { return }
    if let menu = item.parent, menu.perform("AXCancel") {
        pause(0.15)
        return
    }
    pressEscape()
    pause(0.2)
}

/// Opens the More (...) menu and returns its items once they are visible.
func openMoreMenu(_ ctx: StepCtx) -> [AXN]? {
    closeOpenMenu()
    guard let more = openTopBar(ctx) else { return nil }
    _ = more.press(patient: true)
    return waitFor(ctx, 2.5) { () -> [AXN]? in
        let items = menuItems()
        return items.isEmpty ? nil : items
    }
}

func menuTitle(_ item: AXN) -> String { item.title.isEmpty ? item.desc : item.title }

func screenShareItem(_ items: [AXN]) -> AXN? {
    items.first { menuTitle($0).lowercased().contains("screen shares") }
}

/// Selects a tab like a person: press its icon. A tab missing from the row falls back to Zeus's own debug socket.
func openTab(_ ctx: StepCtx, _ raw: String) -> Bool {
    guard openTopBar(ctx) != nil else {
        ctx.notes.append("top bar did not open")
        return false
    }
    if let tab = first(appRoots(), { $0.ident == "notch.tab.\(raw)" }) {
        _ = tab.press()
        return true
    }
    ctx.notes.append("tab \(raw) not in the visible row; used Zeus debug socket")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: opts.appPath + "/Contents/MacOS/Zeus")
    p.arguments = ["debug", "tab", raw]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// MARK: - Settings helpers

let settingsPages: [(raw: String, title: String)] = [
    ("general", "General"), ("appearance", "Appearance"), ("sounds", "Sounds"), ("notifications", "Notifications"),
    ("shortcuts", "Shortcuts"), ("insomnia", "Insomnia"), ("integrations", "Integrations"), ("murmure", "Murmure"),
    ("polyglot", "Polyglot"), ("dictation", "Dictation"), ("voice", "Voice"), ("engine", "Engine"),
    ("features", "Features"), ("beamer", "Beamer"), ("license", "License"), ("permissions", "Permissions"),
    ("privacy", "Privacy"), ("diagnostics", "Diagnostics"), ("about", "About"),
]

func settingsWindow() -> AXN? { window(titleContaining: "Zeus Settings") }

func openSettingsViaMenu(_ ctx: StepCtx) -> AXN? {
    if let w = settingsWindow() { return w }
    guard let items = openMoreMenu(ctx) else { return nil }
    guard let settings = items.first(where: { menuTitle($0).hasPrefix("Settings") }) else { return nil }
    _ = settings.press()
    return waitFor(ctx, 3.0) { settingsWindow() }
}

func sidebarButton(_ win: AXN, raw: String, title: String) -> AXN? {
    first([win]) { $0.role == "AXButton" && ($0.ident == "settings.sidebar.\(raw)" || $0.desc == title || $0.title == title) }
}

func textOf(_ n: AXN) -> String {
    if !n.value.isEmpty { return n.value }
    return n.title.isEmpty ? n.desc : n.title
}

func staticTexts(_ root: AXN) -> [String] {
    search([root], limit: 8000, all: true) { n, inBtn in
        !inBtn && (n.role == "AXStaticText" || n.role == "AXHeading") && !(n.value.isEmpty && n.title.isEmpty && n.desc.isEmpty)
    }.map { textOf($0.node) }
}

func headingVisible(_ win: AXN, _ title: String) -> Bool {
    !search([win], limit: 3000) { n, inBtn in
        !inBtn && (n.role == "AXStaticText" || n.role == "AXHeading") && (n.value == title || n.title == title || n.desc == title)
    }.isEmpty
}

func goToPage(_ ctx: StepCtx, _ win: AXN, _ page: (raw: String, title: String), selectedSupported: Bool) -> Bool {
    guard let button = sidebarButton(win, raw: page.raw, title: page.title) else {
        ctx.notes.append("no sidebar button for \(page.title)")
        return false
    }
    let t0 = mono()
    _ = button.press()
    let shown = waitFor(ctx, 4.0, poll: 0.04) { () -> Bool? in
        guard headingVisible(win, page.title) else { return nil }
        if selectedSupported && !button.selected { return nil }
        return staticTexts(win).count >= 3 ? true : nil
    }
    ctx.stamp(since: t0)
    return shown != nil
}

/// Text found on each Settings page during the sweep, so the card checks can say where something lives.
var pageTexts: [String: [String]] = [:]

func pageContaining(_ needle: String) -> String? {
    let n = needle.lowercased()
    for page in settingsPages {
        if (pageTexts[page.raw] ?? []).contains(where: { $0.lowercased().contains(n) }) { return page.raw }
    }
    return nil
}

func popupItems(_ ctx: StepCtx, _ win: AXN, labelHas words: [String]) -> [String]? {
    guard let popup = first([win], { n in
        ["AXPopUpButton", "AXMenuButton", "AXButton"].contains(n.role)
            && words.allSatisfy { n.desc.lowercased().contains($0) || n.title.lowercased().contains($0) }
    }) else { return nil }
    closeOpenMenu()
    _ = popup.press(patient: true)
    let items = waitFor(ctx, 2.5) { () -> [AXN]? in
        let found = menuItems()
        return found.isEmpty ? nil : found
    }
    let titles = (items ?? []).map { menuTitle($0) }
    closeOpenMenu()
    return titles
}

// MARK: - Persisted state between phases

var statePath: String { opts.evidence + "/state.json" }

func loadState() -> [String: Any] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}

func saveState(_ s: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
}

var state: [String: Any] = loadState()

func sliderNode(_ win: AXN) -> AXN? {
    first([win]) { n in
        n.ident == "settings.appearance.topBarPosition"
            || (n.desc.lowercased().contains("top bar position") && (n.role == "AXSlider" || n.actions().contains("AXIncrement")))
    }
}

func shareToggle(_ win: AXN) -> AXN? {
    first([win]) { n in
        ["AXCheckBox", "AXSwitch", "AXButton", "AXRadioButton"].contains(n.role)
            && (n.desc == "Show Zeus in screen shares" || n.title == "Show Zeus in screen shares")
    }
}

/// Flips the quick screen-share item in the More menu. Returns (title before, title after).
func flipShareViaMenu(_ ctx: StepCtx) -> (String, String)? {
    guard let items = openMoreMenu(ctx), let item = screenShareItem(items) else { return nil }
    let before = menuTitle(item)
    _ = item.press()
    pause(0.25)
    guard let again = openMoreMenu(ctx), let item2 = screenShareItem(again) else { return nil }
    let after = menuTitle(item2)
    closeOpenMenu()
    return (before, after)
}

func currentShareLabel(_ ctx: StepCtx) -> String? {
    guard let items = openMoreMenu(ctx), let item = screenShareItem(items) else { return nil }
    let title = menuTitle(item)
    closeOpenMenu()
    return title
}

// MARK: - Journey: launch

func journeyLaunch() {
    let launchBase = opts.launchedAt > 0 ? mono() - (nowEpoch() - opts.launchedAt) : mono()
    runStep("launch", "launch.process", "Zeus process is running") { _ in
        alive() ? pass("pid \(opts.pid)") : fail("process \(opts.pid) is not running")
    }
    runStep("launch", "launch.window", "Zeus shows a window or panel in under 3 s") { c in
        let found = waitFor(c, 6.0, poll: 0.05) { () -> Bool? in
            appRoots().contains { $0.role == "AXWindow" } ? true : nil
        }
        c.stamp(since: launchBase)
        guard found != nil else { return fail("no window in the accessibility tree after \(Int(c.latency ?? 0)) ms") }
        return (c.latency ?? 0) < 3000 ? pass() : fail("first window after \(Int(c.latency ?? 0)) ms, budget 3000 ms")
    }
    runStep("launch", "launch.topbar", "Top bar opens on hover in under 3 s") { c in
        let found = openTopBar(c, timeout: 6.0)
        c.stamp(since: launchBase)
        guard found != nil else { return fail("More button never appeared after \(Int(c.latency ?? 0)) ms of hovering the notch") }
        return (c.latency ?? 0) < 3000 ? pass() : fail("top bar after \(Int(c.latency ?? 0)) ms, budget 3000 ms")
    }
    runStep("launch", "launch.nocrash", "No crash during the first seconds") { _ in
        pause(1.0)
        return alive() ? pass() : fail("Zeus exited during launch")
    }
}

// MARK: - Journey: top bar

func journeyTopBar() {
    runStep("topbar", "topbar.more-menu", "More (...) menu opens with its items") { c in
        guard let items = openMoreMenu(c) else { return fail("the More menu did not open (button or items not found)") }
        c.stamp()
        let titles = items.map { menuTitle($0) }
        let need = ["Settings", "Edit tabs", "Show Zeus beside the pointer"]
        let missing = need.filter { n in !titles.contains { $0.hasPrefix(n) } }
        if !missing.isEmpty { return fail("menu is missing \(missing.joined(separator: ", ")); has \(titles)") }
        if screenShareItem(items) == nil { return fail("no screen-share item in the menu; has \(titles)") }
        return pass()
    }
    var settingsWin: AXN?
    runStep("topbar", "topbar.settings-open", "Settings opens from the More menu and shows the Appearance page") { c in
        guard let win = openSettingsViaMenu(c) else { return fail("Zeus Settings window did not appear") }
        settingsWin = win
        c.stamp()
        guard let appearance = sidebarButton(win, raw: "appearance", title: "Appearance") else { return fail("no Appearance sidebar button") }
        _ = appearance.press()
        let ok = waitFor(c, 3.0) { () -> Bool? in headingVisible(win, "Appearance") ? true : nil }
        return ok != nil ? pass() : fail("Appearance page did not render")
    }
    runStep("topbar", "topbar.screenshare-flip", "Show Zeus in screen shares: first press flips the setting") { c in
        guard let original = currentShareLabel(c) else { return fail("could not read the screen-share menu item") }
        state["shareLabelOriginal"] = original
        state["sharePrefOriginal"] = prefText(screenShareKey)
        guard let flipped = flipShareViaMenu(c) else { return fail("could not press the screen-share menu item") }
        c.stamp()
        guard flipped.0 != flipped.1 else { return fail("menu item still says \"\(flipped.1)\" after pressing it") }
        state["shareLabelChanged"] = flipped.1
        return pass("\"\(flipped.0)\" became \"\(flipped.1)\"; stored value \(prefText(screenShareKey))")
    }
    runStep("topbar", "topbar.screenshare-flip-back", "Show Zeus in screen shares: second press flips it back") { c in
        guard let flipped = flipShareViaMenu(c) else { return fail("could not press the screen-share menu item") }
        c.stamp()
        let original = state["shareLabelOriginal"] as? String ?? ""
        guard flipped.0 != flipped.1 else { return fail("menu item did not change (\"\(flipped.1)\")") }
        guard flipped.1 == original else { return fail("expected \"\(original)\" after flipping back, got \"\(flipped.1)\"") }
        return pass("stored value \(prefText(screenShareKey))")
    }
    runStep("topbar", "topbar.screenshare-settings-agrees", "Appearance toggle agrees with the menu") { c in
        guard let win = settingsWindow() ?? settingsWin else { return fail("Settings window is gone") }
        guard let toggle = shareToggle(win) else { return fail("no \"Show Zeus in screen shares\" toggle on Appearance") }
        guard let label = currentShareLabel(c) else { return fail("could not read the menu item") }
        let shown = label.lowercased().hasPrefix("hide")
        let on = ["1", "true", "on"].contains(toggle.value.lowercased())
        c.stamp()
        return on == shown ? pass("both say \(shown ? "shown" : "hidden")") : fail("menu says \(shown ? "shown" : "hidden") but the toggle value is \"\(toggle.value)\"")
    }
    runStep("topbar", "topbar.position-slider", "Appearance: top bar position slider moves") { c in
        guard let win = settingsWindow() ?? settingsWin else { return fail("Settings window is gone") }
        guard let slider = sliderNode(win) else { return fail("no \"Top bar position\" slider on Appearance") }
        let before = numberIn(slider.value)
        state["sliderOriginal"] = before ?? -1
        state["sliderPrefOriginal"] = prefText(topBarKey)
        var moved = false
        for action in ["AXIncrement", "AXDecrement"] where !moved {
            _ = slider.perform(action)
            let t0 = mono()
            moved = waitFor(c, 1.5) { () -> Bool? in
                guard let node = sliderNode(win) else { return nil }
                return numberIn(node.value) != before ? true : nil
            } != nil
            if moved { c.stamp(since: t0) }
        }
        guard moved, let now = sliderNode(win).flatMap({ numberIn($0.value) }) else {
            return fail("slider value stayed at \(before.map(String.init) ?? "?") after increment and decrement")
        }
        state["sliderChanged"] = now
        state["sliderPrefChanged"] = prefText(topBarKey)
        return pass("\(before.map(String.init) ?? "?") became \(now); stored value \(prefText(topBarKey))")
    }
    runStep("topbar", "topbar.persist-prep", "Leave both settings changed for the restart check") { c in
        guard let flipped = flipShareViaMenu(c) else { return fail("could not flip the screen-share item") }
        state["shareLabelFinal"] = flipped.1
        saveState(state)
        return pass("left at \"\(flipped.1)\"")
    }
}

// MARK: - Journey: settings

func journeySettings() {
    var win: AXN?
    var selectedSupported = true
    runStep("settings", "settings.sidebar-complete", "Settings window opens and the sidebar lists every page") { c in
        win = openSettingsViaMenu(c)
        guard let w = win else { return fail("Zeus Settings window did not appear") }
        c.stamp()
        let prefix = "settings.sidebar."
        let sidebarIDs = allMatching([w]) { $0.ident.hasPrefix(prefix) }.map { String($0.ident.dropFirst(prefix.count)) }
        if !sidebarIDs.isEmpty {
            let expected = settingsPages.map { $0.raw }
            let missing = expected.filter { !sidebarIDs.contains($0) }
            let extra = sidebarIDs.filter { !expected.contains($0) && $0.lowercased() != "iphone" }
            if !missing.isEmpty || !extra.isEmpty { return fail("sidebar differs from the expected list; missing \(missing), unexpected \(extra)") }
        } else {
            let missing = settingsPages.filter { sidebarButton(w, raw: $0.raw, title: $0.title) == nil }.map { $0.title }
            if !missing.isEmpty { return fail("sidebar buttons not found: \(missing)") }
        }
        selectedSupported = !allMatching([w]) { $0.role == "AXButton" && $0.selected }.isEmpty
        return pass("\(settingsPages.count) pages")
    }
    for page in settingsPages {
        runStep("settings", "settings.page.\(page.raw)", "\(page.title) page renders in under 1 s") { c in
            guard let w = win ?? settingsWindow() else { return fail("Settings window is gone") }
            guard goToPage(c, w, page, selectedSupported: selectedSupported) else {
                return fail("\(page.title) page did not render within 4 s")
            }
            pageTexts[page.raw] = staticTexts(w)
            let ms = c.latency ?? 0
            return ms <= 1000 ? pass() : fail("rendered after \(Int(ms)) ms, budget 1000 ms (Settings freeze regression)")
        }
        // Page-specific checks run right after their page rendered, while it is on screen.
        if page.raw == "dictation" { dictationChecks(win) }
        if page.raw == "engine" { jevCheck() }
        if page.raw == "about" { aboutChecks() }
    }
    runStep("settings", "settings.cards", "Cards present: language packs, speaker recognition") { _ in
        let packs = pageContaining("Language packs")
        let speakers = pageContaining("Speaker recognition")
        var problems: [String] = []
        if packs == nil { problems.append("no \"Language packs\" card on any page") }
        if speakers == nil { problems.append("no \"Speaker recognition\" card on any page") }
        if let p = packs, !["English", "French", "Spanish", "Portuguese"].allSatisfy({ n in (pageTexts[p] ?? []).contains { $0.contains(n) } }) {
            problems.append("Language packs card does not list English, French, Spanish and Portuguese")
        }
        return problems.isEmpty ? pass("language packs on \(packs ?? "?"), speaker recognition on \(speakers ?? "?")") : fail(problems.joined(separator: "; "))
    }
}

func dictationChecks(_ initial: AXN?) {
    runStep("settings", "settings.dictation-sound-picker", "Dictation: sound picker lists Soft click, Glass, Pop, Airy, None") { c in
        guard let w = initial ?? settingsWindow() else { return fail("Settings window is gone") }
        guard let titles = popupItems(c, w, labelHas: ["sound"]) else { return fail("no sound picker (a pop-up whose label mentions sound) on Dictation") }
        c.stamp()
        let wanted = ["Soft click", "Glass", "Pop", "Airy", "None"]
        let missing = wanted.filter { n in !titles.contains { $0.lowercased().contains(n.lowercased()) } }
        return missing.isEmpty ? pass("choices: \(titles.joined(separator: ", "))") : fail("missing \(missing.joined(separator: ", ")); picker lists \(titles)")
    }
    runStep("settings", "settings.dictation-sound-preview", "Dictation: sound preview button works") { c in
        guard let w = initial ?? settingsWindow() else { return fail("Settings window is gone") }
        guard let play = first([w], { $0.role == "AXButton" && ($0.title == "Play" || $0.desc == "Play") }) else {
            return fail("no Play button next to the sound picker")
        }
        guard play.enabled else { return manual("Play is disabled (the sound is set to None); pick a sound and press Play to hear it") }
        guard play.press() else { return fail("pressing Play failed") }
        pause(0.6)
        c.stamp()
        return alive() && first([w], { $0.title == "Play" || $0.desc == "Play" }) != nil
            ? pass("pressed Play; app still responsive. Whether it is audible is on the manual checklist")
            : fail("app stopped responding after Play")
    }
}

func jevCheck() {
    runStep("settings", "settings.jev-limit-default", "Engine: Jev monthly limit shows $10 when unset") { c in
        guard let w = settingsWindow() else { return fail("Settings window is gone") }
        guard let field = first([w], { $0.ident == "settings.engine.jevLimit" || (($0.role == "AXTextField" || $0.role == "AXTextArea") && $0.desc.lowercased().contains("monthly limit")) }) else {
            return fail("no Jev monthly limit field on Engine")
        }
        c.stamp()
        let shown = field.value
        let rowText = staticTexts(w).filter { $0.contains("$") || $0.lowercased().contains("limit") }
        if shown.contains("10") || rowText.contains(where: { $0.contains("US$10") || $0.contains("$10") }) {
            return pass("field shows \"\(shown)\"")
        }
        return fail("field shows \"\(shown)\" (expected 10); row text: \(rowText.prefix(3))")
    }
}

func aboutChecks() {
    runStep("settings", "settings.about-credit", "About shows \"Built by Tony Walteur\"") { c in
        guard let w = settingsWindow() else { return fail("Settings window is gone") }
        let texts = staticTexts(w)
        c.stamp()
        return texts.contains { $0.contains("Built by Tony Walteur") } ? pass() : fail("credit line not found; page text: \(texts.prefix(6))")
    }
    runStep("settings", "settings.about-version", "About shows the version") { c in
        guard let w = settingsWindow() else { return fail("Settings window is gone") }
        let texts = staticTexts(w)
        c.stamp()
        if let line = texts.first(where: { $0.hasPrefix("Version ") && $0.contains(where: { "0123456789".contains($0) }) }) { return pass(line) }
        return fail("no \"Version x.y\" line; page text: \(texts.prefix(6))")
    }
}

// MARK: - Journey: record

func recordButton() -> AXN? {
    first(appRoots()) { n in
        guard n.role == "AXButton" else { return false }
        if n.ident == "record.capture" { return true }
        if n.ident.hasPrefix("notch.tab.") { return false }
        return n.desc == "Record" || n.desc.hasPrefix("Cancel countdown") || n.desc.hasPrefix("Stop recording") || n.desc.hasPrefix("Cancel starting")
    }
}

func displayChips() -> [AXN] {
    allMatching(appRoots()) { n in
        (n.role == "AXButton" || n.role == "AXGroup" || n.role == "AXStaticText") && n.desc.contains("\u{00D7}") && !n.ident.hasPrefix("notch.")
    }
}

func mainWindowOrApp() -> AXN {
    first(appRoots()) { $0.role == "AXWindow" } ?? AXN(appEl)
}

func journeyRecord() {
    var granted = true
    runStep("record", "record.open", "Record page opens") { c in
        guard openTab(c, "recordly") else { return fail("could not select the Record tab") }
        let t0 = mono()
        let button = waitFor(c, 3.0) { recordButton() }
        c.stamp(since: t0)
        guard let b = button else { return fail("no Record button after opening the tab") }
        granted = b.enabled
        if !granted { c.notes.append("Record is disabled: Screen Recording is probably not granted to Zeus") }
        return pass()
    }
    runStep("record", "record.main-display", "Main display is preselected") { _ in
        let chips = displayChips()
        if chips.isEmpty {
            // One display: the page shows a single "Name, Main" line instead of chips.
            let line = staticTexts(mainWindowOrApp()).first { $0.hasSuffix(", Main") }
            return line != nil ? pass("single display: \(line ?? "")") : fail("no display chips and no \"..., Main\" line found")
        }
        if let main = chips.first(where: { $0.desc.lowercased().contains("main display") }) {
            return main.selected ? pass(main.desc) : fail("main display chip is not selected: \(main.desc)")
        }
        return fail("no chip is marked main display; chips: \(chips.map { $0.desc })")
    }
    runStep("record", "record.display-names", "Display picker lists the real display names") { _ in
        let real = NSScreen.screens.map { $0.localizedName }
        let chips = displayChips().map { $0.desc }
        let texts = chips.isEmpty ? staticTexts(mainWindowOrApp()) : chips
        let missing = real.filter { name in !texts.contains { $0.contains(name) } }
        return missing.isEmpty ? pass("\(real.joined(separator: ", "))") : fail("not listed: \(missing); the page shows \(texts.prefix(4))")
    }
    runStep("record", "record.countdown", "Record shows the 3, 2, 1 countdown (no capture)") { c in
        guard granted else { return manual("Screen Recording is not granted to Zeus, so Record is disabled. Grant it in System Settings, then rerun --only record") }
        guard let button = recordButton(), button.desc == "Record" else { return fail("Record button is not idle (\(recordButton()?.desc ?? "missing"))") }
        let t0 = mono()
        activateApp()
        _ = button.press()
        let counting = waitFor(c, 2.0, poll: 0.03) { () -> AXN? in
            guard let b = recordButton(), b.desc.hasPrefix("Cancel countdown") else { return nil }
            return b
        }
        c.stamp(since: t0)
        guard let shown = counting else {
            // Safety: never leave a countdown or a capture running.
            if let b = recordButton(), b.desc != "Record" { _ = b.press() }
            return fail("no countdown appeared within 2 s of pressing Record")
        }
        return pass(shown.desc)
    }
    runStep("record", "record.esc-cancel", "Esc cancels the countdown before it reaches 0") { c in
        guard granted else { return manual("depends on the countdown step, which needs Screen Recording") }
        guard let b = recordButton(), b.desc.hasPrefix("Cancel countdown") else { return fail("no countdown is running to cancel") }
        _ = b
        let t0 = mono()
        pressEscape()
        var idle = waitFor(c, 0.7, poll: 0.03) { () -> Bool? in recordButton()?.desc == "Record" ? true : nil }
        var usedButton = false
        if idle == nil, let still = recordButton(), still.desc.hasPrefix("Cancel countdown") {
            // The safety net: the countdown must never reach 0 and start a capture.
            _ = still.press()
            usedButton = true
            idle = waitFor(c, 0.8, poll: 0.03) { () -> Bool? in recordButton()?.desc == "Record" ? true : nil }
        }
        c.stamp(since: t0)
        guard idle != nil else {
            if let s = recordButton(), s.desc.hasPrefix("Stop recording") || s.desc.hasPrefix("Cancel starting") { _ = s.press() }
            return fail("Record did not return to idle after Esc")
        }
        return usedButton ? fail("Esc did not cancel the countdown (pressing the button did)") : pass()
    }
    runStep("record", "record.idle-no-capture", "State returns to idle and nothing is captured") { c in
        guard granted else { return manual("depends on the countdown step, which needs Screen Recording") }
        // Wait out the 3 s the countdown would have taken; a capture would show Stop recording / Cancel starting.
        let end = mono() + 3.6
        while mono() < end {
            if let b = recordButton(), b.desc.hasPrefix("Stop recording") || b.desc.hasPrefix("Cancel starting") {
                _ = b.press()
                return fail("a recording started even though the countdown was cancelled (\(b.desc))")
            }
            pause(0.1)
        }
        guard let b = recordButton(), b.desc == "Record", b.enabled else { return fail("Record is not idle and enabled after the countdown time passed") }
        c.stamp()
        return pass()
    }
}

// MARK: - Journey: scribe

func journeyScribe() {
    var memoryWin: AXN?
    runStep("scribe", "scribe.open", "Scribe page opens") { c in
        guard openTab(c, "scribe") else { return fail("could not select the Scribe tab") }
        let t0 = mono()
        let ready = waitFor(c, 3.0) { () -> Bool? in
            first(appRoots()) { $0.ident == "scribe.start" || $0.mentions("Listens to a meeting") || $0.mentions("Ready when you are") } != nil ? true : nil
        }
        c.stamp(since: t0)
        return ready != nil ? pass() : fail("Scribe page content did not appear")
    }
    runStep("scribe", "scribe.animation-settles", "Opening animation completes (layout stops moving)") { c in
        guard let start = first(appRoots(), { $0.ident == "scribe.start" }) ?? first(appRoots(), { $0.role == "AXButton" && $0.title == "Start" }) else {
            return fail("no Start button to watch")
        }
        let t0 = mono()
        var last = start.frame
        let settled = waitFor(c, 3.0, poll: 0.15) { () -> Bool? in
            let now = start.frame
            let previous = last
            last = now
            guard let a = now, let b = previous else { return nil }
            return abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 ? true : nil
        }
        c.stamp(since: t0)
        return settled != nil && (c.latency ?? 0) < 2000 ? pass() : fail("layout still moving after \(Int(c.latency ?? 0)) ms")
    }
    runStep("scribe", "scribe.up-next-or-empty", "Up next card or the empty state is shown") { _ in
        let marks = ["Up next", "Ready when you are", "Finished meetings and their notes show up here", "Open notes for", "Recent meetings"]
        let found = marks.first { m in first(appRoots(), { $0.mentions(m) }) != nil }
        return found != nil ? pass("found \"\(found ?? "")\"") : fail("none of \(marks) is on the page")
    }
    runStep("scribe", "scribe.chips", "Source chips (Microphone, Call audio, Names) are present") { _ in
        let names = ["Microphone", "Call audio", "Names"]
        let missing = names.filter { n in first(appRoots(), { $0.desc.hasPrefix(n) || $0.title == n || $0.value == n }) == nil }
        return missing.isEmpty ? pass() : fail("chips not found: \(missing.joined(separator: ", "))")
    }
    runStep("scribe", "scribe.memory-open", "Memory window opens from Scribe") { c in
        guard let button = first(appRoots(), { n in n.role == "AXButton" && (n.title == "Memory" || n.desc == "Memory" || n.ident == "scribe.memory.open") }) else {
            return fail("no Memory button on the Scribe page")
        }
        let t0 = mono()
        _ = button.press()
        memoryWin = waitFor(c, 3.0) { window(titleContaining: "Memory") }
        c.stamp(since: t0)
        return memoryWin != nil ? pass() : fail("no window titled Memory appeared")
    }
    runStep("scribe", "scribe.memory-panes", "Memory shows a list pane and a detail pane") { _ in
        guard let w = memoryWin ?? window(titleContaining: "Memory") else { return fail("Memory window is gone") }
        let hasSearch = first([w], { $0.ident == "memory.search" || $0.desc.lowercased().contains("search") }) != nil
        let scrollAreas = allMatching([w]) { $0.role == "AXScrollArea" }.count
        let detail = first([w]) { $0.ident == "memory.page.editor" || $0.mentions("Select a page") || $0.mentions("No meetings") || $0.mentions("No transcript") }
        let list = first([w]) { $0.ident == "memory.results" || $0.ident.hasPrefix("memory.page.") || $0.role == "AXList" || $0.role == "AXTable" || $0.role == "AXOutline" }
        if hasSearch && (scrollAreas >= 2 || (list != nil && detail != nil)) { return pass("scroll areas: \(scrollAreas)") }
        return fail("search field: \(hasSearch), scroll areas: \(scrollAreas), list pane: \(list != nil), detail pane: \(detail != nil)")
    }
    runStep("scribe", "scribe.memory-search", "Memory search field accepts text and clears") { c in
        guard let w = memoryWin ?? window(titleContaining: "Memory") else { return fail("Memory window is gone") }
        func searchField() -> AXN? {
            first([w]) { n in n.ident == "memory.search" || (n.role == "AXTextField" && n.desc.lowercased().contains("search")) }
        }
        guard let field = searchField() else { return fail("no search field") }
        _ = field.focus()
        guard field.setValue("zzzz-no-such-meeting") else { return fail("could not type into the search field") }
        let t0 = mono()
        let took = waitFor(c, 1.5) { () -> Bool? in searchField()?.value == "zzzz-no-such-meeting" ? true : nil }
        c.stamp(since: t0)
        guard took != nil else { return fail("the search field did not keep the typed text") }
        if let clear = first([w], { $0.title == "Clear search" || $0.desc == "Clear search" || $0.ident == "memory.search.clear" }) {
            _ = clear.press()
        } else {
            _ = field.setValue("")
        }
        let cleared = waitFor(c, 1.5) { () -> Bool? in searchField()?.value.isEmpty == true ? true : nil }
        return cleared != nil ? pass() : fail("search field did not clear")
    }
    runStep("scribe", "scribe.memory-close", "Memory window closes") { c in
        guard let w = memoryWin ?? window(titleContaining: "Memory") else { return pass("already closed") }
        var closed = false
        if let btn = axCopy(w.el, "AXCloseButton"), CFGetTypeID(btn) == AXUIElementGetTypeID() {
            closed = AXN(btn as! AXUIElement).press()
        }
        let gone = waitFor(c, 2.0) { () -> Bool? in window(titleContaining: "Memory") == nil ? true : nil }
        return gone != nil && closed ? pass() : fail("Memory window is still open")
    }
    runStep("scribe", "scribe.start-mic", "Start listening and stop again (uses the microphone)") { c in
        guard opts.allowMic else { return manual("needs the microphone and a meeting; not run without --allow-mic") }
        guard let start = first(appRoots(), { $0.ident == "scribe.start" }) else { return fail("no Start button") }
        let t0 = mono()
        _ = start.press()
        let stop = waitFor(c, 4.0) { first(appRoots(), { $0.ident == "scribe.stop" }) }
        c.stamp(since: t0)
        guard let s = stop else { return fail("Scribe did not enter the listening state (permission prompt or an error banner?)") }
        pause(1.5)
        _ = s.press()
        let idle = waitFor(c, 8.0) { first(appRoots(), { $0.ident == "scribe.start" }) }
        return idle != nil ? pass() : fail("Scribe did not return to idle after Stop (end-of-meeting window may still be open)")
    }
}

// MARK: - Journey: alerts, talk

func journeyAlerts() {
    runStep("alerts", "alerts.open", "Alerts page opens") { c in
        guard openTab(c, "notifications") else { return fail("could not select the Alerts tab") }
        let t0 = mono()
        let ready = waitFor(c, 3.0) { () -> Bool? in
            let tab = first(appRoots()) { $0.ident == "notch.tab.notifications" }
            guard let t = tab else { return nil }
            if t.selected { return true }
            return first(appRoots(), { $0.mentions("alert") || $0.mentions("notification") || $0.mentions("Clear") }) != nil ? true : nil
        }
        c.stamp(since: t0)
        return ready != nil ? pass() : fail("Alerts page did not show")
    }
    runStep("alerts", "alerts.trigger", "A test alert appears and can be cleared") { _ in
        manual("Zeus has no test-alert hook in this build; trigger a real alert (for example a calendar or agent alert) and watch the notch")
    }
}

func journeyTalk() {
    runStep("talk", "talk.text-answer", "Typed question \"what time is it\" gets an answer; time to first answer text") { c in
        guard openTab(c, "chat") else { return fail("could not select the Chat tab") }
        let field = waitFor(c, 3.0) { () -> AXN? in
            first(appRoots()) { n in
                (n.role == "AXTextField" || n.role == "AXTextArea") && (n.ident == "chat.message" || n.mentions("Message") || n.help == "Message")
            }
        }
        guard let f = field else { return fail("no Message field on the Chat tab") }
        let prompt = "what time is it"
        let before = Set(staticTexts(mainWindowOrApp()))
        activateApp()
        _ = f.focus()
        if frontmostIsZeus() {
            typeString(prompt)
        } else {
            c.notes.append("Zeus is not frontmost; set the field value instead of typing")
        }
        if !f.value.contains(prompt) { _ = f.setValue(prompt) }
        guard f.value.contains(prompt) else { return fail("the Message field did not take the text (value: \"\(f.value)\")") }
        guard let send = first(appRoots(), { n in n.role == "AXButton" && (n.desc == "Send" || n.title == "Send") }) else { return fail("no Send button") }
        let t0 = mono()
        _ = send.press()
        let answer = waitFor(c, 30.0, poll: 0.08) { () -> String? in
            let now = staticTexts(mainWindowOrApp())
            return now.first { !before.contains($0) && !$0.lowercased().contains(prompt) && $0.count >= 2 && $0 != "Send" && $0 != "Stop" }
        }
        c.stamp(since: t0)
        guard answer != nil else { return fail("no answer text within 30 s (is an AI provider connected?)") }
        let ms = c.latency ?? 0
        return ms <= 10_000 ? pass("first answer text after \(Int(ms)) ms") : fail("first answer text after \(Int(ms)) ms, budget 10000 ms")
    }
    runStep("talk", "talk.voice", "Talk with the voice key (Ultron voice, speed)") { _ in
        manual("needs a human: microphone, speech recognition and the sound of the answer")
    }
}

// MARK: - Journey: quit and persistence

func waitForExit(_ ctx: StepCtx, _ timeout: Double) -> Bool {
    waitFor(ctx, timeout, poll: 0.1) { () -> Bool? in alive() ? nil : true } != nil
}

func journeyQuit() {
    runStep("quit", "quit.clean", "Zeus quits cleanly") { c in
        let t0 = mono()
        NSRunningApplication(processIdentifier: opts.pid)?.terminate()
        let gone = waitForExit(c, 8.0)
        c.stamp(since: t0)
        return gone ? pass("exited after \(Int(c.latency ?? 0)) ms") : fail("still running 8 s after a normal quit request")
    }
}

func journeyPersist() {
    let launchBase = opts.launchedAt > 0 ? mono() - (nowEpoch() - opts.launchedAt) : mono()
    runStep("persist", "persist.launch", "Relaunch: top bar opens in under 3 s") { c in
        let found = openTopBar(c, timeout: 6.0)
        c.stamp(since: launchBase)
        guard found != nil else { return fail("top bar did not open after the relaunch") }
        return (c.latency ?? 0) < 3000 ? pass() : fail("top bar after \(Int(c.latency ?? 0)) ms, budget 3000 ms")
    }
    runStep("persist", "persist.screenshare", "Screen-share setting survived the restart") { c in
        guard let expected = state["shareLabelFinal"] as? String else { return fail("no state from the main run (state.json missing); run the full script") }
        guard let label = currentShareLabel(c) else { return fail("could not read the menu item") }
        c.stamp()
        return label == expected ? pass("still \"\(label)\"; stored value \(prefText(screenShareKey))") : fail("expected \"\(expected)\", found \"\(label)\"")
    }
    var settingsWin: AXN?
    runStep("persist", "persist.position", "Top bar position survived the restart") { c in
        guard let expected = state["sliderChanged"] as? Int else { return fail("no state from the main run (state.json missing)") }
        guard let win = openSettingsViaMenu(c) else { return fail("Settings did not open") }
        settingsWin = win
        guard let appearance = sidebarButton(win, raw: "appearance", title: "Appearance") else { return fail("no Appearance button") }
        _ = appearance.press()
        _ = waitFor(c, 3.0) { () -> Bool? in headingVisible(win, "Appearance") ? true : nil }
        guard let slider = waitFor(c, 3.0, { sliderNode(win) }) else { return fail("slider not found") }
        c.stamp()
        let now = numberIn(slider.value)
        let expectedPref = state["sliderPrefChanged"] as? String ?? ""
        let nowPref = prefText(topBarKey)
        if now == expected && nowPref == expectedPref { return pass("slider \(expected); stored value \(nowPref)") }
        return fail("expected slider \(expected) and stored \(expectedPref); found \(now.map(String.init) ?? "?") and \(nowPref)")
    }
    runStep("persist", "persist.restore", "Restore your original settings") { c in
        var problems: [String] = []
        // Screen share back to its original label.
        let originalLabel = state["shareLabelOriginal"] as? String ?? ""
        if let label = currentShareLabel(c), label != originalLabel, !originalLabel.isEmpty {
            if let flipped = flipShareViaMenu(c) {
                if flipped.1 != originalLabel { problems.append("screen-share menu says \"\(flipped.1)\", wanted \"\(originalLabel)\"") }
            } else {
                problems.append("could not flip screen share back")
            }
        }
        // Top bar position back to the original.
        if let win = settingsWin ?? settingsWindow(), let slider = sliderNode(win) {
            let original = state["sliderOriginal"] as? Int ?? -1
            let originalPref = state["sliderPrefOriginal"] as? String ?? "unset"
            if originalPref == "unset" {
                if let reset = first([win], { $0.ident == "settings.appearance.topBarPositionReset" || $0.title == "Reset" || $0.desc == "Reset" }) {
                    _ = reset.press()
                    pause(0.3)
                } else {
                    problems.append("no Reset button for the position")
                }
                if prefText(topBarKey) != "unset" { problems.append("stored position is \(prefText(topBarKey)), was unset") }
            } else {
                var tries = 0
                while let node = sliderNode(win), let value = numberIn(node.value), value != original, tries < 20 {
                    _ = slider.perform(value > original ? "AXDecrement" : "AXIncrement")
                    pause(0.15)
                    tries += 1
                }
                if let now = sliderNode(win).flatMap({ numberIn($0.value) }), original >= 0, now != original {
                    problems.append("slider shows \(now), original was \(original)")
                }
            }
        } else {
            problems.append("slider not reachable to restore")
        }
        c.stamp()
        if problems.isEmpty { return pass("screen share \"\(currentShareLabel(c) ?? "?")\", position stored \(prefText(topBarKey))") }
        return fail(problems.joined(separator: "; ") + ". Restore by hand in Settings > Appearance")
    }
    runStep("persist", "persist.quit", "Zeus quits cleanly after the check") { c in
        let t0 = mono()
        NSRunningApplication(processIdentifier: opts.pid)?.terminate()
        let gone = waitForExit(c, 8.0)
        c.stamp(since: t0)
        return gone ? pass() : fail("still running 8 s after a normal quit request")
    }
}

// MARK: - Main

func writeDriverInfo() {
    let screens: [[String: Any]] = NSScreen.screens.map {
        ["name": $0.localizedName, "width": Int($0.frame.width), "height": Int($0.frame.height), "notch": $0.safeAreaInsets.top > 0]
    }
    let info: [String: Any] = [
        "macos": ProcessInfo.processInfo.operatingSystemVersionString, "phase": opts.phase, "app": opts.appPath,
        "bundle_id": opts.bundleID, "pid": Int(opts.pid), "screens": screens, "allow_mic": opts.allowMic,
        "ax_trusted": AXIsProcessTrusted(),
    ]
    if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: opts.evidence + "/driver-info-\(opts.phase).json"), options: .atomic)
    }
}

_ = NSApplication.shared

if opts.checkTrust {
    let trusted = AXIsProcessTrusted()
    print(trusted ? "trusted" : "not trusted")
    exit(trusted ? 0 : 2)
}
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("human-qa: this terminal is not allowed to control the computer (Accessibility).\n".utf8))
    exit(2)
}
guard opts.pid > 0, !opts.evidence.isEmpty else {
    FileHandle.standardError.write(Data("human-qa: --pid and --evidence are required\n".utf8))
    exit(3)
}
FileManager.default.createFile(atPath: opts.evidence + "/driver-\(opts.phase).log", contents: nil)
logHandle = FileHandle(forWritingAtPath: opts.evidence + "/driver-\(opts.phase).log")
AXUIElementSetMessagingTimeout(appEl, 3.0)
writeDriverInfo()
log("human-qa driver phase=\(opts.phase) pid=\(opts.pid) only=\(opts.only ?? "all")")

if opts.phase == "persist" {
    journeyPersist()
} else {
    if wants("launch") { journeyLaunch() }
    if wants("topbar") { journeyTopBar() }
    if wants("settings") { journeySettings() }
    if wants("record") { journeyRecord() }
    if wants("scribe") { journeyScribe() }
    if wants("alerts") { journeyAlerts() }
    if wants("talk") { journeyTalk() }
    if opts.only == nil { journeyQuit() }
}

for p in samplers { p.waitUntilExit() }
writeResults()
exit(anyFail ? 1 : 0)
