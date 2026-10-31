import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var language: String?
    var chapters: [ChapterInfo]
    var hasCover: Bool
    var importedAt: Date
    var lastOpenedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.book)
    var progress: ReadingProgress?

    init(id: UUID = UUID(), title: String, author: String, language: String?, chapters: [ChapterInfo], hasCover: Bool, importedAt: Date = .now) {
        self.id = id
        self.title = title
        self.author = author
        self.language = language
        self.chapters = chapters
        self.hasCover = hasCover
        self.importedAt = importedAt
    }

    var totalLength: Int { chapters.reduce(0) { $0 + $1.length } }

    /// Fração concluída (0...1) com base no texto normalizado de todos os capítulos.
    var progressFraction: Double {
        guard let progress else { return 0 }
        return ReadingMath.fraction(chapters: chapters, chapterIndex: progress.chapterIndex, offset: progress.characterOffset)
    }

    var hasStarted: Bool { (progress?.characterOffset ?? 0) > 0 || (progress?.chapterIndex ?? 0) > 0 }
    var isFinished: Bool { progressFraction >= 0.999 }
}

@Model
final class ReadingProgress {
    var chapterIndex: Int
    /// Posição aproximada (UTF-16) dentro do texto normalizado do capítulo.
    var characterOffset: Int
    var updatedAt: Date
    var book: Book?

    init(chapterIndex: Int = 0, characterOffset: Int = 0, updatedAt: Date = .now) {
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.updatedAt = updatedAt
    }
}

/// Cálculos de progresso, independentes de persistência (testáveis).
nonisolated enum ReadingMath {
    static func fraction(chapters: [ChapterInfo], chapterIndex: Int, offset: Int) -> Double {
        let total = chapters.reduce(0) { $0 + $1.length }
        guard total > 0, !chapters.isEmpty else { return 0 }
        let index = min(max(chapterIndex, 0), chapters.count - 1)
        let before = chapters[..<index].reduce(0) { $0 + $1.length }
        let within = min(max(offset, 0), chapters[index].length)
        return min(1, Double(before + within) / Double(total))
    }

    /// Limita uma posição salva aos limites atuais do livro (arquivo pode ter mudado).
    static func clamp(chapterIndex: Int, offset: Int, chapters: [ChapterInfo]) -> (chapter: Int, offset: Int) {
        guard !chapters.isEmpty else { return (0, 0) }
        let index = min(max(chapterIndex, 0), chapters.count - 1)
        return (index, min(max(offset, 0), max(chapters[index].length - 1, 0)))
    }
}
