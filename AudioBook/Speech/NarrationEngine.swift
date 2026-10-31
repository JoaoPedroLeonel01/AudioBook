import Foundation
import Observation
import OSLog

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case finished
    case failed(String)

    var isActive: Bool { self == .playing || self == .loading }
}

struct NarrationPosition: Equatable {
    var chapter: Int
    /// Offset UTF-16 dentro do texto normalizado do capítulo.
    var offset: Int
}

/// Trecho e palavra sendo falados (offsets UTF-16 relativos ao texto do capítulo), para leitura acompanhada.
struct SpokenHighlight: Equatable {
    var chapter: Int
    var wordStart: Int
    var wordLength: Int
    var chunkStart: Int
    var chunkEnd: Int
}

struct SpeechSettings: Equatable {
    var voiceIdentifier: String?
    var languageCode: String
    var rate: Float
}

/// Motor de narração: mantém uma fila curta de trechos no sintetizador, avança entre trechos e
/// capítulos e mantém a posição atual. Apenas capítulos próximos ficam na memória.
///
/// Consistência: toda operação que reposiciona a fala incrementa `generation`; resultados
/// assíncronos de gerações antigas são descartados, e eventos de pedidos que não estão em
/// `inFlight` são ignorados, evitando repetições, omissões e comandos concorrentes inconsistentes.
@MainActor
@Observable
final class NarrationEngine {
    private(set) var state: PlaybackState = .idle {
        didSet { if oldValue != state { onStateChanged?(state) } }
    }
    private(set) var position = NarrationPosition(chapter: 0, offset: 0)
    private(set) var chapterCount = 0
    private(set) var highlight: SpokenHighlight?
    var settings: SpeechSettings

    @ObservationIgnored var onChapterChanged: ((Int) -> Void)?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onStateChanged: ((PlaybackState) -> Void)?

    private struct LoadedChapter {
        let text: NSString
        let chunks: [TextChunk]
    }

    private struct QueuedItem {
        let id: Int
        let chapter: Int
        let start: Int
        let end: Int
    }

    private struct Cursor {
        var chapter: Int
        var chunk: Int
        var firstOffset: Int?
    }

    @ObservationIgnored private let synthesizer: SpeechSynthesizing
    @ObservationIgnored private var loader: ((Int) async throws -> String)?
    @ObservationIgnored private var chapters: [Int: LoadedChapter] = [:]
    @ObservationIgnored private var inFlight: [QueuedItem] = []
    @ObservationIgnored private var cursor: Cursor?
    @ObservationIgnored private var loadingChapter: Int?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var restartOnResume = false
    @ObservationIgnored private let lookahead = 2
    @ObservationIgnored private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Narration")

