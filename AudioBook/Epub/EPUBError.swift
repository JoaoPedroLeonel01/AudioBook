import Foundation

nonisolated enum EPUBError: LocalizedError, Equatable {
    case invalidFileType
    case unreadableFile
    case notAnEPUB
    case corrupted(String)
    case drmProtected
    case noReadableContent
    case chapterUnavailable(Int)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            "O arquivo selecionado não é um EPUB (.epub)."
        case .unreadableFile:
            "Não foi possível ler o arquivo. Verifique se ele ainda está disponível."
        case .notAnEPUB:
            "O arquivo não é um EPUB válido."
        case .corrupted(let detail):
            "O EPUB parece estar corrompido (\(detail))."
        case .drmProtected:
            "Este EPUB é protegido por DRM e não pode ser aberto. Use uma cópia sem proteção."
        case .noReadableContent:
            "O EPUB não contém texto que possa ser narrado."
        case .chapterUnavailable(let index):
            "O capítulo \(index + 1) não pôde ser carregado."
        case .duplicate(let title):
            "“\(title)” já está na sua biblioteca."
        }
    }
}
