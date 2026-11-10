import AppKit
import SwiftUI
import ZeusCore

/// The guide's eight films, original Zeus remakes of Glance's lengths and framings (running 7.0 s,
/// murmure 25.1 s, intro about 20 s, approve about 5 s, previews about 10 s, shortcuts about 7 s,
/// everywhere 8.5 s). Each scene is a pure function of time, drawn with the real v2 mascot sprites and
/// rendered offline to H.264 by `scripts/render-onboarding-films.sh` (`Zeus --render-film <name> <dir>`
/// writes the frames).
enum OnboardingFilm: String, CaseIterable, Sendable {
    case intro
    case murmure = "learn-murmure"
    case running = "learn-running"
    case approve = "learn-approve"
    case previews = "learn-previews"
    case shortcuts = "learn-shortcuts"
    case everywhere = "learn-everywhere"

    var size: CGSize {
        switch self {
        case .intro: CGSize(width: 1040, height: 798)
        case .murmure: CGSize(width: 720, height: 1280)
        default: CGSize(width: 720, height: 900)
        }
    }
    var fps: Double { self == .running ? 60 : 30 }
    var duration: Double {
        switch self {
        case .intro: 20.0
        case .murmure: 25.1
        case .running: 7.0
        case .approve: 5.0
        case .previews: 10.0
        case .shortcuts: 7.0
        case .everywhere: 8.5
        }
    }
    var frameCount: Int { Int((duration * fps).rounded()) }
    var posterTime: Double {
        switch self {
        case .intro: 6.8
        case .murmure: 9.0
        case .running: 2.6
        case .approve: 1.6
        case .previews: 8.6
        case .shortcuts: 5.2
        case .everywhere: 1.2
        }
    }

    var url: URL? { ZeusResources.bundle?.resourceURL?.appendingPathComponent("Media/Films/\(rawValue).mp4") }

    var accessibilityLabel: String {
        switch self {
        case .intro: "Film: Zeus wakes in the notch, a sweep of light, the tabs unfold and the voice orb answers."
        case .murmure: "Film: hold your dictation key, speak, and the words appear in the app you are using."
        case .running: "Film: Zeus shows a running agent in the notch."
        case .approve: "Film: an agent asks for permission in the notch and you approve it."
        case .previews: "Film: peek cards for a running, a finished and a failed agent."
        case .shortcuts: "Film: hold the talk key, double-tap to latch, and answer with Control Option Y, N or O."
        case .everywhere: "Film: Zeus on every display, quiet in full screen, and the Insomnia lid."
        }
    }

    @MainActor @ViewBuilder func scene(_ t: Double) -> some View {
        switch self {
        case .intro: IntroScene(t: t)
        case .murmure: MurmureScene(t: t)
        case .running: RunningScene(t: t)
        case .approve: ApproveScene(t: t)
        case .previews: PreviewsScene(t: t)
        case .shortcuts: ShortcutsScene(t: t)
        case .everywhere: EverywhereScene(t: t)
        }
    }
}

// MARK: Timing helpers

/// 0 before `a`, 1 after `b`, eased in between.
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    guard b > a else { return t >= b ? 1 : 0 }
    let x = min(max((t - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
}

func mix(_ a: CGFloat, _ b: CGFloat, _ f: Double) -> CGFloat { a + (b - a) * CGFloat(f) }

// MARK: Shared scenery

/// The Mac: black above the lid, the lid's bright edge, the notch, and the blue desktop with
/// soft light waves.
struct Desk: View {
    let t: Double
    let lidY: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            LinearGradient(stops: [
                .init(color: Color(rgb: 6, 10, 26), location: 0),
                .init(color: Color(rgb: 18, 42, 104), location: 0.45),
                .init(color: Color(rgb: 40, 92, 214), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .padding(.top, lidY)
            Canvas { context, size in
                for i in 0..<2 {
                    let base = size.height * (0.72 + 0.12 * Double(i))
                    let phase = t * 0.6 + Double(i) * 1.7
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: base))
                    wave.addCurve(to: CGPoint(x: size.width, y: base - 60 - 20 * sin(phase)),
                                  control1: CGPoint(x: size.width * 0.35, y: base + 50 + 18 * sin(phase)),
                                  control2: CGPoint(x: size.width * 0.7, y: base - 30))
                    context.stroke(wave, with: .color(.white.opacity(0.55)), lineWidth: 2)
                }
            }
            Rectangle().fill(LinearGradient(colors: [.white.opacity(0.2), .white, .white.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 5).blur(radius: 0.6).offset(y: lidY - 12)
        }
    }
}

/// Notch body with a frosted glow along its lower edge.
struct NotchBody: View {
    let width: CGFloat
    let height: CGFloat
    var glow: Color = Color(rgb: 120, 160, 255)
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: height * 0.35, bottomTrailingRadius: height * 0.35, style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: height * 0.35, bottomTrailingRadius: height * 0.35, style: .continuous)
                    .stroke(glow.opacity(0.9), lineWidth: 2.5).blur(radius: 2.5)
            }
            .shadow(color: glow.opacity(0.6), radius: 14, y: 6)
    }
}

