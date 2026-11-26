import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationOffMainSSEReaderTests {
    private let session = UUID(), turn = UUID(), scene = UUID()

    private func event(_ text: String, sequence: Int = 0, isFinal: Bool = true) -> ExplanationEvent {
        .init(sessionID: session, turnID: turn, sceneID: scene, sequence: sequence, baseRevision: sequence,
              revision: sequence + 1, beatID: "beat-\(sequence)", speech: .init(chunkID: "speech-\(sequence)", text: text),
              cues: [], isFinal: isFinal)
    }

    private func envelope(_ delta: [String: Any], finish: Any = NSNull()) throws -> Data {
        var data = Data("data: ".utf8)
        data.append(try JSONSerialization.data(withJSONObject: [
            "choices": [["index": 0, "delta": delta, "finish_reason": finish]]
        ]))
        data.append(contentsOf: "\n\n".utf8)
        return data
    }

    private func contentFrame(_ event: ExplanationEvent) throws -> Data {
        let text = String(decoding: try ExplanationWire.encode(event), as: UTF8.self) + "\n"
        return try envelope(["role": "assistant", "content": text])
    }

    private func suffix() throws -> Data {
        var data = try envelope([:], finish: "stop")
        data.append(contentsOf: "data: [DONE]\n\n".utf8)
        return data
    }

    private func reader<Bytes>(
        _ bytes: Bytes
    ) -> ExplanationOffMainSSEReader where Bytes: AsyncSequence & Sendable, Bytes.Element == UInt8, Bytes.Failure == any Error {
        ExplanationOffMainSSEReader(bytes: bytes, sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0)
    }

    @Test @MainActor func completeFrameYieldsTheSceneEvent() async throws {
        let expected = event("A circle.")
        var body = try contentFrame(expected)
        body.append(try suffix())
        var found: [ExplanationEvent] = []
        for try await event in reader(CountedBytes(body)) {
            found.append(event)
        }
        #expect(found == [expected])
    }

    @Test func partialLineWaitsForTheFrame() async throws {
        let expected = event("A circle.")
        let frame = try contentFrame(expected)
        let gate = GatedBytes(prefix: Array(frame.dropLast()))
        var iterator = reader(gate).makeAsyncIterator()
        let finished = Finished()
        let pending = Task {
            let value = try await iterator.next()
            finished.mark()
            return value
        }
        await gate.waitUntilParked()
        #expect(!finished.isSet)
        gate.append([frame.last!])
        #expect(try await pending.value == expected)
    }

    @Test func nextLineStaysUnreadUntilTheEventIsTaken() async throws {
        let first = event("A circle.")
        let frame = try contentFrame(first)
        var body = frame
        body.append(try suffix())
        let bytes = CountedBytes(body)
        var iterator = reader(bytes).makeAsyncIterator()
        #expect(try await iterator.next() == first)
        #expect(bytes.readCount == frame.count)
        #expect(try await iterator.next() == nil)
        #expect(bytes.readCount == body.count)
    }

    @Test func twoEventsStayInOrder() async throws {
        let first = event("A circle.", sequence: 0, isFinal: false)
        let second = event("A square.", sequence: 1, isFinal: true)
        let firstFrame = try contentFrame(first)
        let secondFrame = try contentFrame(second)
        var body = firstFrame
        body.append(secondFrame)
        body.append(try suffix())
        let bytes = CountedBytes(body)
        var iterator = reader(bytes).makeAsyncIterator()
        #expect(try await iterator.next() == first)
        #expect(bytes.readCount == firstFrame.count)
        #expect(try await iterator.next() == second)
        #expect(bytes.readCount == firstFrame.count + secondFrame.count)
        #expect(try await iterator.next() == nil)
        #expect(bytes.readCount == body.count)
    }

    @Test func incompleteBodyFails() async throws {
        let frame = try contentFrame(event("A circle."))
        var iterator = reader(CountedBytes(frame)).makeAsyncIterator()
        #expect(try await iterator.next() != nil)
        await #expect(throws: ExplanationCompletionStream.Failure.incompleteStream) {
            try await iterator.next()
        }
    }

    @Test func toolCallFails() async throws {
        let frame = try envelope(["tool_calls": []])
        var iterator = reader(CountedBytes(frame)).makeAsyncIterator()
        await #expect(throws: ExplanationCompletionStream.Failure.unsupportedToolCall) {
            try await iterator.next()
        }
    }

    @Test func oversizedLineFails() async throws {
        let frame = Data(repeating: 65, count: 200_000)
        var iterator = reader(CountedBytes(frame)).makeAsyncIterator()
        await #expect(throws: ExplanationCompletionStream.Failure.oversizedEnvelope) {
            try await iterator.next()
        }
    }

    @Test func cancelStopsTheRead() async throws {
        let probe = CancelProbe()
        var iterator = reader(probe).makeAsyncIterator()
        let pending = Task { try await iterator.next() }
        await probe.waitUntilWaiting()
        pending.cancel()
        await probe.waitUntilCancelled()
        switch await pending.result {
        case .success(nil), .failure(is CancellationError):
            break
        case .success(let event):
            Issue.record("cancel returned \(String(describing: event))")
        case .failure(let error):
            Issue.record("cancel threw \(error)")
        }
    }
}

