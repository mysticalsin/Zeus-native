import Foundation

// MARK: Send

public struct FlingSendItem: Equatable, Sendable {
    public var index: Int
    public var name: String
    public var size: Int64
    public var kind: FlingItemKind
    public var uti: String?
    public var url: String?
    public init(index: Int, name: String, size: Int64, kind: FlingItemKind, uti: String?, url: String?) {
        self.index = index; self.name = name; self.size = size; self.kind = kind; self.uti = uti; self.url = url
    }
}

public enum FlingSendFailure: Equatable, Sendable { case peerLost, hashMismatch, protocolError }

public enum FlingSendState: Equatable, Sendable {
    case hashing, awaitingAccept
    case sending(index: Int, sent: Int64)
    case finishing, done
    case declined(FlingDeclineReason)
    case failed(FlingSendFailure)
    case cancelled

    public var isFinal: Bool {
        switch self {
        case .done, .declined, .failed, .cancelled: return true
        default: return false
        }
    }
}

public enum FlingSendEvent: Sendable {
    case start
    case hashReady(index: Int, sha256: String)
    case received(FlingMessage)
    case fileSent(index: Int)
    case progress(sent: Int64)
    case userCancel
    case connectionLost
}

public enum FlingSendEffect: Equatable, Sendable {
    case computeHash(index: Int)
    case send(FlingMessage)
    case streamFile(index: Int)
    case close
}

/// The sending side of one stack. The offer goes out only once every hash is ready. There is no resume: a lost
/// peer ends the transfer, and only a new user gesture sends again.
public struct FlingSendMachine: Sendable {
    public let stackID: UUID
    public private(set) var state: FlingSendState = .hashing
    private let items: [FlingSendItem]
    private var hashes: [Int: String] = [:]

    public init(stackID: UUID, items: [FlingSendItem]) { self.stackID = stackID; self.items = items }

    private var fileIndexes: [Int] { items.filter { $0.kind == .file }.map(\.index) }

    private mutating func end(_ final: FlingSendState, send message: FlingMessage? = nil) -> [FlingSendEffect] {
        state = final
        return (message.map { [.send($0)] } ?? []) + [.close]
    }

    private mutating func streamNext(after current: Int?) -> [FlingSendEffect] {
        let next = fileIndexes.first { current == nil || $0 > current! }
        guard let next else { state = .finishing; return [] }
        state = .sending(index: next, sent: 0)
        return [.streamFile(index: next)]
    }

    public mutating func handle(_ event: FlingSendEvent) -> [FlingSendEffect] {
        if state.isFinal { return [] }
        switch event {
        case .start:
            guard state == .hashing else { return [] }
            return items.map { .computeHash(index: $0.index) }

        case .hashReady(let index, let sha):
            guard state == .hashing, items.contains(where: { $0.index == index }) else { return [] }
            hashes[index] = sha
            guard hashes.count == items.count else { return [] }
            let offerItems = items.map {
                FlingOfferItem(index: $0.index, name: FlingNames.clean($0.name), size: $0.kind == .link ? 0 : $0.size, kind: $0.kind,
                               uti: $0.uti, sha256: hashes[$0.index] ?? "", url: $0.kind == .link ? $0.url : nil)
            }
            state = .awaitingAccept
            return [.send(.offer(FlingOffer(stackID: stackID, items: offerItems)))]

        case .progress(let sent):
            if case .sending(let index, _) = state { state = .sending(index: index, sent: sent) }
            return []

        case .fileSent(let index):
            guard case .sending(let current, _) = state, current == index else { return [] }
            return [.send(.fileDone(FlingFileDone(index: index)))] + streamNext(after: index)

        case .userCancel:
            return end(.cancelled, send: .cancel(FlingStackRef(stackID: stackID)))

        case .connectionLost:
            return end(.failed(.peerLost))

        case .received(let message):
            switch message {
            case .accept(let ref) where ref.stackID == stackID && state == .awaitingAccept:
                return streamNext(after: nil)
            case .decline(let d) where d.stackID == stackID:
                return end(.declined(d.reason))
            case .itemResult(let r):
                guard !r.ok else { return [] }
                return end(.failed(.hashMismatch))
            case .stackDone(let ref) where ref.stackID == stackID:
                guard state == .finishing else { return end(.failed(.protocolError)) }
                state = .done
                return [.close]
            case .cancel(let ref) where ref.stackID == stackID:
                return end(.cancelled)
            default:
                return []
            }
        }
    }
}

