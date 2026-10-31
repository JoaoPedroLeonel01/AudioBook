import SwiftUI
import SwiftData

@main
struct AudioBookApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(environment)
                .environment(environment.library)
                .environment(environment.player)
                .environment(environment.settings)
                .modelContainer(environment.container)
                .task { environment.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { environment.player.saveProgress() }
                }
        }
    }
}
