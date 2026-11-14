import SwiftUI
import ZeusCore

/// The Tiling tab: the switch and the state beside it, the gaps and the key pair, a picture of the layout as it
/// is now, and the keys. The design note is `docs/TILING-DESIGN.md`.
///
/// The page makes no Accessibility call and shows no overlay of its own. It reads a `TilingController`, which in
/// a snapshot render is a seeded fixture, and it writes only through that controller, which writes the same
/// settings the Settings window has. The one permission action opens the existing Permissions page.
struct TilingPage: View {
    let topBar: TopBarModel
    let tiling: TilingController

    var body: some View {
        HStack(spacing: 8) {
            Tile(padding: 12) { TilingControls(topBar: topBar, tiling: tiling) }
                .frame(width: 292)
            Tile(padding: 12) { TilingLayoutPicture(tiling: tiling) }
                .frame(width: 232)
            Tile(padding: 12) { TilingKeyListView(rows: tiling.keyRows) }
        }
        .onAppear { if !TopBarStyle.isSnapshot { tiling.refresh() } }
    }
}

// MARK: Controls

private struct TilingControls: View {
    let topBar: TopBarModel
    let tiling: TilingController

    private var phase: TilingPhase { tiling.phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            status
            accessibilityRow
            gapRow(title: "Gap between windows", inner: true, value: tiling.config.innerGap)
            gapRow(title: "Gap to the screen edge", inner: false, value: tiling.config.outerGap)
            keysRow
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x2.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Tiling").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
            Spacer(minLength: 0)
            if phase == .running || phase == .paused {
                GlyphButton(symbol: phase == .paused ? "play.fill" : "pause.fill", size: 10,
                            label: phase == .paused ? "Resume tiling" : "Pause tiling") { tiling.togglePause() }
            }
            TilingSwitch(isOn: tiling.config.enabled) { tiling.setEnabled($0) }
        }
    }

    /// The state as a symbol and a word, then one plain line.
    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: phase.symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint)
                Text(phase.word).font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            Text(phase.detail).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tiling is \(phase.word)")
        .accessibilityValue(phase.detail)
    }

    private var tint: Color {
        switch phase {
        case .running: Theme.accent
        case .needsAccessibility, .keysUnavailable: Theme.bolt
        case .off, .paused: Theme.cloudQuiet
        }
    }

    private var accessibilityRow: some View {
        HStack(spacing: 6) {
            Image(systemName: tiling.accessibilityOn ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(tiling.accessibilityOn ? Theme.accent : Theme.cloudQuiet)
            Text("\(PermissionSweep.Item.accessibility.title): \(tiling.accessibilityOn ? "On" : "Off")")
                .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            Spacer(minLength: 4)
            if !tiling.accessibilityOn {
                Button("Open Permissions") { topBar.openPermissions() }
                    .buttonStyle(PressableStyle())
                    .font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.storm)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.bolt))
                    .accessibilityHint("Opens Settings, Permissions. Zeus never asks from here.")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func gapRow(title: String, inner: Bool, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            Spacer(minLength: 4)
            GlyphButton(symbol: "minus", size: 9, label: "Smaller: \(title)") { tiling.setGap(inner: inner, to: value - 4) }
            Text("\(Int(value))").font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                .frame(width: 26)
                .accessibilityLabel(title).accessibilityValue("\(Int(value)) points")
            GlyphButton(symbol: "plus", size: 9, label: "Larger: \(title)") { tiling.setGap(inner: inner, to: value + 4) }
        }
    }

    private var keysRow: some View {
        HStack(spacing: 6) {
            Text("Keys").font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            Spacer(minLength: 4)
            ForEach(TileModifierBase.allCases, id: \.self) { base in
                let selected = tiling.config.base == base
                Button { tiling.chooseBase(base) } label: {
                    Text(base.glyphs).font(TopBarStyle.label(11, .semibold))
                        .foregroundStyle(selected ? Theme.storm : Theme.cloudSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(selected ? Theme.accent : Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(base.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The on and off switch: a track and a knob, with the word beside it so the state is never colour alone.
private struct TilingSwitch: View {
    let isOn: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button { action(!isOn) } label: {
            HStack(spacing: 6) {
                Capsule().fill(isOn ? Theme.accent : Color.white.opacity(0.15)).frame(width: 26, height: 15)
                    .overlay(alignment: isOn ? .trailing : .leading) { Circle().fill(.white).frame(width: 11, height: 11).padding(2) }
                Text(isOn ? "On" : "Off").font(TopBarStyle.label(11, .semibold))
                    .foregroundStyle(isOn ? Theme.cloudPrimary : Theme.cloudSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Arrange my windows from the keyboard")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: Layout picture

private struct TilingLayoutPicture: View {
    let tiling: TilingController

    private var windowCount: Int { tiling.picture.reduce(0) { $0 + $1.tiles.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAYOUT").font(TopBarStyle.label(9, .bold)).foregroundStyle(Theme.cloudQuiet)
            if tiling.picture.isEmpty || windowCount == 0 {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.split.2x2").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                    Text(tiling.phase == .running || tiling.phase == .paused
                         ? "No windows are tiled on this Space."
                         : "Your layout shows here once tiling is on.")
                        .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(tiling.picture, id: \.displayID) { display in
                        DisplayPicture(display: display)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(windowCount) \(windowCount == 1 ? "window" : "windows") on \(tiling.picture.count) \(tiling.picture.count == 1 ? "screen" : "screens")")
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Layout")
        .accessibilityValue(windowCount == 0 ? "No windows tiled" : "\(windowCount) windows on \(tiling.picture.count) screens")
    }
}

/// One screen and its tiles. The focused tile is filled and outlined, so it differs by shape as well as colour.
private struct DisplayPicture: View {
    let display: TilingPictureDisplay

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: frame, cornerRadius: 5, style: .continuous), with: .color(Color.white.opacity(0.05)))
            context.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 5, style: .continuous),
                           with: .color(Color.white.opacity(0.25)), lineWidth: 1)
            for tile in display.tiles {
                let rect = CGRect(x: frame.minX + tile.rect.x * frame.width, y: frame.minY + tile.rect.y * frame.height,
                                  width: tile.rect.width * frame.width, height: tile.rect.height * frame.height)
                let path = Path(roundedRect: rect, cornerRadius: 2, style: .continuous)
                context.fill(path, with: .color(tile.isFocused ? Theme.accent.opacity(0.55) : Color.white.opacity(0.14)))
                if tile.isFocused { context.stroke(path, with: .color(Theme.accent), lineWidth: 1.5) }
            }
        }
        .aspectRatio(max(display.aspect, 0.2), contentMode: .fit)
        .frame(maxHeight: 118)
    }
}

// MARK: Keys

private struct TilingKeyListView: View {
    let rows: [TileKeyRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KEYS").font(TopBarStyle.label(9, .bold)).foregroundStyle(Theme.cloudQuiet).padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.title).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(row.keys).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                }
                .frame(height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.spoken)
            }
            Spacer(minLength: 0)
        }
    }
}
