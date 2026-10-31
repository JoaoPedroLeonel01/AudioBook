import SwiftUI

struct BookDetailsView: View {
    let book: Book
    @Environment(PlayerViewModel.self) private var player
    @Environment(LibraryViewModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section("Capítulos (\(book.chapters.count))") {
                ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        player.play(book, chapter: index)
                    } label: {
                        HStack {
                            Text(chapter.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer()
                            if isCurrent(index) {
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityLabel("Capítulo \(index + 1): \(chapter.title)")
                    .accessibilityHint("Toque duas vezes para ouvir a partir daqui")
                    .accessibilityAddTraits(isCurrent(index) ? .isSelected : [])
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Excluir livro", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Excluir livro?", isPresented: $confirmDelete) {
            Button("Excluir “\(book.title)”", role: .destructive) {
                library.delete(book)
                dismiss()
            }
        } message: {
            Text("O arquivo e o progresso de leitura serão removidos do aparelho.")
        }
    }

    private func isCurrent(_ index: Int) -> Bool {
        if player.isCurrent(book) { return player.chapterIndex == index }
        return (book.progress?.chapterIndex ?? 0) == index && book.hasStarted
    }

    private var header: some View {
        VStack(spacing: 16) {
            CoverView(book: book, cornerRadius: 12)
                .frame(width: 150)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            VStack(spacing: 4) {
                Text(book.title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                if let language = book.language {
                    Text(language.uppercased()).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            if book.hasStarted {
                VStack(spacing: 4) {
                    ProgressView(value: book.progressFraction)
                    Text("\(Int(book.progressFraction * 100))% concluído").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                player.play(book)
            } label: {
                Label(book.hasStarted ? (book.isFinished ? "Ouvir novamente" : "Continuar ouvindo") : "Começar a ouvir", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}
