import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Query(sort: \Book.importedAt, order: .reverse) private var books: [Book]
    @Environment(AppEnvironment.self) private var environment
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerViewModel.self) private var player

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var bookToDelete: Book?
    @State private var path: [Book] = []

    var body: some View {
        @Bindable var library = library
        @Bindable var player = player
        NavigationStack(path: $path) {
            Group {
                if books.isEmpty { emptyState } else { bookList }
            }
            .navigationTitle("Biblioteca")
            .navigationDestination(for: Book.self) { BookDetailsView(book: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ajustes", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importar EPUB", systemImage: "plus") { showImporter = true }
                        .disabled(library.isImporting)
                }
            }
            .overlay { if library.isImporting { importingOverlay } }
            .safeAreaInset(edge: .bottom) { if player.currentBook != nil { MiniPlayerView() } }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.epub], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importBooks(from: urls) }
            case .failure(let error): library.alertMessage = error.localizedDescription
            }
        }
        #if DEBUG
        .task {
            // Ganchos de validação visual: -DebugScreen details|settings
            try? await Task.sleep(for: .milliseconds(800))
            switch UserDefaults.standard.string(forKey: "DebugScreen") {
            case "details": if let first = books.first { path = [first] }
            case "settings": showSettings = true
            default: break
            }
        }
        #endif
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: $player.isPlayerPresented) { PlayerView() }
        .confirmationDialog("Excluir livro?", isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }), presenting: bookToDelete) { book in
            Button("Excluir “\(book.title)”", role: .destructive) { library.delete(book) }
        } message: { _ in
            Text("O arquivo e o progresso de leitura serão removidos do aparelho.")
        }
        .alert("Atenção", isPresented: Binding(get: { library.alertMessage != nil }, set: { if !$0 { library.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(library.alertMessage ?? "") }
        .alert("Não foi possível reproduzir", isPresented: Binding(get: { player.errorMessage != nil && !player.isPlayerPresented }, set: { if !$0 { player.dismissError() } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(player.errorMessage ?? "") }
    }

    private var bookList: some View {
        List {
            if let warning = environment.startupWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            ForEach(books) { book in
                BookRow(book: book, onDelete: { bookToDelete = book })
                    .background(NavigationLink(value: book) { EmptyView() }.opacity(0))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Excluir", systemImage: "trash", role: .destructive) { bookToDelete = book }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nenhum livro ainda", systemImage: "books.vertical")
        } description: {
            Text("Importe um arquivo EPUB para ouvir com a voz do seu iPhone. Seus livros ficam apenas neste aparelho.")
        } actions: {
            Button("Importar EPUB") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .disabled(library.isImporting)
        }
    }

    private var importingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(library.importProgress.map { "Importando \($0.current) de \($0.total)…" } ?? "Importando…").font(.subheadline)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct BookRow: View {
    let book: Book
    var onDelete: () -> Void
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(2)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: book.progressFraction).tint(.accentColor).padding(.top, 2)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                player.play(book)
            } label: {
                Image(systemName: player.isCurrent(book) && player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 38))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(player.isCurrent(book) && player.isPlaying ? "Abrir player" : (book.hasStarted ? "Continuar ouvindo \(book.title)" : "Ouvir \(book.title)"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Excluir", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        if book.isFinished { return "Concluído" }
        let percent = Int(book.progressFraction * 100)
        return book.hasStarted ? "\(percent)% • capítulo \((book.progress?.chapterIndex ?? 0) + 1) de \(book.chapters.count)" : "\(book.chapters.count) capítulos"
    }
}
