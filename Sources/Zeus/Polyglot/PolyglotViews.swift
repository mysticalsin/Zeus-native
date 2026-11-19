import AppKit
import SwiftUI
import Translation
import ZeusCore

// MARK: Menus (AppKit menus stay up over the notch; the notch waits while one is open)

@MainActor
private final class PolyglotMenuTarget: NSObject {
    static let shared = PolyglotMenuTarget()
    var actions: [Int: () -> Void] = [:]

    @objc func pick(_ item: NSMenuItem) { actions[item.tag]?() }
}

@MainActor
enum PolyglotMenu {
    static func show(_ entries: [(title: String, checked: Bool, action: () -> Void)], topBar: TopBarModel?) {
        let menu = NSMenu()
        let target = PolyglotMenuTarget.shared
        target.actions = [:]
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(PolyglotMenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.tag = index
            item.state = entry.checked ? .on : .off
            target.actions[index] = entry.action
            menu.addItem(item)
        }
        topBar?.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        topBar?.menuOpen = false
    }

    static func targetLanguages(settings: PolyglotSettings, topBar: TopBarModel?) {
        show(PolyglotLanguage.targets.map { language in
            (language.name, settings.target == language.code, { settings.target = language.code })
        }, topBar: topBar)
    }
}

// MARK: Caption lines

