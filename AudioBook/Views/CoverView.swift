import SwiftUI
import UIKit

private let coverCache = NSCache<NSString, UIImage>()

/// Capa do livro (arquivo local) com placeholder tipográfico quando não há imagem.
struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 8
    @Environment(AppEnvironment.self) private var environment
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.1)))
        .accessibilityHidden(true)
        .task(id: book.id) { image = await load() }
    }

    private var placeholder: some View {
        let hue = Double(abs(book.title.hashValue % 360)) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55), Color(hue: hue, saturation: 0.6, brightness: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: "book.closed.fill").font(.title2)
                Text(book.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(4).padding(.horizontal, 6)
            }
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func load() async -> UIImage? {
        guard book.hasCover else { return nil }
        let key = book.id.uuidString as NSString
        if let cached = coverCache.object(forKey: key) { return cached }
        let url = environment.storage.coverURL(for: book.id)
        let loaded = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        if let loaded { coverCache.setObject(loaded, forKey: key) }
        return loaded
    }
}
