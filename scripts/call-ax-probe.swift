// call-ax-probe.swift
//
// Diagnostic only. Run it yourself in Terminal DURING a live Zoom / Teams / Meet / Slack huddle call to learn how
// the app exposes the participant roster and the "who is speaking" indicator through the macOS Accessibility API.
//
//   xcrun swift scripts/call-ax-probe.swift [--app zoom|teams|meet|slack|auto] [--seconds 20] [--out <dir>]
//                                           [--redact | --no-redact]
//
// - Needs Terminal (or your shell host) enabled in System Settings > Privacy & Security > Accessibility.
//   The trust check never prompts. Exit 2 when not trusted.
// - Read-only on other apps, with one exception: for Chromium / Electron-style apps (Chrome, Edge, Arc, new Teams,
//   Slack) whose web content tree is empty until an assistive client asks for it, it sets AXManualAccessibility and
//   AXEnhancedUserInterface = true on the application element (the same switch VoiceOver-style tools use), only when
//   a first quick walk finds a nearly empty tree, and restores the prior values on exit (also on Ctrl-C).
// - Output stays local: <out>/snapshot-<label>-<n>.jsonl, <out>/diff-<label>.jsonl. Default out dir is
//   ~/AI-Brain-build/call-ax-probe/<timestamp>. No network.
// - Redaction (default ON): every word in a string is replaced by the first 8 hex chars of
//   SHA-256(per-run salt + lowercase word), except an allowlist of indicator words (speaking, muted, ...). The same
//   name gives the same hash within a run, so you can see which tile lights up without seeing the name.
//   --no-redact keeps raw text, for your eyes only.

import AppKit
import ApplicationServices
import CryptoKit
import Foundation

// MARK: - Options

struct Options {
    var app = "auto"
    var seconds = 20
    var out: String?
    var redact = true
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parseOptions() -> Options {
    var o = Options()
    let a = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < a.count {
        switch a[i] {
        case "--app":
            i += 1
            guard i < a.count, ["zoom", "teams", "meet", "slack", "auto"].contains(a[i]) else {
                die("--app must be one of zoom|teams|meet|slack|auto", code: 64)
            }
            o.app = a[i]
        case "--seconds":
            i += 1
            guard i < a.count, let n = Int(a[i]), n >= 1, n <= 600 else { die("--seconds must be 1...600", code: 64) }
            o.seconds = n
        case "--out":
            i += 1
            guard i < a.count else { die("--out needs a directory", code: 64) }
            o.out = (a[i] as NSString).expandingTildeInPath
        case "--redact": o.redact = true
        case "--no-redact": o.redact = false
        case "-h", "--help":
            print("usage: xcrun swift scripts/call-ax-probe.swift [--app zoom|teams|meet|slack|auto] [--seconds 20] [--out <dir>] [--redact|--no-redact]")
            exit(0)
        default:
            die("unknown argument \(a[i]) (try --help)", code: 64)
        }
        i += 1
    }
    return o
}

// MARK: - Targets

struct Target {
    let bundleID: String
    let label: String
    /// Web-content hosts whose AX tree may be empty until enhanced accessibility is requested.
    let web: Bool
}

let knownTargets: [Target] = [
    Target(bundleID: "us.zoom.xos", label: "zoom", web: false),
    Target(bundleID: "com.microsoft.teams2", label: "teams", web: true),
    Target(bundleID: "com.microsoft.teams", label: "teams-classic", web: true),
    Target(bundleID: "com.tinyspeck.slackmacgap", label: "slack", web: true),
    Target(bundleID: "com.google.Chrome", label: "chrome", web: true),
    Target(bundleID: "company.thebrowser.Browser", label: "arc", web: true),
    Target(bundleID: "com.microsoft.edgemac", label: "edge", web: true),
    Target(bundleID: "com.apple.Safari", label: "safari", web: false),
    Target(bundleID: "com.apple.FaceTime", label: "facetime", web: false),
]

func wantedBundleIDs(_ app: String) -> [String] {
    switch app {
    case "zoom": return ["us.zoom.xos"]
    case "teams": return ["com.microsoft.teams2", "com.microsoft.teams"]
    case "slack": return ["com.tinyspeck.slackmacgap"]
    case "meet": return ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.apple.Safari"]
    default: return knownTargets.map { $0.bundleID }
    }
}

// MARK: - AX helpers

func copyAttr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &ref)
    return err == .success ? ref : nil
}

func stringAttr(_ el: AXUIElement, _ name: String) -> String? {
    copyAttr(el, name) as? String
}

func boolAttr(_ el: AXUIElement, _ name: String) -> Bool? {
    guard let r = copyAttr(el, name), CFGetTypeID(r) == CFBooleanGetTypeID() else { return nil }
    return CFBooleanGetValue((r as! CFBoolean))
}

