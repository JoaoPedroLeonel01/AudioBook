import SwiftUI

/// Texto do capítulo com o trecho e a palavra falados em destaque; rola sozinho e permite tocar para ir a um parágrafo.
struct ReadAlongView: View {
    @Environment(PlayerViewModel.self) private var player
    @State private var autoFollow = true

    var body: some View {
        let paragraphs = player.paragraphs
        let highlight = player.engine.highlight?.chapter == player.chapterIndex ? player.engine.highlight : nil
        let currentIndex = ReadParagraph.index(of: highlight?.wordStart ?? player.engine.position.offset, in: paragraphs)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs) { paragraph in
                        Text(attributed(paragraph, highlight: highlight))
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { player.seek(toOffset: paragraph.start) }
                            .id(paragraph.id)
                            .accessibilityAddTraits(paragraph.id == currentIndex ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in autoFollow = false })
            .onChange(of: currentIndex) { _, new in
                guard autoFollow, let new else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onChange(of: player.chapterIndex) { _, _ in autoFollow = true }
            .onAppear {
                if let currentIndex { proxy.scrollTo(currentIndex, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if !autoFollow, let currentIndex {
                    Button("Voltar ao trecho atual", systemImage: "scope") {
                        autoFollow = true
                        withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                if paragraphs.isEmpty { ProgressView() }
            }
        }
    }

    private func attributed(_ paragraph: ReadParagraph, highlight: SpokenHighlight?) -> AttributedString {
        var string = AttributedString(paragraph.text)
        guard let highlight else { return string }

        func apply(_ start: Int, _ end: Int, _ configure: (inout AttributeContainer) -> Void) {
            let lower = max(start, paragraph.start) - paragraph.start
            let upper = min(end, paragraph.end) - paragraph.start
            guard lower < upper else { return }
            let nsRange = NSRange(location: lower, length: upper - lower)
            guard let stringRange = Range(nsRange, in: paragraph.text), let range = Range(stringRange, in: string) else { return }
            var container = AttributeContainer()
            configure(&container)
            string[range].mergeAttributes(container)
        }
        apply(highlight.chunkStart, highlight.chunkEnd) { $0.backgroundColor = Color.accentColor.opacity(0.15) }
        if highlight.wordLength > 0 {
            apply(highlight.wordStart, highlight.wordStart + highlight.wordLength) {
                $0.backgroundColor = Color.accentColor.opacity(0.45)
            }
        }
        return string
    }
}
