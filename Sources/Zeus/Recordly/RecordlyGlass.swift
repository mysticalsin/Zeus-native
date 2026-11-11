import SwiftUI
import ZeusCore

// Shared glass pieces for the Record page. Pure drawing: every number comes from ZeusCore (RecordlyVisuals).
// Nothing here owns a timer. Animations are one-shot, or live in views that exist only while capturing.

// MARK: Glass frame

/// The preview and clip frame: dark liquid glass with a top highlight, a hairline edge and soft depth.
struct RecordlyGlassFrame: ViewModifier {
    var radius: CGFloat = 16
    var glow: Color = Theme.accent
    var glowOpacity: Double = 0.16
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(hex: 0x171A21))
                } else {
                    shape.fill(Color.black.opacity(0.30))
                        .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.09), .clear],
                                                           startPoint: .top, endPoint: .center)))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0.05)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: reduceTransparency ? .clear : glow.opacity(glowOpacity), radius: 16, y: 7)
    }
}

extension View {
    func recordlyGlassFrame(radius: CGFloat = 16, glow: Color = Theme.accent, glowOpacity: Double = 0.16) -> some View {
        modifier(RecordlyGlassFrame(radius: radius, glow: glow, glowOpacity: glowOpacity))
    }
}

// MARK: Entrance

/// Staggered entrance when the page appears: a short rise and fade, item by item (about 0.35 s in all).
/// Reduce Motion: no movement and no stagger, a plain cross-fade. Snapshots start settled.
struct RecordlyEntranceModifier: ViewModifier {
    let item: RecordlyEntrance.Item
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = TopBarStyle.isSnapshot

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : RecordlyEntrance.offset(reduceMotion: reduceMotion))
            .animation(.easeOut(duration: reduceMotion ? Motion.crossfadeDuration : RecordlyEntrance.itemDuration)
                .delay(RecordlyEntrance.delay(item, reduceMotion: reduceMotion)), value: shown)
            .onAppear { shown = true }
    }
}

extension View {
    func recordlyEntrance(_ item: RecordlyEntrance.Item) -> some View {
        modifier(RecordlyEntranceModifier(item: item))
    }
}

// MARK: Live frame and countdown numeral

/// A thin red frame around the preview that breathes slowly. Exists only while capturing, so its repeating
/// animation stops the moment the view goes away. Still under Reduce Motion.
struct RecordlyLiveFrame: View {
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(TopBarStyle.rec, lineWidth: 2)
            .shadow(color: TopBarStyle.rec.opacity(0.5), radius: breathing ? 7 : 2)
            .opacity(opacity * (breathing ? 1 : 0.7))
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion, !TopBarStyle.isSnapshot else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
            }
            .accessibilityHidden(true)
    }
}

/// The large 3, 2, 1 over the preview. The numeral springs in once per second; the clock exists only during the
/// countdown. Reduce Motion: the digit cross-fades and holds still.
struct RecordlyCountdownNumeral: View {
    let remaining: Int
    let beganAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || TopBarStyle.isSnapshot {
            numeral(scale: 1, opacity: 1)
        } else {
            TimelineView(.animation) { context in
                let elapsed = beganAt.map { context.date.timeIntervalSince($0) } ?? 0
                let fraction = RecordlyCountdownVisual.stepFraction(elapsed: elapsed)
                numeral(scale: RecordlyCountdownVisual.numeralScale(stepFraction: fraction),
                        opacity: RecordlyCountdownVisual.numeralOpacity(stepFraction: fraction))
            }
        }
    }

    private func numeral(scale: Double, opacity: Double) -> some View {
        Text(RecordlyCountdownVisual.numeral(remaining: remaining) ?? "")
            .font(TopBarStyle.label(88, .bold).monospacedDigit())
            .foregroundStyle(Theme.cloudPrimary)
            .shadow(color: Color.black.opacity(0.45), radius: 12, y: 3)
            .scaleEffect(scale)
            .opacity(opacity)
            .id(remaining)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Meters

/// Holds the smoothing state between frames. Not observed: only the meter's own clock reads it.
final class RecordlyMeterBox {
    var meter = RecordlyLevelMeter()
    var last: Date?

    func advance(to date: Date, peak: Float) -> Double {
        let dt = last.map { date.timeIntervalSince($0) } ?? 0
        last = date
        return meter.step(target: RecordlyLevelMeter.perceptual(peak: peak), dt: dt)
    }
}

/// A row of small segments. Lit segments are the accent; nothing red.
struct RecordlyMeterBars: View {
    let value: Double
    var count = 12
    var enabled = true

    var body: some View {
        let lit = RecordlyLevelMeter.litSegments(value: value, count: count)
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? Theme.accent : Color.white.opacity(0.12))
                    .frame(width: 5, height: 9)
            }
        }
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Mic and system level meters inside the live capsule. The system meter reads the capture engine's latest peak
/// on a 30 fps clock that exists only while recording. The microphone is not recordable yet, so its row is idle.
struct RecordlyLiveMeters: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var box = RecordlyMeterBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row(symbol: "mic", title: "Mic") { RecordlyMeterBars(value: 0, enabled: false) }
            row(symbol: "speaker.wave.2", title: "System") { systemBars }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recordly.audio.systemAudio ? "System audio level" : "System audio is off")
    }

    @ViewBuilder
    private var systemBars: some View {
        if !recordly.audio.systemAudio {
            RecordlyMeterBars(value: 0, enabled: false)
        } else if reduceMotion || TopBarStyle.isSnapshot {
            RecordlyMeterBars(value: TopBarStyle.isSnapshot ? 0.55 : 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                RecordlyMeterBars(value: box.advance(to: context.date, peak: recordly.systemAudioPeak()))
            }
        }
    }

    private func row<Bars: View>(symbol: String, title: String, @ViewBuilder bars: () -> Bars) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                .frame(width: 14)
            Text(title).font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudSecondary).frame(width: 36, alignment: .leading)
            bars()
        }
    }
}

