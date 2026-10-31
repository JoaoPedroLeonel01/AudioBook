import Foundation
@testable import AudioBook

private final class BundleToken {}

/// Localiza uma fixture EPUB empacotada no bundle de testes.
func fixtureURL(_ name: String) -> URL {
    let bundle = Bundle(for: BundleToken.self)
    return bundle.url(forResource: name, withExtension: "epub")
        ?? bundle.url(forResource: name, withExtension: "epub", subdirectory: "Fixtures")!
}

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
