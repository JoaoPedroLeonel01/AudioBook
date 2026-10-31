import Foundation

nonisolated enum HTMLToken {
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    case end(name: String)
    case text(String)
}

/// Tokenizador de HTML/XHTML tolerante a erros. Não constrói árvore; emite eventos em ordem.
/// Conteúdo de `<script>` e `<style>` é descartado e entidades em texto são decodificadas.
nonisolated enum HTMLScanner {
    static func scan(_ html: String, _ handler: (HTMLToken) -> Void) {
        let bytes = Array(html.utf8)
        let count = bytes.count
        var i = 0
        var textStart = 0

        func flushText(upTo end: Int) {
            if end > textStart {
                let raw = String(decoding: bytes[textStart..<end], as: UTF8.self)
                handler(.text(HTMLEntities.decode(raw)))
            }
        }

        func hasPrefix(_ prefix: String, at position: Int) -> Bool {
            let p = Array(prefix.utf8)
            guard position + p.count <= count else { return false }
            for k in 0..<p.count {
                var b = bytes[position + k]
                if b >= 65 && b <= 90 { b += 32 }
                if b != p[k] { return false }
            }
            return true
        }

        func find(_ needle: String, from position: Int) -> Int? {
            let n = Array(needle.utf8)
            guard !n.isEmpty, count >= n.count else { return nil }
            var k = position
            while k + n.count <= count {
                if hasPrefix(needle, at: k) { return k }
                k += 1
            }
            return nil
        }

        func isNameByte(_ b: UInt8) -> Bool {
            (b >= 48 && b <= 58) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 95 || b == 46
        }
        func isSpace(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 10 || b == 13 || b == 12 }

        while i < count {
            guard bytes[i] == 60 else { i += 1; continue }  // '<'
            guard i + 1 < count else { i += 1; continue }
            let next = bytes[i + 1]

            if hasPrefix("<!--", at: i) {
                flushText(upTo: i)
                i = (find("-->", from: i + 4) ?? count - 3) + 3
                textStart = min(i, count)
                i = textStart
            } else if hasPrefix("<![cdata[", at: i) {
                flushText(upTo: i)
                let end = find("]]>", from: i + 9) ?? count
                if end > i + 9 {
                    handler(.text(String(decoding: bytes[(i + 9)..<end], as: UTF8.self)))
                }
                i = min(end + 3, count)
                textStart = i
            } else if next == 33 || next == 63 {  // '!' ou '?'
                flushText(upTo: i)
                var k = i + 2
                while k < count && bytes[k] != 62 { k += 1 }
                i = min(k + 1, count)
                textStart = i
            } else if next == 47 {  // '</'
                var k = i + 2
                let nameStart = k
                while k < count && isNameByte(bytes[k]) { k += 1 }
                guard k > nameStart else { i += 1; continue }
                flushText(upTo: i)
                let name = String(decoding: bytes[nameStart..<k], as: UTF8.self).lowercased()
                while k < count && bytes[k] != 62 { k += 1 }
                i = min(k + 1, count)
                textStart = i
                handler(.end(name: name))
            } else if (next >= 65 && next <= 90) || (next >= 97 && next <= 122) {
                flushText(upTo: i)
                var k = i + 1
                let nameStart = k
                while k < count && isNameByte(bytes[k]) { k += 1 }
                let name = String(decoding: bytes[nameStart..<k], as: UTF8.self).lowercased()
                var attributes: [String: String] = [:]
                var selfClosing = false

                attributeLoop: while k < count {
                    while k < count && isSpace(bytes[k]) { k += 1 }
                    guard k < count else { break }
                    if bytes[k] == 62 { k += 1; break }
                    if bytes[k] == 47 {
                        selfClosing = true
                        k += 1
                        continue
                    }
                    let attrStart = k
                    while k < count && !isSpace(bytes[k]) && bytes[k] != 61 && bytes[k] != 62 && bytes[k] != 47 { k += 1 }
                    if k == attrStart { k += 1; continue }
                    let attrName = String(decoding: bytes[attrStart..<k], as: UTF8.self).lowercased()
                    while k < count && isSpace(bytes[k]) { k += 1 }
                    var value = ""
                    if k < count && bytes[k] == 61 {
                        k += 1
                        while k < count && isSpace(bytes[k]) { k += 1 }
                        if k < count && (bytes[k] == 34 || bytes[k] == 39) {
                            let quote = bytes[k]
                            k += 1
                            let valueStart = k
                            while k < count && bytes[k] != quote { k += 1 }
                            value = String(decoding: bytes[valueStart..<min(k, count)], as: UTF8.self)
                            k = min(k + 1, count)
                        } else {
                            let valueStart = k
                            while k < count && !isSpace(bytes[k]) && bytes[k] != 62 { k += 1 }
                            value = String(decoding: bytes[valueStart..<k], as: UTF8.self)
                        }
                    }
                    attributes[attrName] = HTMLEntities.decode(value)
                    continue attributeLoop
                }

                i = min(k, count)
                textStart = i
                handler(.start(name: name, attributes: attributes, selfClosing: selfClosing))

                if !selfClosing && (name == "script" || name == "style") {
                    let end = find("</\(name)", from: i) ?? count
                    var k2 = end
                    while k2 < count && bytes[k2] != 62 { k2 += 1 }
                    i = min(k2 + 1, count)
                    textStart = i
                    handler(.end(name: name))
                }
            } else {
                i += 1  // '<' literal
            }
        }
        flushText(upTo: count)
    }
}
