import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Narração") {
                Picker("Idioma", selection: Binding(get: { settings.languageCode }, set: { settings.setLanguage($0) })) {
                    Text("Automático (idioma do livro)").tag(SettingsViewModel.automaticLanguage)
                    ForEach(settings.availableLanguages, id: \.self) { Text(VoiceCatalog.displayName(forLanguage: $0)).tag($0) }
                }
                Picker("Voz", selection: $settings.voiceIdentifier) {
                    Text("Automática (melhor disponível)").tag(String?.none)
                    ForEach(settings.voicesForPicker()) { voice in
                        Text("\(voice.name) • \(voice.quality.label)").tag(Optional(voice.id))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Velocidade")
                        Spacer()
                        Text(SpeechRate.label(for: settings.speedMultiplier)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.speedMultiplier, in: SpeechRate.minMultiplier...SpeechRate.maxMultiplier, step: 0.05)
                        .accessibilityLabel("Velocidade da fala")
                        .accessibilityValue(SpeechRate.label(for: settings.speedMultiplier))
                }
                Text("Para vozes mais naturais, baixe vozes “Aprimoradas” ou “Premium” em Ajustes › Acessibilidade › Conteúdo Falado › Vozes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Teste de voz") {
                VoiceLabView()
            }
            Section("Privacidade") {
                Label("Os livros ficam somente neste aparelho e a narração é gerada nele, sem enviar conteúdo para a internet. As vozes neurais vêm dentro do app.", systemImage: "lock.shield")
                    .font(.footnote)
            }
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

/// Prova de conceito de áudio: narra um texto livre com iniciar, pausar, retomar e parar.
struct VoiceLabView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Environment(PlayerViewModel.self) private var player
    @State private var model = VoiceLabModel()
    @State private var text = "Olá! Esta é uma amostra da voz que vai narrar os seus livros. Ajuste a velocidade e escolha a voz de que mais gostar."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Texto de teste", text: $text, axis: .vertical).lineLimit(2...5)
            HStack {
                Button(model.state == .idle ? "Ouvir" : "Reiniciar", systemImage: "play.fill") {
                    player.pausePlayback()
                    model.play(text, settings: settings.speechSettings(forBookLanguage: nil), languageHint: settings.effectiveLanguage(forBookLanguage: nil))
                }
                if model.state == .speaking {
                    Button("Pausar", systemImage: "pause.fill") { model.pause() }
                } else if model.state == .paused {
                    Button("Retomar", systemImage: "playpause.fill") { model.resume() }
                }
                if model.state != .idle {
                    Button("Parar", systemImage: "stop.fill", role: .destructive) { model.stop() }
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { model.stop() }
    }
}

@MainActor
@Observable
final class VoiceLabModel {
    enum State { case idle, speaking, paused }
    private(set) var state: State = .idle
    @ObservationIgnored private let service = RoutedSpeechService()
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var voiceName = ""

    var statusText: String {
        switch state {
        case .idle: "Parado"
        case .speaking: "Falando com \(voiceName)…"
        case .paused: "Pausado"
        }
    }

    init() {
        service.onEvent = { [weak self] event in
            guard let self else { return }
            if case .finished(let id) = event, id == requestID { state = .idle }
        }
    }

    func play(_ text: String, settings: SpeechSettings, languageHint: String) {
        service.stop()
        requestID += 1
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }
        voiceName = PiperVoices.model(forIdentifier: settings.voiceIdentifier)?.option.name
            ?? SpeechService.resolveVoice(identifier: settings.voiceIdentifier, languageCode: languageHint)?.name ?? "voz padrão"
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        service.enqueue(SpeechRequest(id: requestID, text: trimmed, voiceIdentifier: settings.voiceIdentifier, languageCode: languageHint, rate: settings.rate))
        state = .speaking
    }

    func pause() { service.pause(); state = .paused }
    func resume() { service.resume(); state = .speaking }
    func stop() { service.stop(); state = .idle }
}
