import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// The saved-source route has no permission or capture action. Its live implementation refuses
/// to replace an active Scribe session; an isolated Memory window can supply an inert navigator.
enum WikiMeetingNavigationOutcome: Equatable {
    case opened, busy, panelUnavailable, unavailable
}

/// Owns the Memory (learning wiki) window and its content state; native keyboard focus stays in the view.
/// Pages are learned only from saved Scribe meetings (decisions and action items,
/// never private notes), only while learning is not paused, and only into the `personal` scope.
@MainActor
@Observable
final class WikiController {
    static let shared = WikiController()

    private(set) var pages: [WikiPage] = []
    private(set) var learningPaused = false
    /// Latest status or error line, until dismissed. Also announced to VoiceOver.
    private(set) var notice: String?
    /// Why saved pages or settings couldn't be read (never silent), until dismissed.
    private(set) var loadIssues: [String] = []
    private(set) var meetingTitles: [UUID: String] = [:]
    private(set) var availableMeetingIDs: Set<UUID> = []
    private var dismissedMeetingIDs: Set<UUID> = []
    var query = ""
    private(set) var selectedID: String?
    /// The editor's text. Written to disk shortly after typing pauses, and when the selection changes.
    private(set) var draftBody = ""
    private(set) var promotionOpen = false
    private(set) var promotionFindings: [SensitiveFinding] = []
    private(set) var promotionAcknowledged: Set<String> = []
    var confirmingDelete = false
    private(set) var pendingForget: UUID?
    /// True while the settings file can't be read. Learning stays off until the person confirms a reset;
    /// deleting and forgetting keep working meanwhile.
    private(set) var settingsUnreadable = false
    var confirmingResetSettings = false
    var vaultExport: WikiMCPExportModel?
    var graphOpen = false
    var graphShowsList = false
    var graphQuery = ""
    var graphFilter: WikiGraphFilter = .all
    var graphRelationID: String?