// MARK: Receive

public struct FlingReceiveContext: Equatable, Sendable {
    public var peerID: String
    public var peerName: String
    public var paired: Bool
    public var autoAccept: Bool
    public var freeBytes: Int64
    public var isReplay: Bool
    public init(peerID: String, peerName: String, paired: Bool, autoAccept: Bool, freeBytes: Int64, isReplay: Bool) {
        self.peerID = peerID; self.peerName = peerName; self.paired = paired; self.autoAccept = autoAccept; self.freeBytes = freeBytes; self.isReplay = isReplay
    }
}

public enum FlingReceiveFailure: Equatable, Sendable {
    case hashMismatch, overSize, badName, tooMany, diskFull, notPaired, peerLost, replay, malformed, badLink
}

public enum FlingReceiveState: Equatable, Sendable {
    case validating
    case prompting(deadline: Date)
    case receiving(index: Int, got: Int64)
    case verifying(index: Int)
    case committing(index: Int)
    case done
    case declined(FlingDeclineReason)
    case failed(FlingReceiveFailure)
    case cancelled

    public var isFinal: Bool {
        switch self {
        case .done, .declined, .failed, .cancelled: return true
        default: return false
        }
    }
}

public enum FlingReceiveEvent: Sendable {
    case received(FlingMessage, now: Date)
    case userAccept, userDecline, userCancel
    case tick(now: Date)
    case hashComputed(index: Int, sha256: String)
    case committed(index: Int)
    case commitFailed(index: Int)
    case connectionLost
}

public enum FlingReceiveEffect: Equatable, Sendable {
    case send(FlingMessage)
    case makeTemp(stackID: UUID)
    case write(index: Int, data: Data)
    case verify(index: Int)
    case commit(index: Int)
    case commitLink(index: Int, url: String)
    case addToShelf(index: Int)
    case deleteTemp
    case prompt(peerName: String, itemCount: Int, totalBytes: Int64, stackID: UUID)
    case hidePrompt
    case close
}

/// The receiving side of one stack. A file reaches the Shelf only after its hash matched, and every end state
/// except done deletes the partial folder.
public struct FlingReceiveMachine: Sendable {
    public private(set) var state: FlingReceiveState = .validating
    private let context: FlingReceiveContext
    private var offer: FlingOffer?
    private var cursor = 0

    public init(context: FlingReceiveContext) { self.context = context }

