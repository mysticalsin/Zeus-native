import SwiftUI
import ZeusCore

struct PrompterActions {
    let toggle: () -> Void
    let restart: () -> Void
    let stop: () -> Void
    let importScript: () -> Void
    var loadNotes: () -> Void = {}
    let editScript: () -> Void
    let record: () -> Void
    let close: () -> Void
    let jumpCue: (Bool) -> Void
    var stopFollowing: () -> Void = {}
    var openPermissions: () -> Void = {}

    static var preview: PrompterActions { PrompterActions(toggle: {}, restart: {}, stop: {}, importScript: {}, editScript: {}, record: {}, close: {}, jumpCue: { _ in }) }
}

private struct BlockFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The prompter in the notch's dark glass: big text that rolls under a reading line, with
/// a slim control bar. Everything is reachable from the keyboard and labelled for VoiceOver.
struct PrompterWindowView: View {
    let model: PrompterWindowModel
    let actions: PrompterActions

    var body: some View {
        VStack(spacing: 0) {
            if model.presenter != nil { slideHeader }
            if let empty = model.emptyState {
                emptyView(empty)
            } else {
                scriptArea
            }
            controlBar
        }
        .background(Theme.storm.opacity(0.94), in: RoundedRectangle(cornerRadius: Theme.panelRadius + 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius + 6, style: .continuous).strokeBorder(TopBarStyle.tileStroke))
        .preferredColorScheme(.dark)
    }

