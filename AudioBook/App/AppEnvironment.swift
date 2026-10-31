import Foundation
import Observation
import SwiftData
import OSLog

/// Raiz de composição: cria e conecta persistência, serviços e view models.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let repository: BookRepository
    let storage: EPUBFileStorage
    let settings: SettingsViewModel
    let player: PlayerViewModel
    let library: LibraryViewModel
    /// Preenchido quando o armazenamento persistente falhou e o app opera só em memória.
    private(set) var startupWarning: String?

    init(inMemory: Bool = false, storage: EPUBFileStorage? = nil) {
        let schema = Schema([Book.self, ReadingProgress.self, UserPreferences.self])
        var warning: String?
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)])
        } catch {
            Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "App").error("Falha ao abrir o banco: \(error.localizedDescription)")
            warning = "Não foi possível abrir a biblioteca salva. Os dados desta sessão não serão persistidos."
            // swiftlint:disable:next force_try
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        self.container = container
        self.startupWarning = warning
        let storage = storage ?? EPUBFileStorage()
        self.storage = storage
        let repository = BookRepository(context: container.mainContext)
        self.repository = repository
        let reader = EPUBReaderService()
        let settings = SettingsViewModel(repository: repository)
        self.settings = settings
        let engine = NarrationEngine(synthesizer: RoutedSpeechService(), settings: settings.speechSettings(forBookLanguage: nil))
        let player = PlayerViewModel(engine: engine, repository: repository, storage: storage, reader: reader, settings: settings)
        self.player = player
        self.library = LibraryViewModel(repository: repository, storage: storage, reader: reader, player: player)
    }

    func start() {
        library.cleanOrphans()
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// Ganchos para validação automatizada no simulador:
    /// `-ImportEPUBPath <caminho>` importa um EPUB; `-AutoPlayFirstBook YES` inicia a narração.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        let path = defaults.string(forKey: "ImportEPUBPath")
        let autoPlay = defaults.bool(forKey: "AutoPlayFirstBook")
        guard path != nil || autoPlay else { return }
        Task {
            if let path { await library.importBooks(from: [URL(fileURLWithPath: path)]) }
            if autoPlay, let book = repository.allBooks().first {
                let chapter = defaults.object(forKey: "AutoPlayChapter") as? Int
                player.play(book, chapter: chapter, presentPlayer: true)
            }
        }
    }
    #endif
}
