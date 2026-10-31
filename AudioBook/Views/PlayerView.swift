import SwiftUI

struct PlayerView: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double?
    @State private var showChapters = false
    @AppStorage("playerShowsText") private var showText = false

    var body: some View {
        NavigationStack {
            if let book = player.currentBook {
                VStack(spacing: 16) {
                    if showText {
                        compactTitles(book)
                        ReadAlongView()
                            .task(id: player.chapterIndex) { await player.loadParagraphs() }
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                CoverView(book: book, cornerRadius: 14)
                                    .frame(maxWidth: 240)
                                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                                    .padding(.top, 8)
                                titles(book)
                                if let message = player.errorMessage { errorBanner(message) }
                            }
                        }
                    }
                    if showText, let message = player.errorMessage { errorBanner(message) }
                    VStack(spacing: 20) {
                        scrubber
                        transport
                        secondaryControls
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fechar", systemImage: "chevron.down") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(showText ? "Mostrar capa" : "Acompanhar texto", systemImage: showText ? "book.closed" : "text.alignleft") {
                            withAnimation { showText.toggle() }
                        }
                        Button("Capítulos", systemImage: "list.bullet") { showChapters = true }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showChapters) { chapterList(book) }
            } else {
                ContentUnavailableView("Nada em reprodução", systemImage: "headphones")
            }
        }
    }

    private func titles(_ book: Book) -> some View {
        VStack(spacing: 6) {
            Text(player.chapterTitle).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(3)
            Text(book.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text("Capítulo \(player.chapterIndex + 1) de \(player.chapterCount) • página ≈ \(player.pageEstimate.current) de \(player.pageEstimate.total)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func compactTitles(_ book: Book) -> some View {
        let page = player.pageEstimate
        return VStack(spacing: 2) {
            Text(player.chapterTitle).font(.headline).lineLimit(1)
            Text("Cap. \(player.chapterIndex + 1) de \(player.chapterCount) • página ≈ \(page.current) de \(page.total)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer(minLength: 0)
            Button("Tentar de novo") { player.togglePlayPause() }.font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { scrubValue ?? player.chapterFraction }, set: { scrubValue = $0 })) { editing in
                if !editing, let value = scrubValue {
                    player.seek(toChapterFraction: value)
                    scrubValue = nil
                }
            }
            .accessibilityLabel("Posição no capítulo")
            .accessibilityValue("\(Int((scrubValue ?? player.chapterFraction) * 100)) por cento")
            HStack {
                Text("\(Int((scrubValue ?? player.chapterFraction) * 100))% do capítulo")
                Spacer()
                Text("Livro: \(Int(player.bookFraction * 100))%")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            control("backward.end.fill", "Capítulo anterior", size: 26) { player.previousChapter() }
            control("gobackward.15", "Voltar trecho", size: 30) { player.skipBackward() }
            Button { player.togglePlayPause() } label: {
                ZStack {
                    if player.state == .loading {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                    }
                }
                .frame(width: 72, height: 72)
            }
            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproduzir")
            control("goforward.15", "Avançar trecho", size: 30) { player.skipForward() }
            control("forward.end.fill", "Próximo capítulo", size: 26) { player.nextChapter() }
        }
        .foregroundStyle(.primary)
    }

    private func control(_ icon: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size)).frame(width: 36, height: 44) }
            .accessibilityLabel(label)
    }

    private var secondaryControls: some View {
        HStack {
            Menu {
                Picker("Velocidade", selection: Binding(get: { settings.speedMultiplier }, set: { player.setSpeed($0) })) {
                    ForEach(SpeechRate.multiplierSteps, id: \.self) { Text(SpeechRate.label(for: $0)).tag($0) }
                }
            } label: {
                Label(SpeechRate.label(for: settings.speedMultiplier), systemImage: "gauge.with.dots.needle.67percent")
            }
            .accessibilityLabel("Velocidade da fala")
            .accessibilityValue(SpeechRate.label(for: settings.speedMultiplier))
            Spacer()
            Menu {
                Picker("Timer", selection: Binding(get: { player.sleepTimer }, set: { player.setSleepTimer($0) })) {
                    ForEach(SleepTimerOption.choices, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                Label(player.sleepTimer == .off ? "Timer" : player.sleepTimer.label, systemImage: player.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
            }
            .accessibilityLabel("Timer de repouso")
            .accessibilityValue(player.sleepTimer.label)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func chapterList(_ book: Book) -> some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        player.engine.start(chapter: index)
                        showChapters = false
                    } label: {
                        HStack {
                            Text(chapter.title).foregroundStyle(.primary)
                            Spacer()
                            if index == player.chapterIndex { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
                        }
                    }
                    .id(index)
                }
                .onAppear { proxy.scrollTo(player.chapterIndex, anchor: .center) }
            }
            .navigationTitle("Capítulos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showChapters = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
