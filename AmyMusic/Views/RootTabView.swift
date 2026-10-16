import SwiftUI
import Combine

// MARK: - Phone-First Root Layout (Exact Port of src/mobile/MobileLayout.jsx, MobileMiniPlayer.jsx & src/main.css)
// - 3-Tab Icon-Only Liquid Glass Dock ("Моя волна", "Чарты", "Коллекция")
// - Separate Floating MobileMiniPlayer (64pt height, 20pt radius, 52x52 cover, 48x48 play button, swipe L/R)
// - 10pt gap between MiniPlayer and NavDock
// - Automatic hiding when iPhone virtual keyboard is open (.is-keyboard-open)

public enum AmyMobileTab: Int, CaseIterable, Identifiable {
    case wave = 0
    case trends = 1
    case collection = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .wave: return "Моя волна"
        case .trends: return "Чарты"
        case .collection: return "Коллекция"
        }
    }

    public var systemIcon: String {
        switch self {
        case .wave: return "waveform.path.ecg"
        case .trends: return "flame.fill"
        case .collection: return "heart.rectangle.fill"
        }
    }
}

public struct RootTabView: View {
    @Bindable var player: AudioPlayerManager
    @State private var activeTab: AmyMobileTab = .wave
    @State private var isFullPlayerOpen: Bool = false
    @State private var isEqualizerOpen: Bool = false
    @State private var isQueueSheetOpen: Bool = false
    @State private var isSettingsOpen: Bool = false
    @State private var isMiniKaraokeOpen: Bool = false
    @State private var selectedArtistId: String? = nil
    @State private var selectedRelease: ReleaseItem? = nil
    @State private var isKeyboardVisible: Bool = false

    @Namespace private var glassNamespace

    public init(player: AudioPlayerManager = .shared) {
        self.player = player
    }

