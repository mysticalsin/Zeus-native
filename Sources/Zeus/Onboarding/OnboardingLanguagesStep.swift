import SwiftUI
import ZeusCore

/// Languages: English, French, Spanish and Portuguese are ticked. Continue only remembers the ticks; the
/// installs start after the guide finishes (OnboardingWindowController.finish), in the background.
struct LanguagesStep: View {
    private var packs: LanguagePackController { .shared }
    @Environment(\.ob) private var ob

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Your languages", subtitle: "")
                .frame(width: 520, alignment: .leading)
            VStack(spacing: 0) {
                ForEach(LanguagePackID.allCases, id: \.self) { pack in
                    OBRow(symbol: "globe", title: pack.title, text: "") {
                        Toggle(pack.title, isOn: Binding(
                            get: { packs.onboardingChoice.contains(pack) },
                            set: { on in
                                if on { packs.onboardingChoice.insert(pack) } else { packs.onboardingChoice.remove(pack) }
                            }))
                            .toggleStyle(OBToggleStyle(size: .large))
                            .accessibilityLabel("\(pack.title) language pack")
                            .accessibilityIdentifier("onboarding.language.\(pack.rawValue)")
                    }
                    .frame(height: 61)
                    OBDivider()
                }
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
            Text(note)
                .font(OB.font(12.5)).foregroundStyle(ob.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 420, alignment: .leading)
                .padding(.top, 12)
        }
    }

    private var note: String {
        if packs.state.analyzerSupported {
            return "Nothing downloads now. After setup, Zeus installs the ticked languages in the background, one at a time. macOS shows the size. Pause in Low Power Mode. Change this any time in Settings > Dictation."
        }
        return "This Mac uses the dictation languages set in System Settings. You can pick them later in Settings > Dictation."
    }
}
