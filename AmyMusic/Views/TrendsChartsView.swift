import SwiftUI

// MARK: - Charts & Trends View ("Чарты" - Port of TrendsPanel in src/App.jsx & TopChartsView.jsx)

public struct TrendsChartsView: View {
    @Bindable var player: AudioPlayerManager
    var onOpenArtist: (String) -> Void
    var onOpenSettings: () -> Void

    @State private var isRefreshing: Bool = false

    public var body: some View {
        ZStack {
            Color.amyBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    // Header Section
                    VStack(spacing: 10) {
                        Text("Чарты")
                            .font(.system(size: 40, weight: .black))
                            .tracking(-1.2)
                            .foregroundStyle(.white)

                        Text("Самые популярные треки прямо сейчас")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        HStack(spacing: 12) {
                            Button {
                                if let first = player.chartTracks.first {
                                    player.playTrack(first, in: player.chartTracks)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14, weight: .black))
                                    Text("Слушать")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true, scaleOnPress: 0.94))

                            Button {
                                refreshCharts()
                            } label: {
                                Group {
                                    if isRefreshing {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                        }
                        .padding(.top, 6)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 16)

                    // Top 100 Track List
                    if player.chartTracks.isEmpty {
                        ProgressView("Загрузка чарта Топ-100...")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(player.chartTracks.enumerated()), id: \.element.id) { index, track in
                                ChartTrackRowView(
                                    rank: track.chartPosition ?? (index + 1),
                                    track: track,
                                    player: player,
                                    onTap: {
                                        player.playTrack(track, in: player.chartTracks)
                                    },
                                    onOpenArtist: onOpenArtist
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    Spacer(minLength: 24)
                }
            }
        }
    }

    private func refreshCharts() {
        isRefreshing = true
        Task {
            let fresh = await YandexMusicService.shared.getChartTop100()
            if !fresh.isEmpty {
                player.chartTracks = fresh
            }
            isRefreshing = false
        }
    }
}

// MARK: - Chart Row with Top 3 Gold/Silver/Bronze Glow & Delta Arrow (Port of ChartPositionBadge)

public struct ChartTrackRowView: View {
    public var rank: Int
    public var track: Track
    @Bindable var player: AudioPlayerManager
    public var onTap: () -> Void
    public var onOpenArtist: (String) -> Void

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(hex: "#FBBF24") // Gold
        case 2: return Color(hex: "#CBD5E1") // Silver
        case 3: return Color(hex: "#D97706") // Bronze
        default: return .white.opacity(0.65)
        }
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Rank + Shift Delta Badge
                VStack(spacing: 2) {
                    Text("\(rank)")
                        .font(.system(size: rank <= 3 ? 17 : 14, weight: .black, design: .rounded))
                        .foregroundStyle(rankColor)
                        .shadow(color: rank <= 3 ? rankColor.opacity(0.55) : .clear, radius: 8)

                    chartDeltaBadge
                }
                .frame(width: 34)

                // 48x48 Cover
                ZStack {
                    AmyAsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.12)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isCurrent {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.48))
                            .frame(width: 48, height: 48)

                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                // Title & Artist Links
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isCurrent ? .white : .white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                // Like button + Duration + Context Menu
                Button {
                    player.toggleLike(track)
                } label: {
                    let liked = player.isLiked(track)
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(liked ? .white : .white.opacity(0.35))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                Text(track.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))

                Menu {
                    TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.12) : .white.opacity(0.03))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
        } preview: {
            TrackContextMenuPreviewCard(track: track)
        }
    }

    @ViewBuilder
    private var chartDeltaBadge: some View {
        switch track.chartProgress {
        case .up:
            HStack(spacing: 1) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 7))
                if let shift = track.chartShift, shift > 0 {
                    Text("\(shift)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(Color(hex: "#34D399"))
        case .down:
            HStack(spacing: 1) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                if let shift = track.chartShift, shift > 0 {
                    Text("\(abs(shift))")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(Color(hex: "#FB7185"))
        case .new:
            Text("NEW")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
        default:
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 4, height: 4)
        }
    }

    private func formatCompactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1f млн", Double(value) / 1_000_000.0)
        } else if value >= 1_000 {
            return "\(value / 1_000) тыс"
        }
        return "\(value)"
    }
}

// MARK: - Universal Track Row Item & Context Menu (Port of TrackContextMenu.jsx)

