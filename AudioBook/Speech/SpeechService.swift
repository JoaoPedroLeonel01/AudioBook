import AVFoundation

/// Implementação de `SpeechSynthesizing` sobre `AVSpeechSynthesizer`.
@MainActor
final class SpeechService: NSObject, SpeechSynthesizing {
    var onEvent: ((SpeechEvent) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Mantém os utterances vivos e mapeia cada um ao id do pedido.
    private var pending: [ObjectIdentifier: (id: Int, utterance: AVSpeechUtterance)] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isPaused: Bool { synthesizer.isPaused }
    var isSpeaking: Bool { synthesizer.isSpeaking }

    func enqueue(_ request: SpeechRequest) {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.rate = min(max(request.rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.voice = Self.resolveVoice(identifier: request.voiceIdentifier, languageCode: request.languageCode)
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        pending[ObjectIdentifier(utterance)] = (request.id, utterance)
        synthesizer.speak(utterance)
    }

    func pause() { synthesizer.pauseSpeaking(at: .immediate) }

    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        pending.removeAll()  // eventos de cancelamento passam a ser ignorados
        synthesizer.stopSpeaking(at: .immediate)
    }

    static func resolveVoice(identifier: String?, languageCode: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        return VoiceCatalog.bestVoice(forLanguage: languageCode) ?? AVSpeechSynthesisVoice(language: languageCode)
    }

    fileprivate func handle(_ utteranceKey: ObjectIdentifier, finished: Bool = false, _ build: (Int) -> SpeechEvent) {
        guard let entry = pending[utteranceKey] else { return }
        if finished { pending[utteranceKey] = nil }
        onEvent?(build(entry.id))
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.handle(key) { .started(id: $0) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        let location = characterRange.location, length = characterRange.length
        Task { @MainActor in self.handle(key) { .willSpeak(id: $0, location: location, length: length) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.handle(key, finished: true) { .finished(id: $0) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancelamentos só ocorrem via stop(), que já limpou `pending`.
    }
}
