import Foundation

nonisolated enum HTMLEntities {
    private static let latin1Names: [String] = [
        "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
        "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
        "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml",
        "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
        "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
        "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml"
    ]

    private static let table: [String: String] = {
        var map: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
            "ldquo": "“", "rdquo": "”", "bdquo": "„", "hellip": "…", "bull": "•",
            "trade": "™", "euro": "€", "dagger": "†", "Dagger": "‡", "permil": "‰",
            "lsaquo": "‹", "rsaquo": "›", "oline": "‾", "frasl": "⁄", "ensp": " ",
            "emsp": " ", "thinsp": " ", "zwnj": "", "zwj": "", "larr": "←", "rarr": "→",
            "OElig": "Œ", "oelig": "œ", "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ"
        ]
        for (index, name) in latin1Names.enumerated() {
            map[name] = String(UnicodeScalar(UInt8(160 + index)))
        }
        return map
    }()

    /// Decodifica entidades nomeadas e numéricas. Entidades desconhecidas são preservadas.
    static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            if character == "&", let semicolon = string[index...].prefix(12).firstIndex(of: ";") {
                let body = string[string.index(after: index)..<semicolon]
                if let decoded = decodeBody(body) {
                    result += decoded
                    index = string.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = string.index(after: index)
        }
        return result
    }

    private static func decodeBody(_ body: Substring) -> String? {
        guard !body.isEmpty else { return nil }
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        return table[String(body)]
    }
}
