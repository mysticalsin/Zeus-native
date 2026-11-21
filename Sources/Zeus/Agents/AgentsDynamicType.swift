import SwiftUI

/// Text sizes for this surface. `.large` is the standard macOS size and keeps the point size already on screen.
enum AgentsDynamicType {
    static func points(_ base: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        base * scale(dynamicTypeSize)
    }

    static func scale(_ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        case .accessibility1: 1.64
        case .accessibility2: 1.9
        case .accessibility3: 2.15
        case .accessibility4: 2.4
        case .accessibility5: 2.7
        @unknown default: 1
        }
    }
}
