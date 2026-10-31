import Foundation

/// Árvore XML mínima (nomes locais, sem prefixo de namespace) para container.xml, OPF e NCX.
nonisolated final class XMLNode {
    let name: String
    var attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
    func children(named name: String) -> [XMLNode] { children.filter { $0.name == name } }

    func descendants(named name: String) -> [XMLNode] {
        var result: [XMLNode] = []
        for child in children {
            if child.name == name { result.append(child) }
            result += child.descendants(named: name)
        }
        return result
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func parse(_ data: Data) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() || builder.root != nil else { return nil }
        return builder.root
    }

    private static func localName(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict { attributes[XMLNode.localName(key)] = value }
            let node = XMLNode(name: XMLNode.localName(elementName), attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let string = String(data: CDATABlock, encoding: .utf8) { stack.last?.text += string }
        }
    }
}
