import SwiftUI
import ZeusCore

struct RecordlyPage: View {
    let topBar: TopBarModel
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEditor: Bool { if case .editor = recordly.phase { true } else { false } }

    var body: some View {
        HStack(spacing: 8) {
            Tile(padding: 0) {
                ZStack(alignment: .topLeading) {
                    RecordlyCardBeam(recordly: recordly)
                    Group {
                        if isEditor {
                            RecordlyEditor(recordly: recordly).transition(.opacity)
                        } else {
                            RecordlyCapture(recordly: recordly, topBar: topBar).transition(.opacity)
                        }
                    }
                    .padding(CardFinish.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : TopBarStyle.pageSpring, value: isEditor)
        // Lists the displays and selects the main one with no click and no Screen Recording permission.
        .onAppear { recordly.pageAppeared() }
        .onDisappear { recordly.pageDisappeared() }
    }
}

/// Decorative recording/export activity only. Recordly has no microphone meter, so level stays zero.
/// Export percentages, controls and success/failure still come exclusively from its controller.
private struct RecordlyCardBeam: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var timeline: RecordingFeedback.BeamTimeline?
    @State private var workSnapshot: RecordingFeedback.Snapshot?
    @State private var recordingOrigin: Date?

    var body: some View {
        let feedback = recordly.topBarFeedback()
        let active = recordly.showsRunning || recordly.isExporting || feedback?.phase == .completed
        let completionEnd = feedback.flatMap { snapshot in
            snapshot.phase == .completed
                ? Date(timeIntervalSinceReferenceDate: snapshot.beganAt + RecordingFeedback.Motion.revealDuration) : nil
        }
        DisplaySynchronizedView(paused: !active || reduceMotion || reduceTransparency,
                                preferredFramesPerSecond: 240, until: completionEnd) { context in
            if active {
                let now = context.date.timeIntervalSinceReferenceDate
                let elapsed = (recordly.startedAt ?? recordingOrigin).map { max(0, context.date.timeIntervalSince($0)) }
                    ?? timeline?.elapsed(at: now) ?? 0
                let processing = recordly.isStopping || recordly.isExporting
                    || (feedback?.phase == .completed && workSnapshot != nil)
                AssistantBeamView(frame: AssistantBeam.frame(elapsed: elapsed, level: 0,
                    processing: processing,
                    processingElapsed: workSnapshot.map { max(0, now - $0.beganAt) } ?? 0,
                    reduceMotion: reduceMotion || reduceTransparency),
                    reduceTransparency: reduceTransparency, cornerRadius: CardFinish.radius)
                    .opacity(beamOpacity(feedback, at: now))
            }
        }
        .onChange(of: feedback, initial: true) { _, snapshot in
            guard let snapshot, snapshot.phase != .failed else {
                timeline = nil
                workSnapshot = nil
                if snapshot?.phase == .failed { recordingOrigin = nil }
                return
            }
            if timeline == nil { timeline = RecordingFeedback.BeamTimeline(snapshot) }
            else { timeline?.update(snapshot) }
            // Completion fades the same processing shape. A new export gets its own gather clock.
            if snapshot.phase != .completed { workSnapshot = snapshot }
        }
        .onChange(of: recordly.startedAt, initial: true) { _, start in
            // The controller clears startedAt when the saved project replaces the running capture.
            // Keep this drawing origin through that completion fade, including the new media-path key.
            if let start { recordingOrigin = start }
        }
        .onChange(of: recordly.phase) { _, phase in
            switch phase {
            case .idle, .starting, .failed: recordingOrigin = nil
            default: break
            }
        }
        .onChange(of: recordly.project?.rawMediaPath) { previous, next in
            // nil → first saved project is the capture above; replacing/removing it starts a new lifetime.
            if previous != nil && previous != next { recordingOrigin = nil }
        }
    }

    private func beamOpacity(_ snapshot: RecordingFeedback.Snapshot?, at now: TimeInterval) -> Double {
        guard let snapshot, snapshot.phase == .completed else { return 1 }
        if reduceMotion || reduceTransparency { return 0 }
        return RecordingFeedback.frame(snapshot, at: now, reduceMotion: false, reduceTransparency: false).beamOpacity / 0.6
    }
}

// MARK: Capture page (idle, countdown, starting, recording, stopping)

/// One stable layout for every capture state: the preview stage on the left, options and the capture control on the
/// right. Only the content of the right column changes, so nothing jumps when the state does.
private struct RecordlyCapture: View {
    let recordly: RecordlyController
    let topBar: TopBarModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RecordlyStage(recordly: recordly)
                .frame(width: 340)
            VStack(alignment: .leading, spacing: 10) {
                RecordlyScroll {
                    if recordly.showsRunning {
                        RecordlyLiveCapsule(recordly: recordly).transition(.opacity)
                    } else {
                        RecordlyIdleColumn(recordly: recordly)
                    }
                }
                .layoutPriority(1)
                RecordlyControlRow(recordly: recordly, topBar: topBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// ImageRenderer cannot draw scroll views, so the offscreen snapshots lay the content out flat.
private struct RecordlyScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if TopBarStyle.isSnapshot {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(showsIndicators: false) {
                content.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private enum RecordlySurface {
    static func soft(_ reduceTransparency: Bool) -> Color {
        reduceTransparency ? Color(hex: 0x242933) : Color.white.opacity(0.07)
    }
    static func stage(_ reduceTransparency: Bool) -> Color {
        reduceTransparency ? Color(hex: 0x171A21) : Color.black.opacity(0.28)
    }
}

private struct RecordlyIdleColumn: View {
    let recordly: RecordlyController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                RecordlySourceSwitcher(recordly: recordly)
                sourceDetail
            }
            .recordlyEntrance(.picker)
            RecordlyNotices(recordly: recordly)
            RecordlyOptionChips(recordly: recordly)
                .recordlyEntrance(.chips)
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        switch recordly.sourceKind {
        case .display:
            RecordlyDisplayLegend(recordly: recordly)
        case .window:
            RecordlyWindowList(recordly: recordly)
        case .region:
            Text("Area recording isn't available yet.")
                .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
        }
    }
}

// MARK: Source switcher

private struct RecordlySourceSwitcher: View {
    let recordly: RecordlyController
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static func symbol(_ kind: RecordlyCaptureSource.Kind) -> String {
        switch kind {
        case .display: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }

    private static func title(_ kind: RecordlyCaptureSource.Kind) -> String {
        switch kind {
        case .display: "Display"
        case .window: "Window"
        case .region: "Area"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RecordlyCaptureSource.Kind.allCases, id: \.self) { kind in
                segment(kind)
            }
        }
        .padding(2)
        .background(Capsule().fill(RecordlySurface.soft(reduceTransparency)))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: recordly.sourceKind)
        .fixedSize()
    }

    private func segment(_ kind: RecordlyCaptureSource.Kind) -> some View {
        let selected = recordly.sourceKind == kind
        let available = kind != .region
        let enabled = available && recordly.canChooseSource
        return Button {
            recordly.selectSourceKind(kind)
            Task { await recordly.loadSourceCatalog() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.symbol(kind)).font(.system(size: 11, weight: .semibold))
                Text(Self.title(kind)).font(TopBarStyle.label(11, .semibold))
            }
            .foregroundStyle(selected ? Theme.cloudPrimary : Theme.cloudSecondary)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background {
                if selected {
                    Capsule().fill(reduceTransparency ? Color(hex: 0x3A4150) : Color.white.opacity(0.16))
                        .matchedGeometryEffect(id: "segment", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(available ? (enabled || selected ? 1 : 0.6) : 0.4)
        .help(available ? "" : "Area recording isn't available yet.")
        .accessibilityLabel(Self.title(kind))
        .accessibilityHint(available ? "" : "Not available yet")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Display legend

private struct RecordlyDisplayLegend: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let displays = recordly.displays
        if displays.isEmpty {
            Text("No displays found.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
        } else if displays.count == 1, let only = displays.first {
            compactRow(only)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    chip(display, position: index)
                }
            }
        }
    }

    private func isSelected(_ display: RecordlySourceSelection.CatalogSnapshot.Display) -> Bool {
        recordly.isSelected(.display(id: display.id))
    }

    /// One display: a single selected row, "Built-in Retina Display, Main".
    private func compactRow(_ display: RecordlySourceSelection.CatalogSnapshot.Display) -> some View {
        let selected = isSelected(display)
        return HStack(spacing: 7) {
            Image(systemName: "display").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
            Text(RecordlyDisplayChoice.compactLine(display, position: 0))
                .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            Text(RecordlyDisplayChoice.size(display))
                .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(selected ? Theme.accent.opacity(reduceTransparency ? 0.4 : 0.18) : RecordlySurface.soft(reduceTransparency)))
        .overlay(Capsule().strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecordlyDisplayChoice.spokenLabel(display, position: 0))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func mainTag(_ selected: Bool) -> some View {
        Text("Main").font(TopBarStyle.label(8, .bold)).foregroundStyle(selected ? Theme.storm : Theme.cloudSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(selected ? Theme.accent : Color.white.opacity(0.12)))
    }

    private func chip(_ display: RecordlySourceSelection.CatalogSnapshot.Display, position: Int) -> some View {
        let selected = isSelected(display)
        return Button {
            recordly.selectSource(.display(id: display.id))
        } label: {
            HStack(spacing: 5) {
                Text("\(position + 1)")
                    .font(TopBarStyle.label(9, .bold).monospacedDigit())
                    .foregroundStyle(selected ? Theme.storm : Theme.cloudPrimary)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(selected ? Theme.accent : Color.white.opacity(0.14)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(RecordlyDisplayChoice.title(display, position: position))
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    Text(RecordlyDisplayChoice.size(display))
                        .font(TopBarStyle.label(9).monospacedDigit()).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                }
                if display.isMain { mainTag(selected) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .shadow(color: Theme.accent.opacity(selected && !reduceTransparency ? 0.4 : 0), radius: 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.accent.opacity(reduceTransparency ? 0.4 : 0.18) : RecordlySurface.soft(reduceTransparency)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!recordly.canChooseSource)
        .accessibilityLabel(RecordlyDisplayChoice.spokenLabel(display, position: position))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Window list (Screen Recording permission is needed to list windows)

private struct RecordlyWindowList: View {
    let recordly: RecordlyController

    var body: some View {
        switch recordly.pickerState {
        case .notLoaded:
            quietButton("Load windows") { Task { await recordly.loadSourceCatalog() } }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading windows").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                quietButton("Cancel") { recordly.cancelLoading() }
                    .accessibilityLabel("Cancel loading sources")
            }
        case .loaded(let snapshot, _):
            rows(snapshot)
        case .stale(let snapshot, _, let reason):
            Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
            quietButton("Refresh") { Task { await recordly.loadSourceCatalog() } }
            if let snapshot { rows(snapshot) }
        case .denied(let reason):
            if recordly.screenRecordingGranted {
                Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
                quietButton("Check again") { Task { await recordly.loadSourceCatalog() } }
            }
        case .failed(let reason):
            Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
            quietButton("Refresh") { Task { await recordly.loadSourceCatalog() } }
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudPrimary)
    }

    @ViewBuilder
    private func rows(_ snapshot: RecordlySourcePicker.CatalogSnapshot) -> some View {
        VStack(alignment: .leading, spacing: RecordlyPageLayout.rowSpacing) {
            if snapshot.windows.isEmpty {
                Text("No eligible owned windows available.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
            }
            ForEach(snapshot.windows, id: \.identityToken) { window in
                let intent = RecordlySourceSelection.SelectionIntent.window(number: window.number, identityToken: window.identityToken)
                let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let owner = window.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
                let ownerLabel = owner.flatMap { $0.isEmpty ? nil : $0 } ?? "Owned app"
                let selected = recordly.isSelected(intent)
                Button { recordly.selectSource(intent) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "macwindow")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayTitle).font(TopBarStyle.label(10)).lineLimit(1)
                            Text("\(ownerLabel) \u{00B7} Window \(window.number)").font(TopBarStyle.label(9)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.cloudSecondary)
                }
                .buttonStyle(.plain)
                .disabled(window.number <= 0 || !window.isPresent || !recordly.canChooseSource)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: Banner, notices

private struct RecordlyNotices: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !recordly.screenRecordingGranted {
                banner
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recordly.failureReason != nil {
                Button("Try again") { recordly.retry() }.buttonStyle(.plain)
                    .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
        }
    }

    private var lines: [String] {
        [recordly.displayNotice, recordly.actionNotice, recordly.selectionNotice, recordly.failureReason].compactMap { $0 }
    }

    /// Inline permission banner: icon, one sentence, one button. Never prompts; the button opens System Settings.
    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.bolt)
            Text("Screen Recording is off for Zeus.")
                .font(TopBarStyle.label(10, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
            Spacer(minLength: 4)
            Button { recordly.openScreenRecordingSettings() } label: {
                Text("Open Screen Recording settings")
                    .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.storm)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Theme.cloudPrimary))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(RecordlySurface.soft(reduceTransparency)))
        .accessibilityElement(children: .contain)
    }
}

// MARK: Option chips

private struct RecordlyOptionChips: View {
    let recordly: RecordlyController

    private var systemState: RecordlySourceChipState {
        .resolve(on: recordly.audio.systemAudio, available: true, needsPermission: !recordly.screenRecordingGranted)
    }

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                RecordlySourceChip(symbol: "mic", title: "Microphone", state: .unavailable,
                                   help: "Microphone in recordings is coming soon") { }
                    .frame(maxWidth: .infinity)
                RecordlySourceChip(symbol: "speaker.wave.2", title: "System audio", state: systemState,
                                   help: systemState == .needsPermission
                                       ? "Allow Screen Recording to record the sound your Mac plays"
                                       : "Record the sound your Mac plays") { toggleSystemAudio() }
                    .frame(maxWidth: .infinity)
            }
            GridRow {
                RecordlySourceChip(symbol: "camera", title: "Camera bubble", state: .unavailable,
                                   help: "Camera in recordings is coming soon") { }
                    .frame(maxWidth: .infinity)
                RecordlySourceChip(symbol: "cursorarrow.rays", title: "Cursor zoom",
                                   state: .resolve(on: recordly.exportSettings.followCursor, available: true, needsPermission: false),
                                   help: "Smoothly follows the cursor during zooms on a verified display recording.") {
                    guard recordly.canChooseSource else { return }
                    recordly.exportSettings.followCursor.toggle()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func toggleSystemAudio() {
        if !recordly.screenRecordingGranted {
            recordly.openScreenRecordingSettings()
            return
        }
        guard recordly.canChooseSource else { return }
        recordly.audio.systemAudio.toggle()
    }
}

// MARK: Preview stage

private struct RecordlyStage: View {
    let recordly: RecordlyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = RecordlyVisualTokens.tokens(for: recordly.visualPhase)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            content
            shape.fill(Color.black.opacity(tokens.previewDim)).allowsHitTesting(false)
            if tokens.showsCountdownNumeral, let remaining = recordly.countdownRemaining {
                RecordlyCountdownNumeral(remaining: remaining, beganAt: recordly.countdownBeganAt)
            }
        }
        .clipShape(shape)
        .overlay {
            if tokens.liveFrameOpacity > 0 {
                RecordlyLiveFrame(opacity: tokens.liveFrameOpacity).transition(.opacity)
            }
        }
        .recordlyGlassFrame(radius: 16, glow: recordly.showsRunning ? TopBarStyle.rec : Theme.accent,
                            glowOpacity: recordly.showsRunning ? 0.14 : 0.18)
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .easeInOut(duration: 0.25),
                   value: recordly.visualPhase)
        .recordlyEntrance(.preview)
    }

    @ViewBuilder
    private var content: some View {
        switch recordly.sourceKind {
        case .display:
            RecordlyDisplayDiagram(recordly: recordly)
        case .window, .region:
            VStack(spacing: 8) {
                Image(systemName: recordly.sourceKind == .window ? "macwindow" : "rectangle.dashed")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(Theme.cloudSecondary)
                Text(recordly.sourceKind == .window ? (recordly.selectedSourceName ?? "Choose a window") : "Area recording isn't available yet.")
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .multilineTextAlignment(.center).padding(.horizontal, 16)
            }
        }
    }
}

/// The connected displays as rectangles to scale, placed like System Settings > Displays.
private struct RecordlyDisplayDiagram: View {
    let recordly: RecordlyController

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 16
            let bounds = CGSize(width: max(1, proxy.size.width - inset * 2), height: max(1, proxy.size.height - inset * 2))
            let displays = recordly.displays
            let tiles = RecordlyDisplayChoice.arrangement(displays, in: bounds, gap: displays.count > 1 ? 6 : 0)
            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    if let tile = tiles.first(where: { $0.id == display.id }) {
                        RecordlyDisplayTile(
                            display: display, position: index, size: tile.rect.size,
                            selected: recordly.isSelected(.display(id: display.id)),
                            live: recordly.showsRunning,
                            selectable: displays.count > 1 && recordly.canChooseSource,
                            thumbnail: recordly.thumbnail
                        ) { recordly.selectSource(.display(id: display.id)) }
                        .position(x: inset + tile.rect.midX, y: inset + tile.rect.midY)
                    }
                }
            }
        }
    }
}

private struct RecordlyDisplayTile: View {
    let display: RecordlySourceSelection.CatalogSnapshot.Display
    let position: Int
    let size: CGSize
    let selected: Bool
    let live: Bool
    let selectable: Bool
    let thumbnail: CGImage?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if selectable {
            Button(action: action) { tile }
                .buttonStyle(.plain)
                .accessibilityLabel(RecordlyDisplayChoice.spokenLabel(display, position: position))
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            tile
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RecordlyDisplayChoice.spokenLabel(display, position: position))
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let outline = selected ? (live ? Color.white.opacity(0.35) : Theme.accent) : Color.white.opacity(0.2)
        return ZStack {
            shape.fill(selected ? Theme.accent.opacity(0.30) : Color.white.opacity(0.07))
            if selected, let thumbnail {
                Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipShape(shape)
            }
            label
            shape.strokeBorder(outline, lineWidth: selected ? 2 : 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: Theme.accent.opacity(selected && !live ? 0.55 : 0), radius: 10)
        .contentShape(shape)
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.3, dampingFraction: 0.85), value: selected)
    }

    @ViewBuilder
    private var label: some View {
        if size.width > 70, size.height > 34 {
            VStack(spacing: 1) {
                Text(RecordlyDisplayChoice.title(display, position: position))
                    .font(TopBarStyle.label(9, .semibold)).lineLimit(1)
                Text(display.isMain ? "Main, \(RecordlyDisplayChoice.size(display))" : RecordlyDisplayChoice.size(display))
                    .font(TopBarStyle.label(8).monospacedDigit()).lineLimit(1)
            }
            .foregroundStyle(Theme.cloudPrimary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(selected && thumbnail != nil ? 0.55 : 0)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 6)
        } else {
            Text("\(position + 1)").font(TopBarStyle.label(11, .bold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
        }
    }
}

// MARK: Capture control

enum RecordlyControlVisual: Equatable {
    case idle
    case countdown(Int)
    case starting
    case recording
    case stopping
}

extension RecordlyControlVisual {
    var visualPhase: RecordlyVisualPhase {
        switch self {
        case .idle: .idle
        case .countdown(let n): .countdown(n)
        case .starting: .starting
        case .recording: .recording
        case .stopping: .stopping
        }
    }
}

private extension RecordlyController {
    /// The whole page's visual phase: the control's phase, or saved once a clip is open.
    var visualPhase: RecordlyVisualPhase {
        if case .editor = phase { return .saved }
        return controlVisual.visualPhase
    }

    var controlVisual: RecordlyControlVisual {
        if let remaining = countdownRemaining { return .countdown(remaining) }
        if isStopping { return .stopping }
        if isRecording { return .recording }
        if isStarting { return .starting }
        return .idle
    }
}

private struct RecordlyControlRow: View {
    let recordly: RecordlyController
    let topBar: TopBarModel

    var body: some View {
        let visual = recordly.controlVisual
        HStack(spacing: 14) {
            RecordlyCaptureControl(
                visual: visual, enabled: enabled(visual), countdownBeganAt: recordly.countdownBeganAt,
                help: disabledReason ?? "", spokenSource: recordly.selectedSourceName
            ) { activate(visual) }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(visual)).font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Text(caption(visual)).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 64)
        .recordlyEntrance(.button)
        .background {
            if recordly.isCountingDown {
                // Escape cancels the countdown.
                Button("Cancel countdown") { recordly.cancelCountdown() }
                    .keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
    }

    private var disabledReason: String? {
        if !recordly.screenRecordingGranted { return "Allow Screen Recording in System Settings to record." }
        if recordly.canStart { return nil }
        return "Choose a display or window first."
    }

    private func enabled(_ visual: RecordlyControlVisual) -> Bool {
        switch visual {
        case .idle: recordly.canRecord
        case .countdown, .starting, .recording: true
        case .stopping: false
        }
    }

    private func activate(_ visual: RecordlyControlVisual) {
        switch visual {
        case .idle: recordly.pressRecord(topBar: topBar)
        case .countdown: recordly.cancelCountdown()
        case .starting: Task { await recordly.cancelStart() }
        case .recording: Task { await recordly.stop() }
        case .stopping: break
        }
    }

    private func headline(_ visual: RecordlyControlVisual) -> String {
        switch visual {
        case .idle: "Record"
        case .countdown(let n): "Starting in \(n)"
        case .starting: "Starting"
        case .recording: "Stop"
        case .stopping: "Saving"
        }
    }

    private func caption(_ visual: RecordlyControlVisual) -> String {
        switch visual {
        case .idle:
            if let reason = disabledReason { return reason }
            return "Records \(recordly.selectedSourceName ?? "the selected source")"
        case .countdown: return "Press Esc or the button to cancel"
        case .starting: return "Checking the source"
        case .recording: return "Saves when you stop"
        case .stopping: return "Finishing the file"
        }
    }
}

/// The round glass capture control. Idle: white ring and a filled dot. Countdown: a ring draws around the digits.
/// Recording: the dot morphs into a rounded square. Red only appears while capturing.
struct RecordlyCaptureControl: View {
    let visual: RecordlyControlVisual
    let enabled: Bool
    let countdownBeganAt: Date?
    let help: String
    let spokenSource: String?
    /// Scribe draws this symbol in the idle ring instead of the filled dot.
    let idleSymbol: String?
    /// The spoken name of the idle action ("Record" on the Record page).
    let idleLabel: String
    /// Spoken while capturing ("Stop recording").
    let stopLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false

    /// Explicit because the private properties above would make the memberwise one private to this file.
    init(visual: RecordlyControlVisual, enabled: Bool, countdownBeganAt: Date?, help: String, spokenSource: String?,
         idleSymbol: String? = nil, idleLabel: String = "Record", stopLabel: String = "Stop recording",
         action: @escaping () -> Void) {
        self.visual = visual
        self.enabled = enabled
        self.countdownBeganAt = countdownBeganAt
        self.help = help
        self.spokenSource = spokenSource
        self.idleSymbol = idleSymbol
        self.idleLabel = idleLabel
        self.stopLabel = stopLabel
        self.action = action
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.38, dampingFraction: 0.74)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(reduceTransparency ? Color(hex: 0x2A2F3A) : Color.white.opacity(0.10))
                Circle().strokeBorder(Color.white.opacity(visual == .idle && !enabled ? 0.28 : 0.9), lineWidth: 2.5)
                countdownRing
                glyph
            }
            .frame(width: 56, height: 56)
            .background { ambientGlow }
            .shadow(color: reduceTransparency ? .clear : Color.black.opacity(0.35), radius: 8, y: 3)
            .contentShape(Circle())
        }
        .buttonStyle(RecordlyControlStyle(hovering: hovering, reduceMotion: reduceMotion))
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(motion, value: visual)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(spokenSource ?? "")
        .accessibilityHint(enabled || help.isEmpty ? "" : help)
    }

    /// A calm, static halo behind the button. No animation, so it costs nothing at rest.
    @ViewBuilder
    private var ambientGlow: some View {
        let glow = RecordlyVisualTokens.tokens(for: visual.visualPhase).ambientGlow
        if !reduceTransparency, enabled || visual != .idle {
            Circle().fill(Theme.accent.opacity(glow)).frame(width: 64, height: 64).blur(radius: 14)
        }
    }

    private var accessibilityLabel: String {
        switch visual {
        case .idle: idleLabel
        case .countdown(let n): "Cancel countdown, \(n)"
        case .starting: "Cancel starting the recording"
        case .recording: stopLabel
        case .stopping: "Stopping, unavailable"
        }
    }

    // MARK: Glyph

    private var isCountdown: Bool { if case .countdown = visual { true } else { false } }

    private var shapeSide: CGFloat {
        switch visual {
        case .idle, .starting: 30
        case .countdown: 12
        case .recording, .stopping: 20
        }
    }

    private var shapeRadius: CGFloat {
        switch visual {
        case .idle, .starting, .countdown: 15
        case .recording, .stopping: 6
        }
    }

    private var shapeColor: Color {
        switch visual {
        case .idle: enabled ? Theme.cloudPrimary : Color.white.opacity(0.3)
        case .starting, .countdown: Theme.cloudPrimary.opacity(0.5)
        case .recording: TopBarStyle.rec
        case .stopping: TopBarStyle.rec.opacity(0.5)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        ZStack {
            if reduceMotion {
                // Cross-fades only: each glyph keeps its own geometry and fades in or out.
                Circle().fill(Theme.cloudPrimary).frame(width: 30, height: 30)
                    .opacity(visual == .idle && idleSymbol == nil ? (enabled ? 1 : 0.3) : 0)
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(TopBarStyle.rec).frame(width: 20, height: 20)
                    .opacity(visual == .recording ? 1 : (visual == .stopping ? 0.5 : 0))
            } else {
                RoundedRectangle(cornerRadius: shapeRadius, style: .continuous)
                    .fill(shapeColor).frame(width: shapeSide, height: shapeSide)
                    .opacity(isCountdown || showsIdleSymbol ? 0 : 1)
            }
            idleSymbolGlyph
            if isCountdown {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cloudPrimary)
            }
            if visual == .starting || visual == .stopping { ProgressView().controlSize(.small) }
        }
    }

    private var showsIdleSymbol: Bool { idleSymbol != nil && (visual == .idle || visual == .starting) }

    @ViewBuilder
    private var idleSymbolGlyph: some View {
        if let idleSymbol, showsIdleSymbol {
            Image(systemName: idleSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(enabled ? Theme.cloudPrimary : Color.white.opacity(0.3))
                .opacity(visual == .starting ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private var countdownRing: some View {
        if case .countdown(let remaining) = visual {
            if reduceMotion {
                ring(progress: Double(RecordlyCountdown.seconds - remaining + 1) / Double(RecordlyCountdown.seconds))
            } else {
                // Exists only during the countdown, so nothing redraws while idle.
                TimelineView(.animation) { context in
                    let began = countdownBeganAt ?? context.date
                    ring(progress: min(1, max(0, context.date.timeIntervalSince(began) / Double(RecordlyCountdown.seconds))))
                }
            }
        }
    }

    private func ring(progress: Double) -> some View {
        Circle().trim(from: 0, to: progress)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(1)
    }
}

struct RecordlyControlStyle: ButtonStyle {
    let hovering: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1)))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: hovering)
    }
}

private struct RecordlyEditor: View {
    let recordly: RecordlyController
    @State private var showsEditing = false

