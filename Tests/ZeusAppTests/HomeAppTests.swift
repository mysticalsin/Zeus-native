import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor @Suite struct HomeAppTests {
    @Test func catalogDefaultsMatchTodaysHome() {
        let store = SettingsStore.shared
        let saved = HomeSlots.settingIDs.map { ($0, store.string($0)) }
        defer { for (id, value) in saved { store.set(id, value) } }
        for (index, id) in HomeSlots.settingIDs.enumerated() {
            #expect(SettingsCatalog.option(id)?.defaultValue == HomeSlots.defaults[index].title)
            #expect(SettingsCatalog.option(id)?.isShown == true)
        }
        #expect(SettingsCatalog.option("home.backdrop")?.defaultValue == "None")
        for kind in HomeWidgetKind.allCases where !kind.variants.isEmpty {
            #expect(SettingsCatalog.option(kind.variantSettingID)?.choices == kind.variants.map(\.title))
            #expect(SettingsCatalog.option(kind.variantSettingID)?.defaultValue == kind.variants[0].title)
        }
        #expect(SettingsCatalog.option("home.widget.1")?.choices == HomeWidgetKind.allCases.map(\.title))
    }

    @Test func pickingASlotAndBackdropPersistsThroughSettings() {
        let store = SettingsStore.shared
        let ids = HomeSlots.settingIDs + [HomeBackdrop.settingID, "home.variant.clock"]
        let saved = ids.map { ($0, store.string($0)) }
        defer { for (id, value) in saved { store.set(id, value) } }
        let topBar = TopBarModel()
        topBar.setHomeWidget(slot: 2, to: .clock)
        topBar.setHomeVariant(.clock, to: HomeWidgetKind.clock.variants[3])
        topBar.setHomeBackdrop(.cosmos)
        let slots = HomeSlots(HomeSlots.settingIDs.map { store.string($0) })
        #expect(slots.kinds == [.music, .clock, .weather, .calendar])
        #expect(HomeWidgetKind.clock.resolveVariant(store.string("home.variant.clock")) == "halo")
        #expect(HomeBackdrop.resolve(store.string(HomeBackdrop.settingID)) == .cosmos)
    }

    @Test func customizeModeOnlyOnHomeAndAddsBarHeight() {
        let topBar = TopBarModel()
        topBar.selectedTab = .music
        topBar.beginHomeCustomize()
        #expect(!topBar.homeCustomizing)
        topBar.selectedTab = .home
        let before = topBar.homeExtraHeight
        topBar.beginHomeCustomize()
        #expect(topBar.homeCustomizing && topBar.homePickerSlot == 1)
        #expect(topBar.homeExtraHeight == HomeCustomize.barHeight + HomeStrip.gap)
        topBar.endHomeCustomize()
        #expect(topBar.homeExtraHeight == before)
    }

    @Test func tabEditorPersistsToTheLayoutStore() {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: "topBar.tabs"), defaults.string(forKey: "topBar.tabs.known"))
        defer { defaults.set(saved.0, forKey: "topBar.tabs"); defaults.set(saved.1, forKey: "topBar.tabs.known") }
        let topBar = TopBarModel()
        topBar.layout = TopBarLayout(tabs: [.home, .chat, .todo])
        topBar.beginTabEditing()
        topBar.addTab(.music)
        topBar.moveTab(.music, onto: .chat)
        topBar.removeTab(.todo)
        topBar.endTabEditing()
        #expect(topBar.layout.tabs == [.home, .music, .chat])
        #expect(TopBarLayout.decode(defaults.string(forKey: "topBar.tabs")).tabs == [.home, .music, .chat])
        topBar.selectedTab = .chat
        topBar.removeTab(.chat)
        #expect(topBar.selectedTab == .home)
    }

    @Test func tabEditorRefusesAnEleventhTab() {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: "topBar.tabs"), defaults.string(forKey: "topBar.tabs.known"))
        defer { defaults.set(saved.0, forKey: "topBar.tabs"); defaults.set(saved.1, forKey: "topBar.tabs.known") }
        let topBar = TopBarModel()
        topBar.layout = TopBarLayout(tabs: Array(TopBarTab.allCases.prefix(GlanceTopBar.maxTabs)))
        topBar.addTab(TopBarTab.allCases[GlanceTopBar.maxTabs])
        #expect(topBar.layout.tabs.count == GlanceTopBar.maxTabs)
        #expect(topBar.tabEditorNote != nil)
    }

    @Test func creatingAnEventFiresTheRibbonWhenTheLightIsOn() async {
        let store = SettingsStore.shared
        let saved = store.string("lights.eventGlow")
        defer { store.set("lights.eventGlow", saved) }
        let topBar = TopBarModel()
        topBar.createEvent = { _ in .created(id: "x") }
        store.set("lights.eventGlow", "true")
        let problem = await topBar.addEvent(from: "lunch with Ana tomorrow at 1 pm")
        #expect(problem == nil)
        #expect(topBar.lights.contains { $0.kind == .eventRibbon })

        let quiet = TopBarModel()
        quiet.createEvent = { _ in .created(id: "y") }
        store.set("lights.eventGlow", "false")
        _ = await quiet.addEvent(from: "lunch with Ana tomorrow at 1 pm")
        #expect(quiet.lights.isEmpty)
    }

    @Test func noRibbonWhenTheEventIsNotSaved() async {
        let topBar = TopBarModel()
        topBar.createEvent = { _ in .needsAccess }
        let problem = await topBar.addEvent(from: "lunch with Ana tomorrow at 1 pm")
        #expect(problem != nil)
        #expect(!topBar.lights.contains { $0.kind == .eventRibbon })
        topBar.createEvent = { _ in .failed("nope") }
        #expect(await topBar.addEvent(from: "lunch tomorrow at 1 pm") == "nope")
        #expect(await topBar.addEvent(from: "tomorrow at 1 pm") != nil)
    }

    @Test func eventGlowRowIsShownNow() {
        #expect(SettingsCatalog.option("lights.eventGlow")?.isShown == true)
    }
}