/// One caption: a language tag, the translation as the main line and the original under it. A
/// line already in the target language shows once, as the main line. Partials are dimmer.
struct PolyglotLineView: View {
    let line: PolyglotLine
    let size: PolyglotCaptionSize
    let showOriginal: Bool
    var partial = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.language.map(PolyglotLanguage.badge) ?? "··")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if line.isTarget || (line.translation == nil && !partial && line.language == nil) {
                    Text(line.original).font(.system(size: size.translationPoints, weight: .semibold)).foregroundStyle(.white)
                } else if let translation = line.translation {
                    Text(translation).font(.system(size: size.translationPoints, weight: .semibold)).foregroundStyle(.white)
                    if showOriginal {
                        Text(line.original).font(.system(size: size.originalPoints)).foregroundStyle(Color(white: 0.56))
                    }
                } else {
                    // Heard, not translated yet.
                    Text(line.original).font(.system(size: size.translationPoints, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .opacity(partial ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The last captions, newest at the bottom, with the line being said at the very end. The region never
/// grows with its text: it scrolls (pinned to the newest line) inside the height it is given, so the
/// banners and their buttons under it always keep their place. `height` nil fills the space on offer.
struct PolyglotLinesList: View {
    let polyglot: PolyglotController
    var count = 8
    var height: CGFloat?

    var body: some View {
        let settings = polyglot.settings
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(polyglot.transcript.recent(count)) { line in
                    PolyglotLineView(line: line, size: settings.captionSize, showOriginal: settings.showOriginal)
                }
                ForEach([PolyglotSide.system, .microphone], id: \.self) { side in
                    if let text = polyglot.partials[side] {
                        PolyglotLineView(line: PolyglotLine(id: -1, side: side, original: text, language: polyglot.detectedLanguage, isFinal: false),
                                         size: settings.captionSize, showOriginal: settings.showOriginal, partial: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: height ?? .infinity, alignment: .topLeading)
        .frame(height: height)
    }
}

/// Banners under the captions: a missing pack, a missing permission, anything else worth saying.
struct PolyglotBanner: View {
    let polyglot: PolyglotController

    var body: some View {
        VStack(spacing: 6) {
            if let pack = polyglot.packNeeded {
                let pair = "\(PolyglotLanguage.name(for: pack.source)) to \(PolyglotLanguage.name(for: pack.target))"
                if polyglot.isDownloadingPack {
                    banner("arrow.down.circle", "Downloading the \(pair) language pack. macOS may ask you to confirm.", button: nil, action: {})
                } else {
                    banner("arrow.down.circle", "\(pair) needs a language pack.", button: "Download", action: polyglot.downloadPack)
                }
            }
            // After a failed download the pack banner stays (to try again) and the reason shows under it.
            if let notice = polyglot.notice {
                banner("info.circle", notice, button: polyglot.permissionPane == nil ? nil : "Open Settings", action: polyglot.openPermissionPane)
            }
        }
    }

    private func banner(_ symbol: String, _ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.bolt)
            Text(text).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let button {
                Button(button, action: action)
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Color.black)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Color.white))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

// MARK: The notch page

/// The Polyglot tab: start and stop, the source and target, and the live captions.
struct PolyglotPage: View {
    let polyglot: PolyglotController
    let topBar: TopBarModel

    var body: some View {
        let settings = polyglot.settings
        HStack(spacing: 8) {
            Tile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        GlanceRoundButton(symbol: polyglot.isListening || polyglot.isStarting ? "stop.fill" : "play.fill", size: 38, filled: true,
                                          label: polyglot.isListening || polyglot.isStarting ? "Stop Polyglot" : "Start Polyglot") { polyglot.toggle() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status).font(TopBarStyle.label(12.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                            Text(detail).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(PolyglotSource.allCases) { source in sourceButton(source, settings: settings) }
                    }
                    Button {
                        PolyglotMenu.targetLanguages(settings: settings, topBar: topBar)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                            Text("Translate to \(PolyglotLanguage.name(for: settings.target))")
                                .font(TopBarStyle.label(11.5, .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Theme.cloudPrimary)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Translate to \(PolyglotLanguage.name(for: settings.target))")
                    HStack(spacing: 4) {
                        GlyphButton(symbol: polyglot.isPinned ? "pin.fill" : "pin", size: 12,
                                    tint: polyglot.isPinned ? Theme.bolt : Theme.cloudSecondary,
                                    label: polyglot.isPinned ? "Unpin Polyglot bar" : "Pin Polyglot bar") { polyglot.togglePin() }
                        GlyphButton(symbol: "doc.on.doc", size: 12, tint: Theme.cloudSecondary, label: "Copy transcript") { polyglot.copyTranscript() }
                        GlyphButton(symbol: polyglot.isPoppedOut ? "pip.exit" : "pip.enter", size: 12, tint: Theme.cloudSecondary,
                                    label: polyglot.isPoppedOut ? "Close the floating captions" : "Pop out floating captions") { polyglot.togglePopOut() }
                        GlyphButton(symbol: "trash", size: 12, tint: Theme.cloudSecondary, label: "Clear captions") { polyglot.clear() }
                        GlyphButton(symbol: "xmark", size: 10, tint: Theme.cloudSecondary, label: "Dismiss Polyglot bar") {
                            NotchControllerBridge.controller?.dismissExplicitly()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 262)
            Tile {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(polyglot.isListening ? TopBarStyle.rec : Color.white.opacity(0.25)).frame(width: 7, height: 7)
                        Text(languagePair).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        Spacer()
                        if polyglot.isListening { LevelBars(color: Theme.cloudSecondary, active: true, level: polyglot.level, height: 12) }
                    }
                    if polyglot.transcript.lines.isEmpty && polyglot.partials.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(polyglot.isListening ? "Listening\u{2026}" : "Live captions in your language")
                                .font(TopBarStyle.label(15, .semibold)).foregroundStyle(Theme.cloudPrimary)
                            Text("Press start, then speak or play something. Each line shows what was said and what it means in \(PolyglotLanguage.name(for: settings.target)).")
                                .font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudQuiet).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                    } else {
                        PolyglotLinesList(polyglot: polyglot)
                    }
                    Spacer(minLength: 0)
                    // Reserved first: the captions scroll in what is left, so Download and Open Settings never clip.
                    PolyglotBanner(polyglot: polyglot).layoutPriority(1)
                }
            }
        }
        .polyglotPackHost(polyglot, active: !polyglot.isPoppedOut)
    }

    private var status: String {
        if polyglot.isStarting { return "Starting\u{2026}" }
        return polyglot.isListening ? "Listening" : "Ready"
    }

    private var detail: String {
        let source = polyglot.isListening ? polyglot.activeSource : polyglot.settings.source
        return polyglot.isListening && !polyglot.engineName.isEmpty ? "\(source.title) · \(polyglot.engineName)" : source.title
    }

    private var languagePair: String {
        let from = polyglot.detectedLanguage.map(PolyglotLanguage.badge) ?? "\u{2026}"
        return "\(from)  \u{2192}  \(PolyglotLanguage.badge(polyglot.settings.target))"
    }

    private func sourceButton(_ source: PolyglotSource, settings: PolyglotSettings) -> some View {
        let selected = (polyglot.isListening || polyglot.isStarting ? polyglot.activeSource : settings.source) == source
        return Button {
            settings.source = source
            if polyglot.isListening { polyglot.stop(); polyglot.start(source: source) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: source.symbol).font(.system(size: 10.5, weight: .semibold))
                if selected { Text(source.title).font(TopBarStyle.label(10.5, .semibold)).lineLimit(1) }
            }
            .foregroundStyle(selected ? Color.black : Theme.cloudSecondary)
            .padding(.horizontal, 9).frame(height: 26)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(polyglot.isStarting)
        .help("Listen to: \(source.title)")
        .accessibilityLabel("Listen to \(source.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Language pack download (macOS shows its own sheet)

extension View {
    /// Hosts Apple's translation task, which downloads a missing language pack when asked.
    @ViewBuilder
    func polyglotPackHost(_ polyglot: PolyglotController, active: Bool = true) -> some View {
        if #available(macOS 15.0, *), active {
            modifier(PolyglotPackHost(polyglot: polyglot))
        } else {
            self
        }
    }
}

@available(macOS 15.0, *)
private struct PolyglotPackHost: ViewModifier {
    let polyglot: PolyglotController

    func body(content: Content) -> some View {
        content.translationTask(polyglot.packConfiguration as? TranslationSession.Configuration) { session in
            nonisolated(unsafe) let unsafeSession = session
            do {
                try await unsafeSession.prepareTranslation()
                polyglot.packFinished(success: true)
            } catch {
                polyglot.packFinished(success: false, message: nil)
            }
        }
    }
}

// MARK: The floating caption strip

/// The pop-out: a black card with the last captions, on top of everything, on every space, and
/// invisible to screen sharing and recordings.
struct PolyglotStripView: View {
    let polyglot: PolyglotController
    let close: () -> Void

    var body: some View {
        let settings = polyglot.settings
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(polyglot.isListening ? TopBarStyle.rec : Color.white.opacity(0.3)).frame(width: 8, height: 8)
                Text("\(polyglot.detectedLanguage.map(PolyglotLanguage.badge) ?? "\u{2026}") \u{2192} \(PolyglotLanguage.badge(settings.target))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.75))
                if polyglot.isListening { LevelBars(color: .white.opacity(0.7), active: true, level: polyglot.level, height: 11) }
                Spacer()
                GlyphButton(symbol: polyglot.isListening || polyglot.isStarting ? "stop.fill" : "play.fill", size: 11,
                            label: polyglot.isListening || polyglot.isStarting ? "Stop Polyglot" : "Start Polyglot") { polyglot.toggle() }
                GlyphButton(symbol: "doc.on.doc", size: 11, label: "Copy transcript") { polyglot.copyTranscript() }
                GlyphButton(symbol: "xmark", size: 10, label: "Close the floating captions", action: close)
            }
            if polyglot.transcript.lines.isEmpty && polyglot.partials.isEmpty {
                Text(polyglot.isListening ? "Listening\u{2026}" : "Press play to start live captions.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
            } else {
                PolyglotLinesList(polyglot: polyglot, height: 150)
            }
            PolyglotBanner(polyglot: polyglot)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 460, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .polyglotPackHost(polyglot)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live translation")
    }
}

/// A non-activating panel at the screen's right edge, always on top, on every space and full-screen app.
@MainActor
final class PolyglotCaptionPanel: NSPanel {
    var onClose: () -> Void = {}

    init(polyglot: PolyglotController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: PolyglotStripView(polyglot: polyglot) { [weak self] in self?.close() })
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        setFrameAutosaveName("zeus.polyglot.strip")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        if let screen = NSScreen.main, !frame.intersects(screen.visibleFrame) || frameAutosaveName.isEmpty || frame.origin == .zero {
            let size = contentView?.fittingSize ?? CGSize(width: 460, height: 190)
            setContentSize(size)
            setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 14, y: screen.visibleFrame.maxY - size.height - screen.visibleFrame.height * 0.2))
        }
        orderFrontRegardless()
    }

    override func close() {
        super.close()
        onClose()
    }
}
