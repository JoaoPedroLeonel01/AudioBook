import Foundation
import Observation
import OSLog

enum SleepTimerOption: Hashable {
    case off
    case minutes(Int)
    case endOfChapter

    var label: String {
        switch self {
        case .off: "Desativado"
        case .minutes(let m): "\(m) minutos"
        case .endOfChapter: "Fim do capítulo"
        }
    }

    static let choices: [SleepTimerOption] = [.off, .minutes(5), .minutes(10), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfChapter]
}

/// Coordena motor de narração, sessão de áudio, controles do sistema, persistência de progresso e timer.
@MainActor
@Observable
final class PlayerViewModel {
    let engine: NarrationEngine
    private(set) var currentBook: Book?
    var isPlayerPresented = false
    private(set) var errorMessage: String?
    private(set) var sleepTimer: SleepTimerOption = .off
    private(set) var sleepTimerEndDate: Date?
    private(set) var lastProgressSaveFailed = false
    /// Parágrafos do capítulo atual, para a leitura acompanhada.
    private(set) var paragraphs: [ReadParagraph] = []
    @ObservationIgnored private var paragraphsChapter: Int?
    @ObservationIgnored private var chapterLoader: ((Int) async throws -> String)?

    @ObservationIgnored private let repository: BookRepository
    @ObservationIgnored private let storage: EPUBFileStorage
    @ObservationIgnored private let reader: EPUBReaderService
    @ObservationIgnored private let settings: SettingsViewModel
    @ObservationIgnored private let audioSession: AudioSessionManager
    @ObservationIgnored private let nowPlaying: NowPlayingManager
    @ObservationIgnored private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Player")
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var sleepChapter: Int?
    @ObservationIgnored private var resumeAfterInterruption = false

    init(engine: NarrationEngine, repository: BookRepository, storage: EPUBFileStorage, reader: EPUBReaderService,
         settings: SettingsViewModel, audioSession: AudioSessionManager? = nil, nowPlaying: NowPlayingManager? = nil) {
        self.engine = engine
        self.repository = repository
        self.storage = storage
        self.reader = reader
        self.settings = settings
        self.audioSession = audioSession ?? AudioSessionManager()
        self.nowPlaying = nowPlaying ?? NowPlayingManager()
        wire()
    }

    // MARK: - Estado derivado

    var state: PlaybackState { engine.state }
    var isPlaying: Bool { engine.state == .playing || engine.state == .loading }
    var chapterCount: Int { currentBook?.chapters.count ?? 0 }
    var chapterIndex: Int { engine.position.chapter }

    var chapterTitle: String {
        guard let book = currentBook, book.chapters.indices.contains(chapterIndex) else { return "" }
        return book.chapters[chapterIndex].title
    }

    var chapterFraction: Double {
        guard let book = currentBook, book.chapters.indices.contains(chapterIndex), book.chapters[chapterIndex].length > 0 else { return 0 }
        return min(1, Double(engine.position.offset) / Double(book.chapters[chapterIndex].length))
    }

    /// Página aproximada (EPUB é texto fluido; ~1800 caracteres por página).
    var pageEstimate: (current: Int, total: Int) {
        guard let book = currentBook else { return (1, 1) }
        return PageEstimate.page(chapters: book.chapters, chapterIndex: chapterIndex, offset: engine.position.offset)
    }

    var bookFraction: Double {
        guard let book = currentBook else { return 0 }
        return ReadingMath.fraction(chapters: book.chapters, chapterIndex: chapterIndex, offset: engine.position.offset)
    }

    func isCurrent(_ book: Book) -> Bool { currentBook?.id == book.id }

    // MARK: - Comandos

    /// Abre o livro (se necessário) e começa a narrar — do capítulo informado ou de onde parou.
    func play(_ book: Book, chapter: Int? = nil, presentPlayer: Bool = true) {
        guard open(book) else { return }
        audioSession.activate()
        if let chapter {
            engine.start(chapter: chapter, offset: 0)
        } else if engine.state == .finished {
            engine.start(chapter: 0, offset: 0)
        } else {
            engine.resume()
        }
        if presentPlayer { isPlayerPresented = true }
    }

    func togglePlayPause() {
        guard let book = currentBook else { return }
        switch engine.state {
        case .playing, .loading:
            engine.pause()
        case .paused:
            audioSession.activate()
            engine.resume()
        case .finished:
            play(book, chapter: 0, presentPlayer: false)
        case .failed:
            audioSession.activate()
            engine.start(chapter: engine.position.chapter, offset: engine.position.offset)
        case .idle:
            play(book, presentPlayer: false)
        }
    }

    func resumePlayback() {
        if engine.state == .paused { togglePlayPause() }
    }

    func pausePlayback() { engine.pause() }
    func nextChapter() { engine.nextChapter() }
    func previousChapter() { engine.previousChapter() }
    func skipForward() { engine.skipForward() }
    func skipBackward() { engine.skipBackward() }

    func seek(toChapterFraction fraction: Double) {
        guard let book = currentBook, book.chapters.indices.contains(chapterIndex) else { return }
        let length = book.chapters[chapterIndex].length
        engine.seek(chapter: chapterIndex, offset: Int(Double(length) * min(max(fraction, 0), 1)))
    }

    func seek(toOffset offset: Int) {
        engine.seek(chapter: chapterIndex, offset: offset)
        if engine.state == .paused { engine.resume() }
    }

