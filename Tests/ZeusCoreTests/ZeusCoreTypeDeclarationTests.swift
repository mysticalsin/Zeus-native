import Foundation
import Testing

/// Top-level type names in the ZeusCore module are unique. A second `struct`, `class`, `enum`,
/// `actor`, `protocol`, or `typealias` with the same name is the invalid redeclaration that
/// stopped `swift build`. Nested types and extensions are not a second top-level type.
struct ZeusCoreTypeDeclarationScan {
    private static let declaration = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:public|open|internal|fileprivate|private|package|final|indirect|nonisolated)\s+|@[A-Za-z_][A-Za-z0-9_]*(?:\([^()\n]*\))?\s+)*(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    )

    static func blankComments(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        var triple = false
        var inBlock = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            let next: Character = index + 1 < chars.count ? chars[index + 1] : "\0"
            let next2: Character = index + 2 < chars.count ? chars[index + 2] : "\0"
            if inBlock {
                if char == "*" && next == "/" {
                    inBlock = false
                    out.append("  ")
                    index += 2
                    continue
                }
                out.append(char == "\n" ? "\n" : " ")
                index += 1
                continue
            }
            if inString {
                if triple {
                    if char == "\"" && next == "\"" && next2 == "\"" {
                        out.append("\"\"\"")
                        inString = false
                        triple = false
                        index += 3
                        continue
                    }
                    out.append(char)
                } else if escaped {
                    out.append(char)
                    escaped = false
                } else if char == "\\" {
                    out.append(char)
                    escaped = true
                } else if char == "\"" {
                    out.append(char)
                    inString = false
                } else {
                    out.append(char)
                }
                index += 1
                continue
            }
            if char == "\"" && next == "\"" && next2 == "\"" {
                inString = true
                triple = true
                out.append("\"\"\"")
                index += 3
                continue
            }
            if char == "\"" {
                inString = true
                out.append(char)
                index += 1
                continue
            }
            if char == "/" && next == "/" {
                while index < chars.count && chars[index] != "\n" {
                    out.append(" ")
                    index += 1
                }
                continue
            }
            if char == "/" && next == "*" {
                inBlock = true
                out.append("  ")
                index += 2
                continue
            }
            out.append(char)
            index += 1
        }
        return out
    }

    static func declarationSites(in text: String, label: String = "sample") -> [String] {
        var sites: [String] = []
        var depth = 0
        for (offset, line) in blankComments(text).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let row = String(line)
            if depth == 0 {
                let range = NSRange(row.startIndex..., in: row)
                if let match = declaration.firstMatch(in: row, range: range),
                   let nameRange = Range(match.range(at: 1), in: row) {
                    sites.append("\(label):\(offset + 1) \(row[nameRange])")
                }
            }
            var paren = 0
            for char in row {
                if char == "(" {
                    paren += 1
                } else if char == ")" {
                    paren = max(0, paren - 1)
                } else if paren == 0 && char == "{" {
                    depth += 1
                } else if paren == 0 && char == "}" {
                    depth = max(0, depth - 1)
                }
            }
        }
        return sites
    }

    static func duplicateReports(_ sites: [String]) -> [String] {
        var grouped: [String: [String]] = [:]
        for site in sites {
            guard let space = site.lastIndex(of: " ") else { continue }
            let name = String(site[site.index(after: space)...])
            let place = String(site[..<space])
            grouped[name, default: []].append(place)
        }
        return grouped.keys.sorted().compactMap { name in
            let places = grouped[name] ?? []
            guard places.count > 1 else { return nil }
            return name + " at " + places.joined(separator: ", ")
        }
    }

    static func repositorySites(sources: URL = zeusCoreSources) throws -> [String] {
        var sites: [String] = []
        let paths = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        for relative in paths {
            let url = sources.appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)
            sites.append(contentsOf: declarationSites(in: text, label: "Sources/ZeusCore/" + relative))
        }
        return sites
    }

    static func repositoryDuplicates(sources: URL = zeusCoreSources) throws -> [String] {
        try duplicateReports(repositorySites(sources: sources))
    }

    static let zeusCoreSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ZeusCore")
}

@Suite struct ZeusCoreTypeDeclarationTests {
    @Test func zeusCoreTopLevelTypeNamesAreUnique() throws {
        let found = try ZeusCoreTypeDeclarationScan.repositoryDuplicates()
        #expect(found == [])
    }

    @Test func aSecondTopLevelDeclarationIsReported() {
        let text = """
        public struct PlacedMark: Equatable {}
        // public struct PlacedMark {}
        extension PlacedMark {}
        struct Holder {
            struct PlacedMark {}
        }
        public struct PlacedMark {}
        struct Other {}
        """
        #expect(ZeusCoreTypeDeclarationScan.duplicateReports(
            ZeusCoreTypeDeclarationScan.declarationSites(in: text)
        ) == ["PlacedMark at sample:1, sample:7"])
    }

    @Test func drawingKeepsTheOnlyPlacedMark() throws {
        let sites = try ZeusCoreTypeDeclarationScan.repositorySites()
        let placed = sites.filter { $0.hasSuffix(" PlacedMark") }
        let screen = sites.filter { $0.hasSuffix(" ScreenPlacedMark") }
        #expect(placed.count == 1)
        #expect(placed.first?.hasPrefix("Sources/ZeusCore/Present/DrawingScene.swift:") == true)
        #expect(screen.count == 1)
        #expect(screen.first?.hasPrefix("Sources/ZeusCore/Pointing/MarkLayout.swift:") == true)
    }

    @Test func aCommentThatSpansLinesIsNotADeclaration() {
        let text = "/*\npublic struct PlacedMark {}\n*/\npublic struct OnlyOnce {}\n"
        #expect(ZeusCoreTypeDeclarationScan.duplicateReports(
            ZeusCoreTypeDeclarationScan.declarationSites(in: text)
        ) == [])
        #expect(ZeusCoreTypeDeclarationScan.declarationSites(in: text) == ["sample:4 OnlyOnce"])
    }
}
