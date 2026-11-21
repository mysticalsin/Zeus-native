import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Mac end-to-end run (`specs/008-providers/e2e-mac.md`). Off unless
/// `ZEUS_VOICE_PROVIDER_FAKE` is `1` or `fail`. No real key is accepted.
public enum VoiceProviderE2E {
    public static let environmentName = "ZEUS_VOICE_PROVIDER_FAKE"
    /// The only key the fake answers. It is not a vendor credential.
    public static let fakeKey = "zeus-e2e-fake-key"
    public static let voiceID = "e2e-voice"
    public static let voiceName = "E2E Voice"

    public static func isEnabled(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let value = environment[environmentName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value == "1" || value == "fail"
    }

    public static func failsSynthesis(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[environmentName]?.trimmingCharacters(in: .whitespacesAndNewlines) == "fail"
    }

    /// Test-only Keychain service. Production keys stay on `com.zeus.app`.
    public static func service(for providerID: String) -> String {
        let clean = providerID.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        return "app.zeus.voice-provider.e2e.\(clean)"
    }
}

enum VoiceProviderFakeAudio {
    /// A short silent WAV. `AVAudioPlayer` can play it; it is not a recording of anyone.
    static func wavSilence() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount = 160
        let dataSize = sampleCount * 2
        var bytes = Data()
        func ascii(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func le16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        func le32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        ascii("RIFF")
        le32(36 + UInt32(dataSize))
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1)
        le16(1)
        le32(sampleRate)
        le32(sampleRate * 2)
        le16(2)
        le16(16)
        ascii("data")
        le32(UInt32(dataSize))
        bytes.append(Data(count: dataSize))
        return bytes
    }
}

/// Answers the ElevenLabs and Google HTTPS URLs inside this process. It never opens a socket.
public final class VoiceProviderFakeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) public static var failSynthesis = false

    public override class func canInit(with request: URLRequest) -> Bool {
        guard request.url?.scheme?.lowercased() == "https" else { return false }
        switch request.url?.host?.lowercased() {
        case "api.elevenlabs.io", "texttospeech.googleapis.com": return true
        default: return false
        }
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let url = request.url
        let path = url?.path ?? ""
        let key = request.value(forHTTPHeaderField: "xi-api-key") ?? request.value(forHTTPHeaderField: "X-Goog-Api-Key") ?? ""
        let status: Int
        var body = Data()
        var chunks: [Data] = []
        if key != VoiceProviderE2E.fakeKey {
            status = 401
        } else if Self.failSynthesis && (path.contains("/stream") || path.contains(":synthesize")) {
            status = 500
        } else if path.hasSuffix("/user") {
            status = 200
            body = Data("{}".utf8)
        } else if path.hasSuffix("/voices") {
            status = 200
            if url?.host?.contains("googleapis") == true {
                body = Data(#"{"voices":[{"name":"e2e-voice","languageCodes":["en-US"]}]}"#.utf8)
            } else {
                body = Data(#"{"voices":[{"voice_id":"e2e-voice","name":"E2E Voice"}]}"#.utf8)
            }
        } else if path.contains(":synthesize") {
            status = 200
            let audio = VoiceProviderFakeAudio.wavSilence().base64EncodedString()
            body = Data("{\"audioContent\":\"\(audio)\"}".utf8)
        } else if path.contains("/stream") {
            status = 200
            let wav = VoiceProviderFakeAudio.wavSilence()
            let mid = max(1, wav.count / 2)
            chunks = [Data(wav.prefix(mid)), Data(wav.dropFirst(mid))]
        } else {
            status = 404
        }
        let response = HTTPURLResponse(url: url ?? URL(string: "https://example.invalid/")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if chunks.isEmpty {
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        } else {
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}