// MARK: Live capsule

/// Glass capsule while capturing: live dot, "Recording", the timer in monospaced digits, then the meters.
/// Red is only the dot and the timer.
struct RecordlyLiveCapsule: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RecordlyPulseDotView()
                Text(recordly.isStopping ? "Saving" : "Recording")
                    .font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                if recordly.isStopping { ProgressView().controlSize(.small) }
                Spacer(minLength: 6)
                timer
            }
            if let name = recordly.selectedSourceName {
                Text(name).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            if !recordly.isStopping { RecordlyLiveMeters(recordly: recordly) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .recordlyGlassFrame(radius: 18, glow: TopBarStyle.rec, glowOpacity: reduceTransparency ? 0 : 0.12)
    }

    /// A TimelineView only ticks while it is on screen, once a second, and not at all when nothing shows it.
    private var timer: some View {
        TimelineView(.periodic(from: recordly.startedAt ?? Date(), by: 1)) { context in
            let seconds = recordly.startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? recordly.elapsed
            Text(RecordlyElapsed.format(seconds))
                .font(TopBarStyle.label(26, .bold).monospacedDigit())
                .foregroundStyle(TopBarStyle.rec)
                .contentTransition(.numericText())
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(RecordlyElapsed.spoken(seconds))
        }
    }
}

/// The live dot with a slow halo. Standing still under Reduce Motion.
struct RecordlyPulseDotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle().fill(TopBarStyle.rec).frame(width: 9, height: 9)
            .overlay {
                Circle().strokeBorder(TopBarStyle.rec.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(pulsing ? 2.4 : 1).opacity(pulsing ? 0 : 0.8)
            }
            .frame(width: 20, height: 20)
            .onAppear {
                guard !reduceMotion, !TopBarStyle.isSnapshot else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulsing = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording")
    }
}

// MARK: Source chip

/// One toggle chip with a clear state: on (filled, check), off (outline), needs permission (lock, amber),
/// unavailable (dim, "Soon" in the tooltip and VoiceOver value).
struct RecordlySourceChip: View {
    let symbol: String
    let title: String
    let state: RecordlySourceChipState
    let help: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(TopBarStyle.label(10, .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                badge
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 9).frame(height: 26)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .shadow(color: state == .on && !reduceTransparency ? Theme.accent.opacity(0.28) : .clear, radius: 6)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .disabled(state == .unavailable)
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.28, dampingFraction: 0.85), value: state)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(state == .unavailable ? "Soon. \(help)" : state.word)
        .accessibilityAddTraits(state == .on ? .isSelected : [])
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .on:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
        case .off:
            Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1).frame(width: 9, height: 9)
        case .needsPermission:
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.bolt)
        case .unavailable:
            Text("Soon").font(TopBarStyle.label(8, .bold)).foregroundStyle(Theme.cloudSecondary)
        }
    }

    private var foreground: Color {
        switch state {
        case .on: Theme.cloudPrimary
        case .off, .needsPermission: Theme.cloudSecondary
        case .unavailable: Theme.cloudSecondary.opacity(0.7)
        }
    }

    private var fill: Color {
        switch state {
        case .on: Theme.accent.opacity(reduceTransparency ? 0.4 : 0.20)
        case .off, .needsPermission: reduceTransparency ? Color(hex: 0x242933) : Color.white.opacity(0.07)
        case .unavailable: reduceTransparency ? Color(hex: 0x1D2129) : Color.white.opacity(0.04)
        }
    }

    private var stroke: Color {
        switch state {
        case .on: Theme.accent.opacity(0.75)
        case .needsPermission: Theme.bolt.opacity(0.55)
        case .off: Color.white.opacity(0.12)
        case .unavailable: Color.clear
        }
    }
}

// MARK: Clip card

/// The saved clip: first frame (the pinned preview player), duration and size, and four actions.
struct RecordlyClipCard: View {
    let recordly: RecordlyController
    @Binding var showsEditing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordlyMediaPreview(media: recordly.mediaAuthority, unavailableReason: recordly.previewUnavailableReason)
                .frame(width: 168)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                header
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .recordlyGlassFrame(radius: 16, glow: Theme.accent, glowOpacity: 0.18)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
                Text("Recording saved").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            let line = RecordlyClipSummary.line(duration: recordly.elapsed, bytes: recordly.mediaByteCount)
            if !line.isEmpty {
                Text(line).font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
            }
            if let url = recordly.lastMediaURL {
                Text(url.lastPathComponent).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            if let project = recordly.project {
                Text("\(project.zoomRegions.count) zoom regions")
                    .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let url = recordly.lastMediaURL {
            HStack(spacing: 6) {
                clipButton("Open", symbol: "play.rectangle") { recordly.openMedia(url) }
                clipButton("Show in Finder", symbol: "folder") { recordly.revealInFinder(url) }
                    .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
            }
            HStack(spacing: 6) {
                clipButton("Copy", symbol: "doc.on.doc") { recordly.copyMedia(url) }
                clipButton(showsEditing ? "Done" : "Edit", symbol: "slider.horizontal.3", prominent: true) {
                    showsEditing.toggle()
                }
            }
        }
    }

    private func clipButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(TopBarStyle.label(10, .semibold)).lineLimit(1)
            }
            .foregroundStyle(prominent ? Theme.storm : Theme.cloudPrimary)
            .padding(.horizontal, 9).frame(height: 24)
            .background(Capsule().fill(prominent ? Theme.cloudPrimary : Color.white.opacity(0.10)))
        }
        .buttonStyle(PressableStyle())
    }
}