/// Dot-matrix numerals ("02"), as in the learn films' headers.
struct DotDigits: View {
    let text: String
    static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    ]
    var body: some View {
        Canvas { context, _ in
            var x: CGFloat = 0
            for character in text {
                for (row, line) in (Self.glyphs[character] ?? []).enumerated() {
                    for (col, bit) in line.enumerated() where bit == "1" {
                        context.fill(Path(ellipseIn: CGRect(x: x + CGFloat(col) * 7, y: CGFloat(row) * 7, width: 5, height: 5)),
                                     with: .color(Color(rgb: 74, 144, 240)))
                    }
                }
                x += 48
            }
        }
        .frame(width: 92, height: 50)
    }
}

struct FilmHeader: View {
    let number: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 26) {
                DotDigits(text: number).padding(.top, 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(Glass.font(30, .semibold)).foregroundStyle(.white)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                Text("zeus").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.4)).padding(.top, 6)
            }
            Rectangle().fill(LinearGradient(colors: [Color(rgb: 74, 144, 240).opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1).padding(.top, 20)
        }
        .padding(.horizontal, 30).padding(.top, 28)
    }
}

/// The living mascot in a film: the pose's sprite clip, started at `since` and driven by the film's clock.
struct FilmMascot: View {
    let pose: LivingPose
    let t: Double
    let size: CGFloat
    var since: Double = 0
    var body: some View {
        SpriteFrame(pose: pose, elapsed: max(0, t - since), size: size)
    }
}

// MARK: Running (7.0 s)

/// Beats, like Glance's: wide view with "Mascot" (0 to 1.4 s), push in on the notch (1.4 to 1.9),
/// hold on Zeus at work (to 3.6), pull back (3.6 to 4.2), then "Glyph" mode with "1 Running"
/// (4.8 s to the end).
struct RunningScene: View {
    let t: Double
    var body: some View {
        let zoom = ramp(t, 1.4, 1.9) * (1 - ramp(t, 3.6, 4.2))
        let glyph = ramp(t, 4.7, 5.1)
        ZStack(alignment: .top) {
            Color.black
            ZStack(alignment: .top) {
                Desk(t: t, lidY: 250)
                NotchBody(width: 690, height: 70).offset(y: 250)
                FilmMascot(pose: .working, t: t, size: 52)
                    .opacity(1 - glyph)
                    .position(x: 70, y: 285)
                Image(systemName: "rays").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color(rgb: 150, 190, 255))
                    .rotationEffect(.degrees(t * 240))
                    .opacity(glyph)
                    .position(x: 66, y: 285)
                runningPill.opacity((1 - glyph) * (1 - zoom)).position(x: 610, y: 285)
                Text("1 Running\u{2026}").font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(rgb: 150, 190, 255)).opacity(glyph).position(x: 600, y: 287)
            }
            .scaleEffect(mix(1, 2.3, zoom), anchor: UnitPoint(x: 0.05, y: 0.3))
            .offset(y: mix(0, 140, zoom))
            .frame(width: 720, height: 900).clipped()
            ZStack {
                Text("Mascot").opacity(1 - ramp(t, 1.0, 1.4))
                Text("Glyph").opacity(glyph)
            }
            .font(Glass.font(48, .bold)).foregroundStyle(Color(rgb: 96, 160, 248))
            .position(x: 360, y: 214)
            Color.black.frame(height: 150)
            FilmHeader(number: "02", title: "Running", subtitle: OnboardingMockCopy.runningFilmSubtitle)
        }
        .frame(width: 720, height: 900)
    }

    private var runningPill: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Circle().fill(.white.opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 0.8)))).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10).frame(height: 18)
        .background(Capsule().fill(Color(rgb: 30, 40, 90)))
    }
}

