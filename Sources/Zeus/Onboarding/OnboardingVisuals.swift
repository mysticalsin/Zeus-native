import AppKit
import ZeusCore
import AVFoundation
import Observation
import SwiftUI

// MARK: Films

/// A looping, muted film card, Glance's learn-* preview (260 pt wide, radius 20; the intro is wider).
/// More than one film plays as a loop of the list.
struct FilmCard: View {
    let films: [OnboardingFilm]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onboardingReduceMotion) private var motionOverride
    private var reduceMotion: Bool { OnboardingMotionPolicy.reduced(system: systemReduceMotion, override: motionOverride) }
    var body: some View {
        let size = films.first.map { film in
            let width: CGFloat = film == .intro ? 420 : 260
            return CGSize(width: width, height: width * film.size.height / film.size.width)
        } ?? .zero
        content
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            .accessibilityElement()
            .accessibilityLabel(films.map(\.accessibilityLabel).joined(separator: " "))
    }

    /// QA7 round 11 (report-11.md VISUAL section): every onboarding step with a film ("Welcome",
    /// "Murmure", "Your agents", "Stay in control", "Keys and displays") rendered this whole tile as a
    /// solid yellow "no-entry" placeholder glyph under `ImageRenderer`'s one-shot `--snapshots` pass.
    /// Same root cause as `GSTextField`'s doc comment above: `AVPlayerLayer` (`LoopingFilm`'s real,
    /// hardware-composited video layer) can't produce a frame on a windowless, synchronous render pass
    /// any more than an `NSTextField`'s field editor can, and macOS substitutes the same glyph. The
    /// live product is unaffected -- a real on-screen `--onboarding-only` window plays the film fine;
    /// only the offscreen QA capture needs a stand-in. In snapshot mode, grab one real decoded frame
    /// (the same `posterTime` Reduce Motion already freezes on) with `AVAssetImageGenerator` and show
    /// it as a plain `Image` -- actual film content, not a placeholder.
    @ViewBuilder private var content: some View {
        if let film = films.first, film == .intro {
            IntroScene(t: film.posterTime)
                .scaleEffect(filmCardScale(for: film))
        } else if TopBarStyle.isSnapshot || reduceMotion {
            if let film = films.first, let image = FilmPoster.image(for: film) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                // A missing poster must not silently turn animation back on.
                Color.black.overlay(Text("Preview unavailable").font(OB.font(13)).foregroundStyle(.white.opacity(0.7)))
            }
        } else {
            LoopingFilm(films: films, reduceMotion: reduceMotion)
        }
    }

    private func filmCardScale(for film: OnboardingFilm) -> CGFloat {
        let width: CGFloat = film == .intro ? 420 : 260
        let height = width * film.size.height / film.size.width
        return min(width / film.size.width, height / film.size.height)
    }
}

/// Synchronous poster-frame extraction for snapshot mode only (see `FilmCard.content` above). Cached
/// per film so a run that visits the same step more than once (or several steps sharing a film) only
/// decodes each one once.
@MainActor
enum FilmPoster {
    private static var cache: [OnboardingFilm: NSImage] = [:]

    static func image(for film: OnboardingFilm) -> NSImage? {
        if let cached = cache[film] { return cached }
        guard let url = film.url else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: film.posterTime, preferredTimescale: 600), actualTime: nil) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache[film] = image
        return image
    }
}

/// AVPlayerLooper (one film) or a re-queued AVQueuePlayer (several) in a layer-backed view; with Reduce
/// Motion it shows the first film's poster frame only.
struct LoopingFilm: NSViewRepresentable {
    let films: [OnboardingFilm]
    var reduceMotion = false

    func makeNSView(context: Context) -> FilmView { FilmView(films: films, reduceMotion: reduceMotion) }
    func updateNSView(_ view: FilmView, context: Context) { view.setReducedMotion(reduceMotion) }
    static func dismantleNSView(_ view: FilmView, coordinator: ()) { view.dispose() }

