import Foundation

/// The pages of the expanded notch. People choose which ones show and in what order.
public enum TopBarTab: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, today, agents, chat, notifications, music, calendar, todo, reminders, weather, clipboard, shelf, focus, dictation, teleprompter, insomnia, polyglot, recordly, scribe, usage
    /// Appended last on purpose: not in `standard` or the default row. Switch it on in Settings › Beamer.
    case continuity
    /// Appended last, off by default: the live audio spectrum. Switch it on in Settings › Top Bar.
    case waves

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .agents: "Agents"
        case .music: "Music"
        case .calendar: "Calendar"
        case .todo: "To-do"
        case .weather: "Weather"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .focus: "Focus"
        case .dictation: "Murmure"
        case .teleprompter: "Prompter"
        case .chat: "Chat"
        case .today: "Today"
        case .notifications: "Alerts"
        case .reminders: "Reminders"
        case .usage: "Usage"
        case .insomnia: "Insomnia"
        case .continuity: "Continuity"
        case .waves: "Waves"
        case .polyglot: "Polyglot"
        case .recordly: "Recordly"
        case .scribe: "Scribe"
        }
    }

    /// Tooltip and VoiceOver name: the title, plus what the less obvious tabs do.
    public var help: String {
        switch self {
        case .insomnia: "Insomnia — keep working with the lid closed"
        case .continuity: "Continuity — your keyboard and mouse across Macs and PCs (Beamer)"
        case .polyglot: "Polyglot — live translated captions"
        case .scribe: "Scribe — listens to a meeting and writes your notes"
        default: title
        }
    }

    /// SF Symbol name. Filled / rounder marks match Glance 0.3.1 live tab glyphs (parity/tabs).
    public var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .agents: "bolt.fill"
        case .music: "music.note"
        case .calendar: "calendar"
        case .todo: "checklist"
        case .weather: "cloud.sun.fill"
        case .clipboard: "list.clipboard.fill"
        case .shelf: "tray.fill"
        case .focus: "timer"
        case .dictation: "water.waves"
        case .teleprompter: "text.alignleft"
        case .chat: "bubble.left.fill"
        case .today: "sun.horizon.fill"
        case .notifications: "bell.fill"
        case .reminders: "checklist"
        case .usage: "gauge.with.dots.needle.67percent"
        case .insomnia: "moon.zzz.fill"
        case .continuity: "rectangle.connected.to.line.below"
        case .waves: "waveform"
        case .polyglot: "globe"
        case .recordly: "record.circle"
        case .scribe: "waveform.and.mic"
        }
    }
}

/// Which tabs show in the header, in order. Home always comes first; unknown or repeated
/// entries are dropped so a hand-edited or older value can never break the bar.
public struct TopBarLayout: Codable, Equatable, Sendable {
    public var tabs: [TopBarTab]

    /// Glance's seven, as the live app labels them when selected (glance-clone-proof/parity/tabs):
    /// Home, Chat, Alerts, Clipboard, Shelf, then Zeus To-do and Murmure.
    public static let glanceSeven: [TopBarTab] = [.home, .chat, .notifications, .clipboard, .shelf, .todo, .dictation]
    /// The row Tony asked for: Glance's seven, then Teleprompter, Insomnia and Polyglot. The row shows
    /// these ten, then Recordly and Scribe; the rest stay one click away in Settings › Top Bar.
    public static let defaultRow: [TopBarTab] = glanceSeven + [.teleprompter, .insomnia, .polyglot, .recordly, .scribe]
    public static let standard = TopBarLayout(tabs: defaultRow + [.reminders, .today, .agents, .music, .calendar, .focus, .usage])

    /// A saved layout with Glance's seven moved to the front (in Glance's order), every other
    /// tab kept in its order after them. Tabs the person turned off stay off.
    public func glanceOrdered() -> TopBarLayout { ordered(first: Self.glanceSeven) }

