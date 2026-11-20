import Foundation
import Testing

/// Findings from the delta review at 896512ae. These fail on that tree and pass once each hole is closed.
@Suite struct InspectorDeltaTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func aProbeSlotFileAppearsWithNoOtherEdits() throws {
        let probe = """
        public enum ProbeSectionSlot {
            public static let slot = GlassSectionSlot(id: "glass.probe", title: "Probe", filled: true, keys: [], order: 500)
        }
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try probe.write(to: directory.appendingPathComponent("ProbeSectionSlot.swift"), atomically: true, encoding: .utf8)
        let slots = SettingsSlotDiscovery.slots(in: directory)
        let rows = SettingsSectionRegistry.sections(slots: slots, includePhone: false)
        #expect(rows.contains { $0.id == "glass.probe" })
        #expect(SettingsSectionRegistry.search("Probe", in: rows).contains { $0.id == "glass.probe" })
        #expect(rows.map(\.accessibilityLabel).contains("Probe"))
        #expect(SettingsSectionHostPlan.hostedIDs(in: rows).contains("glass.probe"))
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Sources/ZeusCore/Settings/GlassSettingsShell.swift"), encoding: .utf8)
        let host = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/GlassSettingsSectionHost.swift"), encoding: .utf8)
        #expect(!manifest.contains("MediaSectionSlot.slot"))
        #expect(!host.contains("switch id"))
    }

    @Test func selectionIsExactlyOneRow() {
        var state = SettingsSelectionState.section("settings.general")
        state = SettingsSelectionRules.selectingSlot("glass.probe", current: state)
        #expect(state == .slot("glass.probe"))
        state = SettingsSelectionRules.selectingSection("settings.sounds", current: state)
        #expect(state == .section("settings.sounds"))
        let kept = SettingsSelectionRules.selectingSlot("  ", current: state)
        #expect(kept == state)
        #expect(SettingsSelectionRules.isExclusive(state))
        #expect(SettingsSelectionRules.isExclusive(.slot("glass.probe")))
        let window = try! String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/SettingsWindow.swift"), encoding: .utf8)
        #expect(window.contains("enum SettingsSelection"))
        #expect(window.contains("case section(GSSection)"))
        #expect(window.contains("case slot(SlotID)"))
        #expect(!window.contains("var glassSlotID"))
    }

    @Test func sidebarFitsEveryVisibleRowCount() {
        for count in [21, 22, 23, 34] {
            let bottom = SettingsSidebarLayout.bottom(rowCount: count)
            #expect(bottom <= SettingsSidebarLayout.versionY)
            let metrics = SettingsSidebarLayout.rowMetrics(rowCount: count)
            #expect(metrics.height >= 1)
            #expect(metrics.gap >= 1)
        }
        let window = try! String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/SettingsWindow.swift"), encoding: .utf8)
        #expect(!window.contains("rowMetrics(rowCount: GSSection.shown.count)"))
        #expect(window.contains("SettingsSidebarLayout.rowMetrics(rowCount:"))
    }

    @Test func phoneRowReturnsWhenPairingIsAvailable() {
        let hidden = SettingsSectionRegistry.sections(slots: [], includePhone: false).map(\.title)
        let shown = SettingsSectionRegistry.sections(slots: [], includePhone: true).map(\.title)
        #expect(!hidden.contains("iPhone"))
        #expect(shown.contains("iPhone"))
        let engine = shown.firstIndex(of: "Engine")
        #expect(engine != nil)
        #expect(shown[(engine ?? 0) + 1] == "iPhone")
        #expect(shown[(engine ?? 0) + 2] == "Features")
        let window = try! String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/SettingsWindow.swift"), encoding: .utf8)
        #expect(window.contains("includePhone: GSSection.iPhonePairingAvailable"))
    }

    @Test func duplicateFilledIDsCollapseAndStayOrdered() {
        let first = GlassSectionSlot(id: "glass.dup", title: "First", filled: true, keys: [], order: 10)
        let second = GlassSectionSlot(id: "glass.dup", title: "Second", filled: true, keys: [], order: 11)
        let later = GlassSectionSlot(id: "glass.later", title: "Later", filled: true, keys: [], order: 12)
        let earlier = GlassSectionSlot(id: "glass.earlier", title: "Earlier", filled: true, keys: [], order: 9)
        let rows = SettingsSectionRegistry.sections(slots: [later, second, first, earlier], includePhone: false)
        let duplicates = rows.filter { $0.id == "glass.dup" }
        #expect(duplicates.count == 1)
        #expect(duplicates.first?.title == "First")
        let tail = rows.suffix(3).map(\.id)
        #expect(tail == ["glass.earlier", "glass.dup", "glass.later"])
    }

    @Test func registrationDoesNotReadSectionSources() throws {
        let settings = Self.root.appendingPathComponent("Sources/ZeusCore/Settings")
        let files = try Self.swiftSources(at: settings)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("FileManager"), "\(file.lastPathComponent) reads the filesystem")
            #expect(!text.contains("#filePath"), "\(file.lastPathComponent) uses the build path")
        }
        let sections = settings.appendingPathComponent("Sections")
        let parked = sections.appendingPathExtension("held")
        try FileManager.default.moveItem(at: sections, to: parked)
        defer { try? FileManager.default.moveItem(at: parked, to: sections) }
        #expect(GlassSectionManifest.slots.count == 12)
    }

    private static func swiftSources(at directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
