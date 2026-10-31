import Foundation

nonisolated struct TextChunk: Equatable, Sendable {
    /// Intervalo em unidades UTF-16 do texto normalizado do capítulo.
    let start: Int
    let end: Int
    var length: Int { end - start }
}

/// Divide o texto de um capítulo em trechos de fala em fronteiras naturais
/// (parágrafo > sentença > cláusula > palavra). Os trechos cobrem todo o texto sem sobreposição.
nonisolated enum TextChunker {
    static let defaultMaxLength = 500

    static func chunks(in text: String, maxLength: Int = defaultMaxLength) -> [TextChunk] {
        let units = Array(text.utf16)
        let count = units.count
        guard count > 0, maxLength > 20 else { return [] }

        let newline: UInt16 = 10
        func isWhitespace(_ u: UInt16) -> Bool { u == 32 || u == 10 || u == 9 || u == 13 || u == 0xA0 }
        func isSentenceEnd(_ u: UInt16) -> Bool { u == 46 || u == 33 || u == 63 || u == 0x2026 }
        func isClauseEnd(_ u: UInt16) -> Bool { u == 59 || u == 58 || u == 44 || u == 0x2014 }
        func isLowSurrogate(_ u: UInt16) -> Bool { u >= 0xDC00 && u <= 0xDFFF }
        func isClosingQuote(_ u: UInt16) -> Bool { u == 0x201D || u == 0x2019 || u == 34 || u == 39 || u == 41 }

        var result: [TextChunk] = []
        var start = 0
        while start < count {
            while start < count && isWhitespace(units[start]) { start += 1 }
            if start >= count { break }

            var limit = min(start + maxLength, count)
            if limit == count {
                result.append(TextChunk(start: start, end: trimmedEnd(units, start, limit, isWhitespace)))
                break
            }
            if isLowSurrogate(units[limit]) { limit -= 1 }

            // Procura de trás para frente: parágrafo, depois sentença, depois cláusula, depois espaço.
            var cut = -1
            var k = limit
            while k > start { if units[k - 1] == newline { cut = k; break }; k -= 1 }
            if cut < 0 {
                k = limit
                while k > start + 1 {
                    let previous = units[k - 1]
                    if (isSentenceEnd(previous) && (k == count || isWhitespace(units[k]) || isClosingQuote(units[k]))) {
                        cut = k
                        if isClosingQuote(units[k]) && k + 1 < count { cut = k + 1 }
                        break
                    }
                    k -= 1
                }
            }
            if cut < 0 || cut - start < maxLength / 4 {
                var clause = -1
                k = limit
                while k > start + 1 { if isClauseEnd(units[k - 1]) { clause = k; break }; k -= 1 }
                if clause > start + maxLength / 4 { cut = clause }
            }
            if cut < 0 || cut - start < maxLength / 8 {
                k = limit
                while k > start + 1 { if isWhitespace(units[k - 1]) { cut = k; break }; k -= 1 }
            }
            if cut <= start { cut = limit }

            result.append(TextChunk(start: start, end: trimmedEnd(units, start, cut, isWhitespace)))
            start = cut
        }
        return result
    }

    /// Índice do trecho que contém `offset` (ou o primeiro trecho posterior).
    static func index(of offset: Int, in chunks: [TextChunk]) -> Int {
        guard !chunks.isEmpty else { return 0 }
        if let found = chunks.firstIndex(where: { offset < $0.end }) { return found }
        return chunks.count - 1
    }

    private static func trimmedEnd(_ units: [UInt16], _ start: Int, _ end: Int, _ isWhitespace: (UInt16) -> Bool) -> Int {
        var e = end
        while e > start + 1 && isWhitespace(units[e - 1]) { e -= 1 }
        return e
    }
}
