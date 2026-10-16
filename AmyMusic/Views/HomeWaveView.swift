import SwiftUI

// MARK: - Phone-First Home "Моя волна" View with Embedded Search Slot inside .home-hero
// Exact Port of src/components/HomeView.jsx, .mobile-wave-search-slot in src/main.css & WaveView.jsx

public struct HomeWaveView: View {
    @Bindable var player: AudioPlayerManager
    var triggerSearchFocus: Binding<Bool>? = nil
    var onOpenFullPlayer: () -> Void
    var onOpenArtist: (String) -> Void
    var onOpenRelease: (ReleaseItem) -> Void
    var onOpenSettings: () -> Void
    var onNavigateCollection: () -> Void

    public init(
        player: AudioPlayerManager,
        triggerSearchFocus: Binding<Bool>? = nil,
        onOpenFullPlayer: @escaping () -> Void,
        onOpenArtist: @escaping (String) -> Void,
        onOpenRelease: @escaping (ReleaseItem) -> Void,
        onOpenSettings: @escaping () -> Void,
        onNavigateCollection: @escaping () -> Void
    ) {
        self.player = player
        self.triggerSearchFocus = triggerSearchFocus
        self.onOpenFullPlayer = onOpenFullPlayer
        self.onOpenArtist = onOpenArtist
        self.onOpenRelease = onOpenRelease
        self.onOpenSettings = onOpenSettings
        self.onNavigateCollection = onNavigateCollection
    }

    @State private var isWaveSeedModalOpen: Bool = false
    @State private var isHistoryDrawerOpen: Bool = false
    @State private var refreshRotation: Double = 0
    @State private var isRefreshingWave: Bool = false

