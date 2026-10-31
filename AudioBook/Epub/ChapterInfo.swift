import Foundation

/// Capítulo (documento da spine) com texto narrável. Persistido junto ao livro.
nonisolated struct ChapterInfo: Codable, Hashable, Sendable, Identifiable {
    var title: String
    /// Caminho da entrada dentro do arquivo EPUB.
    var href: String
    /// Tamanho do texto normalizado em unidades UTF-16.
    var length: Int

    var id: String { href }
}

/// Resultado da leitura de um EPUB, ainda não persistido.
nonisolated struct ImportedBook: Sendable {
    var title: String
    var author: String
    var language: String?
    var chapters: [ChapterInfo]
    var coverJPEG: Data?
}