    public var body: some View {
        let themeAccent = Color(hex: player.settings.themePreset.primaryHex)

        ZStack(alignment: .bottom) {
            Color.amyBackground.ignoresSafeArea()

            // Main Phone Stage (.mobile-content-stage) with smooth fluid crossfade
            ZStack {
                switch activeTab {
                case .wave:
                    HomeWaveView(
                        player: player,
                        onOpenFullPlayer: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                isFullPlayerOpen = true
                            }
                        },
                        onOpenArtist: { id in selectedArtistId = id },
                        onOpenRelease: { rel in selectedRelease = rel },
                        onOpenSettings: { isSettingsOpen = true },
                        onNavigateCollection: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                                activeTab = .collection
                            }
                        }
                    )
                    .transition(.opacity)
                case .trends:
                    TrendsChartsView(
                        player: player,
                        onOpenArtist: { id in selectedArtistId = id },
                        onOpenSettings: { isSettingsOpen = true }
                    )
                    .transition(.opacity)
                case .collection:
                    CollectionView(
                        player: player,
                        onOpenArtist: { id in selectedArtistId = id },
                        onOpenRelease: { rel in selectedRelease = rel },
                        onOpenSettings: { isSettingsOpen = true }
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: activeTab)
            .safeAreaInset(edge: .bottom) {
                // Separate Floating Surfaces: MobileMiniPlayer (64pt) + 8pt gap + MobileNavDock (58pt)
                VStack(spacing: 8) {
                    PhoneLiquidGlassMiniPlayer(
                        player: player,
                        glassNamespace: glassNamespace,
                        onOpenFull: {
                            isFullPlayerOpen = true
                        },
                        onOpenEqualizer: { isEqualizerOpen = true },
                        onToggleKaraoke: {
                            withAnimation(.spring(duration: 0.3)) {
                                isMiniKaraokeOpen.toggle()
                            }
                        }
                    )

                    PhoneFloatingNavDock(
                        activeTab: $activeTab,
                        accentColor: themeAccent
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isFullPlayerOpen) {
            FullPlayerOverlayView(
                player: player,
                isPresented: $isFullPlayerOpen,
                onOpenArtist: { artistId in
                    isFullPlayerOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedArtistId = artistId
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(Color.amyBackground)
        }
        .sheet(isPresented: $isEqualizerOpen) {
            EqualizerSheetView(player: player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isQueueSheetOpen) {
            QueueBottomSheetView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSettingsOpen) {
            SettingsAndProfileView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { selectedArtistId.map { IdentifiableArtistId(id: $0) } },
            set: { selectedArtistId = $0?.id }
        )) { item in
            ArtistDetailSheetView(
                artistId: item.id,
                player: player,
                onOpenRelease: { rel in
                    selectedRelease = rel
                }
            )
        }
        .sheet(item: $selectedRelease) { release in
            AlbumOrPlaylistSheetView(
                release: release,
                player: player,
                onOpenArtist: { id in
                    selectedArtistId = id
                }
            )
        }
    }
}

// MARK: - Phone Liquid Glass Mini-Player (Exact Port of .mobile-mini-player in MobileMiniPlayer.jsx)
// - min-height: 64pt, border-radius: 20pt, padding: 6pt 8pt 6pt 6pt
// - Cover: 52x52pt, border-radius: 14pt
// - Title: 14pt bold (#fff), Artist: 12pt (#a1a1aa)
// - Play button: 48x48pt white circle (#fff) with 21x21pt black icon (#0b0b0d)
// - Swipe gesture: deltaX >= 52pt -> left = previous(), right = next()

public struct PhoneLiquidGlassMiniPlayer: View {
    @Bindable var player: AudioPlayerManager
    var glassNamespace: Namespace.ID
    var onOpenFull: () -> Void
    var onOpenEqualizer: () -> Void
    var onToggleKaraoke: () -> Void

    @State private var dragXOffset: CGFloat = 0

    public var body: some View {
        let track = player.currentTrack
        let hasTrack = track != nil
        let palette = track?.palette ?? .defaultPalette
        let progress = player.duration > 0 ? min(1.0, max(0.0, player.currentTime / player.duration)) : 0

        HStack(spacing: 8) {
            // .mobile-mini-player__track (свайп по всей поверхности + тап для открытия фуллплеера)
            HStack(spacing: 10) {
                // .mobile-mini-player__cover (50x50pt, radius 14pt)
                AsyncImage(url: URL(string: track?.coverUrl ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color(hex: "#252529")
                        LinearGradient(
                            colors: [Color(hex: palette.line).opacity(0.6), Color(hex: palette.base)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // .mobile-mini-player__meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasTrack ? (track?.title ?? "Без названия") : "Нет трека")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(hasTrack ? (track?.artist ?? "Неизвестный артист") : "Трек не загружен")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "#A1A1AA"))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: dragXOffset)
            .onTapGesture {
                onOpenFull()
            }

            if player.settings.miniPlayerStyle == .classic {
                Button(action: onToggleKaraoke) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button(action: onOpenEqualizer) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(player.settings.equalizerEnabled ? .white : .white.opacity(0.75))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Кнопка Лайка (слева от кнопки плей/стоп)
            if let track {
                let isLiked = player.isLiked(track)
                Button {
                    player.toggleLike(track)
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isLiked ? .white : .white.opacity(0.78))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(ScalePressButtonStyle(scale: 0.88))
            }

            // .mobile-mini-player__play (46x46pt white circle, 18x18pt black icon)
            Button {
                if hasTrack {
                    player.togglePlay()
                } else {
                    onOpenFull()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 46, height: 46)

                    if player.isLoading {
                        ProgressView()
                            .tint(Color(hex: "#0B0B0D"))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color(hex: "#0B0B0D"))
                            .offset(x: player.isPlaying ? 0 : 1.5)
                    }
                }
            }
            .buttonStyle(ScalePressButtonStyle(scale: 0.92))
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        .frame(height: 64)
        .background {
            if player.settings.miniPlayerStyle == .waveform {
                MiniWaveformBackdropView(
                    seed: track?.id ?? "amy",
                    progress: progress,
                    isPlaying: player.isPlaying
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .amyLiquidGlass(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: Color(hex: palette.line),
            tintOpacity: player.settings.glassTintIntensity,
            interactive: true
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.42), radius: 20, y: 10)
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // Приоритет горизонтального свайпа треков
                    if abs(dx) > abs(dy) * 0.75 && hasTrack {
                        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                            dragXOffset = dx * 0.35
                        }
                    }
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        dragXOffset = 0
                    }

                    // Свайп по любой поверхности миниплеера:
                    // Вправо (dx >= 25) -> предыдущий трек
                    // Влево (dx <= -25) -> следующий трек
                    if abs(dx) >= 25 && abs(dx) > abs(dy) * 0.7 && hasTrack {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if dx > 0 {
                            player.previous()
                        } else {
                            player.next()
                        }
                    } else if dy < -30 {
                        // Свайп снизу вверх -> открыть полный плеер
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenFull()
                    }
                }
        )
    }
}

// MARK: - Telegram-Style Liquid Glass Floating Navigation Dock
// Exact reproduction of Telegram iOS 26 Liquid Glass floating bar with draggable chromatic droplet (image0.jpg & image1.jpg)
// - Floating Capsule() with glossy specular top highlight & deep dark frosted glass
// MARK: - Telegram & Kavsoft iOS 26 Pure Liquid Glass Floating Nav Dock
// - Pure Apple Liquid Glass effect: Crystal frosted glass with specular reflections (NO RAINBOW, NO ORANGE)
// - Pixel-perfect centering on active tab icon and label across all iPhone screen sizes
// - Bulging liquid glass droplet on hold & fluid drag with spring snap physics

public struct PhoneFloatingNavDock: View {
    @Binding var activeTab: AmyMobileTab
    var accentColor: Color

    @State private var isHoldingDroplet: Bool = false
    @State private var dragX: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var hoveredTab: AmyMobileTab? = nil

    public var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height
            let tabCount = CGFloat(AmyMobileTab.allCases.count)
            let slotW = totalW / tabCount

            // Active Tab Center X - exactly aligned with the slot center
            let activeIndex = CGFloat(activeTab.rawValue)
            let idleCenterX = slotW * (activeIndex + 0.5)

            // Droplet Center X (smooth tracking when dragging, exact center when resting)
            let dropletCenterX = isHoldingDroplet
                ? min(max(slotW * 0.45, dragX), totalW - slotW * 0.45)
                : idleCenterX

            // Elastic horizontal expansion during drag
            let stretchW = isHoldingDroplet ? min(24, abs(dragOffset) * 0.22) : 0
            let dropletW = slotW * 0.88 + stretchW
            // Bulges slightly above and below the dock when held
            let dropletH = isHoldingDroplet ? totalH + 8 : totalH - 12

            ZStack {
                // Background Liquid Glass Droplet ("Капля") - однотонная чистая прозрачная капсула
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(isHoldingDroplet ? 0.18 : 0.12))
                        .frame(width: dropletW, height: dropletH)

                    Capsule()
                        .strokeBorder(Color.white.opacity(isHoldingDroplet ? 0.22 : 0.12), lineWidth: 0.8)
                        .frame(width: dropletW, height: dropletH)
                }
                .position(x: dropletCenterX, y: totalH / 2)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.68), value: dropletCenterX)
                .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isHoldingDroplet)
                .allowsHitTesting(false)

                // 3 Tabs: Explicit slot width guarantees 100% dead-center icon and text alignment
                HStack(spacing: 0) {
                    ForEach(AmyMobileTab.allCases) { tab in
                        let isCurrent = (isHoldingDroplet ? (hoveredTab == tab) : (activeTab == tab))

                        VStack(spacing: 3) {
                            Image(systemName: tab.systemIcon)
                                .font(.system(size: 20, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? .white : .white.opacity(isHoldingDroplet ? 0.40 : 0.60))
                                .scaleEffect(isCurrent ? (isHoldingDroplet ? 1.15 : 1.05) : 1.0)

                            Text(tab.label)
                                .font(.system(size: 10.5, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? .white : .white.opacity(isHoldingDroplet ? 0.40 : 0.60))
                        }
                        .frame(width: slotW, height: totalH)
                        .contentShape(Rectangle())
                        .animation(.spring(response: 0.24, dampingFraction: 0.70), value: isCurrent)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { val in
                        let x = val.location.x
                        if !isHoldingDroplet {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                                isHoldingDroplet = true
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        dragX = x
                        dragOffset = val.translation.width

                        let index = min(2, max(0, Int(floor(x / slotW))))
                        if let tab = AmyMobileTab(rawValue: index), hoveredTab != tab {
                            hoveredTab = tab
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { val in
                        let finalIndex = min(2, max(0, Int(floor(val.location.x / slotW))))
                        let finalTab = AmyMobileTab(rawValue: finalIndex) ?? activeTab
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.70)) {
                            activeTab = finalTab
                            isHoldingDroplet = false
                            dragOffset = 0
                            hoveredTab = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
            )
        }
        .frame(height: 58)
        .background {
            Capsule()
                .fill(Color(hex: "#141418").opacity(0.88))
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        }
        .shadow(color: .black.opacity(0.50), radius: 22, y: 10)
    }
}

public struct ScalePressButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.95
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Deterministic Waveform Bar Renderer (Port of WaveformPlayer in src/App.jsx)

public struct MiniWaveformBackdropView: View {
    public var seed: String
    public var progress: Double
    public var isPlaying: Bool

    private var bars: [CGFloat] {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return (0..<72).map { idx in
            let v = sin(Double(idx) * 0.43 + Double(hash % 97)) * 0.5 + 0.5
            return CGFloat(0.22 + v * 0.72)
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let allBars = bars
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<allBars.count, id: \.self) { i in
                    let ratio = Double(i) / Double(allBars.count)
                    let isPlayed = ratio <= progress
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPlayed ? .white.opacity(0.42) : .white.opacity(0.14))
                        .frame(
                            height: geo.size.height * 0.72 * (isPlaying ? allBars[i] : 0.14)
                        )
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(duration: 0.35), value: isPlaying)
        }
    }
}