// MARK: Murmure (25.1 s)

/// Beats, like Glance's: title (0 to 1), key pressed (1 to 3), hands-free notch over a chat (3 to 5),
/// words appear in the field (5 to 7), send (7 to 8), the agent works and asks (8 to 12), approved
/// and done "In the bag" (12 to 16), key again (16 to 18), a second request (18 to 22), end card
/// (22 to 25.1).
struct MurmureScene: View {
    let t: Double
    var body: some View {
        ZStack {
            Color.black
            if t < 1.2 { opening.opacity(1 - ramp(t, 0.9, 1.2)) }
            if t >= 0.9 && t < 3.2 { FnKey(t: t - 0.9, glow: false).opacity(ramp(t, 0.9, 1.2) * (1 - ramp(t, 2.9, 3.2))) }
            if t >= 2.9 && t < 16.2 { desktop(firstPass: true).opacity(ramp(t, 2.9, 3.2) * (1 - ramp(t, 15.9, 16.2))) }
            if t >= 15.9 && t < 18.2 { FnKey(t: t - 15.9, glow: true).opacity(ramp(t, 15.9, 16.2) * (1 - ramp(t, 17.9, 18.2))) }
            if t >= 17.9 && t < 22.4 { desktop(firstPass: false).opacity(ramp(t, 17.9, 18.2) * (1 - ramp(t, 22.0, 22.4))) }
            if t >= 22.0 { endCard.opacity(ramp(t, 22.0, 22.6)) }
        }
        .frame(width: 720, height: 1280)
        .clipped()
    }

    private var opening: some View {
        ZStack(alignment: .top) {
            Desk(t: t, lidY: 300)
            ChatWindow(t: t, phase: .empty).scaleEffect(0.8).offset(y: 380)
            Text("Murmure").font(Glass.font(78, .heavy)).tracking(-2)
                .foregroundStyle(LinearGradient(colors: [Color(rgb: 236, 72, 153), Color(rgb: 139, 92, 246), Color(rgb: 59, 130, 246)], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Color(rgb: 139, 92, 246).opacity(0.8), radius: 18)
                .offset(y: 150)
        }
    }

    /// Notch label and glow per beat.
    private func notchState(_ local: Double, first: Bool) -> (String, Color) {
        if first {
            switch local {
            case ..<4.0: return ("Hands-free", Color(rgb: 180, 120, 255))
            case ..<5.0: return ("Writing it out", Color(rgb: 255, 170, 60))
            case ..<9.0: return ("Working", Color(rgb: 90, 150, 255))
            case ..<10.0: return ("Needs you", Color(rgb: 255, 150, 60))
            default: return ("In the bag", Color(rgb: 70, 220, 150))
            }
        }
        switch local {
        case ..<2.0: return ("Hands-free", Color(rgb: 180, 120, 255))
        case ..<2.8: return ("Writing it out", Color(rgb: 255, 170, 60))
        default: return ("In the bag", Color(rgb: 70, 220, 150))
        }
    }

    private func desktop(firstPass: Bool) -> some View {
        let local = firstPass ? t - 3.0 : t - 18.0
        let (label, glow) = notchState(local, first: firstPass)
        let phase: ChatWindow.Phase
        if firstPass {
            phase = local < 2 ? .typing(0) : local < 4 ? .typing(ramp(local, 2, 3.6)) : local < 5 ? .sent : local < 7 ? .working(ramp(local, 5, 7)) : local < 9 ? .approval : .done
        } else {
            phase = local < 0.6 ? .done : local < 2.8 ? .followUp(ramp(local, 0.6, 2.4)) : .doneAgain
        }
        let closeUp = firstPass ? ramp(local, 2.0, 2.4) * (1 - ramp(local, 3.8, 4.2)) : 0
        return ZStack(alignment: .top) {
            Desk(t: t, lidY: 190)
            NotchBody(width: 560, height: 72, glow: glow).offset(y: 190)
            HStack {
                Text(label).font(Glass.font(17, .semibold)).foregroundStyle(glow)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        Capsule().fill(glow.opacity(0.8)).frame(width: 2, height: 4 + 10 * abs(sin(t * 7 + Double(i))))
                    }
                }
            }
            .frame(width: 480).offset(y: 216)
            ChatWindow(t: t, phase: phase)
                .scaleEffect(mix(0.92, 1.9, closeUp), anchor: UnitPoint(x: 0.6, y: 0.45))
                .offset(y: 330)
        }
    }

    private var endCard: some View {
        VStack(spacing: 22) {
            FilmMascot(pose: .welcome, t: t, size: 150, since: 22.0)
            Text("Zeus").font(Glass.font(92, .heavy)).tracking(-3).foregroundStyle(.white)
            VStack(spacing: 4) {
                Text("Light-Powered").font(Glass.font(34, .bold)).foregroundStyle(Color(rgb: 96, 160, 248))
                Text("Notch for Mac").font(Glass.font(34, .bold)).foregroundStyle(.white)
            }
        }
        .scaleEffect(mix(0.94, 1, ramp(t, 22.0, 23.0)))
    }
}

