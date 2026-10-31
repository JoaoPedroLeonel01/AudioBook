import Foundation
import Observation
import SwiftData
import OSLog

/// Importação, exclusão e manutenção da biblioteca.
@MainActor
@Observable
final class LibraryViewModel {
    private(set) var isImporting = false
    private(set) var importProgress: (current: Int, total: Int)?
    var alertMessage: String?
    private(set) var lastImportedBook: Book?

    @ObservationIgnored private let repository: BookRepository
    @ObservationIgnored private let storage: EPUBFileStorage
    @ObservationIgnored private let reader: EPUBReaderService
    @ObservationIgnored private let player: PlayerViewModel
    @ObservationIgnored private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Library")

    init(repository: BookRepository, storage: EPUBFileStorage, reader: EPUBReaderService, player: PlayerViewModel) {
        self.repository = repository
        self.storage = storage
        self.reader = reader
        self.player = player
    }

    /// Importa uma lista de arquivos escolhidos pelo usuário. Falhas individuais não interrompem as demais.
    func importBooks(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        var errors: [String] = []
        for (index, url) in urls.enumerated() {
            importProgress = (index + 1, urls.count)
            do {
                lastImportedBook = try await importBook(from: url)
            } catch {
                logger.error("Importação falhou (\(url.lastPathComponent)): \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errors.append(urls.count > 1 ? "\(url.lastPathComponent): \(message)" : message)
            }
        }
        isImporting = false
        importProgress = nil
        if !errors.isEmpty { alertMessage = errors.joined(separator: "\n\n") }
    }

    func importBook(from url: URL) async throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let temporary = try await Self.copyToTemporary(url)
        defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }

        let imported = try await reader.readBook(at: temporary)
        let total = imported.chapters.reduce(0) { $0 + $1.length }
        if let duplicate = repository.findDuplicate(title: imported.title, author: imported.author, totalLength: total) {
            throw EPUBError.duplicate(duplicate.title)
        }

        let id = UUID()
        do {
            try storage.store(epubAt: temporary, coverJPEG: imported.coverJPEG, id: id)
            return try repository.insert(imported, id: id)
        } catch {
            storage.delete(id: id)
            throw error
        }
    }

    /// Remove o livro, seu progresso e seus arquivos locais. Se estiver tocando, para a narração antes.
    func delete(_ book: Book) {
        let id = book.id
        player.closeIfCurrent(book)
        do {
            try repository.delete(book)
            storage.delete(id: id)
        } catch {
            logger.error("Falha ao excluir livro: \(error.localizedDescription)")
            alertMessage = "Não foi possível excluir o livro. Tente novamente."
        }
    }

    /// Remove sobras de importações interrompidas (pastas sem registro correspondente).
    func cleanOrphans() {
        let known = Set(repository.allBooks().map(\.id))
        for id in storage.orphanedDirectories(knownIDs: known) { storage.delete(id: id) }
    }

    /// Copia o arquivo (com coordenação, para forçar o download de itens do iCloud) para um diretório temporário.
    @concurrent
    private static func copyToTemporary(_ url: URL) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
        }
        if coordinationError != nil || copyError != nil {
            try? FileManager.default.removeItem(at: directory)
            throw EPUBError.unreadableFile
        }
        return destination
    }
}
