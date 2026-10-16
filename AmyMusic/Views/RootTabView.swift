import SwiftUI
import Combine

// MARK: - Phone-First Root Layout with Apple Liquid Glass Navigation
// - 4 Tabs: "Моя волна", "Чарты", "Поиск", "Коллекция"
// - Intelligent Liquid Glass Morphing:
//   * At top / resting: Full MiniPlayer (54pt) + Full 4-Tab Liquid Glass Dock (56pt)
//   * Scrolling down: Morphs into a single streamlined row:
//     [ Active Tab Circle Button ]  [ Compact MiniPlayer ]  [ Search Circle Button ]
// - Guaranteed Zero Overflow: All buttons and track titles comfortably nest inside the capsule.

public enum AmyMobileTab: Int, CaseIterable, Identifiable {
    case wave = 0
    case trends = 1
    case search = 2
    case collection = 3

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .wave: return "Моя волна"
        case .trends: return "Чарты"
        case .search: return "Поиск"
        case .collection: return "Коллекция"
        }
    }

    public var systemIcon: String {
        switch self {
        case .wave: return "waveform.path.ecg"
        case .trends: return "flame.fill"
        case .search: return "magnifyingglass"
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
    @State private var isScrolledDown: Bool = false

    @Namespace private var glassNamespace

    public init(player: AudioPlayerManager = .shared) {
        self.player = player
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            appleNativeLiquidGlassTabView
        } else {
            legacyLiquidGlassTabView
        }
    }

    // MARK: - Authentic Apple Liquid Glass TabView (iOS 26+ / WWDC 2025 Session 323)
    @available(iOS 26.0, *)
    @ViewBuilder
    private var appleNativeLiquidGlassTabView: some View {
        TabView(selection: $activeTab) {
            Tab(AmyMobileTab.wave.label, systemImage: AmyMobileTab.wave.systemIcon, value: AmyMobileTab.wave) {
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
            }

            Tab(AmyMobileTab.trends.label, systemImage: AmyMobileTab.trends.systemIcon, value: AmyMobileTab.trends) {
                TrendsChartsView(
                    player: player,
                    onOpenArtist: { id in selectedArtistId = id },
                    onOpenSettings: { isSettingsOpen = true }
                )
            }

            Tab(AmyMobileTab.search.label, systemImage: AmyMobileTab.search.systemIcon, value: AmyMobileTab.search, role: .search) {
                SearchView(
                    player: player,
                    onOpenArtist: { id in selectedArtistId = id },
                    onOpenRelease: { rel in selectedRelease = rel },
                    onOpenSettings: { isSettingsOpen = true }
                )
            }

            Tab(AmyMobileTab.collection.label, systemImage: AmyMobileTab.collection.systemIcon, value: AmyMobileTab.collection) {
                CollectionView(
                    player: player,
                    onOpenArtist: { id in selectedArtistId = id },
                    onOpenRelease: { rel in selectedRelease = rel },
                    onOpenSettings: { isSettingsOpen = true }
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NativeAppleLiquidGlassAccessory(
                player: player,
                onOpenFull: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isFullPlayerOpen = true
                    }
                }
            )
        }
        .preferredColorScheme(.dark)
        .modifier(RootSheetsModifier(
            player: player,
            isFullPlayerOpen: $isFullPlayerOpen,
            isEqualizerOpen: $isEqualizerOpen,
            isQueueSheetOpen: $isQueueSheetOpen,
            isSettingsOpen: $isSettingsOpen,
            selectedArtistId: $selectedArtistId,
            selectedRelease: $selectedRelease
        ))
    }

    // MARK: - Legacy Fallback TabView (iOS < 26.0)
    private var legacyLiquidGlassTabView: some View {
        let themeAccent = Color(hex: player.settings.themePreset.primaryHex)

        return ZStack(alignment: .bottom) {
            Color.amyBackground.ignoresSafeArea()

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

                case .search:
                    SearchView(
                        player: player,
                        onOpenArtist: { id in selectedArtistId = id },
                        onOpenRelease: { rel in selectedRelease = rel },
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
                VStack(spacing: 8) {
                    PhoneLiquidGlassMiniPlayer(
                        player: player,
                        glassNamespace: glassNamespace,
                        isCompact: false,
                        onOpenFull: { isFullPlayerOpen = true }
                    )

                    PhoneFloatingNavDock(
                        activeTab: $activeTab,
                        accentColor: themeAccent
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .preferredColorScheme(.dark)
        .modifier(RootSheetsModifier(
            player: player,
            isFullPlayerOpen: $isFullPlayerOpen,
            isEqualizerOpen: $isEqualizerOpen,
            isQueueSheetOpen: $isQueueSheetOpen,
            isSettingsOpen: $isSettingsOpen,
            selectedArtistId: $selectedArtistId,
            selectedRelease: $selectedRelease
        ))
    }
}

// MARK: - Root Sheets & Overlays Modifier
public struct RootSheetsModifier: ViewModifier {
    @Bindable var player: AudioPlayerManager
    @Binding var isFullPlayerOpen: Bool
    @Binding var isEqualizerOpen: Bool
    @Binding var isQueueSheetOpen: Bool
    @Binding var isSettingsOpen: Bool
    @Binding var selectedArtistId: String?
    @Binding var selectedRelease: ReleaseItem?

    public func body(content: Content) -> some View {
        content
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

// MARK: - Authentic Native Apple Liquid Glass Bottom Accessory (iOS 26+ WWDC 2025)
// - Seamlessly responds to @Environment(\.tabViewBottomAccessoryPlacement)
// - In .expanded mode: 52pt height, full album art, title, artist, like button, prominent play button
// - In .inline mode (minimized on scroll down): 44pt height, automatically sits between leading active tab and trailing search tab
// - Guaranteed 100% inside capsule bounds with zero button overflow!
@available(iOS 26.0, *)
public struct NativeAppleLiquidGlassAccessory: View {
    @Bindable var player: AudioPlayerManager
    var onOpenFull: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement: TabViewBottomAccessoryPlacement?
    @State private var dragXOffset: CGFloat = 0

    public var body: some View {
        let isInline = placement == .inline
        let track = player.currentTrack
        let hasTrack = track != nil
        let palette = track?.palette ?? .defaultPalette
        let paletteColor = Color(hex: palette.line)

        let coverSize: CGFloat = isInline ? 32 : 40
        let height: CGFloat = isInline ? 44 : 52
        let playBtnSize: CGFloat = isInline ? 32 : 36
        let likeBtnSize: CGFloat = 30

        HStack(spacing: isInline ? 6 : 8) {
            // Track Info & Cover (Tap opens FullPlayer)
            HStack(spacing: 8) {
                // Cover Art
                AsyncImage(url: URL(string: track?.coverUrl ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color(hex: "#222226")
                        Image(systemName: "music.note")
                            .font(.system(size: isInline ? 12 : 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: coverSize, height: coverSize)
                .clipShape(RoundedRectangle(cornerRadius: isInline ? 8 : 10, style: .continuous))

                // Title & Artist
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasTrack ? (track?.title ?? "Без названия") : "Нет трека")
                        .font(.system(size: isInline ? 12.5 : 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(hasTrack ? (track?.artist ?? "Неизвестный артист") : "Нажмите для воспроизведения")
                        .font(.system(size: isInline ? 10.5 : 11.5, weight: .medium))
                        .foregroundStyle(Color(hex: "#A1A1AA"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: dragXOffset)
            .onTapGesture {
                onOpenFull()
            }

            // Like Button (shown in expanded mode to maximize space in inline mode)
            if !isInline, let track {
                let isLiked = player.isLiked(track)
                Button {
                    player.toggleLike(track)
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isLiked ? Color(hex: "#FF3B30") : .white.opacity(0.82))
                        .frame(width: likeBtnSize, height: likeBtnSize)
                }
                .buttonStyle(AppleLiquidGlassButtonStyle(
                    shape: Circle(),
                    tintColor: isLiked ? Color(hex: "#FF3B30").opacity(0.28) : nil
                ))
            }

            // Play / Pause Button
            Button {
                if hasTrack {
                    player.togglePlay()
                } else {
                    onOpenFull()
                }
            } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView()
                            .tint(Color(hex: "#0B0B0D"))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isInline ? 12 : 14, weight: .black))
                            .foregroundStyle(Color(hex: "#0B0B0D"))
                            .offset(x: player.isPlaying ? 0 : 1.0)
                    }
                }
                .frame(width: playBtnSize, height: playBtnSize)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(
                shape: Circle(),
                tintColor: .white,
                isFilledAccent: true,
                scaleOnPress: 0.92
            ))
        }
        .padding(.leading, isInline ? 6 : 10)
        .padding(.trailing, isInline ? 6 : 10)
        .padding(.vertical, 2)
        .frame(height: height)
        .contentShape(Capsule())
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
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
                    if abs(dx) >= 25 && abs(dx) > abs(dy) * 0.7 && hasTrack {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if dx > 0 { player.previous() } else { player.next() }
                    } else if dy < -30 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenFull()
                    }
                }
        )
    }
}

// MARK: - Phone Liquid Glass Mini-Player with Exact Inner Bounds
// - Full mode: height 54pt, capsule shape, padding leading 7, trailing 11
// - Compact mode: height 48pt, capsule shape, padding leading 6, trailing 9
// - Play button & Heart button nest strictly within the inner glass boundaries.

public struct PhoneLiquidGlassMiniPlayer: View {
    @Bindable var player: AudioPlayerManager
    var glassNamespace: Namespace.ID
    var isCompact: Bool = false
    var onOpenFull: () -> Void

    @State private var dragXOffset: CGFloat = 0

    public var body: some View {
        let track = player.currentTrack
        let hasTrack = track != nil
        let palette = track?.palette ?? .defaultPalette
        let progress = player.duration > 0 ? min(1.0, max(0.0, player.currentTime / player.duration)) : 0

        let coverSize: CGFloat = isCompact ? 36 : 40
        let height: CGFloat = isCompact ? 48 : 54
        let playBtnSize: CGFloat = isCompact ? 34 : 38
        let likeBtnSize: CGFloat = isCompact ? 30 : 32

        HStack(spacing: isCompact ? 7 : 9) {
            // Track Info & Cover (Tap opens FullPlayer)
            HStack(spacing: 8) {
                // Cover Art
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
                            .font(.system(size: isCompact ? 13 : 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: coverSize, height: coverSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Title & Artist
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasTrack ? (track?.title ?? "Без названия") : "Нет трека")
                        .font(.system(size: isCompact ? 13 : 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(hasTrack ? (track?.artist ?? "Неизвестный артист") : "Нажмите для воспроизведения")
                        .font(.system(size: isCompact ? 11 : 11.5, weight: .medium))
                        .foregroundStyle(Color(hex: "#A1A1AA"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: dragXOffset)
            .onTapGesture {
                onOpenFull()
            }

            // Like Button
            if let track {
                let isLiked = player.isLiked(track)
                Button {
                    player.toggleLike(track)
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                        .foregroundStyle(isLiked ? Color(hex: "#FF3B30") : .white.opacity(0.82))
                        .frame(width: likeBtnSize, height: likeBtnSize)
                }
                .buttonStyle(AppleLiquidGlassButtonStyle(
                    shape: Circle(),
                    tintColor: isLiked ? Color(hex: "#FF3B30").opacity(0.28) : nil
                ))
            }

            // Play / Pause Button (Strictly nested inside right curve)
            Button {
                if hasTrack {
                    player.togglePlay()
                } else {
                    onOpenFull()
                }
            } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView()
                            .tint(Color(hex: "#0B0B0D"))
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isCompact ? 13 : 15, weight: .black))
                            .foregroundStyle(Color(hex: "#0B0B0D"))
                            .offset(x: player.isPlaying ? 0 : 1.2)
                    }
                }
                .frame(width: playBtnSize, height: playBtnSize)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(
                shape: Circle(),
                tintColor: .white,
                isFilledAccent: true,
                scaleOnPress: 0.92
            ))
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(height: height)
        .amyLiquidGlass(
            in: Capsule(),
            tint: nil,
            tintOpacity: 0,
            interactive: true
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.38), radius: 14, y: 6)
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
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

                    if abs(dx) >= 25 && abs(dx) > abs(dy) * 0.7 && hasTrack {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if dx > 0 {
                            player.previous()
                        } else {
                            player.next()
                        }
                    } else if dy < -30 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenFull()
                    }
                }
        )
    }
}