    var body: some View {
        RecordlyScroll {
            VStack(alignment: .leading, spacing: 8) {
                RecordlyClipCard(recordly: recordly, showsEditing: $showsEditing)
                if let notice = recordly.recoveryNotice {
                    Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = recordly.checkpointWarning {
                    Text(warning).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RecordlyExportPanel(recordly: recordly, showsOptions: showsEditing)
                if recordly.isConfirmingNew {
                    Text("This recording is saved and will reopen next time unless you discard it. Discarding keeps the video file unless you also delete it.")
                        .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        NotchActionButton(title: "Keep saved", tint: Theme.cloudSecondary) { recordly.reset() }
                            .accessibilityLabel("Start a new recording and keep this one saved")
                        NotchActionButton(title: "Discard recording", tint: TopBarStyle.rec) {
                            recordly.discardRecording(deleteMedia: false)
                        }
                        NotchActionButton(title: "Discard and delete file", tint: TopBarStyle.rec) {
                            recordly.discardRecording(deleteMedia: true)
                        }
                        NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary) { recordly.cancelNew() }
                        Spacer()
                    }
                } else {
                    HStack {
                        if recordly.checkpointWarning != nil {
                            NotchActionButton(title: "Retry save", tint: TopBarStyle.rec) { recordly.retryCheckpoint() }
                        }
                        NotchActionButton(title: "New", tint: Theme.cloudSecondary) { recordly.requestNew() }
                            .disabled(recordly.isExporting)
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct RecordlyExportPanel: View {
    let recordly: RecordlyController
    let showsOptions: Bool

    private static let qualityOrder: [RecordlyExportQuality] = [.light, .balanced, .high]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsOptions { options }
            controls
            result
        }
    }

    @ViewBuilder
    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Format").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                ForEach(RecordlyExportFormat.allCases, id: \.self) { format in
                    RecordlyChip(
                        title: format.rawValue.uppercased(),
                        selected: recordly.exportSettings.formats.contains(format),
                        enabled: !recordly.isExporting
                    ) { toggle(format) }
                    .accessibilityLabel("Export as \(format.rawValue.uppercased())")
                }
            }
            HStack(spacing: 6) {
                Text("Size").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                ForEach(RecordlyVideoPreset.allCases, id: \.self) { preset in
                    RecordlyChip(
                        title: preset.label,
                        selected: recordly.exportSettings.preset == preset,
                        enabled: !recordly.isExporting
                    ) { recordly.exportSettings.preset = preset }
                    .accessibilityLabel("Export size \(preset.label)")
                }
            }
            HStack(spacing: 6) {
                Text("Quality").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                ForEach(Self.qualityOrder, id: \.self) { quality in
                    RecordlyChip(
                        title: quality.rawValue.capitalized,
                        selected: recordly.exportSettings.quality == quality,
                        enabled: !recordly.isExporting
                    ) { recordly.exportSettings.quality = quality }
                    .accessibilityLabel("Export quality \(quality.rawValue)")
                }
            }
            HStack(spacing: 6) {
                Text("Cursor").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                RecordlyChip(title: "Follow while zoomed", selected: recordly.exportSettings.followCursor,
                             enabled: !recordly.isExporting) {
                    recordly.exportSettings.followCursor.toggle()
                }
                .accessibilityLabel("Follow cursor while zoomed")
                .help("Smoothly follows the cursor during zooms on a verified display recording.")
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var controls: some View {
        if case .exporting(let value) = recordly.exportState {
            HStack(spacing: 8) {
                ProgressView(value: value)
                    .accessibilityLabel("Export progress")
                    .accessibilityValue("\(Int((value * 100).rounded())) percent")
                Text("\(Int((value * 100).rounded()))%")
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary) { recordly.cancelExport() }
                    .accessibilityLabel("Cancel export")
            }
        } else {
            HStack {
                NotchActionButton(title: "Export", tint: TopBarStyle.rec) { recordly.export() }
                    .disabled(recordly.exportSettings.formats.isEmpty)
                    .accessibilityLabel("Export recording")
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch recordly.exportState {
        case .idle, .exporting:
            EmptyView()
        case .exported(let urls):
            Text(urls.count == 1 ? "Exported 1 file to Movies/Zeus Recordly." : "Exported \(urls.count) files to Movies/Zeus Recordly.")
                .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudPrimary)
            ForEach(urls, id: \.self) { url in
                HStack(spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                    Spacer()
                    Button("Show in Finder") { recordly.revealInFinder(url) }
                        .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
                        .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
                }
            }
        case .failed(let message):
            Text(message).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(Array(recordly.exportNotes.enumerated()), id: \.offset) { _, note in
            Text(note).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ format: RecordlyExportFormat) {
        var formats = recordly.exportSettings.formats
        if let index = formats.firstIndex(of: format) {
            formats.remove(at: index)
        } else {
            formats.append(format)
        }
        recordly.exportSettings.formats = formats
    }
}

private struct RecordlyChip: View {
    let title: String
    let selected: Bool
    var enabled = true
    var disabledHelp = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(TopBarStyle.label(10, .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(selected ? TopBarStyle.rec.opacity(0.25) : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(enabled ? "" : disabledHelp)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum RecordlyElapsed {
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// The same time as VoiceOver should say it: "1 minute 5 seconds".
    static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let m = total / 60
        let s = total % 60
        let seconds = "\(s) second\(s == 1 ? "" : "s")"
        return m == 0 ? seconds : "\(m) minute\(m == 1 ? "" : "s") \(seconds)"
    }
}
