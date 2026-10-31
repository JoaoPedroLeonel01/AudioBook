import Testing
import Foundation
import SwiftData
@testable import AudioBook

@MainActor
struct IntegrationTests {
    func makeEnvironment() -> (AppEnvironment, EPUBFileStorage) {
        let storage = EPUBFileStorage(root: makeTemporaryDirectory())
        return (AppEnvironment(inMemory: true, storage: storage), storage)
    }

    @Test func importPersistsBookFilesAndCover() async throws {
        let (env, storage) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        #expect(env.repository.allBooks().count == 1)
        #expect(book.title == "Livro de Teste" && book.chapters.count == 2 && book.hasCover)
        #expect(storage.epubExists(for: book.id))
        #expect(FileManager.default.fileExists(atPath: storage.coverURL(for: book.id).path))
        #expect(book.progress?.chapterIndex == 0)
        #expect(book.progressFraction == 0)
    }

    @Test func duplicateImportIsRejectedWithoutLeavingFiles() async throws {
        let (env, storage) = makeEnvironment()
        _ = try await env.library.importBook(from: fixtureURL("sample"))
        await #expect(throws: EPUBError.duplicate("Livro de Teste")) { try await env.library.importBook(from: fixtureURL("sample")) }
        #expect(env.repository.allBooks().count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.root.path).count == 1)
    }

    @Test func invalidImportLeavesLibraryUntouched() async {
        let (env, storage) = makeEnvironment()
        await env.library.importBooks(from: [fixtureURL("notzip"), fixtureURL("drm"), fixtureURL("empty")])
        #expect(env.repository.allBooks().isEmpty)
        #expect(env.library.alertMessage?.contains("DRM") == true)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: storage.root.path))?.isEmpty ?? true)
    }

    @Test func importContinuesAfterAFailure() async {
        let (env, _) = makeEnvironment()
        await env.library.importBooks(from: [fixtureURL("notzip"), fixtureURL("sample"), fixtureURL("ncx")])
        #expect(env.repository.allBooks().count == 2)
        #expect(env.library.alertMessage != nil)
    }

    @Test func progressIsSavedAndRecovered() async throws {
        let (env, _) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        #expect(env.repository.saveProgress(bookID: book.id, chapterIndex: 1, offset: 10))
        let reloaded = try #require(env.repository.book(id: book.id))
        #expect(reloaded.progress?.chapterIndex == 1 && reloaded.progress?.characterOffset == 10)
        #expect(reloaded.progressFraction > 0 && reloaded.progressFraction < 1)
        // Posição inválida é limitada aos limites do livro.
        #expect(env.repository.saveProgress(bookID: book.id, chapterIndex: 50, offset: 99999))
        #expect(env.repository.book(id: book.id)?.progress?.chapterIndex == 1)
        #expect(!env.repository.saveProgress(bookID: UUID(), chapterIndex: 0, offset: 0))
    }

    @Test func progressSurvivesAppRestartOnDisk() async throws {
        let dir = makeTemporaryDirectory()
        let schema = Schema([Book.self, ReadingProgress.self, UserPreferences.self])
        let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("store.sqlite"))
        var bookID: UUID!
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let repo = BookRepository(context: container.mainContext)
            let imported = try EPUBReaderService().readBookSync(at: fixtureURL("sample"))
            bookID = UUID()
            try repo.insert(imported, id: bookID)
            #expect(repo.saveProgress(bookID: bookID, chapterIndex: 1, offset: 7))
        }
        let container = try ModelContainer(for: schema, configurations: [config])
        let repo = BookRepository(context: container.mainContext)
        let book = try #require(repo.book(id: bookID))
        #expect(book.chapters.count == 2 && book.chapters[0].title == "Primeiro Capítulo")
        #expect(book.progress?.chapterIndex == 1 && book.progress?.characterOffset == 7)
    }

    @Test func openingBookRestoresSavedPositionPaused() async throws {
        let (env, _) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        env.repository.saveProgress(bookID: book.id, chapterIndex: 1, offset: 5)
        env.player.play(book, presentPlayer: false)
        #expect(env.player.chapterIndex == 1)
        #expect(env.player.engine.position.offset == 5)
        env.player.close()
    }

    @Test func deleteRemovesRecordProgressAndFiles() async throws {
        let (env, storage) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        let id = book.id
        env.library.delete(book)
        #expect(env.repository.allBooks().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.directory(for: id).path))
        #expect(try env.container.mainContext.fetch(FetchDescriptor<ReadingProgress>()).isEmpty)
    }

    @Test func deletingBookInUseStopsPlayback() async throws {
        let (env, storage) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        let id = book.id
        env.player.play(book, chapter: 0, presentPlayer: false)
        #expect(env.player.currentBook?.id == id)
        env.library.delete(book)
        #expect(env.player.currentBook == nil)
        #expect(env.player.engine.state == .idle)
        #expect(!storage.epubExists(for: id))
    }

    @Test func missingFileIsReportedInsteadOfPlaying() async throws {
        let (env, storage) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        storage.delete(id: book.id)
        env.player.play(book, presentPlayer: false)
        #expect(env.player.currentBook == nil)
        #expect(env.player.errorMessage?.contains("não está mais disponível") == true)
    }

    @Test func storageDeleteNeverEscapesRoot() throws {
        let root = makeTemporaryDirectory()
        let outside = makeTemporaryDirectory()
        let storage = EPUBFileStorage(root: root.appendingPathComponent("Books"))
        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        storage.delete(id: UUID())
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(storage.orphanedDirectories(knownIDs: []).isEmpty)
    }

    @Test func orphanedDirectoriesAreCleaned() async throws {
        let (env, storage) = makeEnvironment()
        let orphan = UUID()
        try FileManager.default.createDirectory(at: storage.directory(for: orphan), withIntermediateDirectories: true)
        let kept = try await env.library.importBook(from: fixtureURL("sample"))
        env.library.cleanOrphans()
        #expect(!FileManager.default.fileExists(atPath: storage.directory(for: orphan).path))
        #expect(storage.epubExists(for: kept.id))
    }

    @Test func preferencesPersist() async throws {
        let (env, _) = makeEnvironment()
        env.settings.speedMultiplier = 1.5
        env.settings.setLanguage("en-US")
        let stored = env.repository.preferences()
        #expect(stored.speedMultiplier == 1.5 && stored.languageCode == "en-US")
        #expect(env.settings.speechSettings(forBookLanguage: nil).rate == SpeechRate.utteranceRate(forMultiplier: 1.5))
    }

    @Test func chapterTransitionThroughPlayerUpdatesSavedProgress() async throws {
        let (env, _) = makeEnvironment()
        let book = try await env.library.importBook(from: fixtureURL("sample"))
        env.player.play(book, chapter: 0, presentPlayer: false)
        env.player.nextChapter()
        for _ in 0..<200 where env.player.chapterIndex != 1 { try await Task.sleep(for: .milliseconds(5)) }
        env.player.pausePlayback()
        env.player.saveProgress()
        #expect(env.repository.book(id: book.id)?.progress?.chapterIndex == 1)
        env.player.close()
    }
}
