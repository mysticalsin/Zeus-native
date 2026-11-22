import Foundation
import Testing
@testable import ZeusCore

@Suite("Face module isolation")
struct FaceModuleIsolationTests {
    private static let forbidden = [
        "URLSession",
        "URLRequest",
        "NWConnection",
        "import Network",
        "CFSocket",
        "NSURLSession",
        "openai",
        "anthropic",
        "claude",
        "ChatGPT",
        "GenerativeModel",
        "languageModel",
        "http://",
        "https://",
    ]

    @Test func faceModuleDoesNotLinkOrCallNetworkOrALanguageModel() throws {
        let files = try moduleSources()
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lowered = text.lowercased()
            for marker in Self.forbidden {
                #expect(!text.contains(marker) && !lowered.contains(marker.lowercased()), "\(file.lastPathComponent) contains \(marker)")
            }
        }
        let coreImports = try files.filter { $0.path.contains("/ZeusCore/") }.flatMap { url -> [String] in
            let text = try String(contentsOf: url, encoding: .utf8)
            return text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("import ") }
        }
        let allowed: Set<String> = ["import Foundation", "import CryptoKit"]
        #expect(coreImports.allSatisfy { allowed.contains($0.trimmingCharacters(in: .whitespaces)) })

        let package = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let clause = zeusCoreClause(in: package)
        #expect(clause.contains(".target(name: \"ZeusCore\""))
        let lowered = clause.lowercased()
        #expect(!lowered.contains("http"))
        #expect(!clause.contains("FluidAudio"))
        #expect(!clause.contains("WhisperKit"))
        #expect(!clause.contains("FoundationNetworking"))
        if clause.contains("dependencies") {
            #expect(clause.contains("CoreGraphics"))
            #expect(!clause.contains("ZeusFling"))
        }
    }

    /// The nearest package that declares the core target. A portable fixture may sit above the checkout.
    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            let manifest = url.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8), text.contains("name: \"ZeusCore\"") {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func zeusCoreClause(in package: String) -> String {
        let lines = package.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("name: \"ZeusCore\"") }) else { return "" }
        var clause = lines[start]
        var index = start
        while !clause.contains("),") && index + 1 < lines.count && index - start < 8 {
            index += 1
            clause += lines[index]
        }
        return clause
    }

    @Test func nativeCameraRunsStayMarkedPending() {
        #expect(FaceVerificationNativePlan.status == "MAC-PENDING")
        let plan = FaceVerificationNativePlan.steps.joined(separator: " ").lowercased()
        #expect(plan.contains("his face"))
        #expect(plan.contains("other"))
        #expect(plan.contains("light"))
        #expect(plan.contains("distance"))
        #expect(plan.contains("fail"))
        #expect(plan.contains("photo"))
        #expect(FaceVerificationNativePlan.steps.count >= 6)
    }

    private func moduleSources() throws -> [URL] {
        let folders = [
            "Sources/ZeusCore/Settings/Sections/FaceID",
            "Sources/Zeus/Settings/GlassShell/Sections/FaceID",
        ].map { Self.root.appendingPathComponent($0) }
        let singles = [
            "Sources/ZeusCore/Settings/Sections/FaceIDSectionSlot.swift",
            "Sources/Zeus/Settings/GlassShell/Sections/FaceIDSettingsSection.swift",
        ].map { Self.root.appendingPathComponent($0) }
        var files: [URL] = []
        for folder in folders {
            let found = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            files.append(contentsOf: found.filter { $0.pathExtension == "swift" })
        }
        files.append(contentsOf: singles)
        return files.sorted { $0.path < $1.path }
    }
}
