import Foundation
import Testing
@testable import ZeusCore

/// The bundled-helper launch sites. A new handoff that this scan does not already
/// list fails the equality check, and a listed site whose file dropped the gate fails too.
@Suite struct BundledHelperLaunchGateTests {
    @Test func knownSigningIdentifiersAreExactlyTheBundledHelpers() {
        #expect(BundledHelperLaunchPolicy.knownSigningIdentifiers.sorted() == [
            "zeus", "zeus-bridge", "zeus-cli", "zeus-hook",
        ])
    }

    @Test func staticValidityUsesStrictNestedAndAllArchitectures() throws {
        let source = try repoSource("Sources/Zeus/App/BundledHelperSignature.swift")
        #expect(source.contains("kSecCSStrictValidate"))
        #expect(source.contains("kSecCSCheckNestedCode"))
        #expect(source.contains("kSecCSCheckAllArchitectures"))
        #expect(source.contains("requiredValidityFlags"))
        #expect(source.contains("SecStaticCodeCheckValidity"))
        #expect(!source.contains("SecStaticCodeCheckValidity(staticCode, SecCSFlags()"))
        #expect(!source.contains("kSecCSEnforceRevocationChecks"))

        let policy = try repoSource("Sources/ZeusCore/Support/BundledHelperLaunchPolicy.swift")
        #expect(policy.contains("kSecCSStrictValidate"))
        #expect(policy.contains("kSecCSCheckNestedCode"))
        #expect(policy.contains("kSecCSCheckAllArchitectures"))
        #expect(policy.contains("kSecCSEnforceRevocationChecks"))
        #expect(policy.contains("not offline-safe"))
    }

    @Test func requiredValidityFlagsAreTheThreeOfflineSafeChecks() {
        #expect(BundledHelperLaunchPolicy.requiredValidityFlags == [
            "kSecCSStrictValidate",
            "kSecCSCheckNestedCode",
            "kSecCSCheckAllArchitectures",
        ])
        #expect(BundledHelperLaunchPolicy.omittedValidityFlags == ["kSecCSEnforceRevocationChecks"])
        #expect(Set(BundledHelperLaunchPolicy.requiredValidityFlags)
            .isDisjoint(with: Set(BundledHelperLaunchPolicy.omittedValidityFlags)))
    }

    @Test func aSupportDirectoryCopyIsNotThePublishedExecutable() {
        let bridge = "/Users/tony/Library/Application Support/Zeus/bin/zeus-bridge"
        let hook = "$HOME/Library/Application Support/Zeus/bin/zeus-hook"
        #expect(BundledHelperLaunchPolicy.isUserWritableHelperCopy(bridge))
        #expect(BundledHelperLaunchPolicy.isUserWritableHelperCopy(hook))
        #expect(BundledHelperLaunchPolicy.isUserWritableHelperCopy("~/Library/Application Support/Zeus/bin/zeus"))
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bridge, helperName: "zeus-bridge") == nil)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: hook, helperName: "zeus-hook") == nil)
        #expect(BundledHelperLaunchPolicy.isUserWritableHelperCopy("/usr/bin/pmset") == false)

        let bundledBridge = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        let bundledHook = "/Applications/Zeus.app/Contents/Helpers/zeus-hook"
        let bundledCLI = "/Applications/Zeus.app/Contents/Helpers/zeus"
        let development = "/src/.build/debug/zeus-cli"
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bundledBridge, helperName: "zeus-bridge") == bundledBridge)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bundledHook, helperName: "zeus-hook") == bundledHook)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bundledCLI, helperName: "zeus") == bundledCLI)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: development, helperName: "zeus-cli") == development)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bundledBridge, helperName: "zeus-hook") == nil)
        #expect(BundledHelperLaunchPolicy.executableToPublish(checkedPath: bundledBridge + "/extra", helperName: "zeus-bridge") == nil)
    }

    @Test func aRefusalPublishesNoExecutable() {
        let bundledBridge = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        #expect(BundledHelperLaunchPolicy.publishedExecutable(
            checkedPath: bundledBridge, helperName: "zeus-bridge", decision: .launch) == bundledBridge)
        #expect(BundledHelperLaunchPolicy.publishedExecutable(
            checkedPath: bundledBridge, helperName: "zeus-bridge",
            decision: .refuse(BundledHelperLaunchPolicy.refusalSentence)) == nil)
        let support = "/Users/tony/Library/Application Support/Zeus/bin/zeus-bridge"
        #expect(BundledHelperLaunchPolicy.publishedExecutable(
            checkedPath: support, helperName: "zeus-bridge", decision: .launch) == nil)
    }

    @Test func insomniaRootCommandsRunSystemPmset() {
        #expect(InsomniaSudoers.commands == [
            "/usr/bin/pmset -a disablesleep 1",
            "/usr/bin/pmset -a disablesleep 0",
            "/usr/bin/pmset -a lowpowermode 1",
            "/usr/bin/pmset -a lowpowermode 0",
        ])
        for command in InsomniaSudoers.commands {
            let executable = command.split(separator: " ").first.map(String.init)
            #expect(executable == "/usr/bin/pmset")
            #expect(command.contains("Application Support") == false)
        }
    }

    @Test func everyBundledHelperLaunchSiteIsTheGatedCatalog() throws {
        let files = try swiftSources()
        let found = BundledHelperLaunchScan.sites(in: files).map(\.key).sorted()
        #expect(found == Self.catalog)
        for site in BundledHelperLaunchScan.sites(in: files) {
            let source = try #require(files[site.file])
            if Self.gateFiles.contains(site.file) {
                #expect(source.contains("BundledHelperLaunch"), "\(site.file) launches a helper without the gate")
            }
        }
        let appDelegate = try #require(files["Sources/Zeus/App/AppDelegate.swift"])
        #expect(appDelegate.contains("refreshHelper("))
        #expect(appDelegate.contains("authorizeInstalledBridge("))
        #expect(!appDelegate.contains("HelperInstaller.refresh("))
        let otherAgents = try #require(files["Sources/Zeus/Agents/OtherAgents.swift"])
        #expect(otherAgents.contains("referencedHookPath("))
        #expect(!otherAgents.contains("installedHook"))
        #expect(!otherAgents.contains("HelperInstaller.refresh("))
        let bridge = try #require(files["Sources/Zeus/Chrome/ChromeInstaller.swift"])
        #expect(bridge.contains("Contents/Helpers/zeus-bridge"))
        #expect(!bridge.contains("appendingPathComponent(\"zeus-bridge\")"))
        #expect(bridge.contains("BundledHelperPublish.replaceIfAccepted"))
        #expect(!bridge.contains("try? NativeHostRegistration.reconcile"))
        let refusal = refusalFunction(bridge)
        #expect(refusal.contains("NativeHostRegistration.reconcile"))
        #expect(refusal.contains(".registrationNotRemoved"))
        #expect(!refusal.contains("uninstall("))
        let install = functionBody(bridge, name: "static func install")
        #expect(!install.contains("publishedExecutable(checkedPath: url.path"))
        #expect(install.contains("mayStage"))
        let signature = try #require(files["Sources/Zeus/App/BundledHelperSignature.swift"])
        #expect(!signature.contains("String(format: \"%02x\""))
        #expect(signature.contains("asciiHex"))
        #expect(!appDelegate.contains("_ = ChromeInstaller.authorizeInstalledBridge()"))
        #expect(appDelegate.contains("registrationRemovalFailed"))
        let hook = try #require(files["Sources/Zeus/Agents/ClaudeHookInstaller.swift"])
        #expect(hook.contains("Contents/Helpers/zeus-hook"))
        #expect(!hook.contains("Application Support/Zeus/bin/zeus-hook"))
        #expect(!hook.contains("HelperInstaller.refresh("))
    }

    /// file | kind | helper. Order is part of the lock.
    private static let catalog = [
        "Sources/Zeus/Agents/ClaudeHookInstaller.swift|bundle|zeus-hook",
        "Sources/Zeus/Agents/ClaudeHookInstaller.swift|hook-reference|zeus-hook",
        "Sources/Zeus/Agents/ClaudeHookInstaller.swift|hook-refresh|zeus-hook",
        "Sources/Zeus/Agents/OtherAgents.swift|hook-reference|zeus-hook",
        "Sources/Zeus/App/AppDelegate.swift|bridge-authorize|zeus-bridge",
        "Sources/Zeus/App/AppDelegate.swift|hook-refresh|zeus-hook",
        "Sources/Zeus/App/CommandCenter.swift|bundle|zeus",
        "Sources/Zeus/App/CommandCenter.swift|path-component|zeus",
        "Sources/Zeus/Chrome/ChromeInstaller.swift|bridge-authorize|zeus-bridge",
        "Sources/Zeus/Chrome/ChromeInstaller.swift|bundle|parameter",
        "Sources/Zeus/Chrome/ChromeInstaller.swift|bundle|zeus-bridge",
        "Sources/Zeus/Insomnia/InsomniaInstaller.swift|bundle|zeus",
        "Sources/Zeus/Insomnia/InsomniaInstaller.swift|path-component|zeus-cli",
        "Sources/Zeus/Wiki/WikiMCPExport.swift|bundle|zeus",
        "Sources/Zeus/Wiki/WikiMCPExport.swift|exec|zeus",
        "Sources/Zeus/Wiki/WikiMCPExport.swift|path-component|zeus-cli",
    ]

    private static let gateFiles: Set<String> = [
        "Sources/Zeus/Agents/ClaudeHookInstaller.swift",
        "Sources/Zeus/App/CommandCenter.swift",
        "Sources/Zeus/Chrome/ChromeInstaller.swift",
        "Sources/Zeus/Insomnia/InsomniaInstaller.swift",
        "Sources/Zeus/Wiki/WikiMCPExport.swift",
    ]
}

