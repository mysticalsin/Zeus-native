import Foundation
import ZeusCore

/// Holds events from a brain that was started during a pause, until the final words confirm or drop it.
final class EventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Result<BrainEvent, Error>] = []
    private var continuation: AsyncThrowingStream<BrainEvent, Error>.Continuation?
    private var finished = false

    func push(_ event: BrainEvent) {
        lock.lock()
        let continuation = self.continuation
        if continuation == nil { pending.append(.success(event)) }
        lock.unlock()
        continuation?.yield(event)
    }

    func fail(_ error: Error) {
        lock.lock()
        let continuation = self.continuation
        if continuation == nil { pending.append(.failure(error)) }
        finished = continuation != nil
        lock.unlock()
        continuation?.finish(throwing: error)
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        finished = true
        lock.unlock()
        continuation?.finish()
    }

    func stream() -> AsyncThrowingStream<BrainEvent, Error> {
        AsyncThrowingStream { continuation in
            self.lock.lock()
            let queued = self.pending
            self.pending.removeAll()
            self.continuation = continuation
            let done = self.finished
            self.lock.unlock()
            for item in queued {
                switch item {
                case .success(let event): continuation.yield(event)
                case .failure(let error): continuation.finish(throwing: error); return
                }
            }
            if done { continuation.finish() }
        }
    }
}

/// Starts the fastest brain after a 0.7 s pause. A revised phrase cancels that run and keeps none of it.
@MainActor
final class AheadRunner {
    private var state = AheadBrain()
    private var pause: Task<Void, Never>?
    private var job: Task<Void, Never>?
    private var bridge: EventBridge?
    private var provider: BrainProvider?
    private var turn: UUID?
    private(set) var engineID: String?

    func partial(_ text: String, start: @escaping @MainActor (String, Int) -> Void) {
        pause?.cancel()
        pause = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(AheadBrain.pauseMs)))
            guard let self, !Task.isCancelled else { return }
            switch self.state.consider(text) {
            case .ignore:
                self.cancelJob()
            case .wait:
                break
            case .start(let generation):
                start(text, generation)
            case .dropAndStart(let generation):
                self.cancelJob()
                start(text, generation)
            }
        }
    }

    func begin(engineID: String, provider: BrainProvider, request: BrainRequest) {
        cancelJob()
        let bridge = EventBridge()
        self.bridge = bridge
        self.provider = provider
        self.turn = request.turn
        self.engineID = engineID
        job = Task { [weak self] in
            do {
                for try await event in provider.send(request) {
                    if Task.isCancelled { break }
                    bridge.push(event)
                }
                bridge.finish()
            } catch {
                bridge.fail(error)
            }
            await MainActor.run { self?.job = nil }
        }
    }

    /// The buffered run when the final words are the ones that were started. Otherwise the run is dropped.
    func take(matching text: String) -> (id: String, events: AsyncThrowingStream<BrainEvent, Error>)? {
        pause?.cancel()
        pause = nil
        guard state.matches(text), let bridge, let engineID else {
            state.discard()
            cancelJob()
            return nil
        }
        return (engineID, bridge.stream())
    }

    func cancel() {
        pause?.cancel()
        pause = nil
        state.discard()
        cancelJob()
    }

    private func cancelJob() {
        job?.cancel()
        job = nil
        if let turn { Task { await provider?.cancel(turn: turn) } }
        provider = nil
        turn = nil
        bridge = nil
        engineID = nil
    }
}
