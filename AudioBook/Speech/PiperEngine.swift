import Foundation
import OSLog
import SherpaOnnx

/// Vozes neurais do Piper empacotadas em `PiperVoices/<pasta>/` no app (modelo `.onnx` + `tokens.txt`),
/// com o `espeak-ng-data` compartilhado convertendo o texto em fonemas pt-BR.
/// Uma voz só aparece se a pasta dela estiver no bundle: o Miro (licença não comercial) fica fora do Git.
nonisolated enum PiperVoices {
    static let prefix = "piper:"

    struct Model: Equatable {
        let option: VoiceOption
        let modelURL: URL
        let tokensURL: URL
    }

    /// Pasta do modelo → nome exibido. Todas as vozes são pt-BR.
    private static let known: [(folder: String, name: String)] = [
        ("cadu-medium", "Cadu"),
        ("miro-high", "Miro"),
    ]

    static let root = Bundle.main.url(forResource: "PiperVoices", withExtension: nil)
    static var espeakDataURL: URL? { root?.appendingPathComponent("espeak-ng-data", isDirectory: true) }

    static let models: [Model] = {
        guard let root else { return [] }
        let fileManager = FileManager.default
        return known.compactMap { folder, name in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            let tokens = directory.appendingPathComponent("tokens.txt")
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
                  let model = files.first(where: { $0.pathExtension == "onnx" }),
                  fileManager.fileExists(atPath: tokens.path) else { return nil }
            let option = VoiceOption(id: prefix + folder, name: name, language: "pt-BR", quality: .neural)
            return Model(option: option, modelURL: model, tokensURL: tokens)
        }
    }()

    static var all: [VoiceOption] { models.map(\.option) }

    static func isPiper(_ identifier: String?) -> Bool {
        identifier?.hasPrefix(prefix) ?? false
    }

    static func model(forIdentifier identifier: String?) -> Model? {
        models.first { $0.option.id == identifier }
    }
}

enum PiperError: LocalizedError {
    case modelUnavailable
    case synthesisFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "Não foi possível carregar a voz neural."
        case .synthesisFailed: "A voz neural não gerou áudio para este trecho."
        }
    }
}

/// Dono do sintetizador do sherpa-onnx, que não é thread-safe: toda chamada passa por uma fila serial.
/// Mantém carregada só a última voz usada, para não ocupar memória com as duas.
nonisolated final class PiperRunner: @unchecked Sendable {
    static let shared = PiperRunner()

    private let queue = DispatchQueue(label: "br.com.estudoSwiftUI.AudioBook.piper", qos: .userInitiated)
    private var loaded: (id: String, tts: SherpaOnnxOfflineTtsWrapper)?
    private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Piper")

    /// Sintetiza `text` fora da thread principal. Retorna PCM mono e a taxa de amostragem do modelo.
    func synthesize(text: String, voice: PiperVoices.Model, speed: Double) async throws -> (samples: [Float], sampleRate: Int) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    let tts = try self.tts(for: voice)
                    let audio = tts.generate(text: text, sid: 0, speed: Float(speed))
                    guard audio.audio != nil, audio.n > 0 else { throw PiperError.synthesisFailed }
                    return (audio.samples, Int(audio.sampleRate))
                })
            }
        }
    }

    /// Chamado só dentro de `queue`.
    private func tts(for voice: PiperVoices.Model) throws -> SherpaOnnxOfflineTtsWrapper {
        if let loaded, loaded.id == voice.option.id { return loaded.tts }
        loaded = nil
        guard let espeak = PiperVoices.espeakDataURL else { throw PiperError.modelUnavailable }
        let vits = sherpaOnnxOfflineTtsVitsModelConfig(model: voice.modelURL.path, lexicon: "",
                                                       tokens: voice.tokensURL.path, dataDir: espeak.path)
        var config = sherpaOnnxOfflineTtsConfig(model: sherpaOnnxOfflineTtsModelConfig(vits: vits, numThreads: 2))
        let tts = SherpaOnnxOfflineTtsWrapper(config: &config)
        guard tts.tts != nil else {
            logger.error("Falha ao carregar a voz \(voice.option.id)")
            throw PiperError.modelUnavailable
        }
        loaded = (voice.option.id, tts)
        return tts
    }
}