/// Dictation key close-up (a mic key, so it fits whichever key is bound), pressed half a second in.
private struct FnKey: View {
    let t: Double
    let glow: Bool
    var body: some View {
        let press = ramp(t, 0.5, 0.65) * (1 - ramp(t, 1.7, 1.85))
        ZStack {
            LinearGradient(colors: [Color(rgb: 244, 245, 247), Color(rgb: 196, 199, 205)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(rgb: 22, 23, 26))
                .frame(width: 640, height: 600).offset(x: 0, y: 90).blur(radius: 1)
            VStack(alignment: .leading, spacing: 18) {
                key("shift", width: 330).offset(x: 0)
                HStack(spacing: 18) {
                    key("mic.fill", width: 190, symbol: true).offset(y: CGFloat(press) * 4).scaleEffect(1 - 0.03 * press)
                        .overlay {
                            if glow {
                                RoundedRectangle(cornerRadius: 18).stroke(Color(rgb: 120, 180, 255), lineWidth: 3)
                                    .blur(radius: 3).opacity(press)
                            }
                        }
                    key("control", width: 190)
                }
            }
            // Centred in the 720 pt frame (398 x 318 at 1.45 is 577 wide): the keys never touch the card edge.
            .scaleEffect(1.45)
            .offset(x: 0, y: 90)
        }
        .scaleEffect(mix(1.0, 1.08, ramp(t, 0, 2)))
    }

    private func key(_ label: String, width: CGFloat, symbol: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(rgb: 46, 47, 52), Color(rgb: 30, 31, 35)], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: 150)
            .overlay(alignment: .bottomLeading) {
                Group {
                    if symbol { Image(systemName: label).font(.system(size: 30, weight: .medium)) } else { Text(label).font(.system(size: 30, weight: .medium)) }
                }
                .foregroundStyle(.white.opacity(0.85)).padding(22)
            }
    }
}

/// A generic agent chat app (not any vendor's), in the states the film walks through.
private struct ChatWindow: View {
    enum Phase { case empty, typing(Double), sent, working(Double), approval, done, followUp(Double), doneAgain }
    let t: Double
    let phase: Phase

