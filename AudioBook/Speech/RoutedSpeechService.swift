import Foundation

/// Encaminha cada pedido ao sintetizador da voz escolhida: Piper para vozes `piper:`, sistema para as demais.
/// Se o Piper falhar (ou a voz salva não estiver no app), os pedidos caem para a melhor voz do sistema.
@MainActor
final class RoutedSpeechService: SpeechSynthesizing {
    var onEvent: ((SpeechEvent) -> Void)?

    private let system: SpeechSynthesizing
    private let neural: PiperSpeechService

    init(system: SpeechSynthesizing? = nil, neural: PiperSpeechService? = nil) {
        let system = system ?? SpeechService()
        self.system = system
        self.neural = neural ?? PiperSpeechService()
        system.onEvent = { [weak self] event in self?.onEvent?(event) }
        self.neural.onEvent = { [weak self] event in self?.onEvent?(event) }
        self.neural.onUnavailable = { [weak self] requests in
            requests.forEach { self?.system.enqueue($0.withSystemVoice()) }
        }
    }

    var isPaused: Bool { system.isPaused || neural.isPaused }
    var isSpeaking: Bool { system.isSpeaking || neural.isSpeaking }

    func enqueue(_ request: SpeechRequest) {
        if PiperVoices.model(forIdentifier: request.voiceIdentifier) != nil {
            neural.enqueue(request)
        } else {
            system.enqueue(request.withSystemVoice())
        }
    }

    func pause() {
        system.pause()
        neural.pause()
    }

    func resume() {
        system.resume()
        neural.resume()
    }

    func stop() {
        system.stop()
        neural.stop()
    }
}

private extension SpeechRequest {
    /// O mesmo pedido sem voz do Piper, para o sintetizador do sistema escolher a melhor voz do idioma.
    func withSystemVoice() -> SpeechRequest {
        guard PiperVoices.isPiper(voiceIdentifier) else { return self }
        return SpeechRequest(id: id, text: text, voiceIdentifier: nil, languageCode: languageCode, rate: rate)
    }
}
