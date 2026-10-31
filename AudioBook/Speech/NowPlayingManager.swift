import MediaPlayer
import UIKit

/// Informações da tela de bloqueio e comandos remotos (fones, Central de Controle, CarPlay).
@MainActor
final class NowPlayingManager {
    struct Commands {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var nextChapter: () -> Void
        var previousChapter: () -> Void
        var skipForward: () -> Void
        var skipBackward: () -> Void
    }

    private let center = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkBookID: UUID?

    func install(_ commands: Commands) {
        removeTargets()
        func add(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
            command.isEnabled = true
            let token = command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
            targets.append((command, token))
        }
        add(center.playCommand, commands.play)
        add(center.pauseCommand, commands.pause)
        add(center.togglePlayPauseCommand, commands.toggle)
        add(center.nextTrackCommand, commands.nextChapter)
        add(center.previousTrackCommand, commands.previousChapter)
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        add(center.skipForwardCommand, commands.skipForward)
        add(center.skipBackwardCommand, commands.skipBackward)
        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    func removeTargets() {
        for (command, token) in targets { command.removeTarget(token) }
        targets.removeAll()
    }

    func update(book: Book, chapterTitle: String, chapterFraction: Double, isPlaying: Bool, coverURL: URL?) {
        if artworkBookID != book.id {
            artworkBookID = book.id
            artwork = coverURL.flatMap { UIImage(contentsOfFile: $0.path) }.map { image in
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPNowPlayingInfoPropertyPlaybackProgress: chapterFraction,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        artworkBookID = nil
        artwork = nil
    }
}