    /// A saved layout with the default row in front, in its order; tabs turned off stay off.
    public func defaultRowOrdered() -> TopBarLayout { ordered(first: Self.defaultRow) }

    /// The one-time upgrade to the nine-tab row: Teleprompter and Insomnia switched on (Tony asked
    /// for both), the default row in front. Other tabs the person turned off stay off.
    public func upgradedToNineTabRow() -> TopBarLayout {
        TopBarLayout(tabs: tabs + [.teleprompter, .insomnia].filter { !tabs.contains($0) }).defaultRowOrdered()
    }

    /// The one-time upgrade to the ten-tab row: Polyglot switched on after Insomnia (Tony asked for
    /// it), the default row in front. Other tabs the person turned off stay off.
    public func upgradedToTenTabRow() -> TopBarLayout {
        TopBarLayout(tabs: tabs + [.polyglot].filter { !tabs.contains($0) }).defaultRowOrdered()
    }

    /// One-time upgrade: Recordly joins the default row after Polyglot.
    public func upgradedToRecordlyRow() -> TopBarLayout {
        TopBarLayout(tabs: tabs + [.recordly].filter { !tabs.contains($0) }).defaultRowOrdered()
    }

    /// One-time upgrade: Scribe joins the default row after Recordly.
    public func upgradedToScribeRow() -> TopBarLayout {
        TopBarLayout(tabs: tabs + [.scribe].filter { !tabs.contains($0) }).defaultRowOrdered()
    }

    private func ordered(first order: [TopBarTab]) -> TopBarLayout {
        let first = order.filter { tabs.contains($0) }
        return TopBarLayout(tabs: first + tabs.filter { !first.contains($0) })
    }

    public init(tabs: [TopBarTab]) {
        var seen = Set<TopBarTab>([.home])
        self.tabs = [.home] + tabs.filter { seen.insert($0).inserted }
    }

    public func contains(_ tab: TopBarTab) -> Bool { tabs.contains(tab) }

