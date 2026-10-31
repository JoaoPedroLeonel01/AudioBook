import Foundation

/// Pedido de fala de um trecho. `id` é único dentro de uma sessão do motor.
struct SpeechRequest: Equatable {
    let id: Int
    let text: String
    let voiceIdentifier: String?
    let languageCode: String
    let rate: Float
}

enum SpeechEvent: Equatable {
    case started(id: Int)
    /// Intervalo (UTF-16) da palavra prestes a ser falada, relativo ao texto do pedido.
    case willSpeak(id: Int, location: Int, length: Int)
    case finished(id: Int)
}

/// Abstração do sintetizador para permitir testes determinísticos do motor de narração.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    var isPaused: Bool { get }
    var isSpeaking: Bool { get }
    func enqueue(_ request: SpeechRequest)
    func pause()
    func resume()
    /// Interrompe a fala e descarta toda a fila. Eventos de pedidos descartados não são emitidos.
    func stop()
}

nonisolated enum SpeechRate {
    static let minMultiplier = 0.5
    static let maxMultiplier = 2.0
    static let multiplierSteps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Converte o multiplicador percebido para a escala de `AVSpeechUtterance.rate` (0...1, padrão 0.5).
    /// 1.0x => 0.50; 0.5x => 0.30; 2.0x => 0.70 (acima disso a voz fica ininteligível).
    static func utteranceRate(forMultiplier multiplier: Double) -> Float {
        let m = min(max(multiplier, minMultiplier), maxMultiplier)
        let rate = m <= 1.0 ? 0.30 + (m - 0.5) * 0.4 : 0.50 + (m - 1.0) * 0.2
        return Float(rate)
    }

    /// Inverso de `utteranceRate(forMultiplier:)`, para sintetizadores que recebem o multiplicador (ex.: Piper).
    static func multiplier(forUtteranceRate rate: Float) -> Double {
        let r = Double(rate)
        let m = r <= 0.50 ? 0.5 + (r - 0.30) / 0.4 : 1.0 + (r - 0.50) / 0.2
        return min(max(m, minMultiplier), maxMultiplier)
    }

    static func label(for multiplier: Double) -> String {
        let text = multiplier.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(multiplier))
            : String(format: "%g", multiplier)
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }
}
