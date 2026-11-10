// e2e helper: `axtree [window-title|-] [button-to-press]` dumps or presses ZEUS UI through accessibility.
import AppKit
// Prints the accessibility tree of a window of the running Zeus app: role, title, description, value.
let title = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "app.zeus.mac").first else { print("not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ a: String) -> String? {
    var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success, let v else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v); return (v as? [AXUIElement]) ?? []
}
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = attr(e, kAXRoleAttribute) ?? "?"
    let parts = [attr(e, kAXTitleAttribute), attr(e, kAXDescriptionAttribute), attr(e, kAXValueAttribute), attr(e, kAXHelpAttribute).map { "hint: \($0)" }].compactMap { $0 }
    if role != "AXGroup" || !parts.isEmpty { print(String(repeating: "  ", count: depth) + role + " " + parts.joined(separator: " | ")) }
    children(e).forEach { walk($0, depth + 1) }
}
var windows: CFTypeRef?; AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &windows)
for w in (windows as? [AXUIElement]) ?? [] where title.isEmpty || attr(w, kAXTitleAttribute) == title || (title == "-" && attr(w, kAXTitleAttribute) == nil) {
    print("WINDOW \(attr(w, kAXTitleAttribute) ?? "(untitled)")"); walk(w, 1)
}
if CommandLine.arguments.count > 2 {   // press a button by title
    func find(_ e: AXUIElement) -> AXUIElement? {
        if attr(e, kAXRoleAttribute) == "AXButton", attr(e, kAXTitleAttribute) == CommandLine.arguments[2] || attr(e, kAXDescriptionAttribute) == CommandLine.arguments[2] { return e }
        for c in children(e) { if let f = find(c) { return f } }; return nil
    }
    for w in (windows as? [AXUIElement]) ?? [] { if let b = find(w) { print("PRESS", AXUIElementPerformAction(b, kAXPressAction as CFString) == .success); break } }
}
