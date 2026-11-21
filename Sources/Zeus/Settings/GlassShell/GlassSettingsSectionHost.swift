import SwiftUI
import ZeusCore

/// The app-side page for a compile-time slot provider. The host asks the provider; it does not branch on the id.
protocol GlassSlotPage: GlassSlotProviding {
    static func erasePage() -> AnyView
}

enum GlassSettingsSectionHost {
    @ViewBuilder
    static func page(for slot: GlassSectionSlot) -> some View {
        if let provider = GlassSectionManifest.providers.first(where: { $0.descriptor.id == slot.id }),
           let page = provider as? any GlassSlotPage.Type {
            page.erasePage()
        } else {
            Text(slot.title)
                .accessibilityLabel(slot.title)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct GlassSettingsCardHost: View {
    let page: GlassCardPage

    var body: some View {
        let cards = GlassSectionManifest.cards(on: page)
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
                ForEach(cards, id: \.id) { slot in
                    GlassSettingsSlotPage(slot: slot)
                }
            }
        }
    }
}

struct GlassTopbarPage: View {
    let selected: String
    let navigation: GSNavigation

    var body: some View {
        let tabs = GlassSectionManifest.topbarTabs()
        VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.id) { tab in
                    let on = tab.id == selected
                    Button(tab.title) { navigation.selectTopbar(tab.id) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let slot = tabs.first(where: { $0.id == selected }) {
                GlassSettingsSlotPage(slot: slot)
            }
        }
    }
}

struct GlassSettingsSlotPage: View {
    let slot: GlassSectionSlot

    var body: some View {
        let heading = SettingsSectionRegistry.pageHeading(for: slot).map { [$0] } ?? []
        let exposed = GlassSettingsAccessibility.exposure(sections: heading)
        VStack(alignment: .leading, spacing: 8) {
            if let item = exposed.first {
                Text(item.label)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(item.heading ? .isHeader : [])
                    .accessibilityHidden(item.hidden)
            }
            GlassSettingsSectionHost.page(for: slot)
        }
        .accessibilityElement(children: .contain)
    }
}
