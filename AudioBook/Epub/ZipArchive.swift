import Foundation
import Compression

/// Leitor mínimo de ZIP (somente leitura) para os formatos usados por EPUB:
/// entradas armazenadas (método 0) ou comprimidas com deflate (método 8).
/// O arquivo é mapeado em memória; apenas a entrada solicitada é descomprimida.
nonisolated struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error, Equatable {
        case notAZip
        case corrupted(String)
        case unsupported(String)
        case entryNotFound(String)
        case decompressionFailed(String)
    }

    /// Limite de segurança por entrada descomprimida (proteção contra zip bombs).
    static let maxEntrySize = 256 * 1024 * 1024

    private let data: Data
    private(set) var entries: [String: Entry]
    private(set) var orderedNames: [String]

    init(url: URL) throws {
        let mapped: Data
        do {
            mapped = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw ZipError.corrupted("arquivo ilegível")
        }
        try self.init(data: mapped)
    }

    init(data: Data) throws {
        self.data = data.startIndex == 0 ? data : Data(data)
        self.entries = [:]
        self.orderedNames = []
        try parseCentralDirectory()
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// Procura ignorando maiúsculas/minúsculas quando o nome exato não existe.
    func resolvedName(_ name: String) -> String? {
        if entries[name] != nil { return name }
        let lower = name.lowercased()
        return orderedNames.first { $0.lowercased() == lower }
    }

    func read(_ name: String) throws -> Data {
        guard let key = resolvedName(name), let entry = entries[key] else {
            throw ZipError.entryNotFound(name)
        }
        return try read(entry)
    }

    func read(_ entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntrySize else {
            throw ZipError.unsupported("entrada grande demais")
        }
        let offset = entry.localHeaderOffset
        guard offset >= 0, offset + 30 <= data.count, u32(offset) == 0x04034b50 else {
            throw ZipError.corrupted("cabeçalho local inválido")
        }
        let nameLength = Int(u16(offset + 26))
        let extraLength = Int(u16(offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count else {
            throw ZipError.corrupted("dados fora dos limites")
        }

        switch entry.method {
        case 0:
            return data.subdata(in: start..<end)
        case 8:
            return try inflate(start: start, compressedSize: entry.compressedSize, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("método de compressão \(entry.method)")
        }
    }

    // MARK: - Interno

    private mutating func parseCentralDirectory() throws {
        let count = data.count
        guard count >= 22 else { throw ZipError.notAZip }

        // Procura a assinatura do End Of Central Directory nos últimos 64 KB.
        let lowerBound = max(0, count - 22 - 65535)
        var eocd = -1
        var position = count - 22
        while position >= lowerBound {
            if u32(position) == 0x06054b50 {
                eocd = position
                break
            }
            position -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let totalEntries = Int(u16(eocd + 10))
        let directorySize = Int(u32(eocd + 12))
        let directoryOffset = Int(u32(eocd + 16))
        if totalEntries == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipError.unsupported("ZIP64")
        }
        guard directoryOffset >= 0, directoryOffset + directorySize <= count else {
            throw ZipError.corrupted("diretório central fora dos limites")
        }

        var cursor = directoryOffset
        var parsed = 0
        while parsed < totalEntries {
            guard cursor + 46 <= count, u32(cursor) == 0x02014b50 else {
                throw ZipError.corrupted("entrada do diretório inválida")
            }
            let flags = u16(cursor + 8)
            let method = u16(cursor + 10)
            let compressedSize = Int(u32(cursor + 20))
            let uncompressedSize = Int(u32(cursor + 24))
            let nameLength = Int(u16(cursor + 28))
            let extraLength = Int(u16(cursor + 30))
            let commentLength = Int(u16(cursor + 32))
            let localOffset = Int(u32(cursor + 42))
            guard cursor + 46 + nameLength <= count else {
                throw ZipError.corrupted("nome de entrada fora dos limites")
            }
            if flags & 0x1 != 0 {
                // Entradas criptografadas no nível do ZIP não são suportadas.
                throw ZipError.unsupported("ZIP criptografado")
            }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            if !name.hasSuffix("/") {
                entries[name] = Entry(
                    name: name,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
                orderedNames.append(name)
            }
            cursor += 46 + nameLength + extraLength + commentLength
            parsed += 1
        }
    }

    private func inflate(start: Int, compressedSize: Int, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written: Int = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB em Apple decodifica deflate "cru" (sem cabeçalho zlib).
                return compression_decode_buffer(dst, expectedSize, src + start, compressedSize, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else {
            throw ZipError.decompressionFailed("tamanho inesperado (\(written)/\(expectedSize))")
        }
        return output
    }

    private func u16(_ offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
    }

    private func u32(_ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }
}