    public var body: some View {
        let currentOrLast = player.currentTrack ?? player.playHistory.first ?? player.forYouTracks.first
        let palette = currentOrLast?.palette ?? .defaultPalette

        ZStack {
            Color.amyBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Phone Hero Banner (.home-hero: 280pt height + embedded .mobile-wave-search-slot at top)
                    PhoneHomeHeroWithEmbeddedSearch(
                        player: player,
                        heroTrack: currentOrLast,
                        palette: palette,
                        triggerSearchFocus: triggerSearchFocus,
                        onConfigureSeeds: { isWaveSeedModalOpen = true },
                        onStartWave: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if player.isPlaying {
                                player.togglePlay()
                            } else {
                                // Активируем поиск по Моей волне
                                Task {
                                    await player.startPersonalWave()
                                }
                            }
                        },
                        onOpenSettings: onOpenSettings,
                        onOpenArtist: onOpenArtist,
                        onOpenRelease: onOpenRelease
                    )

                        // Active Wave Seed Chips Row
                        if !player.waveSeeds.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(player.waveSeeds.prefix(6)) { seed in
                                        HStack(spacing: 6) {
                                            if let avatar = seed.avatarUrl, let url = URL(string: avatar) {
                                                AsyncImage(url: url) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    Color.white.opacity(0.12)
                                                }
                                                .frame(width: 20, height: 20)
                                                .clipShape(Circle())
                                            }
                                            Text(seed.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.9))

                                            Button {
                                                player.waveSeeds.removeAll { $0.id == seed.id }
                                                player.persistState()
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .amyLiquidGlass(in: Capsule(), tint: nil, tintOpacity: 0)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // 2-Card Grid: "История" & "Любимые треки" with <CoverMosaic> (h-[80px] rounded-[18px])
                        HStack(spacing: 12) {
                            CoverMosaicFeatureCard(
                                title: "История",
                                subtitle: "\(player.playHistory.count) треков",
                                covers: Array(player.playHistory.prefix(5).compactMap(\.coverUrl)),
                                icon: "clock.arrow.circlepath"
                            ) {
                                isHistoryDrawerOpen = true
                            }

                            CoverMosaicFeatureCard(
                                title: "Любимые треки",
                                subtitle: "\(player.likedTracks.count) в коллекции",
                                covers: Array(player.likedTracks.prefix(5).compactMap(\.coverUrl)),
                                icon: "heart.fill"
                            ) {
                                onNavigateCollection()
                            }
                        }
                        .padding(.horizontal, 16)

                        // "Для вас" Personalized Carousel (140pt square cards)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Для вас")
                                        .font(.system(size: 22, weight: .black))
                                        .foregroundStyle(.white)
                                    Text("Подобрано алгоритмом Моей волны")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                        refreshRotation += 360
                                        isRefreshingWave = true
                                    }
                                    Task {
                                        await player.loadInitialRecommendations(forceFresh: true)
                                        isRefreshingWave = false
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .rotationEffect(.degrees(refreshRotation))
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                                .disabled(isRefreshingWave)
                            }
                            .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(player.forYouTracks.prefix(20)) { track in
                                        ForYouTrackSquareCard(
                                            track: track,
                                            isCurrent: player.currentTrack?.id == track.id,
                                            isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                                            player: player,
                                            onTap: {
                                                player.playTrack(track, in: player.forYouTracks)
                                            },
                                            onOpenArtist: onOpenArtist
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Mobile bottom padding for floating mini-player (64pt) + dock (64pt) + safe-bottom
                        Spacer(minLength: 184)
                    }
                }
                .scrollDisabled(true)
                .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(isPresented: $isWaveSeedModalOpen) {
            WaveSeedModalView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isHistoryDrawerOpen) {
            PlayHistorySheetView(player: player, onOpenArtist: onOpenArtist)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Phone Hero Banner (.home-hero: 280pt height, 124x124pt cover, .mobile-wave-search-slot at top)

private struct PhoneHomeHeroWithEmbeddedSearch: View {
    @Bindable var player: AudioPlayerManager
    var heroTrack: Track?
    var palette: TrackPalette
    var triggerSearchFocus: Binding<Bool>? = nil
    var onConfigureSeeds: () -> Void
    var onStartWave: () -> Void
    var onOpenSettings: () -> Void
    var onOpenArtist: (String) -> Void
    var onOpenRelease: (ReleaseItem) -> Void

    @State private var searchQuery: String = ""
    @State private var selectedFilter: SearchFilterTab = .all
    @State private var trackResults: [Track] = []
    @State private var artistResults: [ArtistRef] = []
    @State private var albumResults: [ReleaseItem] = []
    @State private var playlistResults: [ReleaseItem] = []
    @State private var isSearching: Bool = false
    @FocusState private var isSearchFocused: Bool

    private let trendingQueries = [
        "Kai Angel", "9mice", "Viperr", "OG Buda", "Phonk", "Toxis", "Big Baby Tape", "Shadowraze"
    ]

    private var isSearchExpanded: Bool {
        isSearchFocused || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCompactScreen: Bool {
        UIScreen.main.bounds.width < 380
    }
    private var isLargeScreen: Bool {
        UIScreen.main.bounds.width > 410
    }
    private var coverDimension: CGFloat {
        isCompactScreen ? 104 : (isLargeScreen ? 124 : 114)
    }
    private var titleFontSize: CGFloat {
        isCompactScreen ? 30 : (isLargeScreen ? 38 : 34)
    }
    private var playButtonSize: CGFloat {
        isCompactScreen ? 50 : 56
    }
    private var topSafeInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return max(window?.safeAreaInsets.top ?? 48, 48)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Foreground Hero Structure: Search at top, Cover + Wave + Play at bottom
            VStack(spacing: 12) {
                    // Top Embedded Liquid Glass Search Slot
                    HStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.70))

                            TextField("Трек, артист, альбом или жанр...", text: $searchQuery)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .focused($isSearchFocused)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                                .onSubmit {
                                    runEmbeddedSearch()
                                }

                            if isSearching {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                    trackResults = []
                                    artistResults = []
                                    albumResults = []
                                    playlistResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .amyLiquidGlass(in: Capsule(), interactive: true)

                        if isSearchExpanded {
                            Button("Отмена") {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    isSearchFocused = false
                                    searchQuery = ""
                                    trackResults = []
                                    artistResults = []
                                    albumResults = []
                                    playlistResults = []
                                }
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            // Compact Profile / Settings Avatar Button
                            Button(action: onOpenSettings) {
                                ProfileAvatarView(
                                    avatarDataUrl: player.settings.avatarDataUrl,
                                    displayName: player.settings.displayName,
                                    size: 42,
                                    primaryHex: player.settings.themePreset.primaryHex,
                                    secondaryHex: player.settings.themePreset.secondaryHex
                                )
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, topSafeInset + 6)
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSearchExpanded)

                    // Search Filter Chips Lane when focused
                    if isSearchExpanded {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SearchFilterTab.allCases) { tab in
                                    let active = selectedFilter == tab
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                            selectedFilter = tab
                                        }
                                    } label: {
                                        Text(tab.rawValue)
                                            .font(.system(size: 13, weight: active ? .bold : .medium))
                                            .foregroundStyle(active ? .black : .white.opacity(0.78))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background {
                                                if active {
                                                    Capsule().fill(.white)
                                                } else {
                                                    Capsule().fill(.white.opacity(0.08))
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Trending Queries when search query is empty
                    if isSearchExpanded && searchQuery.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Популярные запросы")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.horizontal, 14)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(trendingQueries, id: \.self) { query in
                                        Button {
                                            searchQuery = query
                                            runEmbeddedSearch()
                                        } label: {
                                            Text(query)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.white.opacity(0.08), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        .padding(.top, 2)
                        .transition(.opacity)
                    }

                    Spacer(minLength: 4)

                    // Hero Content Row: Cover + Text + Play
                    HStack(alignment: .bottom, spacing: 0) {
                        // 1. Cover Square
                        AsyncImage(url: URL(string: heroTrack?.coverUrl ?? "")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            LinearGradient(
                                colors: [Color(hex: palette.line), Color(hex: palette.base)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .frame(width: coverDimension, height: coverDimension)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)

                        // 2. Title & Seeds Counter & НАСТРОИТЬ button
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Моя\nволна")
                                .font(.system(size: titleFontSize, weight: .black))
                                .tracking(-1.2)
                                .lineSpacing(-4)
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 4)

                            VStack(alignment: .leading, spacing: 4) {
                                if player.isLoading {
                                    HStack(spacing: 5) {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.65)
                                        Text("Поиск по волне...")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                } else {
                                    Text("\(player.waveSeeds.count) источников")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                Button(action: onConfigureSeeds) {
                                    Text("НАСТРОИТЬ")
                                        .font(.system(size: 10, weight: .black))
                                        .tracking(0.6)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: nil))
                            }
                        }
                        .frame(height: coverDimension, alignment: .bottomLeading)
                        .padding(.leading, isCompactScreen ? 10 : 14)

                        Spacer(minLength: 6)

                        // 3. Main Play/Pause Button
                        Button(action: onStartWave) {
                            ZStack {
                                if player.isLoading {
                                    ProgressView()
                                        .tint(Color(hex: "#0B0B0D"))
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: playButtonSize * 0.38, weight: .black))
                                        .foregroundStyle(.black)
                                        .offset(x: player.isPlaying ? 0 : 2)
                                }
                            }
                            .frame(width: playButtonSize, height: playButtonSize)
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: .white, isFilledAccent: true, scaleOnPress: 0.92))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hex: "#1a0030"),
                            Color(hex: palette.base),
                            .black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    if let cover = heroTrack?.coverUrl, let url = URL(string: cover) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                        .blur(radius: 55)
                        .opacity(0.42)
                    }

                    LinearGradient(
                        colors: [.black.opacity(0.25), .clear, .black.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .top)
            }

            // Expandable Embedded Search Results (.mobile-wave-search-panel .search-panel__results: max-height 52vh)
            if isSearchExpanded && (!trackResults.isEmpty || !artistResults.isEmpty || !albumResults.isEmpty || !playlistResults.isEmpty) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        if (selectedFilter == .all || selectedFilter == .artists) && !artistResults.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(artistResults) { artist in
                                        Button {
                                            isSearchFocused = false
                                            onOpenArtist(artist.id)
                                        } label: {
                                            VStack(spacing: 6) {
                                                AsyncImage(url: URL(string: artist.avatarUrl ?? "")) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    Circle().fill(Color.white.opacity(0.12))
                                                }
                                                .frame(width: 72, height: 72)
                                                .clipShape(Circle())

                                                Text(artist.name)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 80)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }

                        if (selectedFilter == .all || selectedFilter == .tracks) && !trackResults.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(trackResults.prefix(12)) { track in
                                    TrackRowItemView(
                                        track: track,
                                        player: player,
                                        onTap: {
                                            isSearchFocused = false
                                            player.playTrack(track, in: trackResults)
                                        },
                                        onOpenArtist: onOpenArtist
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                        }

                        if (selectedFilter == .all || selectedFilter == .albums) && !albumResults.isEmpty {
                            ReleaseHorizontalSection(title: "Альбомы", releases: albumResults, onSelect: onOpenRelease)
                        }

                        if (selectedFilter == .all || selectedFilter == .playlists) && !playlistResults.isEmpty {
                            ReleaseHorizontalSection(title: "Плейлисты", releases: playlistResults, onSelect: onOpenRelease)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: 440)
                .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            let q = newValue.trimmingCharacters(in: .whitespaces)
            if q.count >= 2 {
                runEmbeddedSearch()
            } else if q.isEmpty {
                trackResults = []
                artistResults = []
                albumResults = []
                playlistResults = []
            }
        }
        .onChange(of: triggerSearchFocus?.wrappedValue) { _, shouldFocus in
            if shouldFocus == true {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isSearchFocused = true
                }
                triggerSearchFocus?.wrappedValue = false
            }
        }
    }

