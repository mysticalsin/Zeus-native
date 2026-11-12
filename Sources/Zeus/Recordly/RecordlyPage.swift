import AppKit
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

/// Two screens in the same card, both sized to the top bar page with no scroll view (docs/RECORD-LAYOUT.md):
/// the source grid, and a setup screen for one source that a double click opens. Both keep the options and the
/// capture control in the same side column, so nothing jumps when the capture state changes.
private struct RecordlyCapture: View {
    let recordly: RecordlyController
    let topBar: TopBarModel
    @State private var navigation = RecordlyRecordNavigation()
    /// The staggered entrance plays once, when the page opens, not again after Back.
    @State private var entranceDone = TopBarStyle.isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RecordlyFitOrScroll(minimumHeight: RecordlyRecordLayout.minimumHeight, resetToken: navigation.openCount) {
            ZStack(alignment: .topLeading) {
                if let intent = navigation.detailSource {
                    RecordlyDetail(recordly: recordly, topBar: topBar, intent: intent) { navigation.back() }
                        // A new identity per open: the setup screen always starts at its top.
                        .id(navigation.openCount)
                        .transition(RecordlyPush.detail(reduceMotion: reduceMotion))
                } else {
                    RecordlyGrid(recordly: recordly, topBar: topBar, entrance: !entranceDone) { intent, count in
                        click(intent, count: count)
                    }
                    .transition(RecordlyPush.grid(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(RecordlyPush.motion(reduceMotion: reduceMotion), value: navigation)
        .onChange(of: detailSourceAvailable) { reconcile() }
        .onChange(of: recordly.canChooseSource) { reconcile() }
    }

    private var detailSourceAvailable: Bool {
        navigation.detailSource.map { recordly.isAvailable($0) } ?? true
    }

    private func reconcile() {
        navigation.reconcile(sourceAvailable: detailSourceAvailable, capturing: !recordly.canChooseSource, editor: false)
    }

    private func click(_ intent: RecordlySourceSelection.SelectionIntent, count: Int) {
        let effect = navigation.click(intent, count: count, canChoose: recordly.canChooseSource,
                                      isSelected: recordly.isSelected(intent))
        switch effect {
        case .select:
            recordly.selectSource(intent)
        case .selectAndOpen:
            entranceDone = true
            recordly.selectSource(intent)
        case .open:
            entranceDone = true
        case .none:
            break
        }
    }
}

/// Grid and setup screen slide a short way past each other: the setup screen comes in from the trailing side,
/// the grid leaves toward the leading side, and Back reverses it. Reduce Motion: a plain cross-fade.
private enum RecordlyPush {
    static let distance: CGFloat = 28

    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.3, dampingFraction: 0.9)
    }

    static func detail(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: distance))
    }

    static func grid(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -distance))
    }
}

/// Lays the content out at the room it gets. Only when that room is under `minimumHeight` (the top bar page never
/// is) does the content keep its minimum height inside a vertical scroll view, which a new `resetToken` returns to
/// the top. ImageRenderer cannot draw scroll views, so snapshots always lay out flat.
private struct RecordlyFitOrScroll<Content: View>: View {
    let minimumHeight: CGFloat
    let resetToken: Int
    @ViewBuilder var content: Content

    private static var topID: String { "recordly.top" }

    var body: some View {
        GeometryReader { proxy in
            if TopBarStyle.isSnapshot || proxy.size.height >= minimumHeight {
                content.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            } else {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        content
                            .frame(width: proxy.size.width, height: minimumHeight, alignment: .topLeading)
                            .id(Self.topID)
                    }
                    .onAppear { reader.scrollTo(Self.topID, anchor: .top) }
                    .onChange(of: resetToken) { reader.scrollTo(Self.topID, anchor: .top) }
                }
            }
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

/// The click count of the mouse event that triggered a button: 2 on the second click of a double click.
/// Keyboard and VoiceOver activation count as one click (they have their own "Open setup" action).
@MainActor
private enum RecordlyClick {
    static func count() -> Int {
        guard let event = NSApp.currentEvent else { return 1 }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return max(1, event.clickCount)
        default:
            return 1
        }
    }
}

