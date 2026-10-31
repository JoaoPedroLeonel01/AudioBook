import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        if let book = player.currentBook {
            HStack(spacing: 12) {
                CoverView(book: book, cornerRadius: 5).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.chapterTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(book.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproduzir")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottom) {
                ProgressView(value: player.chapterFraction).padding(.horizontal, 14).scaleEffect(y: 0.5)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { player.isPlayerPresented = true }
            .accessibilityElement(children: .contain)
            .accessibilityHint("Toque para abrir o player")
        }
    }
}