    private func runEmbeddedSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            async let t = SoundCloudService.shared.searchTracks(query: q, limit: 15)
            async let a = SoundCloudService.shared.searchArtists(query: q, limit: 10)
            async let al = SoundCloudService.shared.searchReleases(query: q, albumsOnly: true, limit: 8)
            async let pl = SoundCloudService.shared.searchReleases(query: q, albumsOnly: false, limit: 8)

            let (tracks, artists, albums, playlists) = await (t, a, al, pl)
            self.trackResults = tracks
            self.artistResults = artists
            self.albumResults = albums
            self.playlistResults = playlists
            self.isSearching = false
        }
    }
}

// MARK: - Cover Mosaic Feature Card (Port of <CoverMosaic> in HomeView.jsx)

private struct CoverMosaicFeatureCard: View {
    var title: String
    var subtitle: String
    var covers: [String]
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(covers.prefix(5).enumerated()), id: \.offset) { _, urlStr in
                            AsyncImage(url: URL(string: urlStr)) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.12)
                            }
                            .frame(width: geo.size.width / CGFloat(max(1, covers.prefix(5).count)), height: geo.size.height)
                            .clipped()
                        }
                    }
                }

                LinearGradient(
                    colors: [.black.opacity(0.92), .black.opacity(0.65), .black.opacity(0.35)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "Для вас" Square Track Card (140pt wide matching mobile HomeView.jsx)

private struct ForYouTrackSquareCard: View {
    var track: Track
    var isCurrent: Bool
    var isPlaying: Bool
    @Bindable var player: AudioPlayerManager
    var onTap: () -> Void
    var onOpenArtist: (String) -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(
                            colors: [Color(hex: track.palette.line), Color(hex: track.palette.base)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.black)
                    }
                    .padding(10)
                }

                Text(track.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
        .contextMenu {
            TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
        } preview: {
            TrackContextMenuPreviewCard(track: track)
        }
    }
}

// MARK: - WaveSeedModalView (Port of src/components/WaveSeedModal.jsx)

public struct WaveSeedModalView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var artists: [ArtistRef] = []

    private let defaultPopularArtists: [ArtistRef] = [
        ArtistRef(id: "kai_angel", name: "Kai Angel"),
        ArtistRef(id: "9mice", name: "9mice"),
        ArtistRef(id: "pharaoh", name: "PHARAOH"),
        ArtistRef(id: "platina", name: "Платина"),
        ArtistRef(id: "madk1d", name: "madk1d"),
        ArtistRef(id: "saluki", name: "SALUKI"),
        ArtistRef(id: "friendly_thug", name: "FRIENDLY THUG 52 NGG"),
        ArtistRef(id: "dora", name: "дора"),
        ArtistRef(id: "playboi_carti", name: "Playboi Carti")
    ]

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Кого будем слушать?", text: $query)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .onSubmit {
                                performArtistSearch()
                            }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                artists = defaultPopularArtists
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(artists.isEmpty ? defaultPopularArtists : artists) { artist in
                                let isSelected = player.waveSeeds.contains(where: { $0.name.lowercased() == artist.name.lowercased() })
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    if isSelected {
                                        player.waveSeeds.removeAll { $0.name.lowercased() == artist.name.lowercased() }
                                    } else {
                                        player.waveSeeds.append(WaveSeed(id: artist.id, name: artist.name, avatarUrl: artist.avatarUrl))
                                    }
                                    player.persistState()
                                } label: {
                                    VStack(spacing: 10) {
                                        ZStack(alignment: .bottomTrailing) {
                                            AsyncImage(url: URL(string: artist.avatarUrl ?? "")) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                ZStack {
                                                    Circle().fill(Color.white.opacity(0.12))
                                                    Text(String(artist.name.prefix(1)).uppercased())
                                                        .font(.system(size: 24, weight: .black))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(isSelected ? .white : .white.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
                                            }

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(isSelected ? .white : .white)
                                                .background(Circle().fill(.black))
                                        }

                                        Text(artist.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity)
                                    .amyLiquidGlass(
                                        in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                                        tint: isSelected ? Color.white.opacity(0.25) : nil,
                                        tintOpacity: isSelected ? 0.35 : 0.1
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Настройка волны")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task { await player.loadInitialRecommendations() }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onChange(of: query) { _, newValue in
                guard newValue.count >= 2 else { return }
                performArtistSearch()
            }
        }
    }

    private func performArtistSearch() {
        let q = query
        Task {
            let results = await SoundCloudService.shared.searchArtists(query: q, limit: 20)
            self.artists = results
        }
    }
}

// MARK: - PlayHistorySheetView (Slide-Out History Drawer in HomeView.jsx)

public struct PlayHistorySheetView: View {
    @Bindable var player: AudioPlayerManager
    var onOpenArtist: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                if player.playHistory.isEmpty {
                    ContentUnavailableView(
                        "История пуста",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Прослушанные треки появятся здесь")
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(player.playHistory) { track in
                                TrackRowItemView(
                                    track: track,
                                    player: player,
                                    compact: true,
                                    onTap: {
                                        player.playTrack(track, in: player.playHistory)
                                    },
                                    onOpenArtist: onOpenArtist
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("История прослушивания")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !player.playHistory.isEmpty {
                        Button("Очистить", role: .destructive) {
                            player.playHistory.removeAll()
                            player.persistState()
                        }
                    }
                }
            }
        }
    }
}

public enum SearchFilterTab: String, CaseIterable, Identifiable {
    case all = "Все"
    case tracks = "Треки"
    case playlists = "Плейлисты"
    case albums = "Альбомы"
    case artists = "Артисты"

    public var id: String { rawValue }
}
