import Foundation
import SwiftData

/// Preferências de narração (linha única).
@Model
final class UserPreferences {
    var voiceIdentifier: String?
    /// Código BCP-47 (ex.: "pt-BR") ou "auto" para seguir o idioma do livro.
    var languageCode: String
    /// Multiplicador de velocidade percebida (0.5x ... 2.0x).
    var speedMultiplier: Double
    var updatedAt: Date

    init(voiceIdentifier: String? = nil, languageCode: String = "pt-BR", speedMultiplier: Double = 1.0) {
        self.voiceIdentifier = voiceIdentifier
        self.languageCode = languageCode
        self.speedMultiplier = speedMultiplier
        self.updatedAt = .now
    }
}
