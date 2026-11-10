import SwiftUI

// MARK: - Offline Music Library View (Dedicated Full Screen / Sheet)
// High-end shadcn & Emil Kowalski inspired layout: crisp borders, subtle glass, tactile buttons

public enum OfflineLibraryTab: String, CaseIterable, Identifiable {
    case tracks = "Треки"
    case albums = "Альбомы"
    case playlists = "Плейлисты"
    case artists = "Артисты"

    public var id: String { rawValue }
}

public struct OfflineLibraryView: View {
    @Bindable var player: AudioPlayerManager
    var onOpenArtist: (String) -> Void
    var onOpenRelease: (ReleaseItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var activeTab: OfflineLibraryTab = .tracks
    @State private var searchQuery: String = ""
    @State private var isClearAllAlertPresented: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var selectedArtistSummary: DownloadedArtistSummary? = nil
    @State private var selectedReleaseLocally: ReleaseItem? = nil

    private var offlineManager: OfflineMusicManager {
        OfflineMusicManager.shared
    }

    private var filteredTracks: [Track] {
        let all = offlineManager.downloadedTracks
        guard !searchQuery.isEmpty else { return all }
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    private var filteredAlbums: [ReleaseItem] {
        let all = offlineManager.downloadedAlbums
        guard !searchQuery.isEmpty else { return all }
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    private var filteredPlaylists: [ReleaseItem] {
        let all = offlineManager.downloadedPlaylists
        guard !searchQuery.isEmpty else { return all }
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    private var filteredArtists: [DownloadedArtistSummary] {
        let all = offlineManager.downloadedArtists
        guard !searchQuery.isEmpty else { return all }
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter {
            $0.name.lowercased().contains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header: Title, Storage Stats & Clear All Button
                        headerSection

                        // Active Downloading Progress Banner (if any item is downloading)
                        if let title = offlineManager.currentDownloadTitle {
                            downloadingBanner(title: title, subtitle: offlineManager.currentDownloadSubtitle)
                        }

                        // Playback Action Controls: "▶ Слушать всё" & "🔀 Перемешать"
                        if !offlineManager.downloadedTracks.isEmpty {
                            playbackActionsBar
                        }

                        // Search Field (Instant filter)
                        if !offlineManager.downloadedTracks.isEmpty {
                            searchBar
                        }

                        // Segmented Pill Tabs (shadcn/ui style with counts)
                        segmentedTabs

                        // Tab Content
                        tabContent

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
            }
            .alert("Удалить всю скачанную музыку?", isPresented: $isClearAllAlertPresented) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить всё", role: .destructive) {
                    offlineManager.deleteAll()
                }
            } message: {
                Text("Все скачанные треки, альбомы и плейлисты будут удалены с устройства.")
            }
            .sheet(item: $selectedReleaseLocally) { rel in
                AlbumOrPlaylistSheetView(
                    release: rel,
                    player: player,
                    onOpenArtist: onOpenArtist,
                    onClose: { selectedReleaseLocally = nil }
                )
            }
            .sheet(item: $selectedArtistSummary) { summary in
                OfflineArtistTracksSheetView(
                    summary: summary,
                    player: player,
                    onOpenArtist: onOpenArtist,
                    onClose: { selectedArtistSummary = nil }
                )
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Скачанная музыка")
                        .font(.system(size: 30, weight: .black))
                        .tracking(-0.8)
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Text("\(offlineManager.downloadedTracks.count) треков")
                        Text("•")
                        Text(offlineManager.totalStorageFormatted)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        isRefreshing = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            await player.refreshAllCachedAndDownloadedTracks()
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text("Обновить")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)

                    if !offlineManager.downloadedTracks.isEmpty {
                        Button(role: .destructive) {
                            isClearAllAlertPresented = true
                        } label: {
                            Text("Очистить")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "#FF453A"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color(hex: "#FF453A").opacity(0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color(hex: "#FF453A").opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Active Download Banner

    private func downloadingBanner(title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.9)

            VStack(alignment: .leading, spacing: 2) {
                Text("Скачивание: \(title)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Playback Actions Bar

    private var playbackActionsBar: some View {
        HStack(spacing: 12) {
            Button {
                if let first = offlineManager.downloadedTracks.first {
                    player.playTrack(first, in: offlineManager.downloadedTracks)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .black))
                    Text("Слушать всё")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))

            Button {
                var shuffled = offlineManager.downloadedTracks
                shuffled.shuffle()
                if let first = shuffled.first {
                    player.playTrack(first, in: shuffled)
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))

            TextField("Поиск среди скачанных...", text: $searchQuery)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.40))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Segmented Tabs

    private var segmentedTabs: some View {
        HStack(spacing: 6) {
            ForEach(OfflineLibraryTab.allCases) { tab in
                let isSelected = (activeTab == tab)
                let count: Int = {
                    switch tab {
                    case .tracks: return offlineManager.downloadedTracks.count
                    case .albums: return offlineManager.downloadedAlbums.count
                    case .playlists: return offlineManager.downloadedPlaylists.count
                    case .artists: return offlineManager.downloadedArtists.count
                    }
                }()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        activeTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .tracks:
            tracksList
        case .albums:
            albumsGrid
        case .playlists:
            playlistsGrid
        case .artists:
            artistsList
        }
    }

    // MARK: - Tracks List

    private var tracksList: some View {
        VStack(spacing: 6) {
            if filteredTracks.isEmpty {
                emptyState(
                    title: searchQuery.isEmpty ? "Нет скачанных треков" : "Ничего не найдено",
                    subtitle: searchQuery.isEmpty
                        ? "Скачивайте любимые треки, альбомы и артистов, чтобы слушать музыку без интернета"
                        : "Попробуйте изменить поисковый запрос"
                )
            } else {
                ForEach(filteredTracks) { track in
                    TrackRowItemView(
                        track: track,
                        player: player,
                        onTap: {
                            player.playTrack(track, in: filteredTracks)
                        },
                        onOpenArtist: onOpenArtist
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            offlineManager.deleteTrack(id: track.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Albums Grid

    private var albumsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if filteredAlbums.isEmpty {
                emptyState(
                    title: "Нет скачанных альбомов",
                    subtitle: "Откройте любой альбом и нажмите кнопку со стрелочкой для скачивания"
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(filteredAlbums) { album in
                        Button {
                            selectedReleaseLocally = album
                        } label: {
                            ReleaseSquareCard(release: album) {}
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                offlineManager.deleteRelease(id: album.id)
                            } label: {
                                Label("Удалить из скачанных", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playlists Grid

    private var playlistsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if filteredPlaylists.isEmpty {
                emptyState(
                    title: "Нет скачанных плейлистов",
                    subtitle: "Вы можете скачивать свои плейлисты или подборки целиком для офлайн-режима"
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(filteredPlaylists) { pl in
                        Button {
                            selectedReleaseLocally = pl
                        } label: {
                            ReleaseSquareCard(release: pl) {}
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                offlineManager.deleteRelease(id: pl.id)
                            } label: {
                                Label("Удалить из скачанных", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Artists List

    private var artistsList: some View {
        VStack(spacing: 12) {
            if filteredArtists.isEmpty {
                emptyState(
                    title: "Нет скачанных артистов",
                    subtitle: "На странице любого артиста нажмите «Скачать всё», чтобы сохранить его дискографию"
                )
            } else {
                ForEach(filteredArtists) { artist in
                    Button {
                        selectedArtistSummary = artist
                    } label: {
                        HStack(spacing: 14) {
                            AmyAsyncImage(url: URL(string: artist.avatarUrl ?? "")) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.12))
                                    .overlay(
                                        Text(String(artist.name.prefix(1)).uppercased())
                                            .font(.system(size: 18, weight: .black))
                                            .foregroundStyle(.white)
                                    )
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(artist.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text("\(artist.trackCount) треков скачано")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            offlineManager.deleteArtist(id: artist.id)
                        } label: {
                            Label("Удалить артиста и все его треки", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State View

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 24)

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.top, 16)
    }
}

// MARK: - Offline Artist Tracks Sheet View

public struct OfflineArtistTracksSheetView: View {
    public var summary: DownloadedArtistSummary
    @Bindable var player: AudioPlayerManager
    public var onOpenArtist: (String) -> Void
    public var onClose: () -> Void

    private var artistTracks: [Track] {
        let all = OfflineMusicManager.shared.downloadedTracks
        return all.filter { summary.trackIds.contains($0.id) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        HStack(spacing: 14) {
                            AmyAsyncImage(url: URL(string: summary.avatarUrl ?? "")) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.12))
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.name)
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundStyle(.white)

                                Text("\(artistTracks.count) скачанных треков")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.60))
                            }

                            Spacer()
                        }
                        .padding(.top, 12)

                        // Play All / Shuffle
                        if !artistTracks.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    if let first = artistTracks.first {
                                        player.playTrack(first, in: artistTracks)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                        Text("Слушать")
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))

                                Button {
                                    var s = artistTracks
                                    s.shuffle()
                                    if let first = s.first {
                                        player.playTrack(first, in: s)
                                    }
                                } label: {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                            }
                        }

                        // Tracks
                        LazyVStack(spacing: 6) {
                            ForEach(artistTracks) { track in
                                TrackRowItemView(
                                    track: track,
                                    player: player,
                                    onTap: {
                                        player.playTrack(track, in: artistTracks)
                                    },
                                    onOpenArtist: onOpenArtist
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        onClose()
                    }
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }
}
