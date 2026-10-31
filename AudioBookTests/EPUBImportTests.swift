import Testing
import Foundation
@testable import AudioBook

struct EPUBImportTests {
    let reader = EPUBReaderService()

    @Test func importsMetadataFromEPUB3() throws {
        let book = try reader.readBookSync(at: fixtureURL("sample"))
        #expect(book.title == "Livro de Teste")
        #expect(book.author == "Ana Silva, Bruno Costa")
        #expect(book.language == "pt-BR")
        #expect(book.coverJPEG != nil)
    }

    @Test func followsSpineOrderAndSkipsEmptyChapters() throws {
        let book = try reader.readBookSync(at: fixtureURL("sample"))
        // Manifest lista c2 antes de c1; a spine manda c1, vazio, c2.
        #expect(book.chapters.map(\.href) == ["OEBPS/text/cap1.xhtml", "OEBPS/text/cap2.xhtml"])
        #expect(book.chapters.map(\.title) == ["Primeiro Capítulo", "Segundo & Final"])
        #expect(book.chapters.allSatisfy { $0.length > 0 })
    }

    @Test func extractsCleanNarrableText() throws {
        let text = try reader.chapterTextSync(epubURL: fixtureURL("sample"), href: "OEBPS/text/cap1.xhtml")
        #expect(text.contains("Era uma vez um texto com ênfase eéntidades — \"aspas\"."))
        #expect(text.contains("Linha nova."))
        #expect(text.contains("Item um\nItem dois"))
        #expect(text.hasPrefix("Primeiro Capítulo."))  // título ganha pontuação para a fala
        #expect(!text.contains("alert"))
        #expect(!text.contains("<"))
        #expect(!text.contains("* * *"))
        #expect(!text.contains("  "))
        #expect(!text.contains("\u{00A0}"))
    }

    @Test func dropsNoterefsPagebreaksAndNavigation() throws {
        let text = try reader.chapterTextSync(epubURL: fixtureURL("sample"), href: "OEBPS/text/cap2.xhtml")
        #expect(text == "Segundo.\nTexto do segundo capítulo.")
    }

    @Test func chapterLengthMatchesExtractedText() throws {
        let book = try reader.readBookSync(at: fixtureURL("sample"))
        for chapter in book.chapters {
            let text = try reader.chapterTextSync(epubURL: fixtureURL("sample"), href: chapter.href)
            #expect(text.utf16.count == chapter.length)
        }
    }

    @Test func readsNCXTableOfContentsAndMetaCover() throws {
        let book = try reader.readBookSync(at: fixtureURL("ncx"))
        #expect(book.chapters.map(\.title) == ["Parte A", "Parte B"])
        #expect(book.author == "Autor desconhecido")  // metadado ausente
        #expect(book.coverJPEG != nil)
    }

    @Test func fallsBackToHeadingsWhenThereIsNoTOC() throws {
        let book = try reader.readBookSync(at: fixtureURL("notoc"))
        #expect(book.title == "Sem Sumário")
        #expect(book.chapters.map(\.title) == ["Introdução", "Seção 2"])
        #expect(book.coverJPEG == nil)
    }

    @Test func rejectsEPUBWithoutReadableText() {
        #expect(throws: EPUBError.noReadableContent) { try reader.readBookSync(at: fixtureURL("empty")) }
    }

    @Test func rejectsDRMProtectedContent() {
        #expect(throws: EPUBError.drmProtected) { try reader.readBookSync(at: fixtureURL("drm")) }
    }

    @Test func allowsFontObfuscation() throws {
        let book = try reader.readBookSync(at: fixtureURL("fontobf"))
        #expect(!book.chapters.isEmpty)
    }

    @Test func rejectsInvalidFiles() {
        #expect(throws: EPUBError.notAnEPUB) { try reader.readBookSync(at: fixtureURL("notzip")) }
        #expect(throws: EPUBError.notAnEPUB) { try reader.readBookSync(at: fixtureURL("nocontainer")) }
    }

