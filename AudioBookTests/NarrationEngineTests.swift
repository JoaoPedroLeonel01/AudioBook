import Testing
import Foundation
@testable import AudioBook

/// Sintetizador falso: a fila é consumida manualmente pelo teste via `advance()`.
@MainActor
final class MockSynthesizer: SpeechSynthesizing {
    var onEvent: ((SpeechEvent) -> Void)?
    private(set) var queue: [SpeechRequest] = []
    private(set) var spoken: [SpeechRequest] = []
    private(set) var paused = false
    private(set) var stopCount = 0
    var isPaused: Bool { paused }
    var isSpeaking: Bool { !queue.isEmpty }

    func enqueue(_ request: SpeechRequest) { queue.append(request) }
    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { queue.removeAll(); paused = false; stopCount += 1 }

    /// Fala o primeiro item da fila por completo.
    func advance() {
        guard let request = queue.first else { return }
        onEvent?(.started(id: request.id))
        onEvent?(.willSpeak(id: request.id, location: 0, length: 3))
        queue.removeFirst()
        spoken.append(request)
        onEvent?(.finished(id: request.id))
    }
}

@MainActor
struct NarrationEngineTests {
    static let settings = SpeechSettings(voiceIdentifier: nil, languageCode: "pt-BR", rate: 0.5)

