import Foundation

/// Gerencia os arquivos locais de cada livro em Application Support/AudioBook/Books/<id>/.
struct EPUBFileStorage {
    let root: URL
    private let fileManager = FileManager.default

    static let epubFileName = "book.epub"
    static let coverFileName = "cover.jpg"

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("AudioBook/Books", isDirectory: true)
        }
    }

    func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func epubURL(for id: UUID) -> URL { directory(for: id).appendingPathComponent(Self.epubFileName) }
    func coverURL(for id: UUID) -> URL { directory(for: id).appendingPathComponent(Self.coverFileName) }

    func epubExists(for id: UUID) -> Bool { fileManager.fileExists(atPath: epubURL(for: id).path) }

    /// Copia o EPUB para o armazenamento do app (e grava a capa). Em falha, remove o que foi criado.
    func store(epubAt source: URL, coverJPEG: Data?, id: UUID) throws {
        let directory = directory(for: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: source, to: epubURL(for: id))
            if let coverJPEG { try coverJPEG.write(to: coverURL(for: id), options: .atomic) }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    /// Remove somente o diretório do livro informado; nunca sai de `root`.
    func delete(id: UUID) {
        let target = directory(for: id)
        guard target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { return }
        try? fileManager.removeItem(at: target)
    }

    /// Diretórios de livros sem registro correspondente (sobras de importações interrompidas).
    func orphanedDirectories(knownIDs: Set<UUID>) -> [UUID] {
        guard let items = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        return items.compactMap(UUID.init(uuidString:)).filter { !knownIDs.contains($0) }
    }
}