    @ObservationIgnored private let store: WikiStore
    @ObservationIgnored private let meetings: ScribeMeetingStore
    @ObservationIgnored private let userName: () -> String
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let cancelledMeetingIDs: () -> Set<UUID>
    @ObservationIgnored private let navigateToMeeting: @MainActor (UUID) -> WikiMeetingNavigationOutcome
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private var forgotten: Set<UUID> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Failed page saves and deletes, kept as explicit intents and retried on every refresh until they commit.
    /// `pages` always shows the effective list: these intents already applied.
    @ObservationIgnored private var pending = WikiPendingWrites()
    @ObservationIgnored private var stampChecked = false
    @ObservationIgnored private var lastStamp: Date?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var windowDelegate: WikiWindowDelegate?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    /// `userName` is the macOS user short name recorded when a page is promoted.
    init(
        store: WikiStore = .standard,
        meetings: ScribeMeetingStore = .standard,
        userName: @escaping () -> String = { NSUserName() },
        clock: @escaping () -> Date = { Date() },
        cancelledMeetingIDs: @escaping () -> Set<UUID> = { ScribeCancelTombstones.ids },
        navigateToMeeting: @escaping @MainActor (UUID) -> WikiMeetingNavigationOutcome = WikiController.openSavedMeeting,
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.store = store
        self.meetings = meetings
        self.userName = userName
        self.clock = clock
        self.cancelledMeetingIDs = cancelledMeetingIDs
        self.navigateToMeeting = navigateToMeeting
        self.announce = announce
        reload()
        // An edit typed in the last 600 ms is written on Cmd-Q, not lost with the debounce.
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushEdit() }
        }
    }

    // MARK: Derived

    var visiblePages: [WikiPage] { WikiSearch.filter(pages, query: query) }

    var selectedPage: WikiPage? {
        guard let selectedID else { return nil }
        return pages.first { $0.id == selectedID }
    }

    /// One row per distinct item to acknowledge (the same item twice is one decision).
    var promotionItems: [SensitiveFinding] {
        var seen = Set<String>()
        return promotionFindings.filter { seen.insert($0.acknowledgementKey).inserted }
    }

    var allFindingsAcknowledged: Bool {
        promotionItems.allSatisfy { promotionAcknowledged.contains($0.acknowledgementKey) }
    }

    func title(forMeeting id: UUID) -> String {
        if cancelledMeetingIDs().contains(id) { return "Cancelled meeting" }
        if forgotten.contains(id) || selectedPage?.forgottenContributors.contains(id) == true {
            return "Forgotten meeting"
        }
        return meetingTitles[id] ?? "Saved meeting unavailable"
    }

    var relatedPages: [WikiRelatedPage] {
        guard !settingsUnreadable, let selectedID else { return [] }
        return WikiRelationships.related(to: selectedID, in: pages,
                                         availableMeetingIDs: availableMeetingIDs,
                                         excluding: forgotten.union(cancelledMeetingIDs()))
    }

    func selectRelated(_ id: String) {
        guard relatedPages.contains(where: { $0.pageID == id }) else { return }
        query = ""
        select(id)
    }

    var graphSnapshot: WikiGraphSnapshot {
        guard !settingsUnreadable else { return .make(focus: nil, relationships: []) }
        return .make(focus: selectedPage, relationships: relatedPages, filter: graphFilter, query: graphQuery)
    }

    var hasGraphFilters: Bool {
        graphFilter != .all || !graphQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var graphFilterDescription: String {
        let search = graphQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return graphFilter.title + (search.isEmpty ? "" : " · Search: “\(search)”")
    }

    func resetGraphFilters() {
        graphQuery = ""
        graphFilter = .all
        graphRelationID = nil
    }

    func openGraph() {
        guard vaultExport == nil else { return }
        refreshFromMeetings(force: true) // Explicit navigation refreshes saved-source availability.
        resetGraphFilters()
        graphOpen = true
    }

    func selectGraphPage(_ id: String) {
        let previous = selectedID
        selectRelated(id) // Rechecks current evidence and flushes the editor before navigating.
        if selectedID != previous { graphRelationID = nil; graphQuery = "" }
    }

    /// A visible explanation, not a guessed replacement for an unavailable original source.
    func meetingSourceIssue(_ id: UUID) -> String? {
        if settingsUnreadable { return "Source access is unavailable until Memory's settings are recovered." }
        if forgotten.contains(id) || selectedPage?.forgottenContributors.contains(id) == true {
            return "This source was forgotten."
        }
        if cancelledMeetingIDs().contains(id) { return "This meeting was cancelled." }
        if dismissedMeetingIDs.contains(id) { return "This source was removed from the Meetings list." }
        if !availableMeetingIDs.contains(id) { return "This saved source is missing or could not be read." }
        return nil
    }

    func openMeetingSource(_ id: UUID) {
        guard selectedPage?.sources.contains(.meeting(id)) == true else {
            setNotice("This meeting is no longer a source of the selected page.")
            return
        }
        // Recheck the durable forget journal without reloading pages or replacing the editor's draft.
        let recovered = store.loadStateRecovering()
        forgotten.formUnion(recovered.state.forgottenMeetings)
        guard recovered.error == nil else {
            settingsUnreadable = true
            learningPaused = true
            setNotice("Source access is unavailable because Memory's settings couldn't be read. Your edits are still here.")
            return
        }
        if let issue = meetingSourceIssue(id) { setNotice(issue); return }
        // Re-read the original before navigation: the visible source list may outlive a deletion,
        // dismissal or unreadable file. Never recreate a missing recap or un-dismiss one.
        let matches = meetings.loadAll().records.filter { $0.id == id }
        guard matches.count == 1, let saved = matches.first else {
            availableMeetingIDs.remove(id)
            meetingTitles.removeValue(forKey: id)
            setNotice("This saved source is missing, ambiguous, or could not be read.")
            return
        }
        guard saved.dismissedAt == nil else {
            availableMeetingIDs.remove(id)
            dismissedMeetingIDs.insert(id)
            setNotice("This source was removed from the Meetings list.")
            return
        }
        // Commit the editor before crossing the navigation boundary, including a refused route.
        // A failure keeps the current page and graph in place with an actionable explanation.
        flushEdit()
        switch navigateToMeeting(id) {
        case .opened: graphOpen = false
        case .busy:
            setNotice("Finish the current recording and notes before opening a saved meeting. Your session is still running.")
        case .panelUnavailable: setNotice("The Meetings panel isn't available right now.")
        case .unavailable: setNotice("This source is no longer available in Meetings.")
        }
    }

    private static func openSavedMeeting(_ id: UUID) -> WikiMeetingNavigationOutcome {
        let scribe = ScribeController.shared
        guard !scribe.phase.isActive else { return .busy }
        guard let panel = NotchControllerBridge.controller, let topBar = panel.topBar else { return .panelUnavailable }
        guard scribe.openRecap(ScribeSessionID(rawValue: id)) else { return .unavailable }
        topBar.selectedTab = .scribe
        panel.show(.panel)
        return .opened
    }

    // MARK: Loading

    /// Reads pages and settings from disk. Unreadable settings pause learning (fail closed) and say so, but the
    /// forgotten meetings that can still be read (and any forgotten since) stay honored, and deleted or
    /// forgotten meetings are still removed from the pages. Learning only resumes after `resetSettings`.
    func reload() {
        var issues: [String] = []
        let loaded = store.loadPages()
        pages = pending.overlaying(loaded.pages)
        issues.append(contentsOf: loaded.failures)
        let recovered = store.loadStateRecovering()
        learningPaused = recovered.state.learningPaused
        if let error = recovered.error {
            settingsUnreadable = true
            forgotten.formUnion(recovered.state.forgottenMeetings)
            issues.append("Learning is paused because Memory's settings couldn't be read, and the list of forgotten meetings may be incomplete. Reset the settings to continue. \(error)")
        } else {
            settingsUnreadable = false
            forgotten = Set(recovered.state.forgottenMeetings)
        }
        loadIssues = issues
        if selectedPage == nil { select(WikiSearch.ordered(pages).first?.id) }
    }

    /// Learns from saved meetings when the meetings folder changed since the last look (or `force`).
    /// Pausing only stops new learning: deleted and forgotten meetings are still removed from the pages.
    /// Meeting files are only read, never written. Writes that failed before are retried on every refresh.
    func refreshFromMeetings(force: Bool = false) {
        flushEdit()
        let stamp = meetingsStamp()
        if !force, pending.isEmpty, stampChecked, stamp == lastStamp { return }
        stampChecked = true
        lastStamp = stamp
        let result = meetings.loadAll()
        let cancelled = cancelledMeetingIDs()
        meetingTitles = Dictionary(result.records.filter { !cancelled.contains($0.id) }.map { ($0.id, $0.title) },
                                   uniquingKeysWith: { first, _ in first })
        dismissedMeetingIDs = Set(result.records.filter { $0.dismissedAt != nil }.map(\.id))
        availableMeetingIDs = Set(result.records.filter { $0.dismissedAt == nil }.map(\.id))
            .subtracting(forgotten).subtracting(cancelled)
        invalidateUnavailableExportSources()
        let removeMissing = WikiCompiler.mayRemoveMissing(
            recordCount: result.records.count,
            failureCount: result.failures.count,
            folderExists: FileManager.default.fileExists(atPath: meetings.directory.path)
        )
        let hasMeetingFacts = pages.contains { page in page.sources.contains { $0.meetingID != nil } }
        let reconciled = WikiCompiler.reconcile(
            meetings: result.records,
            into: pages,
            excluding: forgotten.union(cancelled),
            removeMissing: removeMissing,
            ingest: !learningPaused,
            now: clock()
        )
        let compiled = reconciled.pages
        let demoted = compiled.filter { page in
            page.scope == .personal && pages.contains { $0.id == page.id && $0.scope == .global }
        }
        let flagged = newlyFlagged(from: pages, to: compiled)
        // Applying also retries every pending intent, whatever the compilation produced.
        guard apply(compiled) else { return }
        if !result.failures.isEmpty {
            setNotice("Couldn't read \(result.failures.count) saved meeting(s), so nothing was removed from Memory for them.")
        } else if !removeMissing && result.records.isEmpty && hasMeetingFacts {
            setNotice("No saved meetings were found, so nothing was removed from Memory.")
        } else if flagged > 0 {
            setNotice(reviewNote(flagged) + (reconciled.editedLinesRemoved > 0 ? " " + editedLinesNote(reconciled.editedLinesRemoved) : ""))
        } else if reconciled.editedLinesRemoved > 0 {
            setNotice(editedLinesNote(reconciled.editedLinesRemoved))
        } else if !demoted.isEmpty {
            let names = demoted.map { "“\($0.title)”" }.joined(separator: ", ")
            setNotice("New items were added to \(names), so it is personal again. Promote it again to re-run the sensitive-info check.")
        }
    }

    private func meetingsStamp() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: meetings.directory.path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: Selection and editing

    func select(_ id: String?) {
        flushEdit()
        // A save that failed earlier is tried again here; its page stays shown as edited until it commits.
        if !pending.isEmpty { _ = pending.retry(using: store) }
        selectedID = id
        draftBody = selectedPage?.body ?? ""
        closePromotion()
        confirmingDelete = false
    }

    func setDraftBody(_ text: String) {
        draftBody = text
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushEdit()
        }
    }

    /// Writes the editor's text now. Editing a global page makes it personal again (it must be checked again).
    func flushEdit() {
        saveTask?.cancel()
        saveTask = nil
        guard let id = selectedID,
              let index = pages.firstIndex(where: { $0.id == id }),
              pages[index].body != draftBody else { return }
        var page = pages[index]
        let demoted = page.applyEdit(body: draftBody, now: clock())
        // The edit is the page's effective value from now on, saved or not. A failed save stays pending.
        pages[index] = page
        if demoted { closePromotion() }
        if let failure = pending.commit(page, using: store) {
            setNotice("Couldn't save your edit. It is kept and will be retried: \(failure)")
        } else if demoted {
            setNotice("You edited a global page, so it is personal again. Promote it again to re-run the sensitive-info check.")
        }
    }

    func togglePin(_ id: String) {
        flushEdit()
        update(id) { $0.pinned.toggle() }
    }

    /// Applies `change` to the page as its effective value and commits it. On failure the value is kept and
    /// retried. Returns true when the page is on disk.
    @discardableResult
    private func update(_ id: String, _ change: (inout WikiPage) -> Void) -> Bool {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return false }
        var page = pages[index]
        change(&page)
        pages[index] = page
        if let failure = pending.commit(page, using: store) {
            setNotice("Couldn't save “\(page.title)”. The change is kept and will be retried: \(failure)")
            return false
        }
        return true
    }

    /// The person has read a page flagged for review. Export and promotion unlock.
    func markReviewed() {
        flushEdit()
        guard let page = selectedPage, page.needsReview else { return }
        if update(page.id, { $0.clearReview(now: clock()) }) {
            setNotice("“\(page.title)” is marked as reviewed.")
        }
    }

    // MARK: Learning controls

    func setLearningPaused(_ paused: Bool) {
        guard !settingsUnreadable else {
            setNotice("Memory's settings couldn't be read, so learning stays paused. Reset the settings first.")
            return
        }
        do {
            let state = try store.setLearningPaused(paused)
            learningPaused = state.learningPaused
            setNotice(paused ? "Learning is paused. Zeus won't add anything new to Memory." : "Learning resumed.")
        } catch {
            setNotice("Couldn't change the learning setting: \(error.localizedDescription)")
            return
        }
        if !paused { refreshFromMeetings(force: true) }
    }

    func requestReset() { confirmingResetSettings = true }

    /// After the person confirmed: replaces the unreadable settings with defaults (the old file is kept beside
    /// it) and resumes learning. Every forgotten meeting that is known is carried over.
    func resetSettings() {
        confirmingResetSettings = false
        guard settingsUnreadable else { return }
        do {
            let state = try store.resetState(forgetting: Array(forgotten), now: clock())
            forgotten = Set(state.forgottenMeetings)
        } catch {
            // Still unreadable on disk, so learning stays paused and the issue stays shown until a reset works.
            settingsUnreadable = true
            learningPaused = true
            setNotice("Couldn't reset Memory's settings, so learning stays paused: \(error.localizedDescription)")
            return
        }
        flushEdit()
        reload()
        setNotice("Memory's settings were reset. Learning is on. The unreadable file was kept next to it.")
        refreshFromMeetings(force: true)
    }

    /// Records forgotten meetings in the durable forget journal (separate from the settings, flushed to disk)
    /// before anything is removed or announced, so a failed write can't bring one back. This works even while
    /// the settings are unreadable. Returns false (and says why) when the record couldn't be kept.
    private func recordForgotten(_ ids: [UUID], failure: String) -> Bool {
        do {
            if try exportJournal.invalidate(forgetting: Set(ids)) { vaultExport?.invalidate() }
            let state = try store.forget(meetings: ids)
            forgotten.formUnion(state.forgottenMeetings)
            forgotten.formUnion(ids)
            return true
        } catch {
            setNotice("\(failure): \(error.localizedDescription)")
            return false
        }
    }

    /// Removes everything learned from one meeting and never learns from it again.
    func requestForget(_ id: UUID) { pendingForget = id }

    func cancelForget() { pendingForget = nil }

    func confirmForget() {
        guard let id = pendingForget else { return }
        pendingForget = nil
        forgetMeeting(id)
    }

    func forgetMeeting(_ id: UUID) {
        flushEdit()
        // Without the record the meeting would be learned again, so nothing is removed.
        guard recordForgotten([id], failure: "Couldn't record that this meeting was forgotten, so nothing was changed") else { return }
        let removal = WikiCompiler.removeSourceReporting(.meeting(id), from: pages, meetingTitle: meetingTitles[id], now: clock())
        // The forgotten set is saved, so a failed page write is finished by the next refresh.
        let flagged = newlyFlagged(from: pages, to: removal.pages)
        guard apply(removal.pages) else { return }
        var message = "Forgot everything from “\(title(forMeeting: id))”."
        if removal.editedLinesRemoved > 0 { message += " " + editedLinesNote(removal.editedLinesRemoved) }
        if flagged > 0 { message += " " + reviewNote(flagged) }
        setNotice(message)
    }

    private func newlyFlagged(from old: [WikiPage], to new: [WikiPage]) -> Int {
        let before = Set(old.filter(\.needsReview).map(\.id))
        return new.filter { $0.needsReview && !before.contains($0.id) }.count
    }

    private func reviewNote(_ count: Int) -> String {
        count == 1
            ? "1 page may still hold text from a forgotten meeting and needs your review before it can be exported or made global."
            : "\(count) pages may still hold text from a forgotten meeting and need your review before they can be exported or made global."
    }

    private func editedLinesNote(_ count: Int) -> String {
        count == 1
            ? "1 edited line from a forgotten meeting was removed."
            : "\(count) edited lines from forgotten meetings were removed."
    }

    /// Deletes the page and forgets the meetings behind it, so the next update doesn't rebuild it.
    func confirmDelete() {
        confirmingDelete = false
        guard let page = selectedPage else { return }
        saveTask?.cancel()
        saveTask = nil
        let ids = page.meetingIDs
        if !ids.isEmpty {
            guard recordForgotten(ids, failure: "Couldn't record the deletion, so nothing was changed") else { return }
        }
        var remaining = pages
        for id in ids { remaining = WikiCompiler.removeSource(.meeting(id), from: remaining, meetingTitle: meetingTitles[id], now: clock()) }
        remaining.removeAll { $0.id == page.id }
        guard apply(remaining) else { return }
        setNotice("Deleted “\(page.title)”.")
    }

    // MARK: Promotion

    func beginPromotion() {
        flushEdit()
        guard let page = selectedPage, page.scope == .personal else { return }
        guard !page.needsReview else {
            setNotice(WikiPromotionError.needsReview.localizedDescription)
            return
        }
        let findings = WikiPromotion.findings(for: page)
        if findings.isEmpty {
            completePromotion(page, acknowledged: [])
        } else {
            promotionFindings = findings
            promotionAcknowledged = []
            promotionOpen = true
        }
    }

    func setAcknowledged(_ key: String, _ acknowledged: Bool) {
        if acknowledged { promotionAcknowledged.insert(key) } else { promotionAcknowledged.remove(key) }
    }

    func confirmPromotion() {
        guard let page = selectedPage else { return }
        completePromotion(page, acknowledged: promotionAcknowledged)
    }

    func closePromotion() {
        promotionOpen = false
        promotionFindings = []
        promotionAcknowledged = []
    }

    private func completePromotion(_ page: WikiPage, acknowledged: Set<String>) {
        do {
            let promoted = try WikiPromotion.promote(page, promotedBy: userName(), acknowledged: acknowledged, now: clock())
            if let index = pages.firstIndex(where: { $0.id == promoted.id }) { pages[index] = promoted }
            closePromotion()
            if let failure = pending.commit(promoted, using: store) {
                setNotice("“\(promoted.title)” is global, but couldn't be saved yet. It is kept and will be retried: \(failure)")
            } else {
                setNotice("“\(promoted.title)” is now global, promoted by \(promoted.promotedBy ?? "you").")
            }
        } catch let error as WikiPromotionError {
            if case .blocked = error {
                promotionFindings = WikiPromotion.findings(for: page)
                promotionOpen = true
            }
            setNotice(error.localizedDescription)
        } catch {
            setNotice("Couldn't promote “\(page.title)”: \(error.localizedDescription)")
        }
    }

    func makePersonal() {
        flushEdit()
        guard let page = selectedPage, page.scope == .global else { return }
        if update(page.id, { $0 = WikiPromotion.demote($0) }) {
            setNotice("“\(page.title)” is personal again.")
        }
    }

    // MARK: Export

    private var exportJournal: WikiExportJournal {
        WikiExportJournal(file: store.root.appendingPathComponent("exports/recovery.json"))
    }

    func beginVaultExport() {
        do {
            let snapshot = try exportSnapshot()
            vaultExport = try WikiMCPExportModel(snapshot: snapshot, selectedID: selectedID, journal: exportJournal,
                current: { [weak self] in
                    guard let self else { throw WikiExportError.staleDraft }
                    return try self.exportSnapshot()
                })
        } catch { setNotice(error.localizedDescription) }
    }

    private func exportSnapshot() throws -> WikiExportSnapshot {
        flushEdit()
        let recovered = store.loadStateRecovering()
        forgotten.formUnion(recovered.state.forgottenMeetings)
        if recovered.error != nil { settingsUnreadable = true; learningPaused = true }
        refreshFromMeetings(force: true)
        return WikiExportSnapshot(pages: pages, connection: TodoController.shared.connection,
            availableMeetingIDs: availableMeetingIDs, forgottenMeetingIDs: forgotten.union(cancelledMeetingIDs()),
            sourceTitles: meetingTitles, settingsReadable: !settingsUnreadable && pending.isEmpty)
    }

    /// Recovered drafts never retain bytes from a forgotten, dismissed, cancelled or missing source.
    private func invalidateUnavailableExportSources() {
        do {
            guard var entry = try exportJournal.load(), entry.state == .uncertain, let draft = entry.draft else { return }
            let sourceIDs = Set(draft.pages.flatMap { $0.meetingIDs + $0.contributors + $0.facts.flatMap { $0.sources.compactMap(\.meetingID) } })
            guard settingsUnreadable || !sourceIDs.isSubset(of: availableMeetingIDs)
                || !sourceIDs.isDisjoint(with: forgotten.union(cancelledMeetingIDs())) else { return }
            entry.invalidate()
            try exportJournal.save(entry)
            vaultExport?.invalidate()
        } catch { setNotice("The export recovery record couldn't be updated: \(error.localizedDescription)") }
    }

    /// Writes one page to a Markdown file the person chooses. Only ever runs from the Export button.
    func exportSelected() {
        flushEdit()
        guard let page = selectedPage else { return }
        guard let markdown = page.exportedMarkdown() else {
            setNotice("“\(page.title)” needs your review before it can be exported. Read it, then choose “I've reviewed this”.")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export page"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(page.id).md"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            let flagged = WikiPromotion.findings(for: page).count
            let caution = flagged > 0 ? " It contains \(flagged) item(s) flagged as sensitive." : ""
            setNotice("Exported “\(page.title)” to \(url.lastPathComponent).\(caution)")
        } catch {
            setNotice("Couldn't export “\(page.title)”: \(error.localizedDescription)")
        }
    }

    // MARK: Notices

    func dismissNotice() { notice = nil }

    func dismissLoadIssues() { loadIssues = [] }

    private func setNotice(_ text: String) {
        notice = text
        announce(text)
    }

    // MARK: Persisting a new page list

    /// Stages `new` as explicit intents on top of any pending ones (a pending delete is never overwritten, and
    /// a pending save is only replaced by a value built from it), then tries every intent. An intent is cleared
    /// only when its commit succeeds; failed ones stay and are retried on every refresh, whether or not
    /// learning is paused or anything new compiled. `pages` shows the effective list. Returns true only when
    /// nothing is pending afterwards; on false a failure notice is already shown and the caller must not
    /// announce success.
    @discardableResult
    private func apply(_ new: [WikiPage]) -> Bool {
        let committed = pending.stage(replacing: pages, with: new)
        let failures = pending.retry(using: store)
        pages = committed
        if !failures.isEmpty {
            setNotice("Memory couldn't write everything to disk. Those changes are kept and will be retried: " + failures.joined(separator: " "))
        }
        if let id = selectedID, !committed.contains(where: { $0.id == id }) {
            select(WikiSearch.ordered(pages).first?.id)
        } else if let page = selectedPage, saveTask == nil {
            draftBody = page.body
        }
        return failures.isEmpty
    }

    // MARK: Window

    /// Only this controller's window, never a process-wide window search.
    var ownedWindow: NSWindow? { window }

    /// Ends this controller's lifetime without leaving a delayed edit or notification observer behind.
    /// Synthetic hosts call this before deleting their disposable stores.
    func shutdown() {
        flushEdit()
        window?.close()
        window = nil
        windowDelegate = nil
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
    }

    func showWindow() {
        if window == nil { window = makeWindow() }
        refreshFromMeetings()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let delegate = WikiWindowDelegate(
            onClose: { [weak self] in self?.flushEdit() },
            onBecomeKey: { [weak self] in self?.refreshFromMeetings() }
        )
        windowDelegate = delegate
        let controller = NSHostingController(rootView: WikiView(controller: self))
        let window = NSWindow(contentViewController: controller)
        window.title = "Memory"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentMinSize = NSSize(width: 700, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.setAccessibilityLabel("Memory")
        window.center()
        return window
    }
}

@MainActor
private final class WikiWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private let onBecomeKey: () -> Void

    init(onClose: @escaping () -> Void, onBecomeKey: @escaping () -> Void) {
        self.onClose = onClose
        self.onBecomeKey = onBecomeKey
    }

    func windowWillClose(_ notification: Notification) { onClose() }

    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey() }
}
