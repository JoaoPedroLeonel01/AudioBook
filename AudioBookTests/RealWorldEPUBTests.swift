import Testing
import Foundation
@testable import AudioBook

/// Validação opcional com EPUBs reais (não incluídos no repositório).
/// Execute com: TEST_RUNNER_AUDIOBOOK_SAMPLE_EPUBS=/caminho/da/pasta xcodebuild test ...
struct RealWorldEPUBTests {
    nonisolated static let directory: URL? = ProcessInfo.processInfo.environment["AUDIOBOOK_SAMPLE_EPUBS"].map { URL(fileURLWithPath: $0) }

    @Test(.enabled(if: directory != nil)) func realBooksImportWithSaneText() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.directory!, includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
        #expect(!files.isEmpty)
        let reader = EPUBReaderService()
        for file in files {
            let started = Date()
            let book = try reader.readBookSync(at: file)
            let elapsed = Date().timeIntervalSince(started)
            var totalChunks = 0
            for chapter in book.chapters {
                let text = try reader.chapterTextSync(epubURL: file, href: chapter.href)
                #expect(text.utf16.count == chapter.length)
                // Livros técnicos podem conter código com "</" legítimo; só verifica tags HTML reais de bloco.
                #expect(text.range(of: "<(p|div|span|body|html|h[1-6])[ >]", options: .regularExpression) == nil, "marcação vazou em \(file.lastPathComponent): \(chapter.title)")
                let chunks = TextChunker.chunks(in: text)
                #expect(chunks.allSatisfy { $0.length <= TextChunker.defaultMaxLength })
                totalChunks += chunks.count
            }
            print("REAL \(file.lastPathComponent): \"\(book.title)\" / \(book.author) / \(book.language ?? "?") / \(book.chapters.count) capítulos / \(book.chapters.reduce(0) { $0 + $1.length }) chars / \(totalChunks) trechos / capa=\(book.coverJPEG != nil) / \(String(format: "%.2f", elapsed))s")
            print("REAL   títulos: \(book.chapters.prefix(6).map(\.title))")
        }
    }
}