    @MainActor
    final class FilmView: NSView {
        private var looper: AVPlayerLooper?
        private let player = AVQueuePlayer()
        private let playerLayer = AVPlayerLayer()
        private let films: [OnboardingFilm]
        private var endObserver: NSObjectProtocol?
        private var visibilityObservers: [(NotificationCenter, NSObjectProtocol)] = []
        private weak var observedWindow: NSWindow?
        private var attachmentRevision: UInt64 = 0
        private var motionReduction: Bool
        private var closing = false
        private var disposed = false
        private var ownedItems: [ObjectIdentifier: AVPlayerItem] = [:]

        /// Read-only observations of the real player for native resource-lifecycle verification.
        struct PlaybackState {
            let rate: Float
            let status: AVPlayer.TimeControlStatus
            let seconds: Double
            let queuedItems: Int
            let queuedFilms: [String]
            let trackedItems: Int
            let muted: Bool
            let disposed: Bool
            let observerCount: Int
        }

        var playbackState: PlaybackState {
            .init(rate: player.rate, status: player.timeControlStatus, seconds: player.currentTime().seconds,
                  queuedItems: player.items().count,
                  queuedFilms: player.items().compactMap { ($0.asset as? AVURLAsset)?.url.lastPathComponent },
                  trackedItems: ownedItems.count, muted: player.isMuted,
                  disposed: disposed, observerCount: visibilityObservers.count + (endObserver == nil ? 0 : 1))
        }

        init(films: [OnboardingFilm], reduceMotion: Bool = false) {
            self.films = films
            motionReduction = reduceMotion
            super.init(frame: .zero)
            wantsLayer = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let urls = films.compactMap(\.url)
            guard let first = urls.first else { return }
            if urls.count == 1 {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: first))
            } else {
                for url in urls {
                    let item = AVPlayerItem(url: url)
                    ownedItems[ObjectIdentifier(item)] = item
                    player.insert(item, after: nil)
                }
                // Each film that finishes goes to the back of the queue.
                endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                    guard let item = note.object as? AVPlayerItem else { return }
                    let identity = ObjectIdentifier(item)
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed, let item = self.ownedItems[identity],
                              let asset = item.asset as? AVURLAsset, urls.contains(asset.url) else { return }
                        // Consume an owned completion once. A different player of the same URL,
                        // duplicate completion or callback after disposal cannot grow this queue.
                        self.ownedItems.removeValue(forKey: ObjectIdentifier(item))
                        let next = AVPlayerItem(url: asset.url)
                        self.ownedItems[ObjectIdentifier(next)] = next
                        self.player.insert(next, after: nil)
                        self.synchronizePlayback()
                    }
                }
            }
            if reducesMotion, let film = films.first {
                player.seek(to: CMTime(seconds: film.posterTime, preferredTimescale: 600))
            }
        }

        required init?(coder: NSCoder) { nil }

        isolated deinit { dispose() }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        /// AVPlayer is not a window visibility observer. Pause explicitly when this decorative
        /// preview is hidden or fully covered; never create a timer to poll an invisible guide.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeVisibilityObservers()
            closing = false
            guard !disposed, let window else { player.pause(); return }
            observedWindow = window
            let revision = attachmentRevision
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] note in
                    let isClosing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated {
                        guard let self, let window, self.attachmentRevision == revision,
                              self.window === window, self.observedWindow === window, !self.disposed else { return }
                        if isClosing { self.closing = true }
                        else if window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) {
                            self.closing = false // The retained guide window can be shown again.
                        }
                        self.synchronizePlayback()
                    }
                }
                visibilityObservers.append((.default, token))
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observeVisibility(name, center: .default, object: NSApplication.shared, revision: revision)
            }
            observeVisibility(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                              center: NSWorkspace.shared.notificationCenter, object: NSWorkspace.shared, revision: revision)
            synchronizePlayback()
        }

        override func viewDidHide() { super.viewDidHide(); synchronizePlayback() }
        override func viewDidUnhide() { super.viewDidUnhide(); synchronizePlayback() }

        func setReducedMotion(_ reduced: Bool) {
            motionReduction = reduced
            synchronizePlayback()
        }

        private var reducesMotion: Bool {
            motionReduction || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        private func synchronizePlayback() {
            let eligible: Bool
            if !disposed, !closing, !reducesMotion, !isHiddenOrHasHiddenAncestor, let window {
                eligible = OnboardingPollingPolicy.shouldPoll(presented: true, windowVisible: window.isVisible,
                    miniaturized: window.isMiniaturized, appHidden: NSApplication.shared.isHidden,
                    occluded: !window.occlusionState.contains(.visible))
            } else { eligible = false }
            if eligible, player.currentItem != nil {
                if player.rate == 0 || player.timeControlStatus == .paused { player.play() }
            } else { player.pause() }
        }

        private func observeVisibility(_ name: Notification.Name, center: NotificationCenter,
                                       object: Any?, revision: UInt64) {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.disposed, self.attachmentRevision == revision,
                          let window = self.window, self.observedWindow === window else { return }
                    self.synchronizePlayback()
                }
            }
            visibilityObservers.append((center, token))
        }

        private func removeVisibilityObservers() {
            attachmentRevision &+= 1
            for (center, observer) in visibilityObservers { center.removeObserver(observer) }
            visibilityObservers.removeAll()
            observedWindow = nil
        }

        func dispose() {
            guard !disposed else { return }
            disposed = true
            player.pause()
            removeVisibilityObservers()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
            ownedItems.removeAll()
            playerLayer.player = nil
        }
    }
}

