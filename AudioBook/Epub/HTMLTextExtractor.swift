import Foundation

nonisolated struct ExtractedText: Equatable {
    /// Texto normalizado: parágrafos separados por `\n`, sem marcação.
    let text: String
    /// Primeiro título encontrado no documento (h1–h6 ou <title>), se houver.
    let heading: String?

    var isEmpty: Bool { text.isEmpty }
}

/// Converte XHTML de capítulo em texto narrável, preservando títulos, parágrafos e listas.
nonisolated enum HTMLTextExtractor {
    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "blockquote",
        "section", "article", "tr", "table", "hr", "figure", "figcaption", "pre", "dd", "dt", "dl",
        "header", "footer", "body", "caption", "address", "main"
    ]
    private static let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
    private static let skipTags: Set<String> = ["head", "script", "style", "nav", "svg", "noscript", "template", "rt", "math", "audio", "video", "object"]
    private static let voidTags: Set<String> = ["br", "hr", "img", "meta", "link", "input", "col", "area", "base", "wbr", "source", "track", "embed"]
    private static let skippedEpubTypes = ["pagebreak", "noteref", "toc", "page-list", "landmarks", "doc-pagebreak", "doc-noteref"]
    private static let terminalPunctuation: Set<Character> = [".", "!", "?", "…", ":", ";", "”", "\"", "’", ")"]

    static func extract(html: String) -> ExtractedText {
        var paragraphs: [String] = []
        var current = ""
        var headingDepth = 0
        var firstHeading: String?
        var documentTitle: String?
        var inTitle = false
        var titleBuffer = ""
        var skipName: String?
        var skipDepth = 0

        func finishParagraph() {
            let isHeading = headingDepth > 0
            var cleaned = stripURLs(clean(current))
            current = ""
            guard !cleaned.isEmpty else { return }
            guard cleaned.contains(where: { $0.isLetter || $0.isNumber }) else { return }  // "* * *", "---"
            if isHeading {
                if firstHeading == nil { firstHeading = cleaned }
                if let last = cleaned.last, !terminalPunctuation.contains(last) { cleaned += "." }
            }
            paragraphs.append(cleaned)
        }

        HTMLScanner.scan(html) { token in
            switch token {
            case .start(let name, let attributes, let selfClosing):
                if let active = skipName {
                    if name == active && !selfClosing && !voidTags.contains(name) { skipDepth += 1 }
                    return
                }
                if name == "title" { inTitle = true; titleBuffer = "" }
                if shouldSkip(name: name, attributes: attributes), !selfClosing, !voidTags.contains(name) {
                    skipName = name
                    skipDepth = 1
                    return
                }
                if name == "br" || blockTags.contains(name) { finishParagraph() }
                if headingTags.contains(name) { headingDepth += 1 }
            case .end(let name):
                if let active = skipName {
                    if name == active {
                        skipDepth -= 1
                        if skipDepth == 0 { skipName = nil }
                    }
                    return
                }
                if name == "title" {
                    inTitle = false
                    let cleaned = clean(titleBuffer)
                    if !cleaned.isEmpty { documentTitle = cleaned }
                }
                if blockTags.contains(name) { finishParagraph() }
                if headingTags.contains(name) { headingDepth = max(0, headingDepth - 1) }
            case .text(let string):
                if skipName != nil { return }
                if inTitle { titleBuffer += string } else { current += string }
            }
        }
        finishParagraph()

        return ExtractedText(text: paragraphs.joined(separator: "\n"), heading: firstHeading ?? documentTitle)
    }

    private static func shouldSkip(name: String, attributes: [String: String]) -> Bool {
        if skipTags.contains(name) { return true }
        if attributes["hidden"] != nil || attributes["aria-hidden"] == "true" { return true }
        if let type = attributes["epub:type"] ?? attributes["role"], skippedEpubTypes.contains(where: { type.contains($0) }) {
            return true
        }
        return false
    }

    /// URLs não são narradas: soletrar "agá tê tê pê dois-pontos barra barra…" atrapalha a escuta.
    static func stripURLs(_ string: String) -> String {
        guard string.contains("://") || string.contains("www.") else { return string }
        let pattern = #"\s*<?(?:https?://|ftp://|www\.)[^\s<>]*>?"#
        var result = string.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([.,;:!?)])"#, with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Normaliza espaços, remove caracteres invisíveis e aplica composição canônica Unicode.
    static func clean(_ string: String) -> String {
        var buffer = ""
        buffer.reserveCapacity(string.count)
        var pendingSpace = false
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x00AD, 0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060:
                continue  // hífen suave e caracteres de largura zero
            case 0x09, 0x0A, 0x0D, 0x20, 0xA0, 0x2000...0x200A, 0x202F, 0x205F, 0x3000, 0x2028, 0x2029:
                pendingSpace = !buffer.isEmpty
            case 0xFB00: append("ff", &buffer, &pendingSpace)
            case 0xFB01: append("fi", &buffer, &pendingSpace)
            case 0xFB02: append("fl", &buffer, &pendingSpace)
            case 0xFB03: append("ffi", &buffer, &pendingSpace)
            case 0xFB04: append("ffl", &buffer, &pendingSpace)
            default:
                if scalar.properties.generalCategory == .control { continue }
                append(String(scalar), &buffer, &pendingSpace)
            }
        }
        return buffer.precomposedStringWithCanonicalMapping
    }

    private static func append(_ piece: String, _ buffer: inout String, _ pendingSpace: inout Bool) {
        if pendingSpace { buffer.append(" "); pendingSpace = false }
        buffer.append(piece)
    }
}
