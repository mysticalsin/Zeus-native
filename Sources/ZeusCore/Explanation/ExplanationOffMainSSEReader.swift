import Foundation

/// Off-main reader for an OpenAI-compatible explanation SSE body.
///
/// The byte and line loop runs in a task started from this nonisolated type, so a
/// main-actor caller does not parse the body. Events go into an
/// `AsyncThrowingStream` created with `bufferingPolicy: .bufferingOldest(1)`.
/// The next pull is what lets the loop read the next line, so that one slot
/// stays with the consumer.
public struct ExplanationOffMainSSEReader: AsyncSequence, Sendable {
    public typealias Element = ExplanationEvent

    private let state: State

    public nonisolated init<Bytes>(
        bytes: Bytes,
        sessionID: UUID,
        turnID: UUID,
        sceneID: UUID,
        baseRevision: Int,
        profile: ExplanationWireProfile = .v1
    ) where Bytes: AsyncSequence & Sendable, Bytes.Element == UInt8 {
        let (demand, demandContinuation) = AsyncStream<Void>.makeStream()
        let (events, eventContinuation) = AsyncThrowingStream<ExplanationEvent, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(1))
        let pull = Pull(stream: events, demand: demandContinuation)
        let task = Task {
            await Self.pump(bytes: bytes, demand: demand, events: eventContinuation,
                            sessionID: sessionID, turnID: turnID, sceneID: sceneID,
                            baseRevision: baseRevision, profile: profile)
        }
        eventContinuation.onTermination = { @Sendable _ in
            task.cancel()
            demandContinuation.finish()
        }
        state = State(pull: pull, task: task, demand: demandContinuation)
    }

    public nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(state: state.claim() ? state : nil)
    }

    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        private let state: State?
        fileprivate init(state: State?) { self.state = state }
        public mutating func next() async throws -> ExplanationEvent? {
            guard let state else { return nil }
            return try await state.pull.next()
        }
    }

    private static func pump<Bytes>(
        bytes: Bytes,
        demand: AsyncStream<Void>,
        events: AsyncThrowingStream<ExplanationEvent, any Error>.Continuation,
        sessionID: UUID,
        turnID: UUID,
        sceneID: UUID,
        baseRevision: Int,
        profile: ExplanationWireProfile
    ) async where Bytes: AsyncSequence & Sendable, Bytes.Element == UInt8 {
        do {
            var parser = try ExplanationCompletionStream(sessionID: sessionID, turnID: turnID, sceneID: sceneID,
                                                         baseRevision: baseRevision, profile: profile)
            defer { parser.cancel() }
            var line = Data()
            var pending: [ExplanationEvent] = []
            var iterator = bytes.makeAsyncIterator()
            for await _ in demand {
                let event = try await nextEvent(parser: &parser, line: &line, pending: &pending, bytes: &iterator)
                if let event {
                    switch events.yield(event) {
                    case .enqueued:
                        break
                    case .dropped, .terminated:
                        events.finish(throwing: ExplanationCompletionStream.Failure.cancelled)
                        return
                    @unknown default:
                        events.finish(throwing: ExplanationCompletionStream.Failure.cancelled)
                        return
                    }
                } else {
                    events.finish()
                    return
                }
            }
        } catch {
            events.finish(throwing: error)
        }
    }

    /// Same line cap the provider uses before it hands a line to the envelope parser.
    private static let maxLineBytes = 131_072

    private static func nextEvent<Iterator>(
        parser: inout ExplanationCompletionStream,
        line: inout Data,
        pending: inout [ExplanationEvent],
        bytes: inout Iterator
    ) async throws -> ExplanationEvent? where Iterator: AsyncIteratorProtocol, Iterator.Element == UInt8 {
        if !pending.isEmpty { return pending.removeFirst() }
        while true {
            try Task.checkCancellation()
            guard let byte = try await bytes.next() else {
                if !line.isEmpty {
                    _ = try parser.append(line)
                    line.removeAll(keepingCapacity: true)
                }
                try parser.finish()
                return nil
            }
            guard line.count <= maxLineBytes else { throw ExplanationCompletionStream.Failure.oversizedEnvelope }
            line.append(byte)
            if byte == 10 {
                let produced = try parser.append(line)
                line.removeAll(keepingCapacity: true)
                if !produced.isEmpty {
                    pending = produced
                    return pending.removeFirst()
                }
            }
        }
    }
}

private final class Pull: @unchecked Sendable {
    private var stream: AsyncThrowingStream<ExplanationEvent, any Error>?
    private var inner: AsyncThrowingStream<ExplanationEvent, any Error>.AsyncIterator?
    private let demand: AsyncStream<Void>.Continuation

    init(stream: AsyncThrowingStream<ExplanationEvent, any Error>, demand: AsyncStream<Void>.Continuation) {
        self.stream = stream
        self.demand = demand
    }

    func next() async throws -> ExplanationEvent? {
        if inner == nil {
            guard let stream else { return nil }
            inner = stream.makeAsyncIterator()
            self.stream = nil
        }
        demand.yield(())
        guard var cursor = inner else { return nil }
        let value = try await cursor.next()
        inner = cursor
        return value
    }
}

private final class State: @unchecked Sendable {
    let pull: Pull
    let task: Task<Void, Never>
    let demand: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var issued = false

    init(pull: Pull, task: Task<Void, Never>, demand: AsyncStream<Void>.Continuation) {
        self.pull = pull
        self.task = task
        self.demand = demand
    }

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if issued { return false }
        issued = true
        return true
    }

    deinit {
        task.cancel()
        demand.finish()
    }
}
