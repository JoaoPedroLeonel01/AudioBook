import Foundation
import Observation

/// Preferências de narração (voz, idioma, velocidade), persistidas em SwiftData.
@MainActor
@Observable
final class SettingsViewModel {
    static let automaticLanguage = "auto"

    @ObservationIgnored private let repository: BookRepository
    @ObservationIgnored private let preferences: UserPreferences
    @ObservationIgnored var onChange: (() -> Void)?

    var voiceIdentifier: String? { didSet { persist() } }
    var languageCode: String { didSet { persist() } }
    var speedMultiplier: Double { didSet { persist() } }

    private(set) var availableLanguages: [String] = []

    init(repository: BookRepository) {
        self.repository = repository
        let stored = repository.preferences()
        self.preferences = stored
        self.voiceIdentifier = stored.voiceIdentifier
        self.languageCode = stored.languageCode
        self.speedMultiplier = stored.speedMultiplier
        self.availableLanguages = VoiceCatalog.availableLanguages()
    }

    /// Idioma efetivo para um livro: o escolhido, ou o do livro no modo automático.
    func effectiveLanguage(forBookLanguage bookLanguage: String?) -> String {
        if languageCode != Self.automaticLanguage { return languageCode }
        return VoiceCatalog.supportedLanguage(forBookLanguage: bookLanguage) ?? "pt-BR"
    }

    func speechSettings(forBookLanguage bookLanguage: String?) -> SpeechSettings {
        let language = effectiveLanguage(forBookLanguage: bookLanguage)
        var voice = voiceIdentifier
        // Voz escolhida de outro idioma não deve ser usada para o idioma efetivo.
        if let id = voice, let match = VoiceCatalog.allVoices().first(where: { $0.id == id }),
           !match.language.lowercased().hasPrefix(String(language.lowercased().prefix(2))) {
            voice = nil
        }
        return SpeechSettings(voiceIdentifier: voice, languageCode: language,
                              rate: SpeechRate.utteranceRate(forMultiplier: speedMultiplier))
    }

    /// Vozes do idioma selecionado (ou de todos, no modo automático).
    func voicesForPicker() -> [VoiceOption] {
        languageCode == Self.automaticLanguage
            ? VoiceCatalog.voices(forLanguage: "pt-BR")
            : VoiceCatalog.voices(forLanguage: languageCode)
    }

    func setLanguage(_ code: String) {
        languageCode = code
        if let id = voiceIdentifier, code != Self.automaticLanguage,
           let voice = VoiceCatalog.allVoices().first(where: { $0.id == id }),
           !voice.language.lowercased().hasPrefix(String(code.lowercased().prefix(2))) {
            voiceIdentifier = nil
        }
    }

    private func persist() {
        preferences.voiceIdentifier = voiceIdentifier
        preferences.languageCode = languageCode
        preferences.speedMultiplier = speedMultiplier
        repository.savePreferences()
        onChange?()
    }
}
