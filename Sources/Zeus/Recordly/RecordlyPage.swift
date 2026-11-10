import SwiftUI
import ZeusCore

struct RecordlyPage: View {
    let topBar: TopBarModel
    let recordly: RecordlyController

    var body: some View {
        HStack(spacing: 8) {
            Tile {
                if recordly.showsRunning {
                    RecordlyRunning(recordly: recordly)
                } else if case .editor = recordly.phase {
                    RecordlyEditor(recordly: recordly)
                } else {
                    RecordlyIdle(recordly: recordly, topBar: topBar)
                }
            }
        }
    }
}

private struct RecordlyIdle: View {
    let recordly: RecordlyController
    let topBar: TopBarModel

    var body: some View {
        // The source list and status scroll inside a bounded height; the action footer is pinned below it, inside
        // the page frame, so Record is always within the notch's hit shape (see RecordlyPageLayout).
        VStack(alignment: .leading, spacing: RecordlyPageLayout.footerGap) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle").font(.system(size: 12, weight: .bold)).foregroundStyle(TopBarStyle.rec)
                        Text("Record").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                        Spacer()
                        ForEach(RecordlyCaptureSource.Kind.allCases, id: \.self) { kind in
                            RecordlyChip(
                                title: kind.rawValue.capitalized,
                                selected: recordly.sourceKind == kind,
                                enabled: kind != .region && recordly.canChooseSource,
                                disabledHelp: kind == .region
                                    ? "Region recording isn't available yet."
                                    : "Sources can't change while a recording is starting, running or stopping."
                            ) {
                                recordly.selectSourceKind(kind)
                                if kind != .region {
                                    Task { await recordly.loadSourceCatalog() }
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        ToggleChip(
                            title: "Mic",
                            on: false,
                            enabled: false,
                            help: "Microphone in recordings is coming soon",
                            accessibilityText: "Microphone, unavailable. Microphone in recordings is coming soon"
                        ) { }
                        ToggleChip(title: "Mac audio", on: recordly.audio.systemAudio) { recordly.audio.systemAudio.toggle() }
                        ToggleChip(
                            title: "Camera",
                            on: false,
                            enabled: false,
                            help: "Camera in recordings is coming soon",
                            accessibilityText: "Camera, unavailable. Camera in recordings is coming soon"
                        ) { }
                    }
                    Text("Region recording isn't available yet.")
                        .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice = recordly.actionNotice {
                        Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reason = recordly.failureReason {
                        Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
                        Button("Try again") { recordly.retry() }.buttonStyle(.plain)
                    }
                    pickerContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: RecordlyPageLayout.scrollMaxHeight)
            .layoutPriority(1)
            footer
                .frame(height: RecordlyPageLayout.footerHeight)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if recordly.isStarting || recordly.isStopping {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(recordly.isStopping ? "Stopping…" : "Starting… revalidating the selected source")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary) {
                    Task { await recordly.cancelStart() }
                }
                .disabled(recordly.isStopping)
                .accessibilityLabel(recordly.isStopping ? "Cancel, unavailable while stopping" : "Cancel starting the recording")
            }
        } else {
            HStack(spacing: 0) {
                NotchActionButton(title: "Record", tint: TopBarStyle.rec) {
                    Task { await recordly.start(topBar: topBar) }
                }
                .disabled(!recordly.canStart)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        switch recordly.pickerState {
        case .notLoaded:
            Text("Choose a source to load.")
                .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
            Button(recordly.sourceKind == .window ? "Load windows" : "Load displays") {
                Task { await recordly.loadSourceCatalog() }
            }
            .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading \(recordly.sourceKind.rawValue)…")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                Button("Cancel") { recordly.cancelLoading() }
                    .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
                    .accessibilityLabel("Cancel loading sources")
            }
        case .loaded(let snapshot, _):
            if let notice = recordly.selectionNotice {
                Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            catalogRows(snapshot)
            Button("Refresh") { Task { await recordly.loadSourceCatalog() } }
                .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
        case .stale(let snapshot, _, let reason):
            Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Refresh") { Task { await recordly.loadSourceCatalog() } }
                .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
            if let snapshot { catalogRows(snapshot) }
        case .denied(let reason):
            Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { recordly.openScreenRecordingSettings() }
            .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
            Button("Check again") { Task { await recordly.loadSourceCatalog() } }
                .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
        case .failed(let reason):
            Text(reason).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Refresh") { Task { await recordly.loadSourceCatalog() } }
                .buttonStyle(.plain).font(TopBarStyle.label(9, .semibold))
        }
    }

    @ViewBuilder
    private func catalogRows(_ snapshot: RecordlySourcePicker.CatalogSnapshot) -> some View {
        // No nested scroll: the page's own scroll area bounds the list.
        VStack(alignment: .leading, spacing: RecordlyPageLayout.rowSpacing) {
            VStack(alignment: .leading, spacing: RecordlyPageLayout.rowSpacing) {
                if recordly.sourceKind == .display {
                    if snapshot.displays.isEmpty {
                        Text("No displays available.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    }
                    ForEach(snapshot.displays, id: \.id) { display in
                        let intent = RecordlySourceSelection.SelectionIntent.display(id: display.id)
                        Button { recordly.selectSource(intent) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: recordly.isSelected(intent) ? "checkmark.circle.fill" : "display")
                                Text("Display \(display.id)").font(TopBarStyle.label(10))
                            }
                            .foregroundStyle(recordly.isSelected(intent) ? TopBarStyle.rec : Theme.cloudSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(display.id == 0 || !recordly.canChooseSource)
                    }
                } else if recordly.sourceKind == .window {
                    if snapshot.windows.isEmpty {
                        Text("No eligible owned windows available.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    }
                    ForEach(snapshot.windows, id: \.identityToken) { window in
                        let intent = RecordlySourceSelection.SelectionIntent.window(
                            number: window.number,
                            identityToken: window.identityToken
                        )
                        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let owner = window.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
                        let ownerLabel = owner.flatMap { $0.isEmpty ? nil : $0 } ?? "Owned app"
                        Button { recordly.selectSource(intent) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: recordly.isSelected(intent) ? "checkmark.circle.fill" : "macwindow")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(displayTitle)
                                        .font(TopBarStyle.label(10)).lineLimit(1)
                                    Text("\(ownerLabel) · Window \(window.number)")
                                        .font(TopBarStyle.label(9)).lineLimit(1)
                                }
                            }
                            .foregroundStyle(recordly.isSelected(intent) ? TopBarStyle.rec : Theme.cloudSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(window.number <= 0 || !window.isPresent || !recordly.canChooseSource)
                    }
                }
            }
        }
    }
}

private struct RecordlyRunning: View {
    let recordly: RecordlyController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(TopBarStyle.rec).frame(width: 8, height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recording")
                Text(RecordlyElapsed.format(recordly.elapsed))
                    .font(TopBarStyle.label(28, .bold).monospacedDigit())
                    .foregroundStyle(Theme.cloudPrimary)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(RecordlyElapsed.spoken(recordly.elapsed))
                Spacer()
                if recordly.isStopping {
                    ProgressView().controlSize(.small)
                    Text("Stopping…").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                }
                NotchActionButton(title: "Stop", tint: TopBarStyle.rec) {
                    Task { await recordly.stop() }
                }
                .disabled(recordly.isStopping)
                .accessibilityLabel(recordly.isStopping ? "Stop recording, unavailable while stopping" : "Stop recording")
            }
        }
    }
}

private struct RecordlyEditor: View {
    let recordly: RecordlyController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recording captured").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                if let project = recordly.project {
                    Text("\(project.zoomRegions.count) zoom regions")
                        .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                }
                if let notice = recordly.recoveryNotice {
                    Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RecordlyMediaPreview(media: recordly.mediaAuthority, unavailableReason: recordly.previewUnavailableReason)
                if let warning = recordly.checkpointWarning {
                    Text(warning).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RecordlyExportPanel(recordly: recordly)
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

    private static let qualityOrder: [RecordlyExportQuality] = [.light, .balanced, .high]

    var body: some View {
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
            controls
            result
        }
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

private struct ToggleChip: View {
    let title: String
    let on: Bool
    var enabled = true
    var help = ""
    var accessibilityText: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(TopBarStyle.label(10, .semibold))
                .foregroundStyle(on ? Theme.cloudPrimary : Theme.cloudSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(accessibilityText ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
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