private final class CancelProbe: AsyncSequence, @unchecked Sendable {
    typealias Element = UInt8
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt8?, any Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var cancelledWait: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var didCancel = false

    func makeAsyncIterator() -> Iterator { Iterator(owner: self) }

    func waitUntilWaiting() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didStart { lock.unlock(); cont.resume() } else { waiting = cont; lock.unlock() }
        }
    }

    func waitUntilCancelled() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didCancel { lock.unlock(); cont.resume() } else { cancelledWait = cont; lock.unlock() }
        }
    }

    fileprivate func take() async throws -> UInt8? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt8?, any Error>) in
                lock.lock()
                if didCancel {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                continuation = cont
                didStart = true
                let signal = waiting
                waiting = nil
                lock.unlock()
                signal?.resume()
            }
        } onCancel: {
            self.lock.lock()
            self.didCancel = true
            let cont = self.continuation
            self.continuation = nil
            let signal = self.cancelledWait
            self.cancelledWait = nil
            self.lock.unlock()
            cont?.resume(throwing: CancellationError())
            signal?.resume()
        }
    }

    struct Iterator: AsyncIteratorProtocol {
        let owner: CancelProbe
        mutating func next() async throws -> UInt8? { try await owner.take() }
    }
}

private final class Finished: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false
    func mark() { lock.lock(); set = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return set }
}

private final class CountedBytes: AsyncSequence, @unchecked Sendable {
    typealias Element = UInt8
    private let data: [UInt8]
    private let lock = NSLock()
    private var index = 0
    private var reads = 0

    init(_ data: Data) { self.data = Array(data) }

    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }

    func makeAsyncIterator() -> Iterator { Iterator(owner: self) }

    fileprivate func take() -> UInt8? {
        lock.lock()
        defer { lock.unlock() }
        guard index < data.count else { return nil }
        let byte = data[index]
        index += 1
        reads += 1
        return byte
    }

    struct Iterator: AsyncIteratorProtocol {
        let owner: CountedBytes
        mutating func next() async throws -> UInt8? { owner.take() }
    }
}

private final class GatedBytes: AsyncSequence, @unchecked Sendable {
    typealias Element = UInt8
    private let lock = NSLock()
    private var buffer: [UInt8]
    private var waiters: [CheckedContinuation<UInt8?, any Error>] = []
    private var parked: CheckedContinuation<Void, Never>?
    private var didPark = false

    init(prefix: [UInt8]) { buffer = prefix }

    func makeAsyncIterator() -> Iterator { Iterator(owner: self) }

    func waitUntilParked() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didPark {
                lock.unlock()
                cont.resume()
            } else {
                parked = cont
                lock.unlock()
            }
        }
    }

    func append(_ bytes: [UInt8]) {
        lock.lock()
        buffer.append(contentsOf: bytes)
        guard !waiters.isEmpty, !buffer.isEmpty else { lock.unlock(); return }
        let waiter = waiters.removeFirst()
        let byte = buffer.removeFirst()
        lock.unlock()
        waiter.resume(returning: byte)
    }

    fileprivate func take() async throws -> UInt8? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt8?, any Error>) in
            lock.lock()
            if !buffer.isEmpty {
                let byte = buffer.removeFirst()
                lock.unlock()
                cont.resume(returning: byte)
                return
            }
            waiters.append(cont)
            didPark = true
            let signal = parked
            parked = nil
            lock.unlock()
            signal?.resume()
        }
    }

    struct Iterator: AsyncIteratorProtocol {
        let owner: GatedBytes
        mutating func next() async throws -> UInt8? { try await owner.take() }
    }
}
