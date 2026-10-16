import SwiftUI

// MARK: - Dedicated Phone-First Liquid Glass Search View
// Port of SearchPanel.jsx and mobile search experience with instant live results,
// filter pills, trending chips, track playback, and artist/release sheets.

public struct SearchView: View {
    @Bindable var player: AudioPlayerManager
    var onOpenArtist: (String) -> Void
    var onOpenRelease: (ReleaseItem) -> Void
    var onOpenSettings: () -> Void

    @State private var searchQuery: String = ""
    @State private var selectedFilter: SearchFilterTab = .all
    @State private var isSearching: Bool = false
    @FocusState private var isSearchFocused: Bool

    @State private var trackResults: [Track] = []
    @State private var artistResults: [ArtistRef] = []
    @State private var albumResults: [ReleaseItem] = []
    @State private var playlistResults: [ReleaseItem] = []

    private let trendingQueries = [
        "Kai Angel", "9mice", "Viperr", "OG Buda", "Phonk", "Toxis", "Big Baby Tape", "Shadowraze"
    ]

    public init(
        player: AudioPlayerManager,
        onOpenArtist: @escaping (String) -> Void,
        onOpenRelease: @escaping (ReleaseItem) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.player = player
        self.onOpenArtist = onOpenArtist
        self.onOpenRelease = onOpenRelease
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Liquid Glass Search Input Bar
                    searchHeaderBar

                    // Search Filter Chips
                    filterChipsRow

                    // Search Content Area
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                                trendingQueriesSection
                            } else if isSearching {
                                loadingIndicator
                            } else if trackResults.isEmpty && artistResults.isEmpty && albumResults.isEmpty && playlistResults.isEmpty {
                                emptyStateView
                            } else {
                                resultsSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 120) // Clearance for bottom dock & miniplayer
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: searchQuery) { _, newValue in
            let q = newValue.trimmingCharacters(in: .whitespaces)
            if q.count >= 2 {
                executeSearch(query: q)
            } else if q.isEmpty {
                clearResults()
            }
        }
    }

    // MARK: - Search Header Bar with Liquid Glass

    private var searchHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.70))

                TextField("Трек, артист, альбом или жанр...", text: $searchQuery)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        executeSearch(query: searchQuery)
                    }

                if isSearching {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        clearResults()
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

            if isSearchFocused {
                Button("Отмена") {
                    isSearchFocused = false
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSearchFocused)
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilterTab.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.78))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule().fill(.white)
                                } else {
                                    Capsule().fill(.white.opacity(0.08))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Trending Queries Section

    private var trendingQueriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Популярные запросы")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            FlowLayout(spacing: 8) {
                ForEach(trendingQueries, id: \.self) { query in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        searchQuery = query
                        executeSearch(query: query)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(query)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            Text("Поиск треков и артистов...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 40)
            Text("Ничего не найдено")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("Попробуйте изменить запрос или поискать другое имя артиста")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        // Tracks
        if (selectedFilter == .all || selectedFilter == .tracks) && !trackResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Треки (\(trackResults.count))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                VStack(spacing: 6) {
                    ForEach(Array(trackResults.enumerated()), id: \.element.id) { index, track in
                        trackRow(track: track, index: index)
                    }
                }
            }
        }

        // Artists
        if (selectedFilter == .all || selectedFilter == .artists) && !artistResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Артисты (\(artistResults.count))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(artistResults) { artist in
                            Button {
                                onOpenArtist(artist.id)
                            } label: {
                                VStack(spacing: 8) {
                                    AsyncImage(url: URL(string: artist.avatarUrl ?? "")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Circle().fill(Color.white.opacity(0.12))
                                    }
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))

                                    Text(artist.name)
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .frame(width: 80)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

        // Albums & Playlists
        if (selectedFilter == .all || selectedFilter == .albums || selectedFilter == .playlists) {
            let combined = (selectedFilter == .albums ? albumResults :
                            (selectedFilter == .playlists ? playlistResults :
                             (albumResults + playlistResults)))

            if !combined.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Релизы и Плейлисты")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    VStack(spacing: 8) {
                        ForEach(combined) { release in
                            Button {
                                onOpenRelease(release)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: release.coverUrl ?? "")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12))
                                    }
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(release.title)
                                            .font(.system(size: 14.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)

                                        Text(release.artist)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                .padding(10)
                                .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Track Row Item

    private func trackRow(track: Track, index: Int) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let isLiked = player.isLiked(track)

        return HStack(spacing: 12) {
            // Cover
            AsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white, lineWidth: 1.5)
                }
            }

            // Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isCurrent ? Color.white : Color.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(1)
            }

            Spacer()

            // Like Button
            Button {
                player.toggleLike(track)
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isLiked ? Color(hex: "#FF3B30") : .white.opacity(0.70))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

            // Play Button
            Button {
                if isCurrent {
                    player.togglePlay()
                } else {
                    player.playTrack(track, in: trackResults)
                }
            } label: {
                Image(systemName: (isCurrent && player.isPlaying) ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: isCurrent ? Color.white.opacity(0.25) : nil))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            player.playTrack(track, in: trackResults)
        }
    }

    // MARK: - Actions

    private func executeSearch(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true

        Task {
            async let t = SoundCloudService.shared.searchTracks(query: q, limit: 20)
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

    private func clearResults() {
        trackResults = []
        artistResults = []
        albumResults = []
        playlistResults = []
        isSearching = false
    }
}

// MARK: - Simple FlowLayout for trending tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height = y + rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