    @Test func rejectsWrongExtensionAndMissingFile() throws {
        let dir = makeTemporaryDirectory()
        let txt = dir.appendingPathComponent("a.txt")
        try "x".write(to: txt, atomically: true, encoding: .utf8)
        #expect(throws: EPUBError.invalidFileType) { try reader.readBookSync(at: txt) }
        #expect(throws: EPUBError.unreadableFile) { try reader.readBookSync(at: dir.appendingPathComponent("nao-existe.epub")) }
    }

    @Test func chapterTextFailsForMissingFileOrEntry() {
        #expect(throws: EPUBError.unreadableFile) {
            try reader.chapterTextSync(epubURL: URL(fileURLWithPath: "/nao/existe.epub"), href: "x")
        }
        #expect(throws: EPUBError.self) {
            try reader.chapterTextSync(epubURL: fixtureURL("sample"), href: "OEBPS/nao-existe.xhtml")
        }
    }
}

struct ZipArchiveTests {
    @Test func readsDeflatedAndStoredEntries() throws {
        let zip = try ZipArchive(url: fixtureURL("sample"))
        #expect(String(data: try zip.read("mimetype"), encoding: .utf8) == "application/epub+zip")  // stored
        #expect(try zip.read("OEBPS/content.opf").count > 100)  // deflate
        #expect(zip.contains("META-INF/container.xml"))
    }

    @Test func missingEntryThrows() throws {
        let zip = try ZipArchive(url: fixtureURL("sample"))
        #expect(throws: ZipArchive.ZipError.entryNotFound("nada")) { try zip.read("nada") }
    }

    @Test func rejectsGarbage() {
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data(repeating: 7, count: 100)) }
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data()) }
    }

    @Test func truncatedArchiveDoesNotCrash() throws {
        let data = try Data(contentsOf: fixtureURL("sample"))
        for cut in [30, 200, data.count / 2, data.count - 30] {
            _ = try? ZipArchive(data: data.prefix(cut))
        }
    }
}

struct HTMLTextExtractorTests {
    @Test func decodesEntities() {
        #expect(HTMLEntities.decode("a &amp; b &lt;c&gt; &eacute; &#233; &#xE9; &naoexiste; &") == "a & b <c> é é é &naoexiste; &")
    }

    @Test func headingsGetTerminalPunctuationOnlyWhenMissing() {
        let result = HTMLTextExtractor.extract(html: "<h1>Capítulo 1</h1><h2>Pronto?</h2><p>Texto</p>")
        #expect(result.text == "Capítulo 1.\nPronto?\nTexto")
        #expect(result.heading == "Capítulo 1")
    }

    @Test func toleratesMalformedHTML() {
        let result = HTMLTextExtractor.extract(html: "<p>Um<p>Dois <b>negrito<p>Três</i> <br> fim <!-- comentário --> &amp x")
        #expect(result.text.contains("Um\nDois negrito\nTrês"))
        #expect(!result.text.contains("comentário"))
    }

    @Test func removesSoftHyphensAndLigatures() {
        #expect(HTMLTextExtractor.clean("in\u{00AD}te\u{200B}ressante \u{FB01}m") == "interessante fim")
    }

    @Test func urlsAreNotNarrated() {
        let result = HTMLTextExtractor.extract(html: "<p>Disponível em: &lt;http://www.exemplo.com.br/a?b=1&gt;. Veja também www.site.org, ok.</p><p>https://so.url</p>")
        #expect(result.text == "Disponível em:. Veja também ok.")
    }

    @Test func ordinalTOCLabelsAreCombinedWithTheNextTitle() {
        #expect(EPUBPackage.combine(["a.html": ["1", "Introdução a algoritmos", "Outra"], "b.html": ["Prefácio", "Seção"], "c.html": ["Capítulo 3", "Fim"]])
            == ["a.html": "1. Introdução a algoritmos", "b.html": "Prefácio", "c.html": "Capítulo 3. Fim"])
    }

    @Test func emptyDocumentIsEmpty() {
        #expect(HTMLTextExtractor.extract(html: "<html><body><img src='a'/></body></html>").isEmpty)
        #expect(HTMLTextExtractor.extract(html: "").isEmpty)
    }
}