private extension RecordlyController {
    /// The windows of the current or last known catalog.
    var catalogWindows: [RecordlySourceSelection.CatalogSnapshot.Window] {
        switch pickerState {
        case .loaded(let snapshot, _): snapshot.windows
        case .stale(let snapshot, _, _): snapshot?.windows ?? []
        case .notLoaded, .loading, .denied, .failed: []
        }
    }

    /// Whether a source can still be shown on its setup screen. A catalog that is reloading counts as available,
    /// so a refresh never throws the person back to the grid.
    func isAvailable(_ intent: RecordlySourceSelection.SelectionIntent) -> Bool {
        switch intent {
        case .display(let id):
            return displays.contains { $0.id == id }
        case .window(let number, let token):
            if case .loading = pickerState { return true }
            return catalogWindows.contains { $0.number == number && $0.identityToken == token && $0.isPresent }
        case .region:
            return false
        }
    }
}

// MARK: Grid screen

private struct RecordlyGrid: View {
    let recordly: RecordlyController
    let topBar: TopBarModel
    let entrance: Bool
    let onClick: (RecordlySourceSelection.SelectionIntent, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RecordlyRecordLayout.sectionGap) {
            HStack(spacing: 10) {
                RecordlySourceSwitcher(recordly: recordly)
                Spacer(minLength: 8)
                if !recordly.screenRecordingGranted {
                    RecordlyPermissionPill(recordly: recordly, compact: false).transition(.opacity)
                }
            }
            .frame(height: RecordlyRecordLayout.headerHeight)
            .recordlyEntrance(.picker, enabled: entrance)
            HStack(alignment: .top, spacing: 12) {
                RecordlyStageFrame(recordly: recordly) {
                    RecordlySourceStage(recordly: recordly, onClick: onClick)
                }
                .recordlyEntrance(.preview, enabled: entrance)
                RecordlySideColumn(recordly: recordly, topBar: topBar, showsPermission: false, entrance: entrance)
                    .frame(width: RecordlyRecordLayout.sideColumnWidth)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record.grid")
    }
}

/// What the stage holds on the grid screen: the displays to scale, the window tiles, or the Area note.
private struct RecordlySourceStage: View {
    let recordly: RecordlyController
    let onClick: (RecordlySourceSelection.SelectionIntent, Int) -> Void

