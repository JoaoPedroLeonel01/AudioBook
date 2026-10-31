import Testing
import Foundation
@testable import AudioBook

struct TextChunkerTests {
    private func sample(paragraphs: Int) -> String {
        (1...paragraphs).map { n in
            "Parágrafo \(n). " + String(repeating: "Esta é uma frase de teste com acentuação, vírgulas e pontuação. ", count: 4)
        }.joined(separator: "\n")
    }

    @Test func coversAllTextWithoutOverlap() {
        let text = sample(paragraphs: 30)
        let chunks = TextChunker.chunks(in: text, maxLength: 300)
        let units = Array(text.utf16)
        var previousEnd = 0
        var reconstructed: [UInt16] = []
        for chunk in chunks {
            #expect(chunk.start >= previousEnd)
            #expect(chunk.length > 0 && chunk.length <= 300)
            // Só espaços em branco podem ficar entre trechos.
            let gap = units[previousEnd..<chunk.start]
            #expect(gap.allSatisfy { $0 == 32 || $0 == 10 })
            reconstructed += units[chunk.start..<chunk.end]
            previousEnd = chunk.end
        }
        let squeezed = String(decoding: reconstructed, as: UTF16.self)
        #expect(squeezed.filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
        #expect(chunks.last!.end == units.lastIndex(where: { $0 != 32 && $0 != 10 })! + 1)
    }

    @Test func prefersParagraphAndSentenceBoundaries() {
        let text = "Primeira frase curta. Segunda frase curta.\nNovo parágrafo aqui. E mais uma frase para completar o trecho."
        let chunks = TextChunker.chunks(in: text, maxLength: 60)
        let ns = text as NSString
        for chunk in chunks.dropLast() {
            let last = ns.substring(with: NSRange(location: chunk.end - 1, length: 1))
            #expect(".!?".contains(last), "trecho terminou em \(last)")
        }
    }

    @Test func handlesEmptyAndShortText() {
        #expect(TextChunker.chunks(in: "").isEmpty)
        #expect(TextChunker.chunks(in: " \n ").isEmpty)
        #expect(TextChunker.chunks(in: "Oi.") == [TextChunk(start: 0, end: 3)])
    }

    @Test func neverSplitsSurrogatePairsAndHandlesNoSpaces() {
        let emoji = String(repeating: "😀", count: 400)
        for chunk in TextChunker.chunks(in: emoji, maxLength: 51) {
            #expect(chunk.start % 2 == 0 && chunk.end % 2 == 0)
        }
        let blob = String(repeating: "x", count: 2000)
        let chunks = TextChunker.chunks(in: blob, maxLength: 500)
        #expect(chunks.count == 4)
    }

    @Test func findsChunkForOffset() {
        let chunks = [TextChunk(start: 0, end: 10), TextChunk(start: 11, end: 20), TextChunk(start: 21, end: 30)]
        #expect(TextChunker.index(of: 0, in: chunks) == 0)
        #expect(TextChunker.index(of: 10, in: chunks) == 1)  // espaço entre trechos -> próximo
        #expect(TextChunker.index(of: 25, in: chunks) == 2)
        #expect(TextChunker.index(of: 999, in: chunks) == 2)
    }

    @Test func rateMappingIsMonotonicAndBounded() {
        var previous: Float = 0
        for step in SpeechRate.multiplierSteps {
            let rate = SpeechRate.utteranceRate(forMultiplier: step)
            #expect(rate > previous && rate <= 1.0)
            previous = rate
        }
        #expect(SpeechRate.utteranceRate(forMultiplier: 1.0) == 0.5)
        #expect(SpeechRate.utteranceRate(forMultiplier: 99) == SpeechRate.utteranceRate(forMultiplier: 2.0))
    }
}

struct ReadingMathTests {
    let chapters = [ChapterInfo(title: "a", href: "a", length: 100), ChapterInfo(title: "b", href: "b", length: 300), ChapterInfo(title: "c", href: "c", length: 100)]

    @Test func computesFraction() {
        #expect(ReadingMath.fraction(chapters: chapters, chapterIndex: 0, offset: 0) == 0)
        #expect(ReadingMath.fraction(chapters: chapters, chapterIndex: 1, offset: 100) == 0.4)
        #expect(ReadingMath.fraction(chapters: chapters, chapterIndex: 2, offset: 100) == 1)
        #expect(ReadingMath.fraction(chapters: [], chapterIndex: 0, offset: 5) == 0)
    }

    @Test func clampsOutOfRangePositions() {
        #expect(ReadingMath.clamp(chapterIndex: 9, offset: 9999, chapters: chapters) == (2, 99))
        #expect(ReadingMath.clamp(chapterIndex: -1, offset: -5, chapters: chapters) == (0, 0))
        #expect(ReadingMath.clamp(chapterIndex: 3, offset: 3, chapters: []) == (0, 0))
        #expect(ReadingMath.fraction(chapters: chapters, chapterIndex: 99, offset: 99999) == 1)
    }
}

struct ReadAlongTests {
    @Test func splitsParagraphsWithUTF16Offsets() {
        let text = "Olá 😀 mundo\nSegundo\n\nTerceiro"
        let paragraphs = ReadParagraph.split(text)
        #expect(paragraphs.map(\.text) == ["Olá 😀 mundo", "Segundo", "Terceiro"])
        let ns = text as NSString
        for p in paragraphs { #expect(ns.substring(with: NSRange(location: p.start, length: p.end - p.start)) == p.text) }
        #expect(ReadParagraph.index(of: 0, in: paragraphs) == 0)
        #expect(ReadParagraph.index(of: paragraphs[1].start + 2, in: paragraphs) == 1)
        #expect(ReadParagraph.index(of: 9999, in: paragraphs) == 2)
        #expect(ReadParagraph.index(of: 0, in: []) == nil)
    }

    @Test func pageEstimateIsMonotonicAndBounded() {
        let chapters = [ChapterInfo(title: "a", href: "a", length: 3600), ChapterInfo(title: "b", href: "b", length: 3600)]
        #expect(PageEstimate.page(chapters: chapters, chapterIndex: 0, offset: 0) == (1, 4))
        #expect(PageEstimate.page(chapters: chapters, chapterIndex: 1, offset: 0) == (3, 4))
        #expect(PageEstimate.page(chapters: chapters, chapterIndex: 1, offset: 99999).current == 4)
        #expect(PageEstimate.page(chapters: [], chapterIndex: 0, offset: 0) == (1, 1))
    }
}
