import AVFoundation

final class AudioService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// Speak the given text using the system TTS engine (local, zero-latency).
    func speak(_ text: String, languageCode: String = "en-US") {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
