import AVFoundation

nonisolated struct VoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: Quality

    enum Quality: Int, Comparable {
        case standard = 0, enhanced = 1, premium = 2, neural = 3
        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .standard: "Padrão"
            case .enhanced: "Aprimorada"
            case .premium: "Premium"
            case .neural: "Neural"
            }
        }
    }
}

nonisolated enum VoiceCatalog {
    /// Vozes do sistema e vozes neurais do Piper empacotadas no app.
    static func allVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices().map(option(for:)) + PiperVoices.all
    }

    static func voices(forLanguage code: String) -> [VoiceOption] {
        let prefix = languagePrefix(code)
        return allVoices()
            .filter { $0.language.lowercased().hasPrefix(prefix) }
            .sorted { ($0.quality, $1.name) > ($1.quality, $0.name) }
    }

    /// Idiomas com vozes instaladas (código BCP-47), com pt-BR e o idioma do sistema primeiro.
    static func availableLanguages() -> [String] {
        let all = Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))
        let preferred = ["pt-BR", Locale.current.identifier.replacingOccurrences(of: "_", with: "-")]
        return all.sorted { lhs, rhs in
            let l = preferred.firstIndex(of: lhs) ?? Int.max, r = preferred.firstIndex(of: rhs) ?? Int.max
            return l != r ? l < r : lhs < rhs
        }
    }

    static func bestVoice(forLanguage code: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code }
        let pool = candidates.isEmpty
            ? AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(languagePrefix(code)) }
            : candidates
        return pool.max { quality(of: $0) < quality(of: $1) }
    }

    static func displayName(forLanguage code: String) -> String {
        Locale(identifier: "pt_BR").localizedString(forIdentifier: code)?.capitalized ?? code
    }

    /// Mapeia o código de idioma de um EPUB (ex.: "pt", "en-US") para um idioma com voz disponível.
    static func supportedLanguage(forBookLanguage language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        let normalized = language.replacingOccurrences(of: "_", with: "-")
        let available = availableLanguages()
        if available.contains(normalized) { return normalized }
        let prefix = languagePrefix(normalized)
        if prefix == "pt", available.contains("pt-BR") { return "pt-BR" }
        return available.first { $0.lowercased().hasPrefix(prefix) }
    }

    private static func languagePrefix(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    private static func quality(of voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: 2
        case .enhanced: 1
        default: 0
        }
    }

    private static func option(for voice: AVSpeechSynthesisVoice) -> VoiceOption {
        VoiceOption(id: voice.identifier, name: voice.name, language: voice.language, quality: VoiceOption.Quality(rawValue: quality(of: voice)) ?? .standard)
    }
}

