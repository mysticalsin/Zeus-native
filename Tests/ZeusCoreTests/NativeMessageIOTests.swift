import Foundation
import Testing
@testable import ZeusCore

/// Disposable anonymous pipes only. No Chrome, app launch, provider, settings, permission or capture.
@Suite("Bounded native-message I/O", .serialized)
struct NativeMessageIOTests {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.withLock { value } }
        func change(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
    }
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }
    private func largeFrame() throws -> Data {
        try NativeMessagingFrame.encode(Data(repeating: 0x78, count: NativeMessagingFrame.maxHostToChromeBytes))
    }

    @Test func slowReaderReceivesOrderedCompleteFramesAcrossPartialWrites() async throws {
        let pipe = Pipe()
        let input = try NativeMessageInput(handle: pipe.fileHandleForReading)
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting)
        try pipe.fileHandleForReading.close(); try pipe.fileHandleForWriting.close()
        defer { input.stop(); output.stop() }
        let received = Box(Data()), completions = Box<[Bool]>([]), endings = Box<[NativeMessageInput.End]>([])
        input.start(consume: { bytes in
            received.change { $0.append(bytes) }
            Thread.sleep(forTimeInterval: 0.001) // Slow synthetic consumer; no unbounded buffering.
        }, ended: { end in endings.change { $0.append(end) } })
        let first = try NativeMessagingFrame.encode(Data(String(repeating: "Résumé 🦉", count: 12_000).utf8))
        let second = try NativeMessagingFrame.encode(Data(String(repeating: "第二帧", count: 16_000).utf8))
        let completion: @Sendable (Result<Void, NativeMessageOutput.Failure>) -> Void = { result in
            completions.change { $0.append((try? result.get()) != nil) }
        }
        let admission0 = output.enqueue(first, completion: completion)
        #expect(admission0 == .accepted)
        let admission1 = output.enqueue(second, completion: completion)
        #expect(admission1 == .accepted)
        try await eventually { completions.read().count == 2 }
        #expect(completions.read() == [true, true])
        output.stop()
        try await eventually { endings.read() == [.eof] }
        #expect(received.read() == first + second)
        #expect(output.queuedFrameCount == 0 && output.queuedByteCount == 0)
    }

    @Test func nonReadingPeerCannotBlockCallerOrExceedFrameBudget() async throws {
        let pipe = Pipe()
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting, writeTimeout: 20)
        try pipe.fileHandleForWriting.close()
        defer { output.stop(); try? pipe.fileHandleForReading.close() }
        let results = Box<[Bool]>([])
        let completed: @Sendable (Result<Void, NativeMessageOutput.Failure>) -> Void = { result in
            results.change { $0.append((try? result.get()) != nil) }
        }
        let began = ContinuousClock.now
        let admission2 = output.enqueue(try largeFrame(), completion: completed)
        #expect(admission2 == .accepted)
        let small = try NativeMessagingFrame.encode(Data("{}".utf8))
        for _ in 1..<NativeMessageOutput.maximumQueuedFrames {
            let admission3 = output.enqueue(small, completion: completed)
            #expect(admission3 == .accepted)
        }
        let admission4 = output.enqueue(small, completion: completed)
        #expect(admission4 == .full)
        #expect(began.duration(to: .now) < .milliseconds(150))
        #expect(output.queuedFrameCount == NativeMessageOutput.maximumQueuedFrames)
        #expect(output.queuedByteCount <= NativeMessageOutput.maximumQueuedBytes)
        output.stop()
        try await eventually { results.read().count == NativeMessageOutput.maximumQueuedFrames }
        #expect(results.read().allSatisfy { !$0 })
        #expect(!output.isOpen && output.queuedFrameCount == 0 && output.queuedByteCount == 0)
        let admission5 = output.enqueue(small, completion: completed)
        #expect(admission5 == .closed)
    }

    @Test func byteBudgetRejectsWorkBeforeTheFrameCountBudgetIsReached() async throws {
        let pipe = Pipe()
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting, writeTimeout: 20)
        try pipe.fileHandleForWriting.close()
        defer { output.stop(); try? pipe.fileHandleForReading.close() }
        let completions = Box(0)
        let frame = try largeFrame()
        for _ in 0..<7 {
            let admission6 = output.enqueue(frame) { _ in completions.change { $0 += 1 } }
            #expect(admission6 == .accepted)
        }
        let admission7 = output.enqueue(frame) { _ in Issue.record("Rejected work received a completion") }
        #expect(admission7 == .full)
        #expect(output.queuedFrameCount == 7)
        #expect(output.queuedByteCount == frame.count * 7)
        output.stop()
        try await eventually { completions.read() == 7 }
        #expect(output.queuedByteCount == 0)
    }

    @Test func nonReadingPeerHitsAnAbsoluteWriteDeadlineAndClosesTheStream() async throws {
        let pipe = Pipe()
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting, writeTimeout: 0.1)
        try pipe.fileHandleForWriting.close()
        defer { output.stop(); try? pipe.fileHandleForReading.close() }
        let failures = Box<[NativeMessageOutput.Failure]>([])
        let admission = output.enqueue(try largeFrame()) { result in
            if case .failure(let failure) = result { failures.change { $0.append(failure) } }
        }
        #expect(admission == .accepted)
        try await eventually { failures.read().count == 1 }
        #expect(failures.read() == [.timedOut])
        #expect(!output.isOpen && output.queuedFrameCount == 0 && output.queuedByteCount == 0)
    }

    @Test func stopSettlesQueuedWritesWithoutWaitingForTheirLongDeadline() async throws {
        let pipe = Pipe()
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting, writeTimeout: 20)
        try pipe.fileHandleForWriting.close()
        defer { output.stop(); try? pipe.fileHandleForReading.close() }
        let completions = Box(0)
        for _ in 0..<2 {
            let admission8 = output.enqueue(try largeFrame()) { _ in completions.change { $0 += 1 } }
            #expect(admission8 == .accepted)
        }
        let began = ContinuousClock.now
        output.stop(); output.stop()
        try await eventually { completions.read() == 2 }
        #expect(began.duration(to: .now) < .milliseconds(500))
        #expect(output.queuedFrameCount == 0 && output.queuedByteCount == 0)
    }

    @Test func disconnectedReaderDoesNotRaiseSIGPIPEOrLeaveAcceptedWorkPending() async throws {
        let pipe = Pipe()
        let output = try NativeMessageOutput(handle: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close(); try pipe.fileHandleForReading.close()
        defer { output.stop() }
        let results = Box<[Bool]>([])
        let admission = output.enqueue(try NativeMessagingFrame.encode(Data("{}".utf8))) { result in
            results.change { $0.append((try? result.get()) != nil) }
        }
        #expect(admission == .accepted)
        try await eventually { results.read().count == 1 }
        #expect(results.read() == [false] && !output.isOpen)
    }

    @Test func finalBytesAndEOFArrivingTogetherFinishWithoutAnotherReadinessEvent() async throws {
        let pipe = Pipe()
        let input = try NativeMessageInput(handle: pipe.fileHandleForReading)
        try pipe.fileHandleForReading.close()
        defer { input.stop() }
        let payload = Data("last bytes".utf8)
        try pipe.fileHandleForWriting.write(contentsOf: payload)
        try pipe.fileHandleForWriting.close()
        let received = Box(Data()), endings = Box<[NativeMessageInput.End]>([])
        input.start(consume: { data in received.change { $0.append(data) } }, ended: { end in endings.change { $0.append(end) } })
        try await eventually { endings.read() == [.eof] }
        #expect(received.read() == payload)
    }

    @Test func immediateStopAndStopBeforeStartAlwaysSettleTheAcceptedStartOnce() async throws {
        for stopFirst in [false, true] {
            for _ in 0..<20 {
                let pipe = Pipe()
                let input = try NativeMessageInput(handle: pipe.fileHandleForReading)
                try pipe.fileHandleForReading.close()
                let endings = Box<[NativeMessageInput.End]>([])
                if stopFirst { input.stop() }
                let peerFD = pipe.fileHandleForWriting.fileDescriptor
                let started = input.start(consume: { _ in Issue.record("Stopped input consumed bytes") }, ended: { end in
                    var readiness = pollfd(fd: peerFD, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&readiness, 1, 0)
                    #expect(readiness.revents & Int16(POLLERR) != 0, "The read descriptor must close before its terminal callback")
                    endings.change { $0.append(end) }
                })
                #expect(started)
                input.stop(); input.stop()
                let duplicate = input.start(consume: { _ in }, ended: { _ in Issue.record("Duplicate start received a callback") })
                #expect(!duplicate)
                try await eventually { endings.read() == [.stopped] }
                try pipe.fileHandleForWriting.close()
            }
        }
    }

    @Test func droppingAnIdleInputOwnerCancelsItsDescriptorAndEndsTheRead() async throws {
        let pipe = Pipe()
        var input: NativeMessageInput? = try NativeMessageInput(handle: pipe.fileHandleForReading)
        try pipe.fileHandleForReading.close()
        defer { try? pipe.fileHandleForWriting.close() }
        let endings = Box<[NativeMessageInput.End]>([])
        weak var weakInput = input
        input?.start(consume: { _ in }, ended: { end in endings.change { $0.append(end) } })
        input = nil
        try await eventually { weakInput == nil && endings.read() == [.stopped] }
    }
}
