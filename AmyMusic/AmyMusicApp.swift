import SwiftUI

// MARK: - AmyMusic iOS 26 Native App Entry Point

@main
struct AmyMusicApp: App {
    @State private var player = AudioPlayerManager.shared

    var body: some Scene {
        WindowGroup {
            RootTabView(player: player)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.host == "toggle-like" || url.path.contains("toggle-like") {
                        player.toggleLikeCurrent()
                    }
                }
        }
    }
}
