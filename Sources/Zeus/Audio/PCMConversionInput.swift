import AVFoundation
import Foundation

/// Input for one synchronous AVAudioConverter conversion. The caller must leave the borrowed
/// PCM bytes unchanged until convert returns; AVAudioConverter requires them until its next
/// input callback or the end of conversion. This owner retains that buffer and never mutates it.
/// Only consume-once state crosses callbacks, under the lock. This is not a general PCM transfer
/// wrapper, and its lock does not protect an AVAudioConverter shared by separate conversions.
final class PCMConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let exhaustedStatus: AVAudioConverterInputStatus
    private let lock = NSLock()
    private var supplied = false

    init(buffer: AVAudioPCMBuffer, final: Bool) {
        self.buffer = buffer
        exhaustedStatus = final ? .endOfStream : .noDataNow
    }

    func take(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.withLock {
            guard !supplied else {
                status.pointee = exhaustedStatus
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
    }
}