    public mutating func toggle(_ tab: TopBarTab) {
        guard tab != .home else { return }
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
        } else {
            // Keep the canonical order when a tab comes back.
            let order = TopBarTab.allCases
            let position = tabs.firstIndex { order.firstIndex(of: $0)! > order.firstIndex(of: tab)! } ?? tabs.endIndex
            tabs.insert(tab, at: position)
        }
    }

    public mutating func move(_ tab: TopBarTab, by offset: Int) {
        guard tab != .home, let index = tabs.firstIndex(of: tab) else { return }
        let target = min(max(index + offset, 1), tabs.count - 1)
        tabs.remove(at: index)
        tabs.insert(tab, at: target)
    }

    // MARK: Inline editor (the notch's customise mode)

    /// Every tab this build has, in case order, with whether it is in the row: the editor lists these generically,
    /// so a case added later (at the end of `TopBarTab`) shows up with no editor change.
    public var editorEntries: [(tab: TopBarTab, isOn: Bool)] { TopBarTab.allCases.map { ($0, contains($0)) } }

    /// The row has room for `GlanceTopBar.maxTabs`; a saved layout may list more (they never show). The editor
    /// starts from what shows, so removing a tab never makes a hidden one appear by surprise.
    public func trimmedToRow(max: Int = GlanceTopBar.maxTabs) -> TopBarLayout { TopBarLayout(tabs: Array(tabs.prefix(max))) }

    public func isFull(max: Int = GlanceTopBar.maxTabs) -> Bool { tabs.count >= max }

    /// Tabs that are not in the row, for the editor's "add" list.
    public var removedTabs: [TopBarTab] { TopBarTab.allCases.filter { !contains($0) } }

    /// Drops `tab` onto `target`'s place (a drag): it takes that index, so the one it passed shifts over.
    /// Home stays first and cannot move or be passed.
    public mutating func reorder(_ tab: TopBarTab, onto target: TopBarTab) {
        guard tab != .home, target != tab, let from = tabs.firstIndex(of: tab), let place = tabs.firstIndex(of: target) else { return }
        tabs.remove(at: from)
        tabs.insert(tab, at: max(1, place))
    }

    /// Drops `tab` at the end of the row.
    public mutating func moveToEnd(_ tab: TopBarTab) {
        guard tab != .home, let from = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: from)
        tabs.append(tab)
    }

    /// Adds `tab` at the end of the row (the editor's "+"), unless it is already there.
    public mutating func append(_ tab: TopBarTab, max: Int = GlanceTopBar.maxTabs) {
        guard !contains(tab), !isFull(max: max) else { return }
        tabs.append(tab)
    }

    /// Takes `tab` out of the row; Home stays.
    public mutating func remove(_ tab: TopBarTab) {
        guard tab != .home else { return }
        tabs.removeAll { $0 == tab }
    }

    public func encoded() -> String {
        (try? String(data: JSONEncoder().encode(tabs.map(\.rawValue)), encoding: .utf8)) ?? ""
    }

    /// Every tab this build knows, saved next to the layout so a later build can tell a tab the
    /// person turned off from one that did not exist yet.
    public static func knownEncoded() -> String {
        (try? String(data: JSONEncoder().encode(TopBarTab.allCases.map(\.rawValue)), encoding: .utf8)) ?? ""
    }

    /// No saved-layout trap: a layout saved before `known` existed shows every standard tab, and
    /// tabs added since the last save are switched on in their usual place.
    public static func decode(_ string: String?, known: String?) -> TopBarLayout {
        guard string != nil else { return .standard }
        guard let data = known?.data(using: .utf8), let knownRaw = try? JSONDecoder().decode([String].self, from: data) else {
            return .standard
        }
        var layout = decode(string)
        let knownSet = Set(knownRaw)
        for tab in standard.tabs where !knownSet.contains(tab.rawValue) && !layout.contains(tab) { layout.toggle(tab) }
        return layout
    }

    public static func decode(_ string: String?) -> TopBarLayout {
        guard let data = string?.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else { return .standard }
        return TopBarLayout(tabs: raw.compactMap(TopBarTab.init(rawValue:)))
    }
}

/// Small events that light up the closed notch for a moment ("every move, made visible").
public enum NotchCue: Equatable, Sendable {
    case copied(String)
    case capsLock(Bool)
    case volume(Double, muted: Bool)
    case charging(Int)
    case lowBattery(Int)
    case trackChanged(title: String, artist: String)
    case shelfAdded(Int)
    case focusFinished(String)
    case dictation(String)
    /// A usage limit is getting close ("Claude Code 5h at 82%").
    case usageAlert(String)
    case brightness(Double)
    case keyboardBacklight(Double)
    case shortcut(ShortcutPeek)
    case rain(minutes: Int)
    /// A command was understood; `engine` is the badge (Rules, Laya, Jev, Ollama).
    case decided(engine: String, summary: String)
    /// A feature needs a permission that is off: where to turn it on (never a system prompt).
    case hint(String)
    /// A privacy permission is refused: what to say, and the System Settings pane that fixes it (a button).
    case permission(String, pane: String)
    /// A keep-awake session notice ("Battery 20%", "Ended: Mac too hot").
    case keepAwake(String)
    case screenshot(title: String)

    /// How long the cue stays before the notch settles again.
    public var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardBacklight: SystemHUDMath.holdAfterChange + SystemHUDMath.easeOut
        case .capsLock: 1.2
        case .copied: 1.6
        case .trackChanged: 3.0
        case .focusFinished: 4.0
        case .usageAlert: 4.0
        case .shortcut: 1.0
        case .rain: 6.0
        case .hint: 3.5
        case .permission: 9.0
        case .keepAwake: 4.0
        case .screenshot: 2.5
        default: 2.2
        }
    }
}