func frameAttr(_ el: AXUIElement) -> [Double]? {
    guard let r = copyAttr(el, "AXFrame"), CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue((r as! AXValue), .cgRect, &rect) else { return nil }
    let vals: [Double] = [Double(rect.origin.x), Double(rect.origin.y), Double(rect.size.width), Double(rect.size.height)]
    return vals.map { ($0 * 10).rounded() / 10 }
}

// MARK: - Records and redaction

struct Rec {
    var key: String          // path + role: identity used for diffing
    var path: String         // child-index path, e.g. 0.3.1
    var chain: String        // role chain, e.g. AXWindow>AXGroup>AXList
    var depth: Int
    var role: String?
    var subrole: String?
    var roleDescription: String?
    var title: String?
    var desc: String?
    var value: String?
    var identifier: String?
    var help: String?
    var selected: Bool?
    var enabled: Bool?
    var frame: [Double]?
    var keyword = false      // raw text matched /speak|talk|unmute|mute|parle|micro/i
    var personLike = false   // raw text looks like a person label (1-4 words, letters)

    var text: String? { title ?? desc ?? value }

    var json: [String: Any] {
        var d: [String: Any] = ["path": path, "chain": chain, "depth": depth]
        if let v = role { d["role"] = v }
        if let v = subrole { d["subrole"] = v }
        if let v = roleDescription { d["roleDescription"] = v }
        if let v = title { d["title"] = v }
        if let v = desc { d["description"] = v }
        if let v = value { d["value"] = v }
        if let v = identifier { d["identifier"] = v }
        if let v = help { d["help"] = v }
        if let v = selected { d["selected"] = v }
        if let v = enabled { d["enabled"] = v }
        if let v = frame { d["frame"] = v }
        if keyword { d["indicatorWord"] = true }
        if personLike { d["personLike"] = true }
        return d
    }
}

let allowlist: Set<String> = [
    "speak", "speaking", "speaker", "talking", "muted", "unmuted", "mute", "unmute",
    "participant", "participants", "video", "camera", "raise", "raised", "hand", "host", "you", "me",
    "pinned", "spotlight", "tile", "gallery", "active", "parle", "micro", "désactivé", "activé",
    "microphone", "is", "are", "has", "on", "off", "and", "the", "a", "in", "of", "to",
]

let keywordRegex = try! NSRegularExpression(pattern: "speak|talk|unmute|mute|parle|micro", options: [.caseInsensitive])

