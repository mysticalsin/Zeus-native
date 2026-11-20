import Foundation
import Testing
import ZeusCore

/// Findings from the delta review at 896512ae. These fail on that tree and pass once each hole is closed.
@Suite struct InspectorDeltaTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func fillingOneDescriptorShowsThatSlot() throws {
        let slots = GlassSectionManifest.providers.map { provider -> GlassSectionSlot in
            let slot = provider.descriptor
            guard slot.id == "glass.media" else { return slot }
            return GlassSectionSlot(id: slot.id, title: slot.title, filled: true, keys: slot.keys, order: slot.order, enabled: slot.enabled, placement: slot.placement)
        }
        let rows = SettingsSectionRegistry.sections(slots: slots, includePhone: false)
        #expect(rows.last?.id == SettingsSectionRegistry.topbarID)
        #expect(rows.last?.title == "Topbar")
        #expect(!rows.contains { $0.id == "glass.media" })
        #expect(SettingsSectionRegistry.search("Topbar", in: rows).contains { $0.id == SettingsSectionRegistry.topbarID })
        #expect(rows.map(\.accessibilityLabel).contains("Topbar"))
        let tabs = GlassSectionManifest.topbarTabs(in: slots)
        #expect(tabs.contains { $0.id == "glass.media" })
        #expect(tabs.allSatisfy { $0.filled })
        #expect(!tabs.contains { $0.id == "glass.weather" })
        #expect(GlassSectionManifest.cards(on: .general, in: slots).isEmpty)
        let host = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/GlassSettingsSectionHost.swift"), encoding: .utf8)
        #expect(host.contains("as? any GlassSlotPage.Type"))
        #expect(!host.contains("switch id"))
    }

    @Test func topbarSelectionRejectsHiddenTabsAndCardsStayOnTheirPage() {
        let media = GlassSectionSlot(id: "glass.media", title: "Media", filled: true, keys: [], placement: .topbarTab(0))
        let weather = GlassSectionSlot(id: "glass.weather", title: "Weather", filled: false, keys: [], placement: .topbarTab(1))
        let disabled = GlassSectionSlot(id: "glass.focus", title: "Focus", filled: true, keys: [], enabled: false, placement: .topbarTab(2))
        let face = GlassSectionSlot(id: "glass.faceID", title: "Face ID", filled: true, keys: [], placement: .cardOn(.privacy, 0))
        let license = GlassSectionSlot(id: "glass.license", title: "License", filled: true, keys: [], placement: .cardOn(.license, 1))
        let earlier = GlassSectionSlot(id: "glass.license", title: "Earlier", filled: true, keys: [], placement: .cardOn(.license, 0))
        let tabs = GlassSectionManifest.topbarTabs(in: [weather, disabled, media])
        #expect(tabs.map(\.id) == ["glass.media"])
        var state = SettingsSelectionState.section("settings.general")
        state = SettingsSelectionRules.selectingTopbar("glass.media", filledTabs: tabs.map(\.id), current: state)
        #expect(state == .topbar(tab: "glass.media"))
        let kept = SettingsSelectionRules.selectingTopbar("glass.weather", filledTabs: tabs.map(\.id), current: state)
        #expect(kept == state)
        #expect(SettingsSelectionRules.selectingTopbar("  ", filledTabs: tabs.map(\.id), current: state) == state)
        state = SettingsSelectionRules.selectingSection("settings.sounds", current: state)
        #expect(state == .section("settings.sounds"))
        let cards = GlassSectionManifest.cards(on: .license, in: [license, earlier, face])
        #expect(cards.map(\.title) == ["Earlier"])
        #expect(GlassSectionManifest.cards(on: .privacy, in: [license, earlier, face]).map(\.id) == ["glass.faceID"])
        #expect(SettingsSectionRegistry.sections(slots: [weather, disabled]).last?.id != SettingsSectionRegistry.topbarID)
    }

    @Test func everySectionFileIsRegisteredAndEveryProviderHasAFile() throws {
        let directory = Self.root.appendingPathComponent("Sources/ZeusCore/Settings/Sections")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("SectionSlot.swift") }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Sources/ZeusCore/Settings/GlassSettingsShell.swift"), encoding: .utf8)
        guard let start = manifest.range(of: "static let providers"),
              let equals = manifest[start.upperBound...].range(of: "= ["),
              let close = manifest[equals.upperBound...].firstIndex(of: "]") else {
            Issue.record("provider list missing")
            return
        }
        let registered = manifest[equals.upperBound..<close]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(".self") || $0.hasSuffix(".self,") }
            .map { $0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".self", with: "") }
        #expect(registered.sorted() == files)
        #expect(Set(registered).count == registered.count)
        #expect(GlassSectionManifest.providers.count == files.count)
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
            let metrics = SettingsSidebarLayout.rowMetrics(rowCount: count)
            #expect(metrics.height == 30)
            #expect(metrics.gap >= 1)
        }
        #expect(SettingsSidebarLayout.bottom(rowCount: 34) > SettingsSidebarLayout.versionY)
        #expect(SettingsSidebarLayout.scrollHeight <= SettingsSidebarLayout.versionY - SettingsSidebarLayout.top)
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
        let rows = SettingsSectionRegistry.orderedSlots([later, second, first, earlier])
        let duplicates = rows.filter { $0.id == "glass.dup" }
        #expect(duplicates.count == 1)
        #expect(duplicates.first?.title == "First")
        let tail = rows.suffix(3).map(\.id)
        #expect(tail == ["glass.earlier", "glass.dup", "glass.later"])
    }

    @Test func sidebarRowsStayThirtyPointsAndTheFoundationIsDeclared() throws {
        for count in [21, 22, 23, 34] {
            #expect(SettingsSidebarLayout.rowMetrics(rowCount: count).height == 30)
        }
        #expect(SettingsSidebarLayout.bottom(rowCount: 34) > SettingsSidebarLayout.versionY)
        let shell = try String(contentsOf: Self.root.appendingPathComponent("Sources/ZeusCore/Settings/GlassSettingsShell.swift"), encoding: .utf8)
        let window = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/SettingsWindow.swift"), encoding: .utf8)
        #expect(shell.contains("topbarTab"))
        #expect(shell.contains("cardOn"))
        #expect(window.contains("case topbar"))
        #expect(window.contains("selectTopbar"))
        let registry = try String(contentsOf: Self.root.appendingPathComponent("Sources/ZeusCore/Settings/SettingsSectionRegistry.swift"), encoding: .utf8)
        #expect(registry.contains("\"Topbar\""))
        #expect(GlassSettingsMetrics.controlRow == 52)
        #expect(GlassSettingsMetrics.helperLine == 16)
        #expect(GlassSettingsMetrics.panelPadding == 32)
        #expect(GlassSettingsMetrics.cardSpacing == 28)
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
