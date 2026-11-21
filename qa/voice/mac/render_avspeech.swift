import AVFoundation
import Foundation

// Renders one line with AVSpeechSynthesizer.write.
// Rate, pitch, and the empty-text exit come from avspeech_plan.py.
// This process does not run Zeus's Ultron effect chain.
// Usage: swift render_avspeech.swift OUTPUT.wav TEXTFILE

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: render_avspeech.swift OUTPUT.wav TEXTFILE\n", stderr)
    exit(2)
}

let planScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("avspeech_plan.py")
let planProcess = Process()
planProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
planProcess.arguments = ["python3", planScript.path, arguments[1], arguments[2]]
let planOutput = Pipe()
let planErrors = Pipe()
planProcess.standardOutput = planOutput
planProcess.standardError = planErrors
do {
    try planProcess.run()
} catch {
    fputs("avspeech plan failed\n", stderr)
    exit(2)
}
planProcess.waitUntilExit()
let planErrorData = planErrors.fileHandleForReading.readDataToEndOfFile()
if !planErrorData.isEmpty {
    FileHandle.standardError.write(planErrorData)
}
let planCode = planProcess.terminationStatus
if planCode != 0 {
    exit(planCode)
}
let planData = planOutput.fileHandleForReading.readDataToEndOfFile()
guard let plan = try? JSONSerialization.jsonObject(with: planData) as? [String: Any],
      let rateScale = plan["rate_scale"] as? Double,
      let pitch = plan["pitch"] as? Double else {
    fputs("avspeech plan failed\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: arguments[1])
let text = (try? String(contentsOfFile: arguments[2], encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

let synthesizer = AVSpeechSynthesizer()
let utterance = AVSpeechUtterance(string: text)
utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rateScale)
utterance.pitchMultiplier = Float(pitch)
if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { ["Daniel", "Alex", "Tom"].contains($0.name) }) {
    utterance.voice = voice
}

final class BufferCopy: @unchecked Sendable {
    var samples: [Float] = []
    var sampleRate: Double = 22_050
}

let copy = BufferCopy()
let done = DispatchSemaphore(value: 0)
var started = false
synthesizer.write(utterance) { buffer in
    guard let pcm = buffer as? AVAudioPCMBuffer, let channel = pcm.floatChannelData?[0] else { return }
    if pcm.frameLength == 0 {
        done.signal()
        return
    }
    if !started {
        copy.sampleRate = pcm.format.sampleRate
        started = true
    }
    copy.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
}
let wait = done.wait(timeout: .now() + 60)
guard wait == .success, !copy.samples.isEmpty else {
    fputs("synthesizer produced no buffers\n", stderr)
    exit(1)
}

guard let format = AVAudioFormat(standardFormatWithSampleRate: copy.sampleRate, channels: 1),
      let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(copy.samples.count)),
      let target = pcm.floatChannelData?[0] else {
    fputs("could not build a buffer\n", stderr)
    exit(1)
}
for index in copy.samples.indices { target[index] = copy.samples[index] }
pcm.frameLength = AVAudioFrameCount(copy.samples.count)
do {
    let file = try AVAudioFile(forWriting: output, settings: format.settings)
    try file.write(from: pcm)
} catch {
    fputs("write failed: \(error)\n", stderr)
    exit(1)
}
print("wrote \(output.path) \(copy.samples.count) samples at \(copy.sampleRate) Hz")
