import SwiftUI
import ZeusCore

/// Dark glass page: 52 pt rows, a helper under each control, 32 pt padding, 28 pt between cards.
struct MediaSettingsPage: View {
    var settings: MediaSettings
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var write: (String, String) -> Void

    @State private var playing = true
    @State private var liked = false
    @State private var machine = MediaHideMachine()
    @State private var waitID = 0
    @State private var previewPhase = "Playing"
    @State private var shuffleOn = false
    @State private var repeatMode: RepeatMode = .off
    @State private var lyricPhase: MediaLyricPhase = .ready

    private let phases = ["Playing", "Loading", "Nothing playing", "Can't read"]

    var body: some View {
        let access = GlassSettingsAccess(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
        let preview = MediaPreviewBuilder.make(
            settings: settings,
            phase: phase,
            hide: machine,
            access: access,
            lyricsPhase: lyricPhase
        )
        VStack(alignment: .leading, spacing: 28) {
            previewCard(preview)
            ForEach(grouped, id: \.name) { group in
                card(group.name, group.rows)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { alignMachine() }
        .onChange(of: settings.hideOnPause) { _, _ in alignMachine() }
        .task(id: waitID) { await waitOutTheDelay() }
    }

    private var phase: MediaPreviewPhase {
        switch previewPhase {
        case "Loading": return .loading
        case "Nothing playing": return .empty
        case "Can't read": return .failed("The player could not be read")
        default:
            var sample = MediaPreviewSample.demo
            sample.isPlaying = playing
            return .ready(sample)
        }
    }

    private var grouped: [(name: String, rows: [MediaControl])] {
        var groups: [(name: String, rows: [MediaControl])] = []
        for control in MediaSectionCatalog.controls(for: settings) {
            if groups.last?.name == control.card {
                groups[groups.count - 1].rows.append(control)
            } else {
                groups.append((control.card, [control]))
            }
        }
        return groups
    }

    private func previewCard(_ preview: MediaPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview").font(GS.cardTitle).foregroundStyle(GS.text).accessibilityAddTraits(.isHeader)
            Text("A player card that follows the look, colour, and pause choices on this page.")
                .font(GS.rowText).foregroundStyle(GS.secondary)
            Picker("Preview state", selection: $previewPhase) {
                ForEach(phases, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Preview state. Playing, loading, nothing playing, or the player could not be read.")
            MediaPreviewTile(
                preview: preview,
                settings: settings,
                reduceMotion: reduceMotion,
                playing: playing,
                liked: liked,
                shuffleOn: shuffleOn,
                repeatMode: repeatMode,
                onPlay: { setPlaying(!playing) },
                onLike: { liked.toggle() },
                onLeft: { performLeftButton() },
                onShuffle: { shuffleOn.toggle() },
                onRepeat: { repeatMode = MusicModeRules.nextRepeat(after: repeatMode, player: MediaPreviewSample.demo.player) },
                onLyricState: { lyricPhase = nextLyric(lyricPhase) }
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func card(_ title: String, _ rows: [MediaControl]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(GS.cardTitle).foregroundStyle(GS.text)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row($0) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    @ViewBuilder private func row(_ control: MediaControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 16) {
                Text(control.title).font(GS.rowTitle).foregroundStyle(GS.text).accessibilityHidden(true)
                Spacer(minLength: 12)
                trailing(control)
            }
            .frame(minHeight: 52)
            Text(control.helper).font(GS.rowText).foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func trailing(_ control: MediaControl) -> some View {
        switch control.kind {
        case .toggle(let on):
            MediaGlassToggle(isOn: binding(control.id, on), reduceMotion: reduceMotion, label: control.accessibilityLabel)
        case .choice(let selected, let options):
            Picker(control.title, selection: choice(control.id, selected)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(control.accessibilityLabel)
        case .status(let value):
            Text(value).font(GS.rowText).foregroundStyle(GS.secondary)
                .focusable(true)
                .accessibilityLabel(control.accessibilityLabel)
                .accessibilityAddTraits(.isStaticText)
        case .held:
            Button(action: {}) {
                Text(MediaHeldFeature.heldNote).font(GS.rowText).foregroundStyle(GS.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.55)
            .accessibilityLabel(control.accessibilityLabel)
            .accessibilityHint("Coming later. It does nothing.")
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(GS.card)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private func binding(_ id: String, _ on: Bool) -> Binding<Bool> {
        Binding(get: { on }, set: { write(id, $0 ? "true" : "false") })
    }

    private func choice(_ id: String, _ selected: String) -> Binding<String> {
        Binding(get: { selected }, set: { write(id, storedChoice(id, $0)) })
    }

    private func storedChoice(_ id: String, _ shown: String) -> String {
        switch id {
        case MediaSettingID.playerLook:
            return MediaPlayerLook.allCases.first { $0.title == shown }?.rawValue ?? MediaPlayerLook.art.rawValue
        case MediaSettingID.leftButton:
            return MediaLeftButton.allCases.first { $0.title == shown }?.rawValue ?? MediaLeftButton.previous.rawValue
        case MediaSettingID.hideOnPause:
            return MediaHidePolicy.allCases.first { $0.title == shown }?.rawValue ?? MediaHidePolicy.never.rawValue
        default:
            return shown
        }
    }

    private func performLeftButton() {
        switch settings.leftButton {
        case .previous:
            break
        case .like:
            liked.toggle()
        case .lyrics:
            guard settings.lyrics else { return }
            lyricPhase = nextLyric(lyricPhase)
        }
    }

    private func setPlaying(_ on: Bool) {
        playing = on
        if on {
            _ = machine.send(.beganPlaying, reduceMotion: reduceMotion)
        } else {
            _ = machine.send(.paused(at: Date()), reduceMotion: reduceMotion)
            if case .counting = machine.state { waitID += 1 }
        }
    }

    private func alignMachine() {
        _ = MediaHideMachine.retarget(&machine, to: settings.hideOnPause, playing: playing, at: Date(), reduceMotion: reduceMotion)
        if case .counting = machine.state { waitID += 1 }
    }

    private func waitOutTheDelay() async {
        guard case .counting(let since) = machine.state else { return }
        let remaining = MediaHidePolicy.delay - Date().timeIntervalSince(since)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }
        _ = machine.send(.timePassed(at: Date()), reduceMotion: reduceMotion)
    }

    private func nextLyric(_ current: MediaLyricPhase) -> MediaLyricPhase {
        switch current {
        case .ready: .loading
        case .loading: .empty
        case .empty: .unavailable
        case .unavailable: .ready
        }
    }
}

private struct MediaGlassToggle: View {
    @Binding var isOn: Bool
    var reduceMotion: Bool
    var label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color(rgb: 128, 178, 249) : GS.toggleOff).frame(width: 44, height: 22)
                Circle().fill(GS.knob).frame(width: 16, height: 16).padding(3)
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

private struct MediaPreviewTile: View {
    var preview: MediaPreview
    var settings: MediaSettings
    var reduceMotion: Bool
    var playing: Bool
    var liked: Bool
    var shuffleOn: Bool
    var repeatMode: RepeatMode
    var onPlay: () -> Void
    var onLike: () -> Void
    var onLeft: () -> Void
    var onShuffle: () -> Void
    var onRepeat: () -> Void
    var onLyricState: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if preview.visible {
                player
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                Text(preview.statusTitle).font(GS.rowTitle).foregroundStyle(GS.text)
                    .accessibilityLabel(preview.accessibilityLabel)
            }
            HStack(spacing: 8) {
                previewButton(playing ? "Pause preview" : "Play preview", playing ? "pause.fill" : "play.fill", onPlay)
                if preview.canResume == false && !preview.visible {
                    EmptyView()
                }
            }
            lyricLine
        }
        .animation(reduceMotion ? nil : .easeOut(duration: preview.animationDuration), value: preview.visible)
        .accessibilityElement(children: .contain)
    }

    private var player: some View {
        HStack(alignment: .top, spacing: 14) {
            if preview.showsArt { art }
            VStack(alignment: .leading, spacing: 6) {
                Text(preview.title).font(GS.rowTitle).foregroundStyle(GS.text).lineLimit(2)
                if !preview.artist.isEmpty {
                    Text(preview.artist).font(GS.rowText).foregroundStyle(GS.secondary).lineLimit(1)
                }
                if preview.showsDetail, !preview.detailLine.isEmpty {
                    Text(preview.album).font(GS.rowText).foregroundStyle(GS.secondary).lineLimit(1)
                    Text(preview.detailLine).font(GS.rowText.monospacedDigit()).foregroundStyle(GS.secondary)
                        .accessibilityLabel("Elapsed \(preview.detailLine)")
                }
                if let badge = preview.badge {
                    Text(badge)
                        .font(GS.rowText)
                        .foregroundStyle(color(preview.badgeColor))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(color(preview.badgeColor), lineWidth: 1))
                        .accessibilityLabel("Explicit")
                }
                if let wave = preview.waveform { waveform(wave) }
                controls
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(playerBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(preview.accessibilityLabel)
    }

    private var art: some View {
        RoundedRectangle(cornerRadius: preview.glass ? 18 : 8, style: .continuous)
            .fill(color(preview.palette.accent))
            .frame(width: preview.showsDetail ? 72 : 88, height: preview.showsDetail ? 72 : 88)
            .overlay(Image(systemName: "music.note").foregroundStyle(.white).accessibilityHidden(true))
            .accessibilityLabel("Artwork")
    }

    private var playerBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(preview.solidFallback || !preview.glass ? color(preview.palette.card) : color(preview.palette.card).opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if preview.left.shown {
                previewButton(preview.left.accessibilityLabel, preview.left.symbol, preview.left.enabled ? onLeft : {})
                    .opacity(preview.left.enabled ? 1 : 0.45)
                    .foregroundStyle(settings.leftButton == .like ? color(preview.like) : GS.text)
                    .accessibilityHint(preview.left.enabled ? "" : "Turn on synced lyrics to use this button.")
            }
            previewButton(shuffleOn ? "Shuffle, on" : "Shuffle, off", "shuffle", onShuffle)
            previewButton(playing ? "Pause" : "Play", playing ? "pause.fill" : "play.fill", onPlay)
            previewButton("Repeat, \(repeatMode.rawValue)", repeatMode == .one ? "repeat.1" : "repeat", onRepeat)
                .opacity(preview.offersRepeatOne || repeatMode != .one ? 1 : 0.45)
            previewButton(liked ? "Like, on" : "Like", liked ? "heart.fill" : "heart", onLike)
                .foregroundStyle(color(preview.like))
        }
    }

    private func waveform(_ wave: MediaWaveform) -> some View {
        HStack(alignment: .center, spacing: 3) {
            if wave.isSilent {
                Text("No sound to draw yet.").font(GS.rowText).foregroundStyle(GS.secondary)
            } else {
                ForEach(Array(wave.bars.enumerated()), id: \.offset) { _, level in
                    Capsule().fill(color(preview.palette.waveform))
                        .frame(width: 4, height: max(4, 28 * level))
                }
            }
        }
        .frame(height: 32, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wave.isSilent ? "No sound to draw yet" : (wave.animates ? "Live waveform" : "Waveform, holding still"))
        .animation(wave.animates && !reduceMotion ? .linear(duration: 0.8).repeatForever(autoreverses: true) : nil, value: wave.animates)
    }

    private var lyricLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch preview.lyric {
            case .off:
                Text("Synced lyrics are off. Nothing is sent.").font(GS.rowText).foregroundStyle(GS.secondary)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading lyrics").font(GS.rowText).foregroundStyle(GS.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading lyrics")
            case .empty:
                Text("No synced lyrics for this track.").font(GS.rowText).foregroundStyle(GS.secondary)
            case .unavailable:
                Text("Lyrics are not answering. Playback continues.").font(GS.rowText).foregroundStyle(GS.secondary)
                    .accessibilityLabel("Lyrics are not answering. Playback continues.")
            case .wholeLine(let text):
                Text(text).font(GS.rowText).foregroundStyle(GS.text).accessibilityLabel("Lyric line. \(text)")
            case .word(let text, let index, _):
                wordLine(text, index: index)
            }
            if settings.lyrics {
                Button("Lyric state") { onLyricState() }
                    .buttonStyle(.plain)
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
                    .accessibilityLabel("Lyric state. Cycles loading, nothing found, and not answering.")
                    .accessibilityHint("Shows the loading, empty, and error states for lyrics.")
            }
        }
    }

    private func wordLine(_ text: String, index: Int) -> some View {
        let line = LyricLine(time: MediaPreviewSample.demo.lyricStart, text: text)
        let words = LyricWordTiming.words(in: line, lineEnd: MediaPreviewSample.demo.lyricEnd)
        return HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { offset, word in
                Text(word.text.trimmingCharacters(in: .whitespaces))
                    .font(GS.rowText)
                    .foregroundStyle(offset == index ? GS.text : GS.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyric line. \(text). Word \(index + 1) of \(max(words.count, 1)).")
    }

    private func previewButton(_ label: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GS.text)
        .accessibilityLabel(label)
    }

    private func color(_ rgb: ArtworkColor.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