    /// Carrega os parágrafos do capítulo atual (sob demanda, só quando a leitura acompanhada está visível).
    func loadParagraphs() async {
        let chapter = chapterIndex
        guard paragraphsChapter != chapter, let loader = chapterLoader else { return }
        paragraphs = []
        do {
            let text = try await loader(chapter)
            guard chapter == chapterIndex else { return }
            paragraphs = ReadParagraph.split(text)
            paragraphsChapter = chapter
        } catch {
            logger.error("Falha ao carregar texto do capítulo \(chapter): \(error.localizedDescription)")
        }
    }

    func setSpeed(_ multiplier: Double) {
        settings.speedMultiplier = multiplier
    }

    /// Reaplica as preferências ao motor (voz, idioma, velocidade).
    func applySettings() {
        guard let book = currentBook else { return }
        engine.updateSettings(settings.speechSettings(forBookLanguage: book.language))
    }

    /// Para a narração e libera o livro atual (ex.: ao excluí-lo).
    func close() {
        saveProgress()
        engine.stop()
        cancelSleepTimer()
        currentBook = nil
        paragraphs = []
        paragraphsChapter = nil
        isPlayerPresented = false
        nowPlaying.clear()
        audioSession.deactivate()
    }

    func closeIfCurrent(_ book: Book) {
        if currentBook?.id == book.id { close() }
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Timer de repouso

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTask?.cancel()
        sleepTimer = option
        sleepTimerEndDate = nil
        sleepChapter = nil
        switch option {
        case .off:
            break
        case .minutes(let minutes):
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            sleepTimerEndDate = end
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                self?.sleepTimerFired()
            }
        case .endOfChapter:
            sleepChapter = chapterIndex
        }
    }

    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTimer = .off
        sleepTimerEndDate = nil
        sleepChapter = nil
    }

    private func sleepTimerFired() {
        engine.pause()
        cancelSleepTimer()
    }

    // MARK: - Persistência de progresso

    func saveProgress() {
        guard let book = currentBook else { return }
        lastProgressSaveFailed = !repository.saveProgress(bookID: book.id, chapterIndex: engine.position.chapter, offset: engine.position.offset)
    }

    // MARK: - Interno

    @discardableResult
    private func open(_ book: Book) -> Bool {
        if currentBook?.id == book.id { return true }
        guard storage.epubExists(for: book.id) else {
            errorMessage = "O arquivo de “\(book.title)” não está mais disponível. Remova o livro e importe-o novamente."
            return false
        }
        if currentBook != nil { saveProgress() }
        cancelSleepTimer()
        let url = storage.epubURL(for: book.id)
        let chapters = book.chapters
        let reader = self.reader
        let loader: (Int) async throws -> String = { index in
            guard chapters.indices.contains(index) else { throw EPUBError.chapterUnavailable(index) }
            return try await reader.chapterText(epubURL: url, href: chapters[index].href)
        }
        chapterLoader = loader
        paragraphs = []
        paragraphsChapter = nil
        engine.configure(chapterCount: chapters.count, loader: loader)
        engine.settings = settings.speechSettings(forBookLanguage: book.language)
        currentBook = book
        errorMessage = nil
        let saved = ReadingMath.clamp(chapterIndex: book.progress?.chapterIndex ?? 0, offset: book.progress?.characterOffset ?? 0, chapters: chapters)
        engine.prepare(chapter: saved.chapter, offset: saved.offset)
        return true
    }

    private func wire() {
        engine.onStateChanged = { [weak self] state in self?.stateChanged(state) }
        engine.onChapterChanged = { [weak self] chapter in self?.chapterChanged(chapter) }
        engine.onFinished = { [weak self] in
            guard let self else { return }
            saveProgress()
            audioSession.deactivate()
        }
        settings.onChange = { [weak self] in self?.applySettings() }

        audioSession.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            resumeAfterInterruption = engine.state == .playing
            engine.pause()
        }
        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            defer { resumeAfterInterruption = false }
            if resumeAfterInterruption && shouldResume {
                audioSession.activate()
                engine.resume()
            }
        }
        audioSession.onHeadphonesDisconnected = { [weak self] in self?.engine.pause() }

        nowPlaying.install(.init(
            play: { [weak self] in self?.resumePlayback() },
            pause: { [weak self] in self?.engine.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            nextChapter: { [weak self] in self?.engine.nextChapter() },
            previousChapter: { [weak self] in self?.engine.previousChapter() },
            skipForward: { [weak self] in self?.engine.skipForward() },
            skipBackward: { [weak self] in self?.engine.skipBackward() }
        ))
    }

    private func stateChanged(_ state: PlaybackState) {
        switch state {
        case .playing, .loading:
            startTicker()
        case .paused, .finished, .failed, .idle:
            stopTicker()
            saveProgress()
            if case .failed(let message) = state { errorMessage = message }
        }
        refreshNowPlaying()
    }

    private func chapterChanged(_ chapter: Int) {
        saveProgress()
        refreshNowPlaying()
        if let armed = sleepChapter, armed != chapter {
            // Timer "fim do capítulo": pausa e deixa a posição no início do novo capítulo.
            engine.seek(chapter: chapter, offset: 0)
            engine.pause()
            cancelSleepTimer()
        }
    }

    private func refreshNowPlaying() {
        guard let book = currentBook else { return }
        nowPlaying.update(book: book, chapterTitle: chapterTitle, chapterFraction: chapterFraction, isPlaying: engine.state == .playing,
                          coverURL: book.hasCover ? storage.coverURL(for: book.id) : nil)
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                saveProgress()
                refreshNowPlaying()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
