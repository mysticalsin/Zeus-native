import AppKit
import Observation
import SwiftUI
import ZeusCore

/// What the card shows. Sizes come from the pure placement in ZeusCore, so the view never
/// measures or shrinks anything on its own.
@MainActor @Observable
final class ExplanationCardModel {
    var scene: ExplanationScene?
    var caption = ""
    var visualSize: CGSize?
    var worldHeight: CGFloat = 0
    var captionHeight: CGFloat = 0
    var accessibilitySummary = ""
    var reduceMotion = false
}

/// The card's content. The panel is click-through, so nothing here is interactive: the canvas and
/// the 3D view are rendered without selection, camera controls or object lists.
@MainActor
struct ExplanationCardView: View {
    let model: ExplanationCardModel
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            visual
            world
            captionText
        }
        .padding(.horizontal, CGFloat(ExplanationCardPlacement.sidePadding))
        .padding(.bottom, CGFloat(ExplanationCardPlacement.bottomPadding))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zeus explanation")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.bolt)
            Text("Zeus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(height: CGFloat(ExplanationCardPlacement.headerHeight))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var visual: some View {
        if let scene = model.scene, let size = model.visualSize {
            ExplanationCanvas(scene: scene, selection: $selection, isInteractive: false,
                              showsObjectList: false, minimumHeight: 0)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.accessibilitySummary)
        }
    }

    @ViewBuilder private var world: some View {
        if let scene = model.scene, model.worldHeight > 0 {
            ExplanationSceneView(scene: scene, selection: $selection, isActive: true, isInteractive: false, compact: true)
                .frame(height: model.worldHeight)
                .overlay(alignment: .bottomLeading) {
                    Text("Illustration, not to scale").font(.system(size: 10)).foregroundStyle(.secondary).padding(6)
                }
        }
    }

    @ViewBuilder private var captionText: some View {
        if !model.caption.isEmpty {
            Text(model.caption)
                .font(.system(size: CGFloat(ExplanationCardPlacement.captionFontSize), weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, CGFloat(ExplanationCardPlacement.captionPadding / 2))
                .frame(maxWidth: .infinity, minHeight: model.captionHeight, alignment: .topLeading)
                .accessibilityLabel("Narration: \(model.caption)")
        }
    }
}

/// Click-through connector from the card to the subject. It owns no input.
@MainActor
struct ExplanationCardConnectorView: View {
    let from: CGPoint
    let to: CGPoint
    var body: some View {
        Canvas { context, _ in
            var line = Path()
            line.move(to: from); line.addLine(to: to)
            context.stroke(line, with: .color(.accentColor.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: to.x - 3.5, y: to.y - 3.5, width: 7, height: 7)),
                         with: .color(.accentColor))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
