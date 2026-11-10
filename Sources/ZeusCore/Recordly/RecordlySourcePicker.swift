import Foundation

/// Loads a synthetic-friendly catalog. The production implementation lives in
/// the app target; tests provide deterministic catalogs without ScreenCaptureKit.
public protocol RecordlySourceCatalogProvider: Sendable {
    func loadCatalog() async -> RecordlySourceCatalogLoadResult
}

public enum RecordlySourceCatalogLoadResult: Equatable, Sendable {
    case loaded(RecordlySourceSelection.CatalogSnapshot)
    case denied(reason: String)
    case failed(reason: String)
}

/// Pure picker state and identity gate shared by Recordly UI code and tests.
public struct RecordlySourcePicker: Sendable {
    public typealias CatalogSnapshot = RecordlySourceSelection.CatalogSnapshot
    public typealias SelectionIntent = RecordlySourceSelection.SelectionIntent
    public typealias ResolvedSource = RecordlySourceSelection.ResolvedSource

    public enum State: Equatable, Sendable {
        case notLoaded
        case loading(generation: UInt64)
        case loaded(snapshot: CatalogSnapshot, generation: UInt64)
        case stale(snapshot: CatalogSnapshot?, generation: UInt64?, reason: String)
        case denied(reason: String)
        case failed(reason: String)
    }

    public enum SelectionOutcome: Equatable, Sendable {
        case selected(ResolvedSource)
        case rejected(reason: String)
        case stale(reason: String)
        case catalogUnavailable
    }

    public private(set) var state: State = .notLoaded
    public private(set) var selectionIntent: SelectionIntent?
    public private(set) var resolvedSource: ResolvedSource?
    public private(set) var selectionNotice: String?

    private var latestGeneration: UInt64 = 0

    public init() {}

    public var catalog: CatalogSnapshot? {
        switch state {
        case .loaded(let snapshot, _): snapshot
        case .stale(let snapshot, _, _): snapshot
        case .notLoaded, .loading(_), .denied(_), .failed(_): nil
        }
    }

    public var canStart: Bool {
        guard case .loaded(let snapshot, let generation) = state,
              generation == latestGeneration,
              let selectionIntent,
              let resolvedSource else { return false }
        guard case .ready(let current) = RecordlySourceSelection.resolve(
            intent: selectionIntent,
            in: snapshot,
            permission: .granted
        ) else { return false }
        return current == resolvedSource
    }

    /// Begins a catalog request and invalidates any prior resolved selection
    /// until this generation finishes.
    @discardableResult
    public mutating func beginLoading() -> UInt64 {
        latestGeneration &+= 1
        resolvedSource = nil
        selectionNotice = nil
        state = .loading(generation: latestGeneration)
        return latestGeneration
    }

    /// Applies only the latest request. Older async responses cannot overwrite
    /// a newer catalog or restore a selection that the user has superseded.
    @discardableResult
    public mutating func finishLoading(
        _ result: RecordlySourceCatalogLoadResult,
        generation: UInt64
    ) -> Bool {
        guard generation == latestGeneration,
              case .loading(let activeGeneration) = state,
              activeGeneration == generation else { return false }

        switch result {
        case .loaded(let snapshot):
            if let selectionIntent {
                switch RecordlySourceSelection.resolve(
                    intent: selectionIntent,
                    in: snapshot,
                    permission: .granted
                ) {
                case .ready(let resolved):
                    resolvedSource = resolved
                    selectionNotice = nil
                    state = .loaded(snapshot: snapshot, generation: generation)
                case .denied(let reason), .lostSource(let reason), .invalidIntent(let reason):
                    resolvedSource = nil
                    selectionNotice = reason
                    state = .stale(snapshot: snapshot, generation: generation, reason: reason)
                }
            } else {
                resolvedSource = nil
                state = .loaded(snapshot: snapshot, generation: generation)
            }
        case .denied(let reason):
            resolvedSource = nil
            selectionNotice = nil
            state = .denied(reason: reason)
        case .failed(let reason):
            resolvedSource = nil
            selectionNotice = nil
            state = .failed(reason: reason)
        }
        return true
    }

    /// Selects one exact identity from the current catalog. Region remains
    /// rejected by the shared resolver until its coordinate contract is proven.
    public mutating func selectSource(_ intent: SelectionIntent) -> SelectionOutcome {
        guard let (snapshot, generation) = currentCatalogAndGeneration,
              generation == latestGeneration else { return .catalogUnavailable }

        switch RecordlySourceSelection.resolve(intent: intent, in: snapshot, permission: .granted) {
        case .ready(let resolved):
            selectionIntent = intent
            resolvedSource = resolved
            selectionNotice = nil
            state = .loaded(snapshot: snapshot, generation: generation)
            return .selected(resolved)
        case .denied(let reason):
            clearSelection()
            state = .denied(reason: reason)
            return .rejected(reason: reason)
        case .lostSource(let reason):
            clearSelection()
            selectionNotice = reason
            state = .stale(snapshot: snapshot, generation: generation, reason: reason)
            return .stale(reason: reason)
        case .invalidIntent(let reason):
            clearSelection()
            selectionNotice = reason
            if case .stale = state {
                state = .stale(snapshot: snapshot, generation: generation, reason: reason)
            } else {
                state = .loaded(snapshot: snapshot, generation: generation)
            }
            return .rejected(reason: reason)
        }
    }

    public mutating func clearSelection() {
        selectionIntent = nil
        resolvedSource = nil
        selectionNotice = nil
    }

    /// A fresh engine catalog found that the chosen source is no longer valid.
    /// Drop the old catalog and invalidate outstanding picker responses.
    public mutating func markStale(reason: String) {
        latestGeneration &+= 1
        selectionIntent = nil
        resolvedSource = nil
        selectionNotice = reason
        state = .stale(snapshot: nil, generation: nil, reason: reason)
    }

    public mutating func markDenied(reason: String) {
        latestGeneration &+= 1
        resolvedSource = nil
        selectionNotice = reason
        state = .denied(reason: reason)
    }

    public mutating func reset() {
        latestGeneration &+= 1
        selectionIntent = nil
        resolvedSource = nil
        selectionNotice = nil
        state = .notLoaded
    }

    private var currentCatalogAndGeneration: (CatalogSnapshot, UInt64)? {
        switch state {
        case .loaded(let snapshot, let generation):
            return (snapshot, generation)
        case .stale(let snapshot, let generation, _):
            guard let snapshot, let generation else {
                return nil
            }
            return (snapshot, generation)
        case .notLoaded, .loading(_), .denied(_), .failed(_):
            return nil
        }
    }
}