public struct TrackRowItemView: View {
    public var track: Track
    @Bindable var player: AudioPlayerManager
    public var compact: Bool = false
    public var onTap: () -> Void
    public var onOpenArtist: (String) -> Void

    public init(
        track: Track,
        player: AudioPlayerManager,
        compact: Bool = false,
        onTap: @escaping () -> Void,
        onOpenArtist: @escaping (String) -> Void
    ) {
        self.track = track
        self.player = player
        self.compact = compact
        self.onTap = onTap
        self.onOpenArtist = onOpenArtist
    }

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: compact ? 9 : 12) {
                AmyAsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.12)
                }
                .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))

                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    Text(track.title)
                        .font(.system(size: compact ? 13 : 14, weight: .bold))
                        .foregroundStyle(isCurrent ? .white : .white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    player.toggleLike(track)
                } label: {
                    let liked = player.isLiked(track)
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(liked ? .white : .white.opacity(0.35))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                Text(track.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))

                Menu {
                    TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 32)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 8)
            .background {
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.12) : .white.opacity(0.03))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
        } preview: {
            TrackContextMenuPreviewCard(track: track)
        }
    }
}

// MARK: - Track Context Menu Preview Card (Lifts up with Apple native background blur)

public struct TrackContextMenuPreviewCard: View {
    public var track: Track

    public var body: some View {
        HStack(spacing: 12) {
            AmyAsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.12)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                let count = (track.listenersCount ?? 0) > 0 ? (track.listenersCount ?? 0) : track.playbackCount
                if count > 0 {
                    Text("🎧 \(formatTrackPlayCount(count)) прослушиваний")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }
}

fileprivate func formatTrackPlayCount(_ num: Int) -> String {
    if num >= 1_000_000 {
        return String(format: "%.1f млн", Double(num) / 1_000_000.0)
    } else if num >= 1_000 {
        return "\(num / 1_000) тыс"
    }
    return "\(num)"
}

public struct TrackNativeContextMenuItems: View {
    public var track: Track
    @Bindable var player: AudioPlayerManager
    public var onOpenArtist: (String) -> Void

    public var body: some View {
        let playCount = (track.listenersCount ?? 0) > 0 ? (track.listenersCount ?? 0) : track.playbackCount
        if playCount > 0 {
            Section {
                Button {} label: {
                    Label("\(formatTrackPlayCount(playCount)) прослушиваний", systemImage: "headphones")
                }
                .disabled(true)
            }
        }

        Button {
            player.playNextInQueue(track)
        } label: {
            Label("Следующим", systemImage: "text.insert")
        }

        Button {
            player.addToQueueEnd(track)
        } label: {
            Label("Добавить в очередь", systemImage: "text.append")
        }

        Button {
            Task { await player.startTrackWave(for: track) }
        } label: {
            Label("Волна по треку (TrackDNA)", systemImage: "waveform.path.ecg")
        }

        Divider()

        Button {
            player.toggleLike(track)
        } label: {
            let liked = player.isLiked(track)
            Label(
                liked ? "Удалить из избранного" : "Добавить в избранное",
                systemImage: liked ? "heart.slash.fill" : "heart.fill"
            )
        }

        if !player.userPlaylists.isEmpty {
            Menu("Добавить в плейлист") {
                ForEach(player.userPlaylists.indices, id: \.self) { idx in
                    Button(player.userPlaylists[idx].title) {
                        player.userPlaylists[idx].tracks.append(track)
                        player.userPlaylists[idx].trackCount = player.userPlaylists[idx].tracks.count
                        player.persistState()
                    }
                }
            }
        }

        if !track.artists.isEmpty {
            if track.artists.count == 1, let firstArtist = track.artists.first {
                Button {
                    onOpenArtist(firstArtist.id)
                } label: {
                    Label("Перейти к артисту (\(firstArtist.name))", systemImage: "person.crop.circle")
                }
            } else {
                Menu {
                    ForEach(track.artists) { artist in
                        Button {
                            onOpenArtist(artist.id)
                        } label: {
                            Text(artist.name)
                        }
                    }
                } label: {
                    Label("Перейти к артистам (\(track.artists.count))", systemImage: "person.2.crop.square.stack")
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            player.dislikeTrack(track)
        } label: {
            Label("Не интересно", systemImage: "hand.thumbsdown.fill")
        }
    }
}
