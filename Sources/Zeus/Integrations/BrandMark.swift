import AppKit
import SwiftUI
import ZeusCore

/// A provider's mark from vector assets in `Integrations/Brands`. Drawn as a template in the text colour.
struct BrandMark: View {
    let provider: AIProvider
    var side: CGFloat = 28

    var body: some View {
        let mark = EngineBrand.resolve(provider: provider)
        let image = mark == .fallback ? nil : EngineBrandImage.load(mark)
        Group {
            if provider == .anyLLM {
                Image(systemName: "network")
                    .font(.system(size: side * 0.52, weight: .regular))
            } else if let image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(side * 0.12)
            } else {
                Text(String(provider.title.prefix(1)))
                    .font(OB.font(side * 0.5, .semibold))
            }
        }
        .foregroundStyle(GS.text)
        .frame(width: side, height: side)
        .background {
            if image == nil {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).fill(GS.selectedFill)
            }
        }
        .accessibilityLabel(provider.title)
    }
}