    /// Três capítulos curtos; cada parágrafo (<500 caracteres, sem espaço final) vira exatamente um trecho.
    static func chapterText(_ index: Int) -> String {
        (0..<3).map { "Capítulo \(index) parágrafo \($0): " + String(repeating: "texto ", count: 60).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    func makeEngine(chapters: Int = 3, failing: Set<Int> = []) -> (NarrationEngine, MockSynthesizer) {
        let mock = MockSynthesizer()
        let engine = NarrationEngine(synthesizer: mock, settings: Self.settings)
        engine.configure(chapterCount: chapters) { index in
            if failing.contains(index) { throw EPUBError.chapterUnavailable(index) }
            return Self.chapterText(index)
        }
        return (engine, mock)
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func playsEveryChunkOfEveryChapterInOrderWithoutRepeatsOrGaps() async {
        let (engine, mock) = makeEngine()
        var chapterEvents: [Int] = []
        engine.onChapterChanged = { chapterEvents.append($0) }
        var finished = false
        engine.onFinished = { finished = true }
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        while engine.state != .finished {
            await waitUntil { !mock.queue.isEmpty || engine.state == .finished }
            mock.advance()
        }
        #expect(finished)
        #expect(chapterEvents == [1, 2])  // chapter 0 já era a posição inicial
        // Reconstrói o texto narrado e compara com o texto original (sem omissões nem repetições).
        let spokenText = mock.spoken.map(\.text).joined(separator: "\n")
        let expected = (0..<3).map(Self.chapterText).joined(separator: "\n")
        #expect(spokenText == expected)
        #expect(Set(mock.spoken.map(\.id)).count == mock.spoken.count)
        #expect(engine.position == NarrationPosition(chapter: 2, offset: Self.chapterText(2).utf16.count))
    }

    @Test func keepsOnlyShortLookaheadQueued() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        #expect(mock.queue.count == 2)
        mock.advance()
        #expect(mock.queue.count == 2)
    }

    @Test func pauseAndResumeContinueFromSamePlace() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        mock.advance()
        engine.pause()
        #expect(engine.state == .paused && mock.paused)
        let before = mock.spoken.count
        mock.advance()  // evento tardio durante a pausa não pode enfileirar nada novo
        #expect(engine.state == .paused)
        engine.resume()
        #expect(engine.state == .playing && !mock.paused)
        await waitUntil { mock.queue.count == 2 }
        #expect(mock.spoken.count == before + 1)
        #expect(mock.spoken.map(\.text).first != mock.queue.first?.text)  // sem repetir o que já foi falado
    }

    @Test func rateChangeRestartsFromCurrentWordWithoutLosingPlace() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 1)
        await waitUntil { !mock.queue.isEmpty }
        let first = mock.queue[0]
        mock.onEvent?(.started(id: first.id))
        mock.onEvent?(.willSpeak(id: first.id, location: 40, length: 5))
        engine.updateSettings(SpeechSettings(voiceIdentifier: nil, languageCode: "pt-BR", rate: 0.7))
        await waitUntil { !mock.queue.isEmpty && mock.queue[0].rate == 0.7 }
        #expect(mock.queue[0].rate == 0.7)
        #expect(mock.queue[0].text == String(first.text.dropFirst(40)))
        #expect(mock.queue.count <= 2)
    }

    @Test func rateChangeWhilePausedAppliesOnResume() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        engine.pause()
        engine.updateSettings(SpeechSettings(voiceIdentifier: nil, languageCode: "pt-BR", rate: 0.3))
        #expect(engine.state == .paused && mock.queue.isEmpty)
        engine.resume()
        await waitUntil { !mock.queue.isEmpty }
        #expect(mock.queue.first?.rate == 0.3)
    }

    @Test func nextAndPreviousChapter() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        engine.nextChapter()
        await waitUntil { engine.position.chapter == 1 && !mock.queue.isEmpty }
        #expect(mock.queue.first?.text.hasPrefix("Capítulo 1") == true)
        engine.previousChapter()  // posição no início do capítulo -> volta ao anterior
        await waitUntil { engine.position.chapter == 0 && mock.queue.first?.text.hasPrefix("Capítulo 0") == true }
        #expect(engine.position.chapter == 0)
        engine.previousChapter()  // primeiro capítulo: reinicia no início
        #expect(engine.position == NarrationPosition(chapter: 0, offset: 0))
    }

    @Test func seekWhilePausedStaysPausedAndPlaysFromTarget() async {
        let (engine, mock) = makeEngine()
        engine.prepare(chapter: 0, offset: 0)
        #expect(engine.state == .paused)
        engine.seek(chapter: 2, offset: 10)
        #expect(engine.state == .paused && mock.queue.isEmpty)
        engine.resume()
        await waitUntil { !mock.queue.isEmpty }
        #expect(engine.position.chapter == 2)
        #expect(mock.queue.first?.text.hasPrefix("Capítulo 2") == false)  // começou no offset 10, no meio do trecho
        #expect(mock.queue.first?.text == String(Self.chapterText(2).utf16.dropFirst(10))!.components(separatedBy: "\n").first!)
    }

    @Test func resumesFromSavedOffset() async {
        let (engine, mock) = makeEngine()
        let text = Self.chapterText(1)
        let offset = (text as NSString).range(of: "parágrafo 1").location
        engine.prepare(chapter: 1, offset: offset)
        engine.resume()
        await waitUntil { !mock.queue.isEmpty }
        #expect(mock.queue.first?.text.hasPrefix("parágrafo 1") == true)
    }

    @Test func skipsUnavailableChapterDuringPlayback() async {
        let (engine, mock) = makeEngine(failing: [1])
        engine.start(chapter: 0)
        var guardCount = 0
        while engine.state != .finished && guardCount < 100 {
            guardCount += 1
            await waitUntil { !mock.queue.isEmpty || engine.state == .finished }
            mock.advance()
        }
        let texts = mock.spoken.map(\.text).joined(separator: "\n")
        #expect(texts.contains("Capítulo 0") && texts.contains("Capítulo 2") && !texts.contains("Capítulo 1"))
        #expect(engine.state == .finished)
    }

    @Test func failingFirstChapterReportsError() async {
        let (engine, _) = makeEngine(failing: [0])
        engine.start(chapter: 0)
        await waitUntil { if case .failed = engine.state { true } else { false } }
        guard case .failed(let message) = engine.state else { Issue.record("esperava falha"); return }
        #expect(!message.isEmpty)
    }

    @Test func staleLoadsAreDiscardedWhenCommandsOverlap() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        engine.start(chapter: 2)  // comando concorrente antes do primeiro terminar
        engine.start(chapter: 1)
        await waitUntil { !mock.queue.isEmpty }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(mock.queue.allSatisfy { $0.text.hasPrefix("Capítulo 1") })
        #expect(engine.position.chapter == 1)
    }

    @Test func highlightTracksChunkAndWord() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 1)
        await waitUntil { !mock.queue.isEmpty }
        let first = mock.queue[0]
        mock.onEvent?(.started(id: first.id))
        mock.onEvent?(.willSpeak(id: first.id, location: 12, length: 4))
        let h = engine.highlight
        #expect(h?.chapter == 1 && h?.wordLength == 4)
        #expect(h?.wordStart == (h?.chunkStart ?? 0) + 12)
        engine.stop()
        #expect(engine.highlight == nil)
    }

    @Test func stopClearsEverything() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        engine.stop()
        #expect(engine.state == .idle && mock.queue.isEmpty)
        mock.onEvent?(.finished(id: 0))  // evento tardio é ignorado
        #expect(engine.state == .idle)
    }

    @Test func skipForwardAndBackwardMoveByChunk() async {
        let (engine, mock) = makeEngine()
        engine.start(chapter: 0)
        await waitUntil { !mock.queue.isEmpty }
        engine.skipForward()
        await waitUntil { engine.position.offset > 0 && !mock.queue.isEmpty }
        let second = engine.position.offset
        #expect(second > 0)
        engine.skipBackward()
        await waitUntil { engine.position.offset == 0 && !mock.queue.isEmpty }
        #expect(engine.position.offset == 0)
    }
}