// MARK: Your day

/// Weather, Calendar and Reminders tiles, aligned to the three permission rows on the left.
struct DayIcons: View {
    /// Row pitch of the step's rows: each icon is centred in a cell of this height, so it sits level with its row.
    var pitch: CGFloat = 88
    var count = 3

    var body: some View {
        VStack(spacing: 0) {
            cell { weather.frame(width: 64, height: 64) }
            cell { calendar.frame(width: 56, height: 56) }
            cell { reminders.frame(width: 64, height: 64) }
        }
        .frame(height: pitch * CGFloat(count))
        .accessibilityHidden(true)
    }

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: 80, height: pitch)
    }

    private var weather: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(LinearGradient(colors: [Color(rgb: 74, 144, 240), Color(rgb: 30, 84, 196)], startPoint: .top, endPoint: .bottom))
            .overlay(Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 34)))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    /// Icon art showing today's date in the ZEUS calendar.
    private var calendar: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Text(ZeusDates.string(Date(), template: "MMM").uppercased())
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 15)
                        .background(Color(rgb: 228, 76, 70))
                    Text("\(ZeusDates.day(of: Date()))").font(.system(size: 30, weight: .light)).foregroundStyle(.black)
                        .padding(.top, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private var reminders: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(Color(rgb: 246, 246, 248))
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([Color(rgb: 66, 133, 244), Color(rgb: 234, 76, 70), Color(rgb: 244, 162, 54)], id: \.self) { colour in
                        HStack(spacing: 8) {
                            Circle().fill(colour).frame(width: 9, height: 9)
                            Capsule().fill(Color(rgb: 200, 202, 208)).frame(width: 24, height: 2)
                        }
                    }
                }
            )
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

// MARK: Theme preview