    static let request = "Add dark mode to the settings page"
    static let followUp = "Now add a toggle in the menu bar"

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) { ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 10, height: 10) } }
                Text("Agent").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(.white).padding(.top, 8)
                Label("New chat", systemImage: "plus.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                Group { Text("Chats"); Text("Projects") }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Text("Recents").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).padding(.top, 6)
                Group { Text("Dark mode for settings"); Text("Notch halo tuning"); Text("Release notes 1.0") }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(14).frame(width: 170, alignment: .leading)
            .background(Color(rgb: 30, 30, 32))
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(rgb: 38, 38, 40))
        }
        .frame(width: 640, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .empty, .typing:
            Spacer()
            Text("Good evening").font(.system(size: 30, design: .serif)).foregroundStyle(.white).frame(maxWidth: .infinity)
            field(typed: typedPrefix, glow: true)
            Spacer()
        case .sent, .working, .approval, .done:
            bubble(Self.request)
            Text("I'll add a dark theme to the settings page.").font(.system(size: 13)).foregroundStyle(.white)
            step("Read", "src/app/settings/page.tsx", visible: progress > 0.2)
            step("Edit", "src/app/settings/page.tsx  +42 -3", visible: progress > 0.6)
            if case .approval = phase { approvalCard }
            if case .done = phase { doneLines }
            Spacer()
            field(typed: "", glow: false)
        case .followUp(let f):
            bubble(Self.request)
            doneLines
            Spacer()
            field(typed: String(Self.followUp.prefix(Int(Double(Self.followUp.count) * f))), glow: true)
        case .doneAgain:
            bubble(Self.request)
            doneLines
            bubble(Self.followUp)
            Text("Adding a menu bar toggle\u{2026}").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            field(typed: "", glow: false)
        }
    }

    private var typedPrefix: String {
        if case .typing(let f) = phase { return String(Self.request.prefix(Int(Double(Self.request.count) * f))) }
        return ""
    }

    private var progress: Double {
        switch phase { case .working(let f): f; case .sent: 0; default: 1 }
    }

    private var doneLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\u{2713} Allowed from Zeus \u{00B7} npm run build").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
            Text("\u{2713} Build passed. Dark mode is live in Settings, 3 files changed, all tests pass.")
                .font(.system(size: 13)).foregroundStyle(Color(rgb: 120, 220, 150))
        }
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow the agent to run this command?").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text("$ npm run build").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.4)))
            HStack { Spacer(); Text("Deny"); Text("Always allow"); Text("Allow once").foregroundStyle(.black).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.white)) }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(rgb: 255, 150, 60).opacity(0.7), lineWidth: 1))
    }

    private func bubble(_ text: String) -> some View {
        HStack { Spacer(); Text(text).font(.system(size: 13)).foregroundStyle(.white).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 20, 20, 22))) }
    }

    private func step(_ verb: String, _ path: String, visible: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(rgb: 120, 220, 150)).frame(width: 6, height: 6)
            Text(verb).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(path).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
        }
        .opacity(visible ? 1 : 0)
    }

    private func field(typed: String, glow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(typed.isEmpty ? "How can I help you today?" : typed)
                .font(.system(size: 15)).foregroundStyle(typed.isEmpty ? .white.opacity(0.45) : .white)
            HStack(spacing: 8) {
                ForEach(["plus", "slider.horizontal.3", "clock"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24).overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15)))
                }
                Spacer()
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7).fill(Color(rgb: 74, 120, 230)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(rgb: 48, 48, 50)))
        .shadow(color: glow ? Color(rgb: 255, 140, 60).opacity(0.55) : .clear, radius: 18)
    }
}

// MARK: Offline renderer

/// `Zeus --render-film running|murmure <dir>`: writes every frame as PNG (frame-00001.png ...)
/// at the film's pixel size, then exits. The script encodes them with ffmpeg.
@MainActor
enum FilmRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-film"), flag + 2 < arguments.count,
              let film = OnboardingFilm.allCases.first(where: { $0.rawValue.hasSuffix(arguments[flag + 1]) }) else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 2])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        GlassFonts.register()
        for index in 0..<film.frameCount {
            let renderer = ImageRenderer(content: film.scene(Double(index) / film.fps).frame(width: film.size.width, height: film.size.height))
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: directory.appendingPathComponent(String(format: "frame-%05d.png", index + 1)))
        }
        print("rendered \(film.frameCount) frames of \(film.rawValue) to \(directory.path)")
        return true
    }
}
