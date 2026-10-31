import AVFoundation
import OSLog

/// Implementação de `SpeechSynthesizing` com as vozes neurais do Piper (sherpa-onnx), geradas no aparelho.
///
/// Cada pedido vira um WAV em memória tocado por `AVAudioPlayer`; o pedido seguinte é sintetizado
/// enquanto o atual toca. O Piper não informa o tempo de cada palavra, então `willSpeak` é estimado
/// distribuindo a duração do áudio pelas palavras (`WordTiming`).
///
/// Se a síntese falhar, o serviço fica indisponível até o próximo `stop()`: o que já foi sintetizado termina de
/// tocar e o restante, em ordem, é repassado a `onUnavailable` (sem sobrepor áudio nem pular trechos).
@MainActor
final class PiperSpeechService: NSObject, SpeechSynthesizing {
    var onEvent: ((SpeechEvent) -> Void)?
    /// Recebe, em ordem, os pedidos que este serviço não vai falar.
    var onUnavailable: (([SpeechRequest]) -> Void)?

    private struct Prepared {
        let request: SpeechRequest
        let player: AVAudioPlayer
        let words: [WordTiming.Word]
    }

    private let runner: PiperRunner
    /// Pedidos aguardando síntese, em ordem.
    private var waiting: [SpeechRequest] = []
    /// Pedidos sintetizados aguardando a vez de tocar.
    private var prepared: [Prepared] = []
    private var current: Prepared?
    private var synthesizing = false
    private var generation = 0
    private var wordTimer: Task<Void, Never>?
    private var isUnavailable = false
    /// Pedidos a repassar quando o áudio já sintetizado terminar.
    private var handoff: [SpeechRequest] = []
    private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Piper")

    private(set) var isPaused = false
    var isSpeaking: Bool { current != nil || synthesizing || !waiting.isEmpty || !prepared.isEmpty || !handoff.isEmpty }

    init(runner: PiperRunner = .shared) {
        self.runner = runner
        super.init()
    }

    func enqueue(_ request: SpeechRequest) {
        if isUnavailable {
            handoff.append(request)
            flushHandoff()
            return
        }
        waiting.append(request)
        synthesizeNext()
    }

    func pause() {
        guard isSpeaking else { return }
        isPaused = true
        current?.player.pause()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        if let current {
            current.player.play()
        } else {
            playNext()
        }
    }

    func stop() {
        generation += 1  // sínteses em andamento passam a ser descartadas
        wordTimer?.cancel()
        wordTimer = nil
        current?.player.stop()
        current = nil
        waiting.removeAll()
        prepared.removeAll()
        handoff.removeAll()
        synthesizing = false
        isPaused = false
        isUnavailable = false  // a próxima narração tenta o Piper de novo
    }

    // MARK: - Síntese

    private func synthesizeNext() {
        guard !synthesizing, !isUnavailable, let request = waiting.first else { return }
        guard let voice = PiperVoices.model(forIdentifier: request.voiceIdentifier) else {
            becomeUnavailable(PiperError.modelUnavailable)
            return
        }
        synthesizing = true
        let token = generation
        let speed = SpeechRate.multiplier(forUtteranceRate: request.rate)
        Task {
            do {
                let audio = try await runner.synthesize(text: request.text, voice: voice, speed: speed)
                guard token == generation else { return }
                let player = try AVAudioPlayer(data: PCMWave.data(samples: audio.samples, sampleRate: audio.sampleRate))
                player.delegate = self
                player.prepareToPlay()
                let words = WordTiming.estimate(text: request.text, duration: player.duration)
                waiting.removeFirst()
                prepared.append(Prepared(request: request, player: player, words: words))
                synthesizing = false
                playNext()
                synthesizeNext()
            } catch {
                guard token == generation else { return }
                synthesizing = false
                becomeUnavailable(error)
            }
        }
    }

    private func becomeUnavailable(_ error: Error) {
        logger.error("Piper indisponível; usando a voz do sistema: \(error.localizedDescription)")
        isUnavailable = true
        handoff = waiting + handoff
        waiting.removeAll()
        flushHandoff()
    }

    private func flushHandoff() {
        guard isUnavailable, current == nil, prepared.isEmpty, !handoff.isEmpty else { return }
        let requests = handoff
        handoff.removeAll()
        onUnavailable?(requests)
    }

    // MARK: - Reprodução

    private func playNext() {
        guard current == nil, !isPaused, !prepared.isEmpty else { return }
        let next = prepared.removeFirst()
        current = next
        next.player.play()
        onEvent?(.started(id: next.request.id))
        trackWords(of: next)
    }

    /// Emite `willSpeak` conforme o tempo de reprodução passa pelo início estimado de cada palavra.
    private func trackWords(of item: Prepared) {
        wordTimer?.cancel()
        guard !item.words.isEmpty else { return }
        wordTimer = Task { [weak self] in
            var spoken = -1
            while !Task.isCancelled {
                guard let self, let current = self.current, current.player === item.player else { return }
                let time = current.player.currentTime
                let index = item.words.lastIndex { $0.start <= time } ?? -1
                if index > spoken {
                    spoken = index
                    let word = item.words[index]
                    self.onEvent?(.willSpeak(id: item.request.id, location: word.location, length: word.length))
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    fileprivate func playerFinished(_ player: AVAudioPlayer) {
        guard let current, current.player === player else { return }
        wordTimer?.cancel()
        wordTimer = nil
        self.current = nil
        onEvent?(.finished(id: current.request.id))
        playNext()
        flushHandoff()
    }
}

extension PiperSpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let key = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.current, ObjectIdentifier(current.player) == key else { return }
            self.playerFinished(current.player)
        }
    }
}

/// Estimativa do instante em que cada palavra começa, proporcional ao tamanho das palavras,
/// com peso extra para as pausas de pontuação.
nonisolated enum WordTiming {
    struct Word: Equatable {
        /// Intervalo UTF-16 relativo ao texto do pedido.
        let location: Int
        let length: Int
        let start: TimeInterval
    }

    static func estimate(text: String, duration: TimeInterval) -> [Word] {
        let string = text as NSString
        var ranges: [NSRange] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        guard !ranges.isEmpty, duration > 0 else { return [] }
        let weights = ranges.enumerated().map { index, range -> Double in
            let gapEnd = index + 1 < ranges.count ? ranges[index + 1].location : string.length
            let gap = string.substring(with: NSRange(location: range.upperBound, length: gapEnd - range.upperBound))
            return Double(range.length) + pauseWeight(after: gap)
        }
        let unit = duration / weights.reduce(0, +)
        var elapsed = 0.0
        return zip(ranges, weights).map { range, weight in
            defer { elapsed += weight * unit }
            return Word(location: range.location, length: range.length, start: elapsed)
        }
    }

    private static func pauseWeight(after gap: String) -> Double {
        if gap.contains(where: { ".!?…".contains($0) }) { return 6 }
        if gap.contains(where: { ",;:—".contains($0) }) { return 3 }
        return 1
    }
}

/// WAV PCM 16 bits mono em memória, para tocar amostras `Float` com `AVAudioPlayer`.
nonisolated enum PCMWave {
    static func data(samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * bytesPerSample))
        append(UInt16(bytesPerSample))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(dataSize))
        let pcm = samples.map { sample -> Int16 in
            let clamped = sample.isFinite ? max(-1, min(1, sample)) : 0
            return Int16(clamped * Float(Int16.max)).littleEndian
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