// MARK: - 4-Tab Pure Apple Liquid Glass Floating Nav Dock
// - 4 Dynamic slots with fluid liquid glass droplet tracking & drag stretching
// - Perfectly centered icons & labels across all iPhone widths

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
            let maxIdx = AmyMobileTab.allCases.count - 1

            // Active Tab Center X
            let activeIndex = CGFloat(activeTab.rawValue)
            let idleCenterX = slotW * (activeIndex + 0.5)

            // Droplet Center X
            let dropletCenterX = isHoldingDroplet
                ? min(max(slotW * 0.45, dragX), totalW - slotW * 0.45)
                : idleCenterX

            // Elastic horizontal expansion during drag
            let stretchW = isHoldingDroplet ? min(20, abs(dragOffset) * 0.20) : 0
            let dropletW = slotW * 0.88 + stretchW
            let dropletH = isHoldingDroplet ? totalH + 6 : totalH - 12

            ZStack {
                // Background Liquid Glass Droplet ("Капля")
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule().fill(Color.white.opacity(isHoldingDroplet ? 0.22 : 0.14))
                        }

                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHoldingDroplet ? 0.50 : 0.32),
                                    Color.white.opacity(isHoldingDroplet ? 0.14 : 0.08),
                                    Color.white.opacity(isHoldingDroplet ? 0.28 : 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                }
                .frame(width: dropletW, height: dropletH)
                .shadow(color: .white.opacity(isHoldingDroplet ? 0.16 : 0.05), radius: 8, y: 2)
                .position(x: dropletCenterX, y: totalH / 2)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.68), value: dropletCenterX)
                .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isHoldingDroplet)
                .allowsHitTesting(false)

                // 4 Tabs: Dynamic slot width guarantees 100% dead-center icon and text alignment
                HStack(spacing: 0) {
                    ForEach(AmyMobileTab.allCases) { tab in
                        let isCurrent = (isHoldingDroplet ? (hoveredTab == tab) : (activeTab == tab))

                        VStack(spacing: 2.5) {
                            Image(systemName: tab.systemIcon)
                                .font(.system(size: 19, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? .white : .white.opacity(isHoldingDroplet ? 0.40 : 0.60))
                                .scaleEffect(isCurrent ? (isHoldingDroplet ? 1.15 : 1.05) : 1.0)

                            Text(tab.label)
                                .font(.system(size: 10, weight: isCurrent ? .bold : .medium))
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

                        let index = min(maxIdx, max(0, Int(floor(x / slotW))))
                        if let tab = AmyMobileTab(rawValue: index), hoveredTab != tab {
                            hoveredTab = tab
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { val in
                        let finalIndex = min(maxIdx, max(0, Int(floor(val.location.x / slotW))))
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
        .frame(height: 56)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(Color(hex: "#121216").opacity(0.55))
                }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
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