func matchesKeyword(_ s: String) -> Bool {
    keywordRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

func looksLikePerson(_ s: String) -> Bool {
    // Take the label part before the first comma / paren / dash, then require 1-4 letter-only words.
    let head = s.split(whereSeparator: { ",(-–—|:".contains($0) }).first.map(String.init) ?? s
    let words = head.split(separator: " ").map(String.init)
    guard (1...4).contains(words.count), head.count >= 2, head.count <= 40 else { return false }
    return words.allSatisfy { w in
        w.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            && !w.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
    }
}

final class Walker: @unchecked Sendable {
    let redact: Bool
    let salt = UUID().uuidString
    let maxDepth = 40
    let maxNodes = 20000
    private var count = 0

    init(redact: Bool) { self.redact = redact }

    func hash(_ lower: String) -> String {
        let digest = SHA256.hash(data: Data((salt + lower).utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Truncate to 120 chars, then (when redacting) hash each word except allowlisted indicator words.
    func clean(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let s = String(raw.prefix(120))
        guard redact else { return s }
        var out = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let lower = token.lowercased()
            out += allowlist.contains(lower) ? token : hash(lower)
            token = ""
        }
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" {
                token.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return out
    }

    func snapshot(windows: [AXUIElement], appElement: AXUIElement) -> [Rec] {
        count = 0
        var out: [Rec] = []
        if windows.isEmpty {
            walk(appElement, depth: 0, path: "app", chain: "AXApplication", out: &out)
        } else {
            for (i, w) in windows.enumerated() {
                walk(w, depth: 0, path: "w\(i)", chain: "AXWindow", out: &out)
            }
        }
        return out
    }

    func countNodes(_ root: AXUIElement, cap: Int) -> Int {
        var n = 0
        func go(_ el: AXUIElement, _ d: Int) {
            guard n < cap, d < 12 else { return }
            n += 1
            for c in (copyAttr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { go(c, d + 1) }
        }
        go(root, 0)
        return n
    }

    private func walk(_ el: AXUIElement, depth: Int, path: String, chain: String, out: inout [Rec]) {
        guard count < maxNodes, depth <= maxDepth else { return }
        count += 1
        let role = stringAttr(el, kAXRoleAttribute)
        let titleRaw = stringAttr(el, kAXTitleAttribute)
        let descRaw = stringAttr(el, kAXDescriptionAttribute)
        let valueRaw = stringAttr(el, kAXValueAttribute)
        var rec = Rec(
            key: path + "|" + (role ?? "?"), path: path, chain: chain, depth: depth,
            role: role,
            subrole: stringAttr(el, kAXSubroleAttribute),
            roleDescription: stringAttr(el, kAXRoleDescriptionAttribute),
            title: clean(titleRaw), desc: clean(descRaw), value: clean(valueRaw),
            identifier: clean(stringAttr(el, "AXIdentifier")),
            help: clean(stringAttr(el, kAXHelpAttribute)),
            selected: boolAttr(el, kAXSelectedAttribute),
            enabled: boolAttr(el, kAXEnabledAttribute),
            frame: frameAttr(el)
        )
        let combined = [titleRaw, descRaw, valueRaw, stringAttr(el, kAXHelpAttribute)].compactMap { $0 }.joined(separator: " ")
        rec.keyword = !combined.isEmpty && matchesKeyword(combined)
        if let t = titleRaw ?? descRaw ?? valueRaw { rec.personLike = looksLikePerson(t) }
        out.append(rec)
        let kids = (copyAttr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for (i, c) in kids.enumerated() {
            let r = (stringAttr(c, kAXRoleAttribute) ?? "?")
            walk(c, depth: depth + 1, path: path + "." + String(i), chain: chain + ">" + r, out: &out)
            if count >= maxNodes { break }
        }
    }
}

// MARK: - Probe

final class Probe: @unchecked Sendable {
    struct Change { let el: AXUIElement; let attr: String; let prior: Bool }
    var changes: [Change] = []
    var restored = false

    func enableWebAX(_ el: AXUIElement) {
        for attr in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            let prior = boolAttr(el, attr) ?? false
            if !prior, AXUIElementSetAttributeValue(el, attr as CFString, kCFBooleanTrue) == .success {
                changes.append(Change(el: el, attr: attr, prior: prior))
            }
        }
    }

    func restore() {
        guard !restored else { return }
        restored = true
        for c in changes {
            _ = AXUIElementSetAttributeValue(c.el, c.attr as CFString, c.prior ? kCFBooleanTrue : kCFBooleanFalse)
        }
    }
}

func wait(until target: Date) {
    while Date() < target {
        RunLoop.current.run(mode: .default, before: Date())
        Thread.sleep(forTimeInterval: 0.05)
    }
}

func writeLines(_ lines: [[String: Any]], to url: URL) {
    var data = Data()
    for l in lines {
        if let d = try? JSONSerialization.data(withJSONObject: l, options: [.sortedKeys, .withoutEscapingSlashes]) {
            data.append(d)
            data.append(10)
        }
    }
    do { try data.write(to: url, options: .atomic) } catch { die("cannot write \(url.path): \(error)", code: 1) }
}

func run() {
    let opts = parseOptions()

    // Trust check WITHOUT prompting.
    guard AXIsProcessTrusted() else {
        die("Accessibility not granted: enable Terminal in System Settings > Privacy & Security > Accessibility, then re-run.", code: 2)
    }

    let outDir: URL = {
        if let o = opts.out { return URL(fileURLWithPath: o, isDirectory: true) }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AI-Brain-build/call-ax-probe/\(f.string(from: Date()))", isDirectory: true)
    }()
    do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
    catch { die("cannot create \(outDir.path): \(error)", code: 1) }

    // Find running target apps.
    let wanted = wantedBundleIDs(opts.app)
    var found: [(Target, NSRunningApplication)] = []
    for id in wanted {
        guard let t = knownTargets.first(where: { $0.bundleID == id }) else { continue }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            found.append((t, app))
        }
    }
    guard !found.isEmpty else {
        die("No target app running for --app \(opts.app) (looked for: \(wanted.joined(separator: ", "))). Join the call first.", code: 1)
    }

    let probe = Probe()
    let walker = Walker(redact: opts.redact)

    // Restore any enhanced-accessibility switch on Ctrl-C / kill.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { probe.restore(); exit(130) }
        s.resume()
        return s
    }
    _ = sources

    print("call-ax-probe: redact=\(opts.redact ? "ON" : "OFF (raw text, keep local)") out=\(outDir.path)")
    print("apps: " + found.map { "\($0.0.label)(pid \($0.1.processIdentifier))" }.joined(separator: ", "))

    struct Session { let target: Target; let el: AXUIElement }
    var sessions: [Session] = []
    for (t, app) in found {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.25)
        if t.web, walker.countNodes(el, cap: 400) < 150 {
            probe.enableWebAX(el)
            print("  \(t.label): tree looked empty, enabled AXManualAccessibility/AXEnhancedUserInterface (restored on exit)")
            wait(until: Date().addingTimeInterval(1.0))
        }
        sessions.append(Session(target: t, el: el))
    }

    func windows(for s: Session) -> [AXUIElement] {
        var ws = (copyAttr(s.el, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        if opts.app == "meet" {
            let meet = ws.filter { (stringAttr($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains("meet") }
            if !meet.isEmpty { ws = meet }
        }
        return ws
    }

    var samples: [String: [[Rec]]] = [:]
    let t0 = Date()
    for n in 1...opts.seconds {
        for s in sessions {
            let recs = walker.snapshot(windows: windows(for: s), appElement: s.el)
            samples[s.target.label, default: []].append(recs)
            writeLines(recs.map { $0.json }, to: outDir.appendingPathComponent("snapshot-\(s.target.label)-\(n).jsonl"))
        }
        wait(until: t0.addingTimeInterval(Double(n)))
    }
    probe.restore()

    // Diffs and summary.
    for s in sessions {
        let label = s.target.label
        let snaps = samples[label] ?? []
        guard let last = snaps.last else { continue }
        var diffs: [[String: Any]] = []
        if snaps.count > 1 {
            for i in 1..<snaps.count {
                let prev = Dictionary(snaps[i - 1].map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                for r in snaps[i] {
                    guard let p = prev[r.key] else {
                        if r.keyword { diffs.append(["sample": i + 1, "key": r.key, "chain": r.chain, "change": "added", "text": r.text ?? ""]) }
                        continue
                    }
                    let fields: [(String, String?, String?)] = [
                        ("title", p.title, r.title), ("description", p.desc, r.desc), ("value", p.value, r.value),
                        ("selected", p.selected.map(String.init), r.selected.map(String.init)),
                    ]
                    for (f, a, b) in fields where a != b {
                        diffs.append(["sample": i + 1, "key": r.key, "chain": r.chain, "role": r.role ?? "", "field": f,
                                      "from": a ?? NSNull(), "to": b ?? NSNull()])
                    }
                }
            }
        }
        writeLines(diffs, to: outDir.appendingPathComponent("diff-\(label).jsonl"))

        print("\n=== \(label): \(snaps.count) samples, last has \(last.count) nodes, \(diffs.count) diff entries ===")

        // Roster candidates: parents with >= 3 person-like children.
        var groups: [String: [Rec]] = [:]
        for r in last where r.personLike {
            let parent = r.path.split(separator: ".").dropLast().joined(separator: ".")
            groups[parent + "|" + (r.role ?? "?"), default: []].append(r)
        }
        let roster = groups.filter { $0.value.count >= 3 }.sorted { $0.value.count > $1.value.count }.prefix(6)
        print("roster candidates (parents with 3+ person-like siblings):")
        if roster.isEmpty { print("  none") }
        for (k, v) in roster {
            print("  \(k.split(separator: "|").first ?? "") x\(v.count)  chain: \(v[0].chain)")
            print("    e.g. " + v.prefix(5).map { "\($0.text ?? "")" }.joined(separator: " | "))
        }

        // Indicator-word nodes across all samples (deduped).
        var seen = Set<String>()
        var hits: [Rec] = []
        for snap in snaps {
            for r in snap where r.keyword {
                if seen.insert(r.key + "|" + (r.text ?? "")).inserted { hits.append(r) }
            }
        }
        print("nodes matching /speak|talk|unmute|mute|parle|micro/i (\(hits.count)):")
        for r in hits.prefix(40) {
            print("  [\(r.role ?? "?")\(r.subrole.map { "/" + $0 } ?? "")] \(r.text ?? r.help ?? "")  path: \(r.chain)")
        }
        if hits.count > 40 { print("  ... \(hits.count - 40) more in the snapshot files") }

        // Most volatile nodes: usually the speaking highlight.
        var churn: [String: Int] = [:]
        var churnChain: [String: String] = [:]
        for d in diffs where d["field"] != nil {
            let k = d["key"] as! String
            churn[k, default: 0] += 1
            churnChain[k] = d["chain"] as? String
        }
        print("most-changing nodes (candidate active-speaker indicators):")
        if churn.isEmpty { print("  none changed during the sample (nobody spoke, or state not exposed)") }
        for (k, c) in churn.sorted(by: { $0.value > $1.value }).prefix(10) {
            print("  \(c) changes  \(k)  chain: \(churnChain[k] ?? "")")
        }
    }
    print("\nfiles in \(outDir.path)")
}

run()
