import AppKit
import SwiftUI
import ZeusCore

/// The notch teleprompter. Your script reads just under the camera; it follows your voice,
/// holds while you hover, and the notch hides from screen sharing while it runs.
struct TeleprompterPage: View {
    let topBar: TopBarModel

    var body: some View {
        if topBar.prompterActive { PrompterRolling(topBar: topBar) } else { PrompterSetup(topBar: topBar) }
    }
}

/// Paste never silently discards a script: with one already written, it asks to replace or add to the end.
@MainActor
private enum PrompterPaste {
    static func run(_ topBar: TopBarModel) {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let current = topBar.script
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || current == text {
            topBar.script = text
            return
        }
        let alert = NSAlert()
        alert.messageText = "Replace your script?"
        alert.informativeText = "The clipboard has \(text.count) characters. Replacing deletes the \(current.count) characters of the script you have now."
        alert.addButton(withTitle: "Add to End")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            topBar.script = current.hasSuffix("\n") ? current + "\n" + text : current + "\n\n" + text
        case .alertSecondButtonReturn:
            topBar.script = text
        default:
            break
        }
    }
}

private struct PrompterSetup: View {
    let topBar: TopBarModel

    var body: some View {
        let script = PrompterScript(topBar.script)
        HStack(spacing: 8) {
            Tile {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Script").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        Spacer()
                        Text("\(script.wordCount) words · ~\(PrompterTiming.minutes(script.readingTime())) · \(script.cues.count) cues")
                            .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet)
                    }
                    if script.blocks.isEmpty {
                        Text("No script yet. Write one, or copy text and paste it here.")
                            .font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
                    } else {
                        // As much of the script as fits, fading out at the bottom (never a cue cut from its text).
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(script.blocks.prefix(12)) { block in
                                Text(block.isCue ? block.text.uppercased() : block.text)
                                    .font(block.isCue ? TopBarStyle.label(10, .bold) : TopBarStyle.label(12))
                                    .foregroundStyle(block.isCue ? Theme.bolt : Theme.cloudPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        NotchActionButton(title: "Edit", tint: Theme.cloudPrimary, filled: false) { topBar.editScript() }
                        NotchActionButton(title: "Paste", tint: Theme.cloudPrimary, filled: false) { PrompterPaste.run(topBar) }
                        NotchActionButton(title: "Window", tint: Theme.cloudPrimary, filled: false) { PrompterHub.shared.toggle() }
                            .accessibilityHint("Opens the floating teleprompter under the camera.")
                        NotchActionButton(title: "Slides", tint: Theme.cloudPrimary, filled: false) { PrompterHub.shared.followSlides() }
                            .accessibilityHint("Shows the speaker notes of the Keynote or PowerPoint slide on screen, above the slideshow.")
                    }
                }
            }
            Tile {
                VStack(alignment: .leading, spacing: 9) {
                    toggleRow("Follow my voice", symbol: "mic.fill", on: topBar.roll.voiceFollow) {
                        topBar.setPrompterVoice(!topBar.roll.voiceFollow)
                    }
                    HStack(spacing: 4) {
                        Text("Speed").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                        Spacer()
                        GlyphButton(symbol: "minus", size: 10, label: "Slower") { topBar.roll.adjustSpeed(by: -4) }
                        Text("\(Int(topBar.roll.speed))").font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                            .frame(width: 26)
                        GlyphButton(symbol: "plus", size: 10, label: "Faster") { topBar.roll.adjustSpeed(by: 4) }
                    }
                    HStack(spacing: 4) {
                        Text("Text size").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                        Spacer()
                        GlyphButton(symbol: "textformat.size.smaller", size: 10, label: "Smaller") { topBar.prompterTextSize = max(14, topBar.prompterTextSize - 2) }
                        Text("\(Int(topBar.prompterTextSize))").font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                            .frame(width: 26)
                        GlyphButton(symbol: "textformat.size.larger", size: 10, label: "Larger") { topBar.prompterTextSize = min(34, topBar.prompterTextSize + 2) }
                    }
                    Spacer(minLength: 0)
                    NotchActionButton(title: "Start  3 · 2 · 1", tint: Theme.bolt) { topBar.startPrompter() }
                        .disabled(script.blocks.isEmpty)
                    Text("Hidden from screen sharing while it runs.").font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet)
                }
            }
            .frame(width: 210)
        }
    }

    private func toggleRow(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(TopBarStyle.label(11, .semibold))
                Spacer()
                Capsule().fill(on ? Theme.leaf : Color.white.opacity(0.15)).frame(width: 26, height: 15)
                    .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 11, height: 11).padding(2) }
            }
            .foregroundStyle(on ? Theme.cloudPrimary : Theme.cloudSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct PrompterRolling: View {
    let topBar: TopBarModel

    var body: some View {
        let script = PrompterScript(topBar.script)
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(script.blocks) { block in
                        Text(block.isCue ? block.text.uppercased() : block.text)
                            .font(.system(size: block.isCue ? topBar.prompterTextSize * 0.55 : topBar.prompterTextSize,
                                          weight: block.isCue ? .heavy : .semibold, design: .rounded))
                            .foregroundStyle(block.isCue ? Theme.bolt : Theme.cloudPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: CueOffsets.self,
                                                       value: block.isCue ? [block.id: geo.frame(in: .named("script")).minY] : [:])
                            })
                    }
                    Color.clear.frame(height: TopBarStyle.pageHeight)
                }
                .padding(.leading, 18).padding(.trailing, 6)
                .fixedSize(horizontal: false, vertical: true)
                .coordinateSpace(name: "script")
                .background(GeometryReader { geo in Color.clear.preference(key: ScriptHeight.self, value: geo.size.height) })
                .offset(y: TopBarModel.prompterReadingLine - topBar.roll.offset)
                // Reading line: the words here sit closest to the camera.
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9)).foregroundStyle(Theme.bolt)
                    .offset(x: 2, y: TopBarModel.prompterReadingLine + 6)
                if topBar.roll.phase == .countdown {
                    TickingView(interval: 0.25) { context in
                        Text("\(topBar.roll.countdownRemaining(at: context.date) ?? 1)")
                            .font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(Theme.bolt)
                            .shadow(color: Theme.bolt.opacity(0.6), radius: 12)
                            .frame(maxWidth: .infinity)
                            .frame(height: TopBarStyle.pageHeight)
                            .background(Color.black.opacity(0.55))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: TopBarStyle.pageHeight, alignment: .top)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .contentShape(Rectangle())
            .live { $0.onHover { topBar.prompterHovered = $0 } }
            .onPreferenceChange(ScriptHeight.self) { height in MainActor.assumeIsolated { topBar.prompterContentHeight = height } }
            .onPreferenceChange(CueOffsets.self) { offsets in MainActor.assumeIsolated { topBar.prompterCueOffsets = offsets } }
            .accessibilityLabel("Teleprompter script")

            controls(script)
        }
    }

    private func controls(_ script: PrompterScript) -> some View {
        let roll = topBar.roll
        return VStack(spacing: 6) {
            Text(status(roll)).font(TopBarStyle.label(10, .semibold)).foregroundStyle(statusColor(roll)).lineLimit(1)
            HStack(spacing: 2) {
                GlyphButton(symbol: roll.phase == .rolling ? "pause.fill" : "play.fill", size: 12,
                            label: roll.phase == .rolling ? "Pause" : "Resume") {
                    roll.phase == .rolling ? topBar.roll.pause() : topBar.roll.resume()
                }
                GlyphButton(symbol: "forward.end.fill", size: 11, label: "Next cue") { topBar.jumpToNextCue() }
                GlyphButton(symbol: "stop.fill", size: 11, tint: Theme.danger, label: "Stop") { topBar.stopPrompter() }
            }
            HStack(spacing: 2) {
                GlyphButton(symbol: "tortoise.fill", size: 10, label: "Slower") { topBar.roll.adjustSpeed(by: -4) }
                Text("\(Int(roll.speed))").font(TopBarStyle.label(10.5, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                GlyphButton(symbol: "hare.fill", size: 10, label: "Faster") { topBar.roll.adjustSpeed(by: 4) }
            }
            GlyphButton(symbol: roll.voiceFollow ? "mic.fill" : "mic.slash.fill", size: 11,
                        tint: roll.voiceFollow ? Theme.leaf : Theme.cloudSecondary,
                        label: roll.voiceFollow ? "Voice follow on" : "Voice follow off") { topBar.setPrompterVoice(!roll.voiceFollow) }
            Spacer(minLength: 0)
            // Voice beam: how loud the mic hears you.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(roll.voiceFollow ? Theme.leaf : Theme.cloudQuiet)
                        .frame(width: max(4, geo.size.width * topBar.prompterLevel))
                        .shadow(color: Theme.leaf.opacity(0.7), radius: 4)
                }
            }
            .frame(height: 4)
            if let notice = topBar.prompterNotice {
                Text(notice).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudQuiet).lineLimit(3)
            }
        }
        .padding(8)
        .frame(width: 108, height: TopBarStyle.pageHeight)
        .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous))
    }

    private func status(_ roll: PrompterRoll) -> String {
        switch roll.phase {
        case .countdown: "Get ready"
        case .paused: "Paused"
        case .finished: "The end"
        case .idle: "Ready"
        case .rolling:
            topBar.prompterHovered ? "Holding" : roll.voiceFollow && !roll.isSpeaking() ? "Waiting for you" : "Rolling"
        }
    }

    private func statusColor(_ roll: PrompterRoll) -> Color {
        roll.phase == .rolling && !topBar.prompterHovered ? Theme.leaf : Theme.bolt
    }
}

private struct ScriptHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CueOffsets: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}