    init(synthesizer: SpeechSynthesizing, settings: SpeechSettings) {
        self.synthesizer = synthesizer
        self.settings = settings
        synthesizer.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Configuração do livro

    /// Prepara o motor para um livro. Interrompe qualquer narração em andamento.
    func configure(chapterCount: Int, loader: @escaping (Int) async throws -> String) {
        stop()
        self.chapterCount = chapterCount
        self.loader = loader
        chapters = [:]
    }

    func updateSettings(_ new: SpeechSettings) {
        guard new != settings else { return }
        settings = new
        switch state {
        case .playing, .loading:
            start(chapter: position.chapter, offset: position.offset)
        case .paused:
            discardQueue()
            restartOnResume = true
        default:
            break
        }
    }

    // MARK: - Comandos

    /// Inicia (ou reposiciona) a narração em `chapter`/`offset`.
    func start(chapter: Int, offset: Int = 0) {
        guard chapterCount > 0, loader != nil else { return }
        let target = min(max(chapter, 0), chapterCount - 1)
        discardQueue()
        restartOnResume = false
        let changedChapter = target != position.chapter
        position = NarrationPosition(chapter: target, offset: max(offset, 0))
        if changedChapter { onChapterChanged?(target) }
        state = .loading
        let token = generation

        Task {
            do {
                let loaded = try await ensureLoaded(target)
                guard token == generation else { return }
                guard !loaded.chunks.isEmpty else { throw EPUBError.chapterUnavailable(target) }
                let index = TextChunker.index(of: position.offset, in: loaded.chunks)
                cursor = Cursor(chapter: target, chunk: index, firstOffset: position.offset)
                state = .playing
                fillQueue()
            } catch {
                guard token == generation else { return }
                logger.error("Falha ao iniciar capítulo \(target): \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Posiciona o motor em pausa, sem iniciar a fala (usado ao abrir um livro).
    func prepare(chapter: Int, offset: Int) {
        guard chapterCount > 0 else { return }
        discardQueue()
        cursor = nil
        position = NarrationPosition(chapter: min(max(chapter, 0), chapterCount - 1), offset: max(offset, 0))
        restartOnResume = true
        state = .paused
    }

    func pause() {
        switch state {
        case .playing:
            synthesizer.pause()
            state = .paused
        case .loading:
            discardQueue()
            restartOnResume = true
            state = .paused
        default:
            break
        }
    }

    func resume() {
        guard state == .paused else { return }
        if restartOnResume || (inFlight.isEmpty && cursor == nil) {
            start(chapter: position.chapter, offset: position.offset)
            return
        }
        state = .playing
        if synthesizer.isPaused {
            synthesizer.resume()
        } else if !inFlight.isEmpty && !synthesizer.isSpeaking {
            // Sintetizador perdeu a fila (ex.: interrupção do sistema): recomeça da posição atual.
            start(chapter: position.chapter, offset: position.offset)
            return
        }
        fillQueue()
    }

    func stop() {
        discardQueue()
        restartOnResume = false
        cursor = nil
        state = .idle
    }

    func seek(chapter: Int, offset: Int = 0) {
        guard chapterCount > 0 else { return }
        if state == .paused || state == .finished {
            discardQueue()
            let target = min(max(chapter, 0), chapterCount - 1)
            let changed = target != position.chapter
            position = NarrationPosition(chapter: target, offset: max(offset, 0))
            restartOnResume = true
            state = .paused
            if changed { onChapterChanged?(target) }
        } else {
            start(chapter: chapter, offset: offset)
        }
    }

    func nextChapter() {
        guard position.chapter + 1 < chapterCount else { return }
        seek(chapter: position.chapter + 1)
    }

    func previousChapter() {
        if position.offset > 200 || position.chapter == 0 {
            seek(chapter: position.chapter, offset: 0)
        } else {
            seek(chapter: position.chapter - 1)
        }
    }

    func skipForward() {
        guard let loaded = chapters[position.chapter] else { return }
        let index = TextChunker.index(of: position.offset, in: loaded.chunks)
        if index + 1 < loaded.chunks.count {
            seek(chapter: position.chapter, offset: loaded.chunks[index + 1].start)
        } else {
            nextChapter()
        }
    }

    func skipBackward() {
        guard let loaded = chapters[position.chapter], !loaded.chunks.isEmpty else { return }
        let index = TextChunker.index(of: position.offset, in: loaded.chunks)
        let chunkStart = loaded.chunks[index].start
        if position.offset - chunkStart > 120 {
            seek(chapter: position.chapter, offset: chunkStart)
        } else if index > 0 {
            seek(chapter: position.chapter, offset: loaded.chunks[index - 1].start)
        } else {
            seek(chapter: max(position.chapter - 1, 0), offset: 0)
        }
    }

    // MARK: - Fila

    private func discardQueue() {
        generation += 1
        highlight = nil
        synthesizer.stop()
        inFlight.removeAll()
        loadingChapter = nil
    }

    private func ensureLoaded(_ index: Int) async throws -> LoadedChapter {
        if let cached = chapters[index] { return cached }
        guard let loader else { throw EPUBError.chapterUnavailable(index) }
        let text = try await loader(index)
        let loaded = LoadedChapter(text: text as NSString, chunks: TextChunker.chunks(in: text))
        chapters[index] = loaded
        return loaded
    }

    private func evictChapters(around current: Int) {
        for key in chapters.keys where abs(key - current) > 1 { chapters[key] = nil }
    }

    private func fillQueue() {
        guard state == .playing else { return }
        while inFlight.count < lookahead, var current = cursor {
            guard let loaded = chapters[current.chapter] else {
                loadChapterInBackground(current.chapter)
                return
            }
            if current.chunk >= loaded.chunks.count {
                if current.chapter + 1 >= chapterCount {
                    cursor = nil
                } else {
                    cursor = Cursor(chapter: current.chapter + 1, chunk: 0, firstOffset: nil)
                }
                continue
            }
            let chunk = loaded.chunks[current.chunk]
            let start = max(chunk.start, current.firstOffset ?? 0)
            guard start < chunk.end else {
                current.chunk += 1
                current.firstOffset = nil
                cursor = current
                continue
            }
            let text = loaded.text.substring(with: NSRange(location: start, length: chunk.end - start))
            let item = QueuedItem(id: nextID, chapter: current.chapter, start: start, end: chunk.end)
            nextID += 1
            inFlight.append(item)
            synthesizer.enqueue(SpeechRequest(id: item.id, text: text, voiceIdentifier: settings.voiceIdentifier,
                                              languageCode: settings.languageCode, rate: settings.rate))
            current.chunk += 1
            current.firstOffset = nil
            cursor = current
        }
        if cursor == nil && inFlight.isEmpty { finish() }
    }

    private func loadChapterInBackground(_ index: Int) {
        guard loadingChapter != index else { return }
        loadingChapter = index
        let token = generation
        Task {
            do {
                _ = try await ensureLoaded(index)
                guard token == generation else { return }
                loadingChapter = nil
                fillQueue()
            } catch {
                guard token == generation else { return }
                loadingChapter = nil
                logger.error("Capítulo \(index) indisponível; pulando: \(error.localizedDescription)")
                if index + 1 < chapterCount {
                    cursor = Cursor(chapter: index + 1, chunk: 0, firstOffset: nil)
                } else {
                    cursor = nil
                }
                fillQueue()
            }
        }
    }

    private func finish() {
        guard state == .playing else { return }
        state = .finished
        cursor = nil
        onFinished?()
    }

    // MARK: - Eventos do sintetizador

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .started(let id):
            guard let item = inFlight.first(where: { $0.id == id }) else { return }
            if item.chapter != position.chapter {
                position = NarrationPosition(chapter: item.chapter, offset: item.start)
                evictChapters(around: item.chapter)
                onChapterChanged?(item.chapter)
            } else {
                position.offset = item.start
            }
            highlight = SpokenHighlight(chapter: item.chapter, wordStart: item.start, wordLength: 0, chunkStart: item.start, chunkEnd: item.end)
        case .willSpeak(let id, let location, let length):
            guard let item = inFlight.first(where: { $0.id == id }) else { return }
            position = NarrationPosition(chapter: item.chapter, offset: min(item.start + location, item.end))
            highlight = SpokenHighlight(chapter: item.chapter, wordStart: item.start + location, wordLength: length, chunkStart: item.start, chunkEnd: item.end)
        case .finished(let id):
            guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return }
            let item = inFlight.remove(at: index)
            if inFlight.isEmpty { position = NarrationPosition(chapter: item.chapter, offset: item.end) }
            fillQueue()
        }
    }
}
