import SwiftUI

// MARK: - AmyMusic iOS 26 Native App Entry Point

@main
struct AmyMusicApp: App {
    @State private var player = AudioPlayerManager.shared

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        appearance.backgroundColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

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
