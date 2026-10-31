import Testing
import Foundation
@testable import AudioBook

struct PiperSpeechTests {
    @Test func multiplierRoundTripsThroughUtteranceRate() {
        for multiplier in SpeechRate.multiplierSteps {
            let rate = SpeechRate.utteranceRate(forMultiplier: multiplier)
            #expect(abs(SpeechRate.multiplier(forUtteranceRate: rate) - multiplier) < 0.001)
        }
    }

    @Test func wordTimingCoversWordsInOrderWithinDuration() {
        let text = "Olá, mundo! Esta é uma frase."
        let words = WordTiming.estimate(text: text, duration: 3)
        let ns = text as NSString
        #expect(words.map { ns.substring(with: NSRange(location: $0.location, length: $0.length)) }
                == ["Olá", "mundo", "Esta", "é", "uma", "frase"])
        #expect(words.first?.start == 0)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.start < $1.start })
        #expect(words.last!.start < 3)
    }

    @Test func wordTimingGivesPunctuationExtraTime() {
        // "aa," e "aa" têm o mesmo tamanho, mas a vírgula alonga a primeira palavra.
        let words = WordTiming.estimate(text: "aa, aa bb", duration: 10)
        #expect(words[1].start - words[0].start > words[2].start - words[1].start)
    }

    @Test func wordTimingHandlesEmptyInput() {
        #expect(WordTiming.estimate(text: "   ", duration: 2).isEmpty)
        #expect(WordTiming.estimate(text: "palavra", duration: 0).isEmpty)
    }

    @Test func waveHeaderMatchesSamples() {
        let data = PCMWave.data(samples: [0, 1, -1, 2, .nan], sampleRate: 24000)
        #expect(data.count == 44 + 5 * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        let sampleRate = data.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: sampleRate) == 24000)
        let pcm = data.subdata(in: 44..<data.count).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(pcm == [0, Int16.max, -Int16.max, Int16.max, 0])
    }

    @Test func bundledPiperVoicesAreListedFirstForPortuguese() throws {
        let cadu = try #require(PiperVoices.model(forIdentifier: "piper:cadu-medium"))
        #expect(cadu.option.name == "Cadu" && cadu.option.language == "pt-BR")
        #expect(FileManager.default.fileExists(atPath: cadu.modelURL.path))
        #expect(VoiceCatalog.voices(forLanguage: "pt-BR").first?.quality == .neural)
        #expect(PiperVoices.model(forIdentifier: "piper:inexistente") == nil)
        #expect(!PiperVoices.isPiper("com.apple.voice.compact.pt-BR.Luciana"))
    }

    /// Integração real com o sherpa-onnx: carrega o modelo empacotado e gera áudio.
    @Test func piperSynthesizesPortugueseAudio() async throws {
        let cadu = try #require(PiperVoices.model(forIdentifier: "piper:cadu-medium"))
        let audio = try await PiperRunner.shared.synthesize(text: "Ontem à tarde, o Daniel tirou o carro.", voice: cadu, speed: 1.0)
        #expect(audio.sampleRate == 22050)
        let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
        #expect(seconds > 1 && seconds < 10)
        #expect(audio.samples.contains { abs($0) > 0.01 })
    }

    @MainActor
    @Test func piperHandsOffUnavailableVoiceInOrder() {
        let service = PiperSpeechService()
        var handed: [Int] = []
        service.onUnavailable = { handed += $0.map(\.id) }
        for id in 1...3 {
            service.enqueue(SpeechRequest(id: id, text: "Olá", voiceIdentifier: "piper:inexistente", languageCode: "pt-BR", rate: 0.5))
        }
        #expect(handed == [1, 2, 3])
        #expect(!service.isSpeaking)
    }

    @MainActor
    @Test func systemVoicesAreRoutedToSystemSynthesizer() {
        let system = MockSynthesizer()
        let service = RoutedSpeechService(system: system)
        var events: [SpeechEvent] = []
        service.onEvent = { events.append($0) }
        service.enqueue(SpeechRequest(id: 1, text: "Olá", voiceIdentifier: nil, languageCode: "pt-BR", rate: 0.5))
        #expect(system.queue.map(\.id) == [1])
        system.advance()
        #expect(events.contains(.finished(id: 1)))
    }
}
