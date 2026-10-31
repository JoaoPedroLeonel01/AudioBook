import Foundation

/// Parágrafo do texto normalizado de um capítulo, com sua posição (UTF-16), para leitura acompanhada.
nonisolated struct ReadParagraph: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Int
    let end: Int
    let text: String

    static func split(_ text: String) -> [ReadParagraph] {
        var result: [ReadParagraph] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.utf16.count
            if length > 0 {
                result.append(ReadParagraph(id: result.count, start: offset, end: offset + length, text: String(line)))
            }
            offset += length + 1
        }
        return result
    }

    /// Índice do parágrafo que contém `offset` (ou o último anterior).
    static func index(of offset: Int, in paragraphs: [ReadParagraph]) -> Int? {
        guard !paragraphs.isEmpty else { return nil }
        var low = 0, high = paragraphs.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if paragraphs[mid].start <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// Página aproximada: EPUB é texto fluido e não tem páginas fixas; usa ~1800 caracteres por página.
nonisolated enum PageEstimate {
    static let charactersPerPage = 1800

    static func page(chapters: [ChapterInfo], chapterIndex: Int, offset: Int) -> (current: Int, total: Int) {
        let total = max(1, Int((Double(chapters.reduce(0) { $0 + $1.length }) / Double(charactersPerPage)).rounded(.up)))
        guard !chapters.isEmpty else { return (1, total) }
        let index = min(max(chapterIndex, 0), chapters.count - 1)
        let before = chapters[..<index].reduce(0) { $0 + $1.length }
        let current = (before + max(offset, 0)) / charactersPerPage + 1
        return (min(current, total), total)
    }
}