struct BundledHelperLaunchSite: Hashable, Sendable {
    var file: String
    var helper: String
    var kind: String

    var key: String { "\(file)|\(kind)|\(helper)" }
}

private func functionBody(_ source: String, name: String) -> String {
    guard let start = source.range(of: name) else { return "" }
    let rest = source[start.lowerBound...]
    guard let end = rest.dropFirst().range(of: "\n    static func ") ?? rest.dropFirst().range(of: "\n    private static func ") else {
        return String(rest)
    }
    return String(rest[..<end.lowerBound])
}

private func refusalFunction(_ source: String) -> String {
    guard let start = source.range(of: "static func authorizeInstalledBridge") else { return "" }
    let rest = source[start.lowerBound...]
    guard let end = rest.dropFirst().range(of: "\n    static func ") else { return String(rest) }
    return String(rest[..<end.lowerBound])
}

enum BundledHelperLaunchScan {
    private static let helpers = ["zeus-now-playing", "zeus-bridge", "zeus-hook", "zeus-cli", "zeus"]

    static func sites(in files: [String: String]) -> Set<BundledHelperLaunchSite> {
        var found = Set<BundledHelperLaunchSite>()
        for (file, raw) in files {
            let lines = stripComments(raw).components(separatedBy: "\n")
            let blob = lines.joined(separator: "\n")
            let fileNamesAHelper = blob.contains("Contents/Helpers/zeus") || blob.contains("zeus-cli")
                || blob.contains("zeus-hook") || blob.contains("zeus-bridge") || blob.contains("zeus-now-playing")
            for (offset, line) in lines.enumerated() {
                if let name = argument(line, call: "HelperInstaller.refresh") {
                    found.insert(.init(file: file, helper: name, kind: "refresh-call"))
                }
                if line.contains("refreshHelper(") {
                    found.insert(.init(file: file, helper: "zeus-hook", kind: "hook-refresh"))
                }
                if line.contains("referencedHookPath(") {
                    found.insert(.init(file: file, helper: "zeus-hook", kind: "hook-reference"))
                }
                if line.contains("authorizeInstalledBridge(") {
                    found.insert(.init(file: file, helper: "zeus-bridge", kind: "bridge-authorize"))
                }
                if line.contains("MCPStdioClient("), fileNamesAHelper {
                    found.insert(.init(file: file, helper: "zeus", kind: "exec"))
                }
                if line.contains("posix_spawn") {
                    found.insert(.init(file: file, helper: "posix_spawn", kind: "posix_spawn"))
                }
                if line.contains("zeus-now-playing") {
                    found.insert(.init(file: file, helper: "zeus-now-playing", kind: "now-playing"))
                }
                if line.contains("Contents/Helpers/\\(name)") {
                    found.insert(.init(file: file, helper: "parameter", kind: "bundle"))
                }
                for name in helpers {
                    let token = "Contents/Helpers/\(name)"
                    guard let range = line.range(of: token) else { continue }
                    let after = line[range.upperBound...].first
                    if let after, isHelperContinuation(after) { continue }
                    found.insert(.init(file: file, helper: name, kind: "bundle"))
                }
                if let name = argument(line, call: "appendingPathComponent"), helpers.contains(name) {
                    found.insert(.init(file: file, helper: name, kind: "path-component"))
                }
                if line.contains("NSWorkspace"), let name = nearestHelper(lines, around: offset, radius: 8) {
                    found.insert(.init(file: file, helper: name, kind: "nsworkspace"))
                }
                if line.contains("Process("), let name = nearestHelper(lines, around: offset, radius: 12) {
                    found.insert(.init(file: file, helper: name, kind: "process"))
                }
            }
        }
        return found
    }