/// Home and Music in miniature, drawn in the chosen finish (Glass, Liquid Glass or Physical).
struct ThemePreview: View {
    let style: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black)
            VStack(alignment: .leading, spacing: 0) {
                label("Home").padding(.top, 9)
                HStack(spacing: 5) {
                    musicMini
                    card { VStack(alignment: .leading, spacing: 1) { small("Tuesday"); faint("Nothing on"); Spacer(); big("20") } }
                    card { VStack(alignment: .leading, spacing: 1) { small("Paris"); faint("Sunny"); Spacer(); big("19\u{00B0}") } }
                    card {
                        VStack(alignment: .leading, spacing: 1) {
                            small("Up next"); faint("in 29 minutes"); Spacer()
                            Text("09:58").font(.system(size: 12, weight: .light)).foregroundStyle(Color(rgb: 240, 120, 150))
                            Text("Team sync").font(.system(size: 5.5, weight: .medium)).foregroundStyle(Color(rgb: 120, 150, 255))
                        }
                    }
                }
                .frame(height: 58)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(band)
                label("Music").padding(.top, 10)
                HStack(spacing: 6) {
                    card {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6).fill(Self.art).frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                faint("Paused"); Spacer()
                                Text("Storm Light").font(.system(size: 7, weight: .medium)).foregroundStyle(.white)
                                faint("Zeus Radio")
                                Capsule().fill(.white.opacity(0.15)).frame(height: 2)
                                    .overlay(alignment: .leading) { Capsule().fill(Color(rgb: 240, 120, 150)).frame(width: 40, height: 2) }
                                HStack {
                                    Image(systemName: "backward.fill"); Spacer()
                                    Image(systemName: "play.circle.fill").font(.system(size: 13)); Spacer()
                                    Image(systemName: "forward.fill")
                                }
                                .font(.system(size: 6)).foregroundStyle(.white)
                            }
                        }
                    }
                    card {
                        VStack(alignment: .leading) {
                            small("Lyrics"); Spacer()
                            Text("NOW PLAYING").font(.system(size: 4.5, weight: .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.4))
                            Spacer()
                        }
                    }
                }
                .frame(height: 112)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(band)
            }
            .padding(.horizontal, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: style)
    }

    static let art = LinearGradient(colors: [Color(rgb: 255, 214, 102), Color(rgb: 242, 112, 156), Color(rgb: 140, 92, 230)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private var band: some View {
        Group {
            switch style {
            case "Physical": RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(rgb: 92, 94, 98), Color(rgb: 58, 60, 64)], startPoint: .top, endPoint: .bottom))
            case "Liquid Glass": RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(rgb: 40, 46, 70), Color(rgb: 22, 24, 34)], startPoint: .top, endPoint: .bottom))
            case "Classic": RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.16))
            case "Dashboard", "Dashboard B": RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.07))
            default: RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(rgb: 46, 40, 44), Color(rgb: 30, 28, 30)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private var musicMini: some View {
        card {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Self.art).frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Storm Light").font(.system(size: 5.5, weight: .medium)).foregroundStyle(.white)
                        faint("Zeus Radio")
                    }
                }
                Spacer()
                HStack { Image(systemName: "backward.fill"); Spacer(); Image(systemName: "play.circle.fill").font(.system(size: 9)); Spacer(); Image(systemName: "forward.fill") }
                    .font(.system(size: 4.5)).foregroundStyle(.white)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardFill)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(cardRim, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder private var cardFill: some View {
        switch style {
        case "Physical":
            RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [Color(rgb: 40, 42, 44), Color(rgb: 24, 25, 27)], startPoint: .top, endPoint: .bottom))
        case "Liquid Glass":
            RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.07))
        case "Classic":
            RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.22))
        case "Dashboard":
            RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.03))
        case "Dashboard B":
            RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.11)).overlay(alignment: .top) { Capsule().fill(Theme.glow.opacity(0.7)).frame(height: 1.2).padding(.horizontal, 8) }
        default:
            RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.1))
        }
    }

    private var cardRim: Color {
        switch style {
        case "Physical": .black.opacity(0.6)
        case "Liquid Glass": .white.opacity(0.45)
        case "Dashboard": .white.opacity(0.35)
        default: .white.opacity(0.12)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 6.5, weight: .semibold)).foregroundStyle(.white).padding(.leading, 9).padding(.bottom, 4)
    }
    private func small(_ text: String) -> some View { Text(text).font(.system(size: 5, weight: .medium)).foregroundStyle(.white.opacity(0.8)) }
    private func faint(_ text: String) -> some View { Text(text).font(.system(size: 4.5)).foregroundStyle(.white.opacity(0.5)) }
    private func big(_ text: String) -> some View { Text(text).font(.system(size: 18, weight: .light)).foregroundStyle(.white) }
}

// MARK: Sounds preview