    var body: some View {
        switch recordly.sourceKind {
        case .display:
            RecordlyDisplayDiagram(recordly: recordly, onClick: onClick)
        case .window:
            RecordlyWindowGrid(recordly: recordly, onClick: onClick)
                .padding(RecordlyRecordLayout.stagePadding)
        case .region:
            Text("Area recording isn't available yet.")
                .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Side column (options, notices, capture control)

private struct RecordlySideColumn: View {
    let recordly: RecordlyController
    let topBar: TopBarModel
    let showsPermission: Bool
    let entrance: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: RecordlyRecordLayout.sectionGap) {
            Group {
                if recordly.showsRunning {
                    RecordlyLiveCapsule(recordly: recordly)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: RecordlyRecordLayout.sectionGap) {
                        RecordlyOptionChips(recordly: recordly)
                            .frame(height: RecordlyRecordLayout.optionsHeight, alignment: .top)
                            .recordlyEntrance(.chips, enabled: entrance)
                        RecordlyNotices(recordly: recordly, showsPermission: showsPermission)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            RecordlyControlRow(recordly: recordly, topBar: topBar, entrance: entrance)
        }
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .easeInOut(duration: 0.25),
                   value: recordly.showsRunning)
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

// MARK: Window grid (Screen Recording permission is needed to list windows)

/// Window tiles in pages that fit the stage: never a scroll view. Opens on the page that holds the selection.
private struct RecordlyWindowGrid: View {
    let recordly: RecordlyController
    let onClick: (RecordlySourceSelection.SelectionIntent, Int) -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch recordly.pickerState {
        case .notLoaded:
            centered { quietButton("Load windows") { Task { await recordly.loadSourceCatalog() } } }
        case .loading:
            centered {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading windows").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    quietButton("Cancel") { recordly.cancelLoading() }
                        .accessibilityLabel("Cancel loading sources")
                }
            }
        case .loaded(let snapshot, _):
            grid(snapshot.windows, notice: nil)
        case .stale(let snapshot, _, let reason):
            grid(snapshot?.windows ?? [], notice: reason)
        case .denied(let reason):
            if recordly.screenRecordingGranted {
                message(reason, button: "Check again")
            } else {
                centered {
                    Text("Windows show here once Screen Recording is on.")
                        .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                }
            }
        case .failed(let reason):
            message(reason, button: "Refresh")
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String, button: String) -> some View {
        centered {
            VStack(spacing: 6) {
                Text(text).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .multilineTextAlignment(.center).lineLimit(3)
                quietButton(button) { Task { await recordly.loadSourceCatalog() } }
            }
            .padding(.horizontal, 16)
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudPrimary)
    }

    private func grid(_ windows: [RecordlySourceSelection.CatalogSnapshot.Window], notice: String?) -> some View {
        GeometryReader { proxy in
            let layout = RecordlyRecordLayout.self
            let paging = RecordlySourceGridPaging(
                width: Double(proxy.size.width),
                height: Double(proxy.size.height - layout.pagerHeight - layout.gridSpacing),
                minTileWidth: Double(layout.windowTileMinWidth), tileHeight: Double(layout.windowTileHeight),
                spacing: Double(layout.gridSpacing))
            let current = paging.clamp(page, items: windows.count)
            let range = paging.range(page: current, items: windows.count)
            let rows = (range.count + paging.columns - 1) / paging.columns
            VStack(alignment: .leading, spacing: layout.gridSpacing) {
                VStack(spacing: layout.gridSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: layout.gridSpacing) {
                            ForEach(0..<paging.columns, id: \.self) { column in
                                let index = range.lowerBound + row * paging.columns + column
                                if index < range.upperBound {
                                    tile(windows[index])
                                } else {
                                    Color.clear.frame(maxWidth: .infinity).frame(height: layout.windowTileHeight)
                                }
                            }
                        }
                    }
                }
                .id(current)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer(empty: windows.isEmpty, notice: notice, pages: paging.pageCount(items: windows.count), current: current)
                    .frame(height: layout.pagerHeight)
            }
            .onAppear {
                // Open on the page that holds the selected window.
                if let index = windows.firstIndex(where: {
                    recordly.isSelected(.window(number: $0.number, identityToken: $0.identityToken))
                }) {
                    page = paging.page(of: index)
                }
            }
        }
    }

    private func footer(empty: Bool, notice: String?, pages: Int, current: Int) -> some View {
        HStack(spacing: 8) {
            if let text = notice ?? (empty ? "No eligible owned windows available." : nil) {
                Text(text).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary).lineLimit(1).help(text)
            }
            Spacer(minLength: 4)
            if pages > 1 {
                pagerButton("chevron.left", label: "Previous page", enabled: current > 0) { turn(to: current - 1) }
                Text("\(current + 1) / \(pages)")
                    .font(TopBarStyle.label(9, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                    .accessibilityLabel("Page \(current + 1) of \(pages)")
                pagerButton("chevron.right", label: "Next page", enabled: current < pages - 1) { turn(to: current + 1) }
            }
            quietButton("Refresh") { Task { await recordly.loadSourceCatalog() } }
                .disabled(!recordly.canChooseSource)
                .accessibilityLabel("Refresh windows")
        }
    }

    private func turn(to target: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .easeOut(duration: 0.2)) {
            page = target
        }
    }

    private func pagerButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.cloudPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func tile(_ window: RecordlySourceSelection.CatalogSnapshot.Window) -> some View {
        let intent = RecordlySourceSelection.SelectionIntent.window(number: window.number, identityToken: window.identityToken)
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = window.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
        let ownerLabel = owner.flatMap { $0.isEmpty ? nil : $0 } ?? "Owned app"
        let selected = recordly.isSelected(intent)
        return Button { onClick(intent, RecordlyClick.count()) } label: {
            RecordlyWindowTile(title: displayTitle, detail: "\(ownerLabel) \u{00B7} Window \(window.number)",
                               selected: selected, dimmed: !recordly.canChooseSource && !selected)
        }
        .buttonStyle(PressableStyle())
        .disabled(window.number <= 0 || !window.isPresent)
        .frame(maxWidth: .infinity)
        .frame(height: RecordlyRecordLayout.windowTileHeight)
        .help("Click to choose, double-click to set up this window")
        .accessibilityLabel("\(displayTitle), \(ownerLabel)")
        .accessibilityHint("Double-click to open its recording setup")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open setup") { onClick(intent, 2) }
        .accessibilityIdentifier("record.source.window.\(window.number)")
    }
}

private struct RecordlyWindowTile: View {
    let title: String
    let detail: String
    let selected: Bool
    let dimmed: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 7) {
            Image(systemName: selected ? "checkmark.circle.fill" : "macwindow")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : Theme.cloudSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Text(detail).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(selected ? Theme.accent : Color.white.opacity(hovering ? 0.16 : 0.06), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(selected && !reduceTransparency ? 0.35 : 0), radius: 6)
        .opacity(dimmed ? 0.55 : 1)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.25, dampingFraction: 0.85),
                   value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if selected { return Theme.accent.opacity(reduceTransparency ? 0.4 : 0.18) }
        if hovering { return reduceTransparency ? Color(hex: 0x2E3440) : Color.white.opacity(0.11) }
        return RecordlySurface.soft(reduceTransparency)
    }
}

