import Foundation
import SwiftData
import OSLog

/// Persistência e consultas de livros, progresso e preferências (SwiftData).
@MainActor
final class BookRepository {
    let context: ModelContext
    private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "Repository")

    init(context: ModelContext) {
        self.context = context
    }

    func allBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func book(id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func findDuplicate(title: String, author: String, totalLength: Int) -> Book? {
        allBooks().first { $0.title == title && $0.author == author && $0.totalLength == totalLength }
    }

    @discardableResult
    func insert(_ imported: ImportedBook, id: UUID) throws -> Book {
        let book = Book(id: id, title: imported.title, author: imported.author, language: imported.language,
                        chapters: imported.chapters, hasCover: imported.coverJPEG != nil)
        book.progress = ReadingProgress()
        context.insert(book)
        do {
            try context.save()
        } catch {
            context.delete(book)
            throw error
        }
        return book
    }

    func delete(_ book: Book) throws {
        context.delete(book)
        try context.save()
    }

    /// Salva a posição de leitura. Retorna `false` em caso de falha (o estado em memória é preservado).
    @discardableResult
    func saveProgress(bookID: UUID, chapterIndex: Int, offset: Int) -> Bool {
        guard let book = book(id: bookID) else { return false }
        let clamped = ReadingMath.clamp(chapterIndex: chapterIndex, offset: offset, chapters: book.chapters)
        let progress = book.progress ?? ReadingProgress()
        progress.chapterIndex = clamped.chapter
        progress.characterOffset = clamped.offset
        progress.updatedAt = .now
        if book.progress == nil { book.progress = progress }
        book.lastOpenedAt = .now
        do {
            try context.save()
            return true
        } catch {
            logger.error("Falha ao salvar progresso: \(error.localizedDescription)")
            context.rollback()
            return false
        }
    }

    func preferences() -> UserPreferences {
        if let existing = try? context.fetch(FetchDescriptor<UserPreferences>()).first { return existing }
        let created = UserPreferences()
        context.insert(created)
        try? context.save()
        return created
    }

    func savePreferences() {
        preferences().updatedAt = .now
        do { try context.save() } catch {
            logger.error("Falha ao salvar preferências: \(error.localizedDescription)")
        }
    }
}
