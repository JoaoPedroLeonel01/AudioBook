import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Importação e leitura de EPUB. Sem estado; seguro para uso em qualquer contexto de concorrência.
nonisolated struct EPUBReaderService: Sendable {
    /// Tamanho máximo aceito para um arquivo EPUB.
    static let maxFileSize: Int64 = 512 * 1024 * 1024
    private static let fontOnlyAlgorithms = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]

    init() {}

    /// Valida o arquivo e extrai metadados, capítulos e capa. Pesado: execute fora da main thread.
    @concurrent
    func readBook(at url: URL) async throws -> ImportedBook {
        try readBookSync(at: url)
    }

    func readBookSync(at url: URL) throws -> ImportedBook {
        guard url.pathExtension.lowercased() == "epub" else { throw EPUBError.invalidFileType }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize, size > 0 else { throw EPUBError.unreadableFile }
        guard Int64(size) <= Self.maxFileSize else { throw EPUBError.corrupted("arquivo muito grande") }

        let archive = try openArchive(url)
        let package = try EPUBPackage.load(from: archive)
        try checkDRM(archive: archive, package: package)

        var chapters: [ChapterInfo] = []
        var fallbackIndex = 0
        for item in package.spine where isTextDocument(item) {
            guard let extracted = try? extractText(archive: archive, path: item.path), !extracted.isEmpty else { continue }
            fallbackIndex += 1
            let title = package.tocTitles[item.path] ?? extracted.heading ?? "Seção \(fallbackIndex)"
            chapters.append(ChapterInfo(title: title, href: item.path, length: extracted.text.utf16.count))
        }
        guard !chapters.isEmpty else { throw EPUBError.noReadableContent }

        let fileTitle = url.deletingPathExtension().lastPathComponent
        let title = package.metadata.title ?? fileTitle
        let author = package.metadata.authors.isEmpty ? "Autor desconhecido" : package.metadata.authors.joined(separator: ", ")

        var coverJPEG: Data?
        if let coverPath = package.coverPath, let data = try? archive.read(coverPath) {
            coverJPEG = Self.makeCoverJPEG(from: data)
        }
        return ImportedBook(title: title, author: author, language: package.metadata.language, chapters: chapters, coverJPEG: coverJPEG)
    }

    /// Texto normalizado de um capítulo, lido sob demanda do arquivo armazenado.
    @concurrent
    func chapterText(epubURL: URL, href: String) async throws -> String {
        try chapterTextSync(epubURL: epubURL, href: href)
    }

    func chapterTextSync(epubURL: URL, href: String) throws -> String {
        guard FileManager.default.fileExists(atPath: epubURL.path) else { throw EPUBError.unreadableFile }
        let archive = try openArchive(epubURL)
        return try extractText(archive: archive, path: href).text
    }

    // MARK: - Interno

    private func openArchive(_ url: URL) throws -> ZipArchive {
        do {
            return try ZipArchive(url: url)
        } catch ZipArchive.ZipError.notAZip {
            throw EPUBError.notAnEPUB
        } catch ZipArchive.ZipError.corrupted(let detail) {
            throw EPUBError.corrupted(detail)
        } catch ZipArchive.ZipError.unsupported(let detail) {
            throw EPUBError.corrupted(detail)
        } catch {
            throw EPUBError.unreadableFile
        }
    }

    private func isTextDocument(_ item: EPUBSpineItem) -> Bool {
        let type = item.mediaType.lowercased()
        return type.isEmpty || type.contains("html") || type.contains("xml") && !type.contains("ncx")
    }

    private func extractText(archive: ZipArchive, path: String) throws -> ExtractedText {
        let data: Data
        do {
            data = try archive.read(path)
        } catch {
            throw EPUBError.corrupted("documento ausente: \(path)")
        }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return HTMLTextExtractor.extract(html: html)
    }

    /// Detecta criptografia real de conteúdo (DRM). Ofuscação de fontes é permitida.
    private func checkDRM(archive: ZipArchive, package: EPUBPackage) throws {
        guard let data = try? archive.read("META-INF/encryption.xml"),
              let root = XMLNode.parse(data) else { return }
        let spinePaths = Set(package.spine.map(\.path))
        for encrypted in root.descendants(named: "EncryptedData") {
            let algorithm = encrypted.child("EncryptionMethod")?.attributes["Algorithm"] ?? ""
            if Self.fontOnlyAlgorithms.contains(algorithm) { continue }
            let uri = encrypted.descendants(named: "CipherReference").first?.attributes["URI"] ?? ""
            let path = EPUBPackage.resolve(uri, relativeTo: "")
            if spinePaths.contains(path) { throw EPUBError.drmProtected }
        }
    }

    /// Reduz a capa para no máximo 600 px e converte para JPEG.
    static func makeCoverJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