// MARK: Detail screen (double click on a source)

/// The setup screen for one source: Back, a large preview, then the same options and capture control.
private struct RecordlyDetail: View {
    let recordly: RecordlyController
    let topBar: TopBarModel
    let intent: RecordlySourceSelection.SelectionIntent
    let onBack: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: RecordlyRecordLayout.sectionGap) {
            header.frame(height: RecordlyRecordLayout.headerHeight)
            HStack(alignment: .top, spacing: 12) {
                RecordlyStageFrame(recordly: recordly) { preview }
                    .frame(width: RecordlyRecordLayout.detailPreviewWidth)
                RecordlySideColumn(recordly: recordly, topBar: topBar, showsPermission: true, entrance: false)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record.detail")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Back").font(TopBarStyle.label(11, .semibold))
                }
                .foregroundStyle(Theme.cloudPrimary)
                .padding(.horizontal, 10).frame(height: 24)
                .background(Capsule().fill(RecordlySurface.soft(reduceTransparency)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to sources")
            .accessibilityLabel("Back to sources")
            .accessibilityIdentifier("record.back")
            Text(title).font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            Spacer(minLength: 8)
            if let subtitle {
                Text(subtitle).font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var title: String {
        switch intent {
        case .display: "Record this display"
        case .window: "Record this window"
        case .region: "Record an area"
        }
    }

    private var display: (RecordlySourceSelection.CatalogSnapshot.Display, Int)? {
        guard case .display(let id) = intent,
              let index = recordly.displays.firstIndex(where: { $0.id == id }) else { return nil }
        return (recordly.displays[index], index)
    }

    private var window: RecordlySourceSelection.CatalogSnapshot.Window? {
        guard case .window(let number, let token) = intent else { return nil }
        return recordly.catalogWindows.first { $0.number == number && $0.identityToken == token }
    }

    private var windowTitle: String {
        let title = window?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled window" : title
    }

    private var windowOwner: String {
        let owner = window?.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return owner.isEmpty ? "Owned app" : owner
    }

    private var subtitle: String? {
        if let pair = display {
            let main = pair.0.isMain ? "Main, " : ""
            return "\(RecordlyDisplayChoice.title(pair.0, position: pair.1)), \(main)\(RecordlyDisplayChoice.size(pair.0))"
        }
        if case .window(let number, _) = intent { return "\(windowOwner) \u{00B7} Window \(number)" }
        return nil
    }

    @ViewBuilder
    private var preview: some View {
        switch intent {
        case .display:
            if recordly.isSelected(intent), let thumbnail = recordly.thumbnail {
                Color.clear
                    .overlay { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() }
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                placeholder(symbol: "display", title: display.map { RecordlyDisplayChoice.title($0.0, position: $0.1) } ?? "Display",
                            detail: display.map { RecordlyDisplayChoice.size($0.0) })
            }
        case .window:
            placeholder(symbol: "macwindow", title: windowTitle, detail: windowOwner)
        case .region:
            placeholder(symbol: "rectangle.dashed", title: "Area recording isn't available yet.", detail: nil)
        }
    }

    private func placeholder(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.cloudSecondary)
            Text(title).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .multilineTextAlignment(.center).lineLimit(2)
            if let detail {
                Text(detail).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Notices

/// Display, action, selection and failure notices in one compact slot: two lines, the full text in the tooltip.
private struct RecordlyNotices: View {
    let recordly: RecordlyController
    let showsPermission: Bool

    var body: some View {
        let needsPermission = showsPermission && !recordly.screenRecordingGranted
        VStack(alignment: .leading, spacing: 4) {
            if needsPermission {
                RecordlyPermissionPill(recordly: recordly, compact: true)
            }
            if let summary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(needsPermission ? 1 : 2)
                        .help(summary)
                    if recordly.failureReason != nil {
                        Button("Try again") { recordly.retry() }.buttonStyle(.plain)
                            .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                            .fixedSize()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: summary)
    }

    private var summary: String? {
        let lines = [recordly.displayNotice, recordly.actionNotice, recordly.selectionNotice, recordly.failureReason].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

/// Inline permission prompt: never prompts by itself; the button opens System Settings.
private struct RecordlyPermissionPill: View {
    let recordly: RecordlyController
    let compact: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.bolt)
            if !compact {
                Text("Screen Recording is off for Zeus.")
                    .font(TopBarStyle.label(10, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            }
            Button { recordly.openScreenRecordingSettings() } label: {
                Text("Open Screen Recording settings")
                    .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.storm).lineLimit(1)
                    .padding(.horizontal, 9).frame(height: 20)
                    .background(Capsule().fill(Theme.cloudPrimary))
            }
            .buttonStyle(PressableStyle())
            .help("Screen Recording is off for Zeus.")
        }
        .padding(.leading, 9).padding(.trailing, 2)
        .frame(height: 24)
        .background(Capsule().fill(RecordlySurface.soft(reduceTransparency)))
        .overlay(Capsule().strokeBorder(Theme.bolt.opacity(0.4), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen Recording is off for Zeus.")
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

// MARK: Stage

/// The glass stage around the source grid or a source preview: dims during the countdown, shows the 3 2 1
/// numeral, and wears the live frame while capturing.
private struct RecordlyStageFrame<Content: View>: View {
    let recordly: RecordlyController
    @ViewBuilder var content: Content
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}

/// The connected displays as rectangles to scale, placed like System Settings > Displays.
/// Click chooses a display (the main one is chosen already); double click opens its setup screen.
private struct RecordlyDisplayDiagram: View {
    let recordly: RecordlyController
    let onClick: (RecordlySourceSelection.SelectionIntent, Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 16
            let bounds = CGSize(width: max(1, proxy.size.width - inset * 2), height: max(1, proxy.size.height - inset * 2))
            let displays = recordly.displays
            let tiles = RecordlyDisplayChoice.arrangement(displays, in: bounds, gap: displays.count > 1 ? 6 : 0)
            if displays.isEmpty {
                Text("No displays found.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    if let tile = tiles.first(where: { $0.id == display.id }) {
                        let intent = RecordlySourceSelection.SelectionIntent.display(id: display.id)
                        RecordlyDisplayTile(
                            display: display, position: index, size: tile.rect.size,
                            selected: recordly.isSelected(intent),
                            live: recordly.showsRunning,
                            thumbnail: recordly.thumbnail
                        ) { count in onClick(intent, count) }
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
    let thumbnail: CGImage?
    let action: (Int) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { action(RecordlyClick.count()) } label: { tile }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Click to choose, double-click to set up this display")
            .accessibilityLabel(RecordlyDisplayChoice.spokenLabel(display, position: position))
            .accessibilityHint("Double-click to open its recording setup")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Open setup") { action(2) }
            .accessibilityIdentifier("record.source.display.\(position + 1)")
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let outline = selected ? (live ? Color.white.opacity(0.35) : Theme.accent) : Color.white.opacity(hovering ? 0.32 : 0.2)
        return ZStack {
            shape.fill(selected ? Theme.accent.opacity(0.30) : Color.white.opacity(hovering ? 0.11 : 0.07))
            if selected, let thumbnail {
                Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipShape(shape)
                    .transition(.opacity)
            }
            label
            shape.strokeBorder(outline, lineWidth: selected ? 2 : 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: Theme.accent.opacity(selected && !live ? 0.55 : 0), radius: 10)
        .contentShape(shape)
        .animation(reduceMotion ? .easeInOut(duration: Motion.crossfadeDuration) : .spring(response: 0.3, dampingFraction: 0.85), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
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
    var entrance = true

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
        .frame(height: RecordlyRecordLayout.controlHeight)
        .recordlyEntrance(.button, enabled: entrance)
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
        .accessibilityIdentifier("record.capture")
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
                // Exists only during the countdown and runs at the display's own rate until the ring is full,
                // so nothing redraws while idle, off screen or after the countdown.
                DisplaySynchronizedView(until: countdownBeganAt?.addingTimeInterval(Double(RecordlyCountdown.seconds))) { context in
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

/// The saved clip in two columns so it fits the page: the clip card and its notices on the left, export options,
/// export and the New or discard flow on the right. The right column only scrolls if a long export result outgrows it.
private struct RecordlyEditor: View {
    let recordly: RecordlyController
    @State private var showsEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                RecordlyClipCard(recordly: recordly, showsEditing: $showsEditing)
                if let notice = recordly.recoveryNotice {
                    Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(2).help(notice)
                }
                if let warning = recordly.checkpointWarning {
                    Text(warning).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(2).help(warning)
                }
            }
            .frame(width: 400, alignment: .topLeading)
            RecordlyScroll {
                VStack(alignment: .leading, spacing: 8) {
                    RecordlyExportPanel(recordly: recordly, showsOptions: showsEditing)
                    if recordly.isConfirmingNew {
                        Text("This recording is saved and will reopen next time unless you discard it. Discarding keeps the video file unless you also delete it.")
                            .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            NotchActionButton(title: "Keep saved", tint: Theme.cloudSecondary) { recordly.reset() }
                                .accessibilityLabel("Start a new recording and keep this one saved")
                            NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary) { recordly.cancelNew() }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            NotchActionButton(title: "Discard recording", tint: TopBarStyle.rec) {
                                recordly.discardRecording(deleteMedia: false)
                            }
                            NotchActionButton(title: "Discard and delete file", tint: TopBarStyle.rec) {
                                recordly.discardRecording(deleteMedia: true)
                            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Text(urls.count == 1 ? "Exported 1 file to Movies/Zeus Recordings." : "Exported \(urls.count) files to Movies/Zeus Recordings.")
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