    /// "SLIDE 7/24 · Next: Roadmap", with a live dot while the slideshow plays.
    private var slideHeader: some View {
        HStack(spacing: 8) {
            if model.presenterPlaying {
                Circle().fill(TopBarStyle.rec).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text((model.presenter?.position ?? "Slides").uppercased())
                .font(TopBarStyle.label(10.5, .bold).monospacedDigit())
                .foregroundStyle(Theme.bolt)
            Spacer(minLength: 8)
            if let next = model.presenter?.next {
                Text(next).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet).lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }

    /// Nothing to read: what's wrong and the one thing to do about it.
    private func emptyView(_ state: PresenterEmptyState) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(state.title)
                .font(.system(size: max(17, model.fontSize * 0.6), weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cloudPrimary)
                .multilineTextAlignment(.center)
            Text(state.detail)
                .font(TopBarStyle.label(12.5))
                .foregroundStyle(Theme.cloudSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state.isBlocking {
                HStack(spacing: 8) {
                    if state.opensPermissions {
                        NotchActionButton(title: "Open Settings › Permissions", tint: Theme.bolt, action: actions.openPermissions)
                    }
                    NotchActionButton(title: "Try Again", tint: Theme.cloudSecondary, filled: !state.opensPermissions, action: actions.loadNotes)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var scriptArea: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                scriptText(width: proxy.size.width)
                    .offset(y: -model.offset)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
                    .scaleEffect(x: model.mirrored ? -1 : 1, y: 1)
                readingLine(height: proxy.size.height)
                overlay
            }
            .onAppear { model.viewHeight = proxy.size.height }
            .onChange(of: proxy.size.height) { model.viewHeight = proxy.size.height }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onHover { model.hovered = $0 && model.mode != .words }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Script")
        .accessibilityValue(accessibilityProgress)
    }

    private func scriptText(width: CGFloat) -> some View {
        let current = model.currentBlock
        return VStack(alignment: .leading, spacing: model.fontSize * 0.6) {
            ForEach(model.script.blocks) { block in
                Group {
                    if block.isCue {
                        Text(block.text.uppercased())
                            .font(.system(size: model.fontSize * 0.42, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.bolt)
                    } else {
                        Text(block.text)
                            .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(block.id == current || current == nil ? Theme.cloudPrimary : Theme.cloudQuiet)
                            .lineSpacing(model.fontSize * 0.18)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: BlockFrameKey.self, value: [block.id: geo.frame(in: .named("prompter"))])
                })
            }
            Spacer().frame(height: 400)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "prompter")
        .onPreferenceChange(BlockFrameKey.self) { frames in
            model.blockFrames = frames
            model.contentHeight = Double(frames.values.map(\.maxY).max() ?? 0)
        }
        .animation(.easeOut(duration: 0.25), value: current)
    }

    private func readingLine(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9)).foregroundStyle(Theme.bolt.opacity(0.8))
            Rectangle().fill(Theme.bolt.opacity(0.15)).frame(height: 1)
        }
        .padding(.leading, 10)
        .offset(y: height * PrompterWindowModel.readingLine - 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var overlay: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            if let left = model.roll.countdownRemaining(at: context.date) {
                Text("\(left)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.bolt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.storm.opacity(0.7))
                    .accessibilityLabel("Starting in \(left)")
            }
        }
        .allowsHitTesting(false)
    }

    private var controlBar: some View {
        HStack(spacing: 4) {
            GlyphButton(symbol: model.isRunning ? "pause.fill" : "play.fill", size: 12, tint: Theme.bolt,
                        label: model.isRunning ? "Pause (Space or Control-Option-P)" : "Start (Space or Control-Option-P)", action: actions.toggle)
            GlyphButton(symbol: "backward.end.fill", size: 10, label: "Previous cue (Left arrow)") { actions.jumpCue(false) }
            GlyphButton(symbol: "forward.end.fill", size: 10, label: "Next cue (Right arrow)") { actions.jumpCue(true) }
            GlyphButton(symbol: "arrow.counterclockwise", size: 10, label: "Start over (R)", action: actions.restart)
            divider
            if TopBarStyle.isSnapshot {
                // ImageRenderer cannot draw AppKit-backed menus.
                modeLabel.foregroundStyle(Theme.cloudSecondary)
            } else {
                Menu {
                    Picker("Scrolling", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                        ForEach(PrompterFollowMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Toggle("Countdown", isOn: Binding(get: { model.countdown }, set: { model.countdown = $0 }))
                    Toggle("Mirror text (M)", isOn: Binding(get: { model.mirrored }, set: { model.mirrored = $0 }))
                    Toggle("Hide from screen sharing", isOn: Binding(get: { model.hiddenFromCapture }, set: { model.hiddenFromCapture = $0 }))
                    Divider()
                    if model.isFollowingSlides {
                        Button("Reload Speaker Notes", action: actions.loadNotes)
                        Button("Stop Following Slides", action: actions.stopFollowing)
                    } else {
                        Button("Follow Slides in Keynote or PowerPoint", action: actions.loadNotes)
                    }
                    Toggle("Follow my presentation", isOn: Binding(get: { model.followPresentation }, set: { model.followPresentation = $0 }))
                    Toggle("Advance slides when I finish their notes", isOn: Binding(get: { model.advanceWhileFollowing }, set: { model.advanceWhileFollowing = $0 }))
                    if model.displays.count > 1 {
                        Picker("Show on", selection: Binding(get: { model.displayID }, set: { model.displayID = $0 })) {
                            Text("Next to the camera").tag(PrompterPlacement.camera)
                            ForEach(model.displays, id: \.id) { display in Text(display.name).tag(display.id) }
                        }
                    }
                    Divider()
                    Button("Import Script…", action: actions.importScript)
                    Button("Edit Script…", action: actions.editScript)
                } label: {
                    Label(model.mode.title, systemImage: model.mode == .words ? "text.word.spacing" : (model.mode == .voice ? "waveform" : "speedometer"))
                        .font(TopBarStyle.label(11, .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Prompter options")
            }
            if model.mode != .words {
                GlyphButton(symbol: "tortoise.fill", size: 10, label: "Slower (Down arrow)") { model.roll.adjustSpeed(by: -4) }
                Text("\(Int(model.roll.speed))").font(TopBarStyle.label(10.5).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                    .accessibilityLabel("Speed \(Int(model.roll.speed))")
                GlyphButton(symbol: "hare.fill", size: 10, label: "Faster (Up arrow)") { model.roll.adjustSpeed(by: 4) }
            }
            divider
            GlyphButton(symbol: "textformat.size.smaller", size: 10, label: "Smaller text (-)") {
                model.fontSize = max(model.fontSize - 2, PrompterWindowModel.fontRange.lowerBound)
            }
            GlyphButton(symbol: "textformat.size.larger", size: 10, label: "Larger text (+)") {
                model.fontSize = min(model.fontSize + 2, PrompterWindowModel.fontRange.upperBound)
            }
            GlyphButton(symbol: "circle.lefthalf.filled", size: 10, label: "Dim (\(Int((model.opacity * 100).rounded())) percent)") {
                model.dimStep()
            }
            Spacer(minLength: 4)
            if let notice = model.notice {
                Text(notice).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1).truncationMode(.tail)
            }
            if model.isRunning, model.mode != .steady {
                LevelBars(color: model.level > 0.12 ? Theme.leaf : Theme.cloudQuiet, active: model.level > 0.12, height: 10)
                    .accessibilityHidden(true)
            }
            recordButton
            GlyphButton(symbol: "xmark", size: 10, tint: Theme.cloudSecondary, label: "Close teleprompter (Esc twice)", action: actions.close)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
    }

    private var recordButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: actions.record) {
                HStack(spacing: 5) {
                    Circle().fill(TopBarStyle.rec).frame(width: 8, height: 8)
                    if let since = model.recordingSince {
                        let seconds = Int(context.date.timeIntervalSince(since))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                    } else {
                        Text("Rec")
                    }
                }
                .font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(model.recordingSince == nil ? Theme.cloudSecondary : TopBarStyle.rec)
                .padding(.horizontal, 9).frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(model.recordingSince == nil ? 0.08 : 0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(model.recordingSince == nil ? "Record camera and microphone" : "Stop recording")
            .help("Records camera and microphone to your Movies folder")
        }
    }

    private var modeLabel: some View {
        Label(model.mode.title, systemImage: model.mode == .words ? "text.word.spacing" : (model.mode == .voice ? "waveform" : "speedometer"))
            .font(TopBarStyle.label(11, .semibold))
    }

    private var divider: some View {
        Rectangle().fill(TopBarStyle.tileStroke).frame(width: 1, height: 16).padding(.horizontal, 3)
    }

    private var accessibilityProgress: String {
        switch model.mode {
        case .words: "\(Int(model.follower.progress * 100)) percent read"
        default: model.isRunning ? "Scrolling" : "Paused"
        }
    }
}