    private static func argument(_ line: String, call: String) -> String? {
        guard let start = line.range(of: call + "(\"")?.upperBound else { return nil }
        guard let end = line[start...].firstIndex(of: "\"") else { return nil }
        return String(line[start..<end])
    }

    private static func nearestHelper(_ lines: [String], around index: Int, radius: Int) -> String? {
        let lower = max(0, index - radius)
        let upper = min(lines.count, index + radius + 1)
        let window = lines[lower..<upper].joined(separator: "\n")
        return helperNames(in: window).first
    }

    private static func helperNames(in text: String) -> [String] {
        var found: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            var matched = false
            for name in helpers where text[index...].hasPrefix(name) {
                let after = text.index(index, offsetBy: name.count)
                if after == text.endIndex || !isHelperContinuation(text[after]) {
                    found.append(name)
                    index = after
                    matched = true
                    break
                }
            }
            if !matched { index = text.index(after: index) }
        }
        return found
    }

    private static func isHelperContinuation(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "." || character == "-"
    }

    private static func stripComments(_ source: String) -> String {
        var withoutBlock = ""
        var cursor = source.startIndex
        while let start = source[cursor...].range(of: "/*") {
            withoutBlock.append(contentsOf: source[cursor..<start.lowerBound])
            guard let end = source[start.upperBound...].range(of: "*/") else { break }
            cursor = end.upperBound
        }
        withoutBlock.append(contentsOf: source[cursor...])
        return withoutBlock.components(separatedBy: "\n").map(stripLineComment).joined(separator: "\n")
    }

    private static func stripLineComment(_ line: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
                output.append(character)
            } else if character == "/", line.index(after: index) < line.endIndex, line[line.index(after: index)] == "/" {
                break
            } else {
                output.append(character)
            }
            index = line.index(after: index)
        }
        return output
    }
}

private func repoRoot() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["ZEUS_SOURCE_ROOT"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var url = URL(fileURLWithPath: #filePath)
    let files = FileManager.default
    while url.path != "/" {
        url.deleteLastPathComponent()
        if files.fileExists(atPath: url.appendingPathComponent("Sources/Zeus/App/BundledHelperSignature.swift").path) {
            return url
        }
    }
    throw CocoaError(.fileNoSuchFile)
}

private func repoSource(_ relative: String) throws -> String {
    try String(contentsOf: try repoRoot().appendingPathComponent(relative), encoding: .utf8)
}

private func swiftSources() throws -> [String: String] {
    let root = try repoRoot()
    let sources = root.appendingPathComponent("Sources")
    var files: [String: String] = [:]
    guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
        throw CocoaError(.fileReadNoSuchFile)
    }
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
        files[relative] = try String(contentsOf: url, encoding: .utf8)
    }
    return files
}