/// Right-column art for the sounds onboarding step (matches halo/day preview sizing).
struct SoundsPreviewTile: View {
    var options: OnboardingOptions = .live
    /// Spans the step's rows (feedback switch plus the four cues).
    var height: CGFloat = 160
    @Environment(\.ob) private var ob
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 12, 16, 28), Color(rgb: 24, 32, 52)], startPoint: .topLeading, endPoint: .bottomTrailing))
            // The mascot (`OnboardingRoot`'s hero slot) sits in the upper half; the waveform under it.
            HStack(spacing: 6) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule()
                        .fill(OB.blueLight.opacity(0.55 + Double(index % 3) * 0.12))
                        .frame(width: 5, height: CGFloat(18 + (index * 7) % 28))
                }
            }
            .opacity(options.bool("sound.on") ? 1 : 0.4)
            .offset(y: height * 0.3)
        }
        .frame(width: 260, height: height)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(options.bool("sound.on") ? "Sound on" : "Sound off")
    }
}

// MARK: Halo preview

/// A small screen with the closed notch and its halo (260 pt wide, as tall as the step's rows), and the
/// style's name underneath.
struct HaloPreviewCard: View {
    var options: OnboardingOptions = .live
    var height: CGFloat = 81
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onboardingReduceMotion) private var motionOverride
    private var reduceMotion: Bool { OnboardingMotionPolicy.reduced(system: systemReduceMotion, override: motionOverride) }
    private var drawn: Double { options.haloDrawn }
    @Environment(\.ob) private var ob
    private var style: HaloStyle { HaloStyle.resolve(options.string("halo.style")) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: .black, location: 0.0), .init(color: .black, location: 0.2),
                    .init(color: Color(rgb: 12, 20, 48), location: 0.55), .init(color: Color(rgb: 28, 56, 128), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            HaloOutline(style: style, arm: options.string("halo.armWidth"),
                        thickness: max(100, options.double("halo.thickness")) / 100, drawn: drawn, animated: !reduceMotion)
                .frame(width: 260, height: 81)
            Text(style.title).font(OB.font(13, .medium)).foregroundStyle(.white.opacity(0.7))
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 22)
        }
        .frame(width: 260, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Halo preview, \(style.title)")
        .onChange(of: style) { replay() }
        .onChange(of: options.string("halo.entrance")) { replay() }
    }

    private func replay() {
        guard !reduceMotion else { return }
        options.haloDrawn = 0
        withAnimation(.easeOut(duration: 0.6)) { options.haloDrawn = 1 }
    }
}

/// The lit notch outline: arms either side of the notch, dipping round it. It draws with the same
/// renderer as the live notch (HaloRenderer), so a card is exactly what the notch will show.
struct HaloOutline: View {
    let style: HaloStyle
    let arm: String
    let thickness: Double
    let drawn: Double
    /// Moving styles (rays, dots, the aurora hue) animate when true; otherwise one still frame.
    var animated = false
    var color = Color(rgb: 120, 140, 255)

    private var armLength: CGFloat {
        switch arm { case "Narrow": 26; case "Wide": 64; case "Extra wide": 86; default: 44 }
    }

    var body: some View {
        if animated, !Motion.reduced, !TopBarStyle.isSnapshot {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: 0.35)
        }
    }

    /// The outline from the left arm tip, round the notch, to the right arm tip.
    static func outline(size: CGSize, arm: CGFloat) -> Path {
        let notchWidth: CGFloat = 230 - 2 * 44 + 4
        let mid = size.width / 2
        let left = mid - notchWidth / 2, right = mid + notchWidth / 2
        let top: CGFloat = 30, bottom: CGFloat = 52, r: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: left - arm, y: top))
        path.addLine(to: CGPoint(x: left - r, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + r), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - r), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top + r))
        path.addQuadCurve(to: CGPoint(x: right + r, y: top), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right + arm, y: top))
        return path
    }

    private func canvas(time: Double) -> some View {
        Canvas { context, size in
            let outline = Polyline(path: Self.outline(size: size, arm: armLength))
            let lit = outline.slice(from: 0.5 - drawn / 2, to: 0.5 + drawn / 2)
            var paint = HaloPaint(color: color, opacity: 0.95, line: 1.6 * CGFloat(thickness), bloom: 1, scale: 0.62, time: time)
            paint.reduceMotion = Motion.reduced
            // The path runs left to right, so the outward side is the mirror of the live left arm's.
            paint.normalSign = -1
            var ctx = context
            HaloRenderer.draw(style, line: lit, in: &ctx, paint: paint)
        }
    }
}
