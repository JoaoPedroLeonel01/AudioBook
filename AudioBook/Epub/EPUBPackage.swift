import Foundation

nonisolated struct EPUBMetadata: Equatable {
    var title: String?
    var authors: [String] = []
    var language: String?
}

nonisolated struct EPUBSpineItem: Equatable {
    let id: String
    /// Caminho completo da entrada dentro do ZIP.
    let path: String
    let mediaType: String
    let linear: Bool
}

/// Estrutura lógica do EPUB: metadados, ordem de leitura (spine), sumário e capa.
nonisolated struct EPUBPackage {
    let opfPath: String
    let metadata: EPUBMetadata
    let spine: [EPUBSpineItem]
    /// Títulos do sumário indexados pelo caminho do documento (sem fragmento).
    let tocTitles: [String: String]
    let coverPath: String?

    static func load(from archive: ZipArchive) throws -> EPUBPackage {
        guard archive.contains("META-INF/container.xml") || archive.resolvedName("META-INF/container.xml") != nil else {
            throw EPUBError.notAnEPUB
        }
        let containerData = try readEntry(archive, "META-INF/container.xml")
        guard let container = XMLNode.parse(containerData),
              let rootfile = container.descendants(named: "rootfile").first,
              let fullPath = rootfile.attributes["full-path"], !fullPath.isEmpty else {
            throw EPUBError.corrupted("container.xml inválido")
        }
        let opfPath = normalize(fullPath)
        let opfData = try readEntry(archive, opfPath)
        guard let opf = XMLNode.parse(opfData), opf.name == "package" else {
            throw EPUBError.corrupted("arquivo OPF inválido")
        }

        let baseDirectory = (opfPath as NSString).deletingLastPathComponent

        // Manifest
        struct ManifestItem { let id: String; let path: String; let mediaType: String; let properties: Set<String> }
        var manifest: [String: ManifestItem] = [:]
        for item in opf.child("manifest")?.children(named: "item") ?? [] {
            guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
            manifest[id] = ManifestItem(
                id: id,
                path: resolve(href, relativeTo: baseDirectory),
                mediaType: item.attributes["media-type"] ?? "",
                properties: Set((item.attributes["properties"] ?? "").split(separator: " ").map(String.init))
            )
        }

        // Metadata
        var metadata = EPUBMetadata()
        let metadataNode = opf.child("metadata")
        metadata.title = metadataNode?.children(named: "title").map(\.trimmedText).first { !$0.isEmpty }
        metadata.authors = (metadataNode?.children(named: "creator") ?? []).map(\.trimmedText).filter { !$0.isEmpty }
        metadata.language = metadataNode?.children(named: "language").map(\.trimmedText).first { !$0.isEmpty }

        // Spine
        let spineNode = opf.child("spine")
        var spine: [EPUBSpineItem] = []
        for itemref in spineNode?.children(named: "itemref") ?? [] {
            guard let idref = itemref.attributes["idref"], let item = manifest[idref] else { continue }
            spine.append(EPUBSpineItem(id: item.id, path: item.path, mediaType: item.mediaType, linear: itemref.attributes["linear"] != "no"))
        }
        guard !spine.isEmpty else { throw EPUBError.noReadableContent }

        // Capa
        var coverPath = manifest.values.first { $0.properties.contains("cover-image") }?.path
        if coverPath == nil,
           let coverId = metadataNode?.children(named: "meta").first(where: { $0.attributes["name"] == "cover" })?.attributes["content"],
           let item = manifest[coverId], item.mediaType.hasPrefix("image/") {
            coverPath = item.path
        }

        // Sumário: EPUB 3 (nav) tem prioridade; NCX como alternativa.
        var tocTitles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
           let data = try? archive.read(nav.path) {
            tocTitles = parseNav(data: data, baseDirectory: (nav.path as NSString).deletingLastPathComponent)
        }
        if tocTitles.isEmpty {
            let ncxId = spineNode?.attributes["toc"]
            let ncx = ncxId.flatMap { manifest[$0] } ?? manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }
            if let ncx, let data = try? archive.read(ncx.path) {
                tocTitles = parseNCX(data: data, baseDirectory: (ncx.path as NSString).deletingLastPathComponent)
            }
        }

        return EPUBPackage(opfPath: opfPath, metadata: metadata, spine: spine, tocTitles: tocTitles, coverPath: coverPath)
    }

    // MARK: - Sumário

    static func parseNav(data: Data, baseDirectory: String) -> [String: String] {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [:] }
        var navDepth = 0
        var insideTocNav = false
        var sawTocNav = false
        var anchorHref: String?
        var anchorText = ""

        // Considera apenas o <nav epub:type="toc">; se não houver, usa o primeiro <nav>.
        var firstNavTitles: [String: [String]] = [:]
        var tocNavTitles: [String: [String]] = [:]
        var currentIsToc = false
        var navIndex = 0

        func store(_ href: String, _ text: String) {
            let title = HTMLTextExtractor.clean(text)
            let path = resolve(href.components(separatedBy: "#").first ?? href, relativeTo: baseDirectory)
            guard !title.isEmpty, !(href.components(separatedBy: "#").first ?? "").isEmpty else { return }
            if currentIsToc {
                tocNavTitles[path, default: []].append(title)
            } else if navIndex == 1 {
                firstNavTitles[path, default: []].append(title)
            }
        }

        HTMLScanner.scan(html) { token in
            switch token {
            case .start(let name, let attributes, _):
                if name == "nav" {
                    navDepth += 1
                    if navDepth == 1 {
                        navIndex += 1
                        currentIsToc = (attributes["epub:type"] ?? "").contains("toc")
                        insideTocNav = true
                        sawTocNav = sawTocNav || currentIsToc
                    }
                } else if name == "a", insideTocNav, let href = attributes["href"] {
                    anchorHref = href
                    anchorText = ""
                }
            case .end(let name):
                if name == "nav" {
                    navDepth = max(0, navDepth - 1)
                    if navDepth == 0 { insideTocNav = false }
                } else if name == "a", let href = anchorHref {
                    store(href, anchorText)
                    anchorHref = nil
                }
            case .text(let string):
                if anchorHref != nil { anchorText += string }
            }
        }
        return combine(sawTocNav ? tocNavTitles : firstNavTitles)
    }

    /// Vários itens do sumário podem apontar para o mesmo documento (âncoras). Usa o primeiro como
    /// título; se ele for só um rótulo ordinal ("1", "IV", "Capítulo 3"), anexa o seguinte.
    static func combine(_ titlesByPath: [String: [String]]) -> [String: String] {
        titlesByPath.mapValues { titles in
            guard let first = titles.first else { return "" }
            if titles.count > 1, isOrdinalLabel(first), titles[1] != first { return "\(first). \(titles[1])" }
            return first
        }
    }

    static func isOrdinalLabel(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 3 { return true }
        return trimmed.range(of: #"^(cap[ií]tulo|parte|part|chapter|se[cç][aã]o)\s+[\dIVXLCivxlc]+\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func parseNCX(data: Data, baseDirectory: String) -> [String: String] {
        guard let root = XMLNode.parse(data) else { return [:] }
        var titles: [String: [String]] = [:]
        for point in root.descendants(named: "navPoint") {
            guard let src = point.child("content")?.attributes["src"],
                  let label = point.child("navLabel")?.child("text")?.trimmedText, !label.isEmpty else { continue }
            let file = src.components(separatedBy: "#").first ?? src
            guard !file.isEmpty else { continue }
            let path = resolve(file, relativeTo: baseDirectory)
            titles[path, default: []].append(HTMLTextExtractor.clean(label))
        }
        return combine(titles)
    }

    // MARK: - Caminhos

    private static func readEntry(_ archive: ZipArchive, _ path: String) throws -> Data {
        do {
            return try archive.read(path)
        } catch ZipArchive.ZipError.entryNotFound(let name) {
            throw EPUBError.corrupted("arquivo ausente: \(name)")
        } catch {
            throw EPUBError.corrupted("falha ao ler \(path)")
        }
    }

    static func resolve(_ href: String, relativeTo directory: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        let withoutFragment = decoded.components(separatedBy: "#").first ?? decoded
        if withoutFragment.hasPrefix("/") { return normalize(String(withoutFragment.dropFirst())) }
        return normalize(directory.isEmpty ? withoutFragment : directory + "/" + withoutFragment)
    }

    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }
}
