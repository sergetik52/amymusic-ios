import SwiftUI

// MARK: - Collection View & Playlist Creator/Importer
// Port of src/components/CollectionView.jsx

public struct CollectionView: View {
    @Bindable var player: AudioPlayerManager
    var onOpenArtist: (String) -> Void
    var onOpenRelease: (ReleaseItem) -> Void
    var onOpenSettings: () -> Void

    @State private var isCreatePlaylistOpen: Bool = false

    private var savedAlbums: [ReleaseItem] {
        player.savedReleases.filter { $0.kind == .album || $0.kind == .single }
    }

    private var savedPlaylists: [ReleaseItem] {
        player.savedReleases.filter { $0.kind == .playlist }
    }

    public var body: some View {
        ZStack {
            Color.amyBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    // Header ("Коллекция" / "У вашей музыки есть цвет")
                    VStack(spacing: 8) {
                        Text("Коллекция")
                            .font(.system(size: 40, weight: .black))
                            .tracking(-1.2)
                            .foregroundStyle(.white)

                        Text("У вашей музыки есть цвет")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        Button {
                            if let first = player.likedTracks.first {
                                player.playTrack(first, in: player.likedTracks)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color(hex: "#FF3B30"))
                                Text("Мне нравится (\(player.likedTracks.count))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: Color(hex: "#FF3B30").opacity(0.25)))
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.horizontal, 16)

                    // "Мне нравится" Horizontal Snap Pager (Pages of 5 tracks, matching CollectionView.jsx mobile)
                    if !player.likedTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Мне нравится")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundStyle(.white)
                                Spacer()
                                Button("Все (\(player.likedTracks.count))") {
                                    let likedRelease = ReleaseItem(
                                        id: "liked_tracks_special",
                                        title: "Мне нравится",
                                        artist: player.settings.displayName,
                                        coverUrl: player.likedTracks.first?.coverUrl,
                                        kind: .playlist,
                                        trackCount: player.likedTracks.count,
                                        tracks: player.likedTracks
                                    )
                                    onOpenRelease(likedRelease)
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                            }
                            .padding(.horizontal, 16)

                            let pages = stride(from: 0, to: min(player.likedTracks.count, 15), by: 5).map {
                                Array(player.likedTracks[$0..<min($0 + 5, player.likedTracks.count)])
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(Array(pages.enumerated()), id: \.offset) { _, pageTracks in
                                        VStack(spacing: 6) {
                                            ForEach(pageTracks) { track in
                                                TrackRowItemView(
                                                    track: track,
                                                    player: player,
                                                    onTap: {
                                                        player.playTrack(track, in: player.likedTracks)
                                                    },
                                                    onOpenArtist: onOpenArtist
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

                    // "Мои плейлисты" Carousel with "+" Create/Import Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Мои плейлисты")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                // "+" Add / Import Card
                                Button {
                                    isCreatePlaylistOpen = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .fill(.white.opacity(0.04))
                                                .frame(width: 148, height: 148)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                        .strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                                }

                                            VStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(.white)
                                                Text("Создать или\nИмпорт")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .multilineTextAlignment(.center)
                                                    .foregroundStyle(.white.opacity(0.75))
                                            }
                                        }

                                        Text("Добавить")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text("Yandex / Свой")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .frame(width: 148)
                                }
                                .buttonStyle(.plain)

                                ForEach(player.userPlaylists) { pl in
                                    ReleaseSquareCard(release: pl) {
                                        onOpenRelease(pl)
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            player.deleteUserPlaylist(id: pl.id)
                                        } label: {
                                            Label("Удалить плейлист", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // "Альбомы" Carousel
                    if !savedAlbums.isEmpty {
                        ReleaseHorizontalSection(
                            title: "Альбомы",
                            releases: savedAlbums,
                            onSelect: onOpenRelease
                        )
                    }

                    // "Плейлисты" Carousel
                    if !savedPlaylists.isEmpty {
                        ReleaseHorizontalSection(
                            title: "Плейлисты",
                            releases: savedPlaylists,
                            onSelect: onOpenRelease
                        )
                    }

                    // "Любимые исполнители" Horizontal Circular List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Любимые исполнители")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        if player.subscribedArtists.isEmpty {
                            Text("Подпишитесь на любимых артистов, чтобы они отображались здесь")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 16)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(player.subscribedArtists) { artist in
                                        Button {
                                            onOpenArtist(artist.id)
                                        } label: {
                                            VStack(spacing: 8) {
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
                                                .frame(width: 112, height: 112)
                                                .clipShape(Circle())
                                                .overlay {
                                                    Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                                }

                                                Text(artist.name)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 116)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    Spacer(minLength: 184)
                }
            }
        }
        .sheet(isPresented: $isCreatePlaylistOpen) {
            CreateOrImportPlaylistSheetView(player: player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Create or Import Playlist Sheet (Port of isAddPlaylistOpen in CollectionView.jsx)

public struct CreateOrImportPlaylistSheetView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var playlistTitle: String = ""
    @State private var yandexUrlInput: String = ""
    @State private var isImporting: Bool = false
    @State private var importCurrent: Int = 0
    @State private var importTotal: Int = 0

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Manual Creation Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Новый плейлист")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(.white)

                            TextField("Название плейлиста", text: $playlistTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button {
                                player.createUserPlaylist(title: playlistTitle)
                                dismiss()
                            } label: {
                                Text("Создать плейлист")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))
                        }
                        .padding(18)
                        .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        // Yandex Music / URL Importer Card
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "link.badge.plus")
                                    .foregroundStyle(.white)
                                Text("Импорт из Яндекс Музыки / SoundCloud")
                                    .font(.system(size: 17, weight: .black))
                                    .foregroundStyle(.white)
                            }

                            Text("Вставьте ссылку на плейлист или альбом (например, music.yandex.ru/users/.../playlists/...)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))

                            TextField("Ссылка на плейлист (music.yandex.ru/...)", text: $yandexUrlInput)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(14)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            if isImporting {
                                VStack(alignment: .leading, spacing: 6) {
                                    ProgressView(
                                        value: Double(importCurrent),
                                        total: Double(max(1, importTotal))
                                    )
                                    .tint(.white)

                                    Text("Импорт треков: \(importCurrent) из \(importTotal)...")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }

                            Button {
                                startImport()
                            } label: {
                                HStack {
                                    if isImporting {
                                        ProgressView().tint(.black).padding(.trailing, 6)
                                    }
                                    Text(isImporting ? "Импортируем..." : "Импортировать по ссылке")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .disabled(isImporting || yandexUrlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))
                        }
                        .padding(18)
                        .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Создать или импортировать")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func startImport() {
        let url = yandexUrlInput
        isImporting = true
        Task {
            if let imported = await YandexMusicService.shared.importPlaylistFromUrl(url, onProgress: { current, total in
                Task { @MainActor in
                    self.importCurrent = current
                    self.importTotal = total
                }
            }) {
                player.userPlaylists.insert(imported, at: 0)
                player.persistState()
                isImporting = false
                dismiss()
            } else {
                isImporting = false
            }
        }
    }
}

// MARK: - Shared Release Card & Horizontal Section

public struct ReleaseHorizontalSection: View {
    public var title: String
    public var releases: [ReleaseItem]
    public var onSelect: (ReleaseItem) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(releases) { release in
                        ReleaseSquareCard(release: release) {
                            onSelect(release)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

public struct ReleaseSquareCard: View {
    public var release: ReleaseItem
    public var onTap: () -> Void

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: release.coverUrl ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color(hex: "#18181b")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("\(release.trackCount) тр.")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(8)
                }

                Text(release.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(release.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: 148)
        }
        .buttonStyle(.plain)
    }
}
