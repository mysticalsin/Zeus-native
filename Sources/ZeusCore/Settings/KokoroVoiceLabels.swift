import Foundation

/// Short labels for Kokoro voice picker rows (full ids stay in `VoiceSettings.kokoroVoices`).
public enum KokoroVoiceLabels {
    public static func pickerTitle(voiceID: String, longName: String) -> String {
        switch voiceID {
        case "am_michael": "Michael (US)"
        case "am_adam": "Adam (US)"
        case "am_eric": "Eric (US)"
        case "bm_george": "George (UK)"
        case "bm_lewis": "Lewis (UK)"
        case "bm_daniel": "Daniel (UK)"
        case "bf_emma": "Emma (UK)"
        case "af_heart": "Heart (US)"
        case "af_bella": "Bella (US)"
        default:
            longName.split(separator: ",").first.map(String.init) ?? longName
        }
    }
}