    private var stackID: UUID { offer?.stackID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    private var prompting: Bool { if case .prompting = state { return true } else { return false } }

    private mutating func end(_ final: FlingReceiveState, message: FlingMessage? = nil) -> [FlingReceiveEffect] {
        var effects: [FlingReceiveEffect] = []
        if let message { effects.append(.send(message)) }
        if prompting { effects.append(.hidePrompt) }
        state = final
        effects += [.deleteTemp, .close]
        return effects
    }

    private mutating func decline(_ reason: FlingDeclineReason, as final: FlingReceiveState) -> [FlingReceiveEffect] {
        end(final, message: .decline(FlingDecline(stackID: stackID, reason: reason)))
    }

    private mutating func fail(_ failure: FlingReceiveFailure, decline reason: FlingDeclineReason) -> [FlingReceiveEffect] {
        decline(reason, as: .failed(failure))
    }

    /// Moves on to the next item: a file waits for bytes, a link is committed straight away, and the end finishes the stack.
    private mutating func advance() -> [FlingReceiveEffect] {
        guard let offer else { return [] }
        let ordered = offer.items.sorted { $0.index < $1.index }
        guard cursor < ordered.count else {
            state = .done
            return [.send(.stackDone(FlingStackRef(stackID: offer.stackID))), .close]
        }
        let item = ordered[cursor]
        switch item.kind {
        case .file:
            state = .receiving(index: item.index, got: 0)
            return []
        case .link:
            guard let url = item.url, FlingCrypto.sha256Hex(Data(url.utf8)) == item.sha256.lowercased() else {
                return end(.failed(.hashMismatch), message: .itemResult(FlingItemResult(index: item.index, ok: false)))
            }
            state = .committing(index: item.index)
            return [.commitLink(index: item.index, url: url)]
        }
    }

    private func item(_ index: Int) -> FlingOfferItem? { offer?.items.first { $0.index == index } }

    public mutating func handle(_ event: FlingReceiveEvent) -> [FlingReceiveEffect] {
        if state.isFinal { return [] }
        switch event {
        case .received(let message, let now):
            return receive(message, now: now)

        case .userAccept:
            guard prompting, let offer else { return [] }
            state = .receiving(index: 0, got: 0)
            return [.makeTemp(stackID: offer.stackID), .send(.accept(FlingStackRef(stackID: offer.stackID))), .hidePrompt] + advance()

        case .userDecline:
            guard prompting else { return [] }
            return decline(.declined, as: .declined(.declined))

        case .userCancel:
            return end(.cancelled, message: .cancel(FlingStackRef(stackID: stackID)))

        case .tick(let now):
            guard case .prompting(let deadline) = state, now >= deadline else { return [] }
            return decline(.timeout, as: .declined(.timeout))

        case .connectionLost:
            return end(.failed(.peerLost))

        case .hashComputed(let index, let sha):
            guard case .verifying(let current) = state, current == index, let item = item(index) else { return [] }
            guard sha.lowercased() == item.sha256.lowercased() else {
                return end(.failed(.hashMismatch), message: .itemResult(FlingItemResult(index: index, ok: false)))
            }
            state = .committing(index: index)
            return [.commit(index: index)]

        case .committed(let index):
            guard case .committing(let current) = state, current == index else { return [] }
            cursor += 1
            return [.addToShelf(index: index), .send(.itemResult(FlingItemResult(index: index, ok: true)))] + advance()

        case .commitFailed:
            switch state {
            case .receiving, .verifying, .committing: return fail(.diskFull, decline: .diskFull)
            default: return []
            }
        }
    }

    private mutating func receive(_ message: FlingMessage, now: Date) -> [FlingReceiveEffect] {
        switch (state, message) {
        case (.validating, .offer(let incoming)):
            offer = incoming
            if !context.paired { return fail(.notPaired, decline: .notPaired) }
            if context.isReplay { return fail(.replay, decline: .replay) }
            if let reason = FlingOfferRules.validate(incoming, freeBytes: context.freeBytes) {
                switch reason {
                case .badName: return fail(.badName, decline: .badName)
                case .tooMany: return fail(.tooMany, decline: .tooMany)
                case .diskFull: return fail(.diskFull, decline: .diskFull)
                case .badLink: return fail(.badLink, decline: .badLink)
                default: return fail(.malformed, decline: .malformed)
                }
            }
            if context.paired && context.autoAccept {
                state = .receiving(index: 0, got: 0)
                return [.makeTemp(stackID: incoming.stackID), .send(.accept(FlingStackRef(stackID: incoming.stackID)))] + advance()
            }
            state = .prompting(deadline: now.addingTimeInterval(FlingLimits.promptTimeout))
            let total = incoming.items.filter { $0.kind == .file }.reduce(Int64(0)) { $0 + $1.size }
            return [.prompt(peerName: context.peerName, itemCount: incoming.items.count, totalBytes: total, stackID: incoming.stackID)]

        case (.receiving(let index, let got), .chunk(let chunk)):
            guard Int(chunk.index) == index, let item = item(index) else { return fail(.malformed, decline: .malformed) }
            let total = got + Int64(chunk.bytes.count)
            guard total <= item.size else { return fail(.overSize, decline: .overSize) }
            state = .receiving(index: index, got: total)
            return [.write(index: index, data: chunk.bytes)]

        case (.receiving(let index, let got), .fileDone(let done)):
            guard done.index == index, let item = item(index) else { return fail(.malformed, decline: .malformed) }
            guard got == item.size else {
                return end(.failed(.hashMismatch), message: .itemResult(FlingItemResult(index: index, ok: false)))
            }
            state = .verifying(index: index)
            return [.verify(index: index)]

        case (_, .cancel(let ref)) where ref.stackID == stackID:
            return end(.cancelled)

        case (.prompting, .decline), (.prompting, .accept):
            return fail(.malformed, decline: .malformed)

        default:
            return fail(.malformed, decline: .malformed)
        }
    }
}
