import AVFoundation
import OSLog

/// Configura a sessão de áudio para narração em segundo plano e repassa interrupções e
/// mudanças de rota (ex.: fones desconectados) ao restante do app.
@MainActor
final class AudioSessionManager {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    var onHeadphonesDisconnected: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "br.com.estudoSwiftUI.AudioBook", category: "AudioSession")
    private var observers: [NSObjectProtocol] = []

    init() {
        // iOS 27: a sessão avisa quando fica inativa (interrompida pelo sistema) e quando
        // recomenda retomar; substituem a antiga AVAudioSessionInterruptionNotification.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            MainActor.assumeIsolated { self?.handleDeactivation(context) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            MainActor.assumeIsolated { self?.handleResumption(context) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.handleRouteChange(reasonValue: reasonValue) }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Categoria `.playback` + modo `.spokenAudio`: toca com a tela bloqueada e pausa outros áudios falados.
    func activate() {
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            logger.error("Falha ao ativar sessão de áudio: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Falha ao desativar sessão de áudio: \(error.localizedDescription)")
        }
    }

    private func handleDeactivation(_ context: AVAudioSession.DeactivationContext?) {
        // Desativações pedidas pelo próprio app (source == .app) não são interrupções.
        guard let context, context.source == .system else { return }
        logger.info("Sessão de áudio interrompida pelo sistema")
        onInterruptionBegan?()
    }

    private func handleResumption(_ context: AVAudioSession.ResumptionContext?) {
        onInterruptionEnded?(context?.recommendation == .shouldResume)
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable { onHeadphonesDisconnected?() }
    }
}
