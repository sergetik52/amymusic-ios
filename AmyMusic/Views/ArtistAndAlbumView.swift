import SwiftUI

// MARK: - Artist Detail View & Album/Playlist Detail View
// Port of src/components/ArtistView.jsx & PlaylistView in CollectionView.jsx

// MARK: - Artist Detail Page View (Full separate page with TabBar and MiniPlayer)

public struct ArtistDetailPageView: View {
    public var artistId: String
    @Bindable var player: AudioPlayerManager
    @Binding var activeTab: AmyMobileTab
    public var onBack: () -> Void
    public var onOpenRelease: (ReleaseItem) -> Void
    public var onOpenFullPlayer: () -> Void
    public var onTriggerSearch: (() -> Void)? = nil

    @State private var profile: ArtistProfile? = nil
    @State private var isLoading: Bool = true
    @State private var showAllTracksSheet: Bool = false
    @State private var pushedRelease: ReleaseItem? = nil

    private var topSafeInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return max(window?.safeAreaInsets.top ?? 48, 48)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.amyBackground.ignoresSafeArea()

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Загрузка артиста...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
            } else if let profile {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        // Top spacing to let back button float directly over hero without obstruction
                        Spacer().frame(height: topSafeInset + 44)
                            // Artist Hero Banner (Adaptive across iPhone 11 to 17 Pro Max)
                            VStack(spacing: 12) {
                                let isCompact = UIScreen.main.bounds.width < 380
                                let avatarDim: CGFloat = isCompact ? 116 : 136

                                AsyncImage(url: URL(string: profile.avatarUrl ?? "")) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color.white.opacity(0.12))
                                }
                                .frame(width: avatarDim, height: avatarDim)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
                                .padding(.top, 16)

                                Text(profile.name)
                                    .font(.system(size: isCompact ? 28 : 32, weight: .black))
                                    .tracking(-0.8)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(2)
                                    .padding(.horizontal, 16)

                                HStack(spacing: 10) {
                                    Text("\(profile.trackCount) треков")
                                    Text("•")
                                    Text("\(profile.followersCount) подписчиков")
                                    if let city = profile.city, !city.isEmpty {
                                        Text("•")
                                        Text(city)
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 16)

                                if let bio = profile.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }

                                // Action Buttons: "▶ Слушать все" & "Подписаться"
                                HStack(spacing: 10) {
                                    Button {
                                        if let first = profile.popularTracks.first {
                                            player.playTrack(first, in: profile.popularTracks)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "play.fill")
                                            Text("Слушать все")
                                        }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, isCompact ? 16 : 22)
                                        .padding(.vertical, 11)
                                    }
                                    .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))

                                    let artistRef = ArtistRef(id: profile.id, name: profile.name, avatarUrl: profile.avatarUrl)
                                    let subscribed = player.isSubscribed(to: artistRef)
                                    Button {
                                        player.toggleArtistSubscription(artistRef)
                                    } label: {
                                        Text(subscribed ? "Вы подписаны" : "Подписаться")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, isCompact ? 14 : 18)
                                            .padding(.vertical, 11)
                                    }
                                    .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: subscribed ? Color.white.opacity(0.25) : nil, tintOpacity: subscribed ? 0.45 : 0.15))
                                }

                                // Genre #tag chips
                                if !profile.tags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(profile.tags, id: \.self) { tag in
                                                Text("#\(tag)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.white.opacity(0.75))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(.white.opacity(0.06), in: Capsule())
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity)
                            .background {
                                ZStack {
                                    AsyncImage(url: URL(string: profile.bannerUrl ?? profile.avatarUrl ?? "")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.white.opacity(0.12)
                                    }
                                    .blur(radius: 36)
                                    .opacity(0.45)

                                    LinearGradient(
                                        colors: [.clear, Color.amyBackground.opacity(0.75), Color.amyBackground],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                                .ignoresSafeArea(edges: .top)
                            }

                            // "Новый релиз" (The single TRULY latest release: single or album)
                            if let latest = profile.latestRelease ?? profile.latestReleases.first {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Новый релиз")
                                            .font(.system(size: 20, weight: .black))
                                            .foregroundStyle(.white)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)

                                    Button {
                                        pushedRelease = latest
                                    } label: {
                                        HStack(spacing: 14) {
                                            AsyncImage(url: URL(string: latest.coverUrl ?? "")) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.white.opacity(0.10)
                                            }
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(latest.kind == .single ? "СИНГЛ" : (latest.kind == .album ? "АЛЬБОМ" : latest.kind.rawValue.uppercased()))
                                                    .font(.system(size: 10, weight: .black))
                                                    .tracking(0.6)
                                                    .foregroundStyle(.white.opacity(0.9))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.white.opacity(0.14), in: Capsule())

                                                Text(latest.title)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)

                                                Text(latest.kind == .single ? "Сингл • 1 трек" : "Альбом • \(latest.trackCount) треков")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.55))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                        .padding(14)
                                        .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                }
                            }

                            // "Популярные треки" (5-row horizontal snap pager)
                            if !profile.popularTracks.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Популярные треки")
                                            .font(.system(size: 20, weight: .black))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        let allCount = profile.allTracks.isEmpty ? profile.popularTracks.count : profile.allTracks.count
                                        Button("Все (\(allCount))") {
                                            showAllTracksSheet = true
                                        }
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .amyLiquidGlass(in: Capsule(), interactive: true)
                                    }
                                    .padding(.horizontal, 16)

                                    let pages = stride(from: 0, to: min(profile.popularTracks.count, 10), by: 5).map {
                                        Array(profile.popularTracks[$0..<min($0 + 5, profile.popularTracks.count)])
                                    }

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(alignment: .top, spacing: 14) {
                                            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                                                VStack(spacing: 6) {
                                                    ForEach(page) { track in
                                                        TrackRowItemView(
                                                            track: track,
                                                            player: player,
                                                            onTap: {
                                                                player.playTrack(track, in: profile.popularTracks)
                                                            },
                                                            onOpenArtist: { _ in }
                                                        )
                                                    }
                                                }
                                                .containerRelativeFrame(.horizontal, count: 1, spacing: 14)
                                            }
                                        }
                                        .scrollTargetLayout()
                                    }
                                    .scrollTargetBehavior(.viewAligned)
                                    .contentMargins(.horizontal, 16, for: .scrollContent)
                                }
                            }

                            // "Альбомы", "Синглы и EP", "Плейлисты"
                            if !profile.albums.isEmpty {
                                ReleaseHorizontalSection(title: "Альбомы", releases: profile.albums, onSelect: { rel in pushedRelease = rel })
                            }
                            if !profile.singles.isEmpty {
                                ReleaseHorizontalSection(title: "Синглы и EP", releases: profile.singles, onSelect: { rel in pushedRelease = rel })
                            }
                            if !profile.playlists.isEmpty {
                                ReleaseHorizontalSection(title: "Плейлисты", releases: profile.playlists, onSelect: { rel in pushedRelease = rel })
                            }

                            // "Похожие артисты"
                            if !profile.relatedArtists.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Похожие артисты")
                                        .font(.system(size: 20, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 16) {
                                            ForEach(profile.relatedArtists) { relArtist in
                                                Button {
                                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                        isLoading = true
                                                    }
                                                    Task {
                                                        let newProfile = await SoundCloudService.shared.fetchArtistProfile(artistId: relArtist.id)
                                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                            self.profile = newProfile
                                                            isLoading = false
                                                        }
                                                    }
                                                } label: {
                                                    VStack(spacing: 8) {
                                                        AsyncImage(url: URL(string: relArtist.avatarUrl ?? "")) { img in
                                                            img.resizable().scaledToFill()
                                                        } placeholder: {
                                                            Circle().fill(Color.white.opacity(0.12))
                                                        }
                                                        .frame(width: 96, height: 96)
                                                        .clipShape(Circle())

                                                        Text(relArtist.name)
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundStyle(.white)
                                                            .lineLimit(1)
                                                    }
                                                    .frame(width: 100)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                        // Space for floating bottom miniplayer + tabbar
                        Spacer(minLength: 160)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    ContentUnavailableView("Артист не найден", systemImage: "person.slash")
                    Spacer()
                }
            }

            // Top Bar: Back Button in top-right corner, prominent and larger
            HStack {
                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onBack()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text("Назад")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Capsule())
                }
                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
            }
            .padding(.horizontal, 16)
            .padding(.top, topSafeInset + 6)
            .zIndex(100)
        }
        .task {
            isLoading = true
            profile = await SoundCloudService.shared.fetchArtistProfile(artistId: artistId)
            isLoading = false
        }
        .sheet(isPresented: $showAllTracksSheet) {
            if let profile {
                AllArtistTracksSheetView(
                    artistName: profile.name,
                    tracks: profile.allTracks.isEmpty ? profile.popularTracks : profile.allTracks,
                    player: player
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// Compatibility wrapper for ArtistDetailSheetView
public struct ArtistDetailSheetView: View {
    public var artistId: String
    @Bindable var player: AudioPlayerManager
    public var onOpenRelease: (ReleaseItem) -> Void
    public var isNested: Bool = false
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ArtistDetailPageView(
            artistId: artistId,
            player: player,
            activeTab: .constant(.wave),
            onBack: { dismiss() },
            onOpenRelease: onOpenRelease,
            onOpenFullPlayer: {}
        )
    }
}

// MARK: - Album & Playlist Detail Sheet View (Port of AlbumView & PlaylistView)

public struct AlbumOrPlaylistSheetView: View {
    public var release: ReleaseItem
    @Bindable var player: AudioPlayerManager
    public var onOpenArtist: (String) -> Void
    public var onClose: (() -> Void)? = nil
    public var onOpenFullPlayer: (() -> Void)? = nil
    public var isNested: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var hydratedRelease: ReleaseItem? = nil
    @State private var isLoading: Bool = false
    @State private var isCoverLightboxOpen: Bool = false
    @State private var pushedArtistId: String? = nil

    private var activeRelease: ReleaseItem {
        hydratedRelease ?? release
    }

    private var isLikedSpecialPlaylist: Bool {
        activeRelease.id == "liked_tracks_special" ||
        activeRelease.id == "liked" ||
        activeRelease.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "мне нравится" ||
        activeRelease.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "мне нравиться"
    }

    private var isDeletablePlaylist: Bool {
        guard !isLikedSpecialPlaylist else { return false }
        return activeRelease.kind == .userPlaylist ||
               activeRelease.kind == .playlist ||
               player.userPlaylists.contains(where: { $0.id == activeRelease.id }) ||
               player.savedReleases.contains(where: { $0.id == activeRelease.id })
    }

    private var topButtonPadding: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        let safeTop = window?.safeAreaInsets.top ?? 20
        return isNested ? (safeTop + 6) : 20
    }

    public var body: some View {
        albumContent
    }

    @ViewBuilder
    private var albumContent: some View {
        ZStack(alignment: .top) {
            Color.amyBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        // Blurred Cover Header + 200x200 Cover Art
                        ZStack {
                            AsyncImage(url: URL(string: activeRelease.coverUrl ?? "")) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.12)
                            }
                            .frame(height: 260)
                            .blur(radius: 45)
                            .opacity(0.38)

                            let coverDim: CGFloat = min(196, max(140, UIScreen.main.bounds.width * 0.46))

                            VStack(spacing: 14) {
                                Button {
                                    isCoverLightboxOpen = true
                                } label: {
                                    AsyncImage(url: URL(string: activeRelease.coverUrl ?? "")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.white.opacity(0.12)
                                    }
                                    .frame(width: coverDim, height: coverDim)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                                }
                                .buttonStyle(.plain)

                                Text(activeRelease.kind.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .black))
                                    .tracking(1.0)
                                    .foregroundStyle(.white.opacity(0.9))

                                Text(activeRelease.title)
                                    .font(.system(size: UIScreen.main.bounds.width < 380 ? 22 : 26, weight: .black))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(2)
                                    .padding(.horizontal, 16)

                                Button {
                                    if let artistId = activeRelease.artistId, !artistId.isEmpty {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            onOpenArtist(artistId)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(activeRelease.artist)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text("• \(activeRelease.tracks.count) треков")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                }
                                .buttonStyle(.plain)

                                // Action Buttons: Play All, Shuffle, Save/Like Release
                                HStack(spacing: 14) {
                                    Button {
                                        if let first = activeRelease.tracks.first {
                                            player.playTrack(first, in: activeRelease.tracks)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.fill")
                                            Text("Слушать")
                                        }
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 26)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))

                                    Button {
                                        var shuffled = activeRelease.tracks
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

                                    if !isLikedSpecialPlaylist {
                                        let isSaved = player.savedReleases.contains(where: { $0.id == activeRelease.id })
                                        Button {
                                            player.toggleSavedRelease(activeRelease)
                                        } label: {
                                            Image(systemName: isSaved ? "heart.fill" : "heart")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(isSaved ? Color(hex: "#FF3B30") : .white)
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: isSaved ? Color(hex: "#FF3B30").opacity(0.30) : nil))
                                    }
                                }
                            }
                            .padding(.top, 16)
                        }

                        if isLoading && activeRelease.tracks.isEmpty {
                            ProgressView("Загрузка треков релиза...")
                                .tint(.white)
                                .padding(.top, 30)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(activeRelease.tracks) { track in
                                    TrackRowItemView(
                                        track: track,
                                        player: player,
                                        onTap: {
                                            player.playTrack(track, in: activeRelease.tracks)
                                        },
                                        onOpenArtist: { id in
                                            dismiss()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                onOpenArtist(id)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 14)
                        }

                        Spacer(minLength: player.currentTrack != nil ? 110 : 50)
                    }
                }

                // Top Bar Buttons directly on interface (No grey bar, no stripe)
                HStack {
                    if !isNested {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onClose?()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .contentShape(Circle())
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onClose?()
                            dismiss()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Назад")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                    }

                    Spacer()

                    if isDeletablePlaylist {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.deleteUserPlaylist(id: activeRelease.id)
                            onClose?()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Удалить")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .red.opacity(0.35)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topButtonPadding)
                .zIndex(100)

                // Bottom MiniPlayer: ONLY miniplayer, no tabbar
                if player.currentTrack != nil {
                    VStack {
                        Spacer()
                        PhoneLiquidGlassMiniPlayer(
                            player: player,
                            onOpenFull: {
                                onOpenFullPlayer?()
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                let needsHydration = release.tracks.isEmpty ||
                    release.tracks.contains { $0.title == "Без названия" } ||
                    release.tracks.count < release.trackCount
                if needsHydration {
                    isLoading = true
                    hydratedRelease = await SoundCloudService.shared.hydrateReleaseTracks(release)
                    isLoading = false
                }
            }
        }
    }

// MARK: - All Artist Tracks Sheet View

public struct AllArtistTracksSheetView: View {
    public var artistName: String
    public var tracks: [Track]
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    private var filteredTracks: [Track] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Поиск по всем трекам...", text: $searchText)
                            .foregroundStyle(.white)
                            .tint(.white)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                    // Header stats & Play All / Shuffle buttons
                    HStack(spacing: 12) {
                        Button {
                            if let first = filteredTracks.first {
                                player.playTrack(first, in: filteredTracks)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Слушать все (\(filteredTracks.count))")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))

                        Button {
                            var shuffled = filteredTracks
                            shuffled.shuffle()
                            if let first = shuffled.first {
                                player.playTrack(first, in: shuffled)
                            }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    // Tracks list
                    if filteredTracks.isEmpty {
                        Spacer()
                        ContentUnavailableView("Треки не найдены", systemImage: "music.note")
                        Spacer()
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.4))
                                            .frame(width: 24, alignment: .trailing)

                                        TrackRowItemView(
                                            track: track,
                                            player: player,
                                            onTap: {
                                                player.playTrack(track, in: filteredTracks)
                                            },
                                            onOpenArtist: { _ in }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Все треки: \(artistName)")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
