import SwiftUI
import ZeusCore

/// Waves tab: a big live spectrum of whatever the Mac is playing, with the current track beside it.
/// The capture runs only while this page is on screen (and asks for System Audio Recording once, here).
struct WavesPage: View {
    let topBar: TopBarModel
    private var service: AudioSpectrumService { .shared }
    private var store: SettingsStore { .shared }

    var body: some View {
        let style = WaveStyle.parse(store.string(AudioSpectrumService.styleKey))
        let tint = ArtworkStore.shared.tint(for: topBar.nowPlaying, saturation: 0.55, brightness: 1)
        HStack(spacing: 8) {
            Tile(padding: 14) {
                ZStack {
                    if TopBarStyle.isSnapshot {
                        SpectrumCanvas(levels: service.levels, style: style, tint: tint)
                    } else {
                        TickingView(interval: 1 / 60, paused: !service.running) { _ in
                            SpectrumCanvas(levels: service.levels, style: style, tint: tint)
                        }
                    }
                    if let hint {
                        Text(hint).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudQuiet)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live audio spectrum")
            }
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        AlbumTile(playing: topBar.nowPlaying, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topBar.nowPlaying?.title ?? "Nothing playing")
                                .font(TopBarStyle.label(13.5, .bold)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
                            Text(topBar.nowPlaying?.artist ?? "")
                                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(WaveStyle.allCases) { option in
                            Button { store.set(AudioSpectrumService.styleKey, option.rawValue) } label: {
                                Text(option.rawValue).font(TopBarStyle.label(11, .semibold))
                                    .foregroundStyle(option == style ? Theme.storm : Theme.cloudSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                                    .background(option == style ? Theme.cloudPrimary : Color.white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(option.rawValue) style")
                            .accessibilityAddTraits(option == style ? .isSelected : [])
                        }
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 9.5))
                        Text("Audio source: System").font(TopBarStyle.label(10.5))
                    }
                    .foregroundStyle(Theme.cloudQuiet)
                    if service.permission == .refused {
                        Button("Allow in System Settings") { service.allowPressed() }
                            .buttonStyle(.plain).font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.ember)
                    }
                }
            }
            .frame(width: 250)
        }
        .onAppear { service.setWavesVisible(true); service.setMusicPlaying(topBar.nowPlaying?.isPlaying == true) }
        .onDisappear { service.setWavesVisible(false) }
    }

    private var hint: String? {
        if TopBarStyle.isSnapshot { return nil }
        switch service.permission {
        case .refused: return "System Audio Recording is off for Zeus"
        case .notAsked: return "Waiting for permission"
        case .allowed: return service.overall < 0.02 ? "Play something to see it move" : nil
        }
    }
}

/// Bars, a smooth wave or a mirrored pair, drawn from 28 band levels.
struct SpectrumCanvas: View {
    let levels: [Float]
    let style: WaveStyle
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let n = max(levels.count, 1)
            let values = levels.map { CGFloat(min(1, max(0, $0))) }
            let floor: CGFloat = 0.03
            let fill = Gradient(colors: [tint.opacity(0.95), tint.opacity(0.35)])
            switch style {
            case .bars, .mirror:
                let gap: CGFloat = 4
                let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * (w + gap)
                    let h = max(floor, v) * (style == .mirror ? size.height / 2 : size.height)
                    let rect: CGRect = style == .mirror
                        ? CGRect(x: x, y: size.height / 2 - h, width: w, height: h * 2)
                        : CGRect(x: x, y: size.height - h, width: w, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(w / 2, 4)),
                             with: .linearGradient(fill, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                }
            case .wave:
                let step = size.width / CGFloat(max(n - 1, 1))
                let points = values.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: size.height - max(floor, $0.element) * size.height * 0.92 - 2) }
                var line = Path()
                line.move(to: points[0])
                for i in 1..<points.count {
                    let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                    line.addQuadCurve(to: mid, control: points[i - 1])
                }
                line.addLine(to: points[points.count - 1])
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.45), tint.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
