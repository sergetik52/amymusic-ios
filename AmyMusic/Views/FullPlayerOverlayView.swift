import SwiftUI
import AVKit

// MARK: - Full Player Overlay, Synced Lyrics Engine, Lyrics Context Menu, Queue Sheet & 10-Band Equalizer
// Port of src/components/FullPlayerOverlay.jsx, src/components/LyricsContextMenu.jsx & src/components/EqualizerModal.jsx

public enum FullPlayerCenterStageMode: String, CaseIterable {
    case song = "Песня"
    case lyrics = "Текст"
}

public struct FullPlayerOverlayView: View {
    @Bindable var player: AudioPlayerManager
    @Binding var isPresented: Bool
    var onOpenArtist: (String) -> Void

    @State private var stageMode: FullPlayerCenterStageMode = .song
    @State private var isLyricsConfigOpen: Bool = false
    @State private var isQueueOpen: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var dragDismissOffset: CGFloat = 0

    private var safeTopInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
        let top = window?.safeAreaInsets.top ?? 0
        return top > 0 ? top : 54
    }

    private var safeBottomInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
        let bottom = window?.safeAreaInsets.bottom ?? 0
        return bottom > 0 ? bottom : 34
    }

    public var body: some View {
        let track = player.currentTrack
        let palette = track?.palette ?? .defaultPalette
        let totalDuration = max(1, player.duration > 0 ? player.duration : (track?.duration ?? 1))

        GeometryReader { geo in
            let screenHeight = geo.size.height
            let screenWidth = geo.size.width
            let safeTop = safeTopInset
            let safeBottom = safeBottomInset

            // Dynamic responsive dimensions for all iPhone resolutions (iPhone 11 to 17 Pro Max)
            let isCompact = screenHeight < 780      // iPhone SE
            let isMedium = screenHeight < 860       // iPhone 11 Pro, 12, 13, 14, 15 Pro, 17 Pro
            let coverPadding: CGFloat = isCompact ? 60 : (isMedium ? 54 : 48)
            let maxCoverWidth = screenWidth - coverPadding
            let availableHeight = screenHeight - (safeTop + safeBottom + 270)
            let coverSize: CGFloat = max(175, min(maxCoverWidth, min(availableHeight, isCompact ? 230 : (isMedium ? 275 : 310))))

            let dockSpacing: CGFloat = isCompact ? 10 : (isMedium ? 12 : 15)
            let playBtnSize: CGFloat = isCompact ? 58 : 64

            ZStack {
                // Audio-Reactive Fluid Mesh + Breathing Cover Background
                FluidMeshBackgroundView(
                    palette: palette,
                    energy: player.audioEnergy,
                    isPlaying: player.isPlaying
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Bar: True Centered Switcher via ZStack + Left/Right Action Controls
                    ZStack {
                        // 1. Center Stage Switcher ("Песня" | "Текст") - Dead Center on Screen with Fluid Droplet Physics
                        LiquidGlassSegmentedPicker(
                            selection: $stageMode,
                            items: FullPlayerCenterStageMode.allCases,
                            accentColor: .white,
                            label: \.rawValue
                        )
                        .frame(width: 172, height: 34)

                        // 2. Left ("Свернуть") and Right (aA + Очередь)
                        HStack(alignment: .center) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isPresented = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Свернуть")
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))

                            Spacer()

                            HStack(spacing: 6) {
                                if stageMode == .lyrics {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        isLyricsConfigOpen = true
                                    } label: {
                                        Image(systemName: "textformat.size")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(8)
                                    }
                                    .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                                }

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isQueueOpen = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 12, weight: .bold))

                                        let upcomingCount = max(0, player.queue.count - player.currentIndex - 1)
                                        if upcomingCount > 0 {
                                            Text("\(upcomingCount)")
                                                .font(.system(size: 11, weight: .black, design: .rounded))
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .foregroundStyle(.black)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(.white, in: Capsule())
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)

                    // Center Stage: Cover Art vs Synced Lyrics Engine
                    if stageMode == .song {
                        Spacer(minLength: 6)

                        AsyncImage(url: URL(string: track?.coverUrl ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            LinearGradient(
                                colors: [Color(hex: palette.line), Color(hex: palette.base)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .frame(width: coverSize, height: coverSize)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .scaleEffect(player.isPlaying ? (1.0 + player.audioEnergy.bass * 0.035) : 0.95)
                        .shadow(
                            color: Color(hex: palette.line).opacity(player.settings.fullPlayerGlowEnabled ? 0.55 : 0.25),
                            radius: 32,
                            y: 14
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: player.isPlaying)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                stageMode = .lyrics
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 35)
                                .onEnded { val in
                                    if val.translation.width < -50 {
                                        player.next()
                                    } else if val.translation.width > 50 {
                                        player.previous()
                                    }
                                }
                        )

                        Spacer(minLength: 8)
                    } else {
                        SyncedLyricsStageView(
                            player: player,
                            palette: palette,
                            onOpenLyricsSettings: { isLyricsConfigOpen = true }
                        )
                        .frame(maxHeight: .infinity)
                    }

                    // Bottom Controls Dock
                    VStack(spacing: dockSpacing) {
                        // Track Title, Artist Chips & Menu
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track?.title ?? "Нет трека")
                                    .font(.system(size: isCompact ? 20 : 22, weight: .black))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(track?.artists ?? []) { artistRef in
                                            Button {
                                                let targetArtistId = track?.uploaderId ?? artistRef.id
                                                onOpenArtist(targetArtistId)
                                            } label: {
                                                HStack(spacing: 6) {
                                                    ArtistChipAvatarView(
                                                        artistName: artistRef.name,
                                                        fallbackAvatarUrl: artistRef.avatarUrl
                                                    )
                                                    Text(artistRef.name)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(.white.opacity(0.85))
                                                }
                                                .padding(.vertical, 3)
                                                .padding(.horizontal, 7)
                                                .background(Color.white.opacity(0.08), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let track {
                                Menu {
                                    TrackNativeContextMenuItems(track: track, player: player, onOpenArtist: onOpenArtist)
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                            }
                        }

                        // Sleek Liquid Scrubber Bar + Timestamps
                        VStack(spacing: 4) {
                            LiquidScrubberBar(
                                currentTime: player.currentTime,
                                duration: totalDuration,
                                tintColor: Color(hex: palette.bright),
                                isScrubbing: $isScrubbing,
                                scrubTime: $scrubTime
                            ) { targetTime in
                                player.seek(to: targetTime)
                            }

                            HStack {
                                Text(formatTime(isScrubbing ? scrubTime : player.currentTime))
                                Spacer()
                                Text(formatTime(totalDuration))
                            }
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                        }

                        // Main Transport Row: Dislike, Prev, Play/Pause, Next, Like
                        HStack(alignment: .center) {
                            Button {
                                if let track { player.dislikeTrack(track) }
                            } label: {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                            Spacer()

                            Button {
                                player.previous()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                            Spacer()

                            Button {
                                player.togglePlay()
                            } label: {
                                ZStack {
                                    if player.isLoading {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: isCompact ? 22 : 24, weight: .black))
                                            .foregroundStyle(.black)
                                            .offset(x: player.isPlaying ? 0 : 2)
                                    }
                                }
                                .frame(width: playBtnSize, height: playBtnSize)
                            }
                            .buttonStyle(
                                AppleLiquidGlassButtonStyle(
                                    shape: Circle(),
                                    tintColor: Color(hex: player.settings.themePreset.primaryHex),
                                    isFilledAccent: true,
                                    scaleOnPress: 0.92
                                )
                            )

                            Spacer()

                            Button {
                                player.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                            Spacer()

                            Button {
                                if let track { player.toggleLike(track) }
                            } label: {
                                let liked = player.isLiked(track)
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(liked ? Color(hex: "#FF3B30") : .white.opacity(0.70))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: player.isLiked(track) ? Color(hex: "#FF3B30").opacity(0.30) : nil))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 2)

                        // Bottom Utility Row: Repeat, AirPlay, Queue, Shuffle
                        HStack(alignment: .center) {
                            Button {
                                player.cycleRepeatMode()
                            } label: {
                                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(player.repeatMode != .off ? .white : .white.opacity(0.55))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: player.repeatMode != .off ? Color(hex: player.settings.themePreset.primaryHex).opacity(0.35) : nil))

                            Spacer()

                            AirPlayRoutePickerButton()
                                .frame(width: 22, height: 22)
                                .frame(width: 42, height: 42)
                                .amyLiquidGlass(in: Circle(), interactive: true)

                            Spacer()

                            Button {
                                isQueueOpen = true
                            } label: {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.70))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))

                            Spacer()

                            Button {
                                player.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(player.isShuffleEnabled ? .white : .white.opacity(0.55))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle(), tintColor: player.isShuffleEnabled ? Color(hex: player.settings.themePreset.primaryHex).opacity(0.35) : nil))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.bottom, max(safeBottom, 16) + 4)
                }
                .frame(width: screenWidth)
                .offset(y: max(0, dragDismissOffset))
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            if val.translation.height > 0 {
                                dragDismissOffset = val.translation.height
                            }
                        }
                        .onEnded { val in
                            if val.translation.height > 90 {
                                isPresented = false
                            }
                            withAnimation(.spring(duration: 0.28)) {
                                dragDismissOffset = 0
                            }
                        }
                )
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isLyricsConfigOpen) {
            LyricsSettingsMenuSheet(player: player)
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isQueueOpen) {
            QueueBottomSheetView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func formatTime(_ secs: TimeInterval) -> String {
        guard secs.isFinite && secs >= 0 else { return "0:00" }
        let s = Int(secs.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Liquid Scrubber Bar
public struct LiquidScrubberBar: View {
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let tintColor: Color
    @Binding public var isScrubbing: Bool
    @Binding public var scrubTime: TimeInterval
    public let onCommit: (TimeInterval) -> Void

    public var body: some View {
        let activeTime = isScrubbing ? scrubTime : currentTime
        let progress: CGFloat = duration > 0 ? CGFloat(min(1.0, max(0.0, activeTime / duration))) : 0

        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let trackHeight: CGFloat = isScrubbing ? 5.5 : 4.0
            let thumbDiameter: CGFloat = isScrubbing ? 15.0 : 11.0

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                // Filled track
                Capsule()
                    .fill(tintColor)
                    .frame(width: max(0, width * progress), height: trackHeight)
                    .shadow(color: tintColor.opacity(0.35), radius: 3, y: 0)

                // Thumb handle
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 1.5)
                    .offset(x: max(0, min(width - thumbDiameter, width * progress - thumbDiameter / 2)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isScrubbing {
                            isScrubbing = true
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        let pct = max(0.0, min(1.0, Double(val.location.x / width)))
                        scrubTime = duration * pct
                    }
                    .onEnded { val in
                        let pct = max(0.0, min(1.0, Double(val.location.x / width)))
                        let target = duration * pct
                        onCommit(target)
                        isScrubbing = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - Synced Lyrics Stage (4 Styles: Blur, Scale, Normal, Braccato Word Sweep + 3-Dot Intro)

public struct SyncedLyricsStageView: View {
    @Bindable var player: AudioPlayerManager
    var palette: TrackPalette
    var onOpenLyricsSettings: () -> Void

    @State private var expandedAnnotationId: String? = nil

    public var body: some View {
        let lines = player.currentLyrics.lines
        let offsetMs = player.currentTrackLyricsOffsetMs()
        let isGenius = player.settings.preferredLyricsSource == .genius || player.currentLyrics.source.localizedCaseInsensitiveContains("Genius")
        let activeIdx = isGenius ? nil : LyricsService.activeLyricIndex(
            in: lines,
            currentTime: player.currentTime,
            offsetMs: offsetMs
        )
        let firstLineTime = lines.first?.time ?? 0
        let showIntroDots = !isGenius && player.currentLyrics.status == .synced && firstLineTime > 2.0 && player.currentTime < firstLineTime

        ZStack {
            if player.isLyricsLoading {
                ProgressView("Поиск текста (LRCLib / Genius)...")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.65))
            } else if lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Текст для этого трека не найден")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Попробовать другой источник") {
                        onOpenLyricsSettings()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: isGenius) {
                        VStack(alignment: .leading, spacing: 14) {

                            // 3-Dot Bouncing Intro before first lyric (Port of karaoke-dot-jump)
                            if showIntroDots {
                                HStack(spacing: 8) {
                                    ForEach(0..<3, id: \.self) { i in
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 10, height: 10)
                                            .opacity(0.85)
                                    }
                                }
                                .padding(.vertical, 8)
                            }

                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                let isActive = !isGenius && (activeIdx == index)
                                let distance = abs((activeIdx ?? 0) - index)
                                let annId = line.annotationId
                                let hasAnnotation = (annId != nil && player.currentLyrics.annotations[annId!] != nil)
                                let isExpanded = (expandedAnnotationId == annId && hasAnnotation)

                                VStack(alignment: .leading, spacing: 6) {
                                    // Небольшой разрыв между куплетами заместо заголовков [Припев], [Куплет]
                                    if line.hasVerseGap {
                                        Spacer().frame(height: 18)
                                    }

                                    if isGenius {
                                        // Цельный текст Genius для свободного чтения и листания
                                        Button {
                                            if hasAnnotation {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    expandedAnnotationId = (expandedAnnotationId == annId) ? nil : annId
                                                }
                                            }
                                        } label: {
                                            buildStyledLyricLine(
                                                text: line.text,
                                                baseFontSize: player.settings.lyricsFontSize.pointSize,
                                                isActive: true,
                                                isGenius: true,
                                                hasAnnotation: hasAnnotation
                                            )
                                            .lineSpacing(4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Button {
                                            if hasAnnotation {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    expandedAnnotationId = (expandedAnnotationId == annId) ? nil : annId
                                                }
                                            }
                                            player.seek(to: line.time)
                                        } label: {
                                            lyricLineContent(
                                                line: line,
                                                isActive: isActive,
                                                distance: distance,
                                                hasAnnotation: hasAnnotation
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    // Раскрывающаяся аннотация Genius: серая полупрозрачная полоска слева и очищенный текст
                                    if isExpanded, let annId, let rawAnn = player.currentLyrics.annotations[annId] {
                                        let cleanAnn = LyricsService.cleanAnnotationText(rawAnn)
                                        if !cleanAnn.isEmpty {
                                            HStack(alignment: .top, spacing: 10) {
                                                RoundedRectangle(cornerRadius: 1.5)
                                                    .fill(Color.white.opacity(0.35))
                                                    .frame(width: 3)

                                                Text(cleanAnn)
                                                    .font(.system(size: max(13, player.settings.lyricsFontSize.pointSize * 0.72), weight: .regular))
                                                    .foregroundStyle(.white.opacity(0.85))
                                                    .lineSpacing(4)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.leading, 4)
                                            .padding(.trailing, 8)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                        }
                                    }
                                }
                                .id(line.id)
                            }

                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: activeIdx) { _, newIdx in
                        // В режиме Genius не скроллим автоматически, чтобы пользователь мог свободно листать
                        guard !isGenius else { return }
                        if let newIdx, newIdx < lines.count {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                proxy.scrollTo(lines[newIdx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.settings.lyricsFontSize)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.settings.lyricsTextStyle)
        .contextMenu {
            Button("Настройки текста") { onOpenLyricsSettings() }
            Button("Обновить текст") {
                Task { await player.loadLyricsForCurrentTrack(forceRefresh: true) }
            }
        }
    }

    @ViewBuilder
    private func lyricLineContent(line: LyricLine, isActive: Bool, distance: Int, hasAnnotation: Bool) -> some View {
        let baseFontSize = player.settings.lyricsFontSize.pointSize
        let style = player.settings.lyricsTextStyle
        let syncMode = player.settings.lyricsSyncMode
        let adjustedTime = player.currentTime + 0.08 - (player.currentTrackLyricsOffsetMs() / 1000.0)

        if syncMode == .words && isActive && !line.words.isEmpty {
            WrappingHStackWordsView(
                words: line.words,
                currentTime: adjustedTime,
                fontSize: baseFontSize,
                accentColor: Color(hex: palette.bright),
                hasAnnotation: hasAnnotation
            )
            .scaleEffect(1.04, anchor: .leading)
        } else {
            let blurRadius: CGFloat = {
                guard style == .blur && player.currentLyrics.status == .synced else { return 0 }
                if isActive { return 0 }
                switch distance {
                case 1: return 1.6
                case 2: return 3.2
                case 3: return 5.0
                default: return 7.5
                }
            }()

            let scale: CGFloat = {
                switch style {
                case .scale: return isActive ? 1.12 : 0.96
                case .blur: return isActive ? 1.04 : 1.0
                case .normal: return 1.0
                }
            }()

            buildStyledLyricLine(
                text: line.text,
                baseFontSize: baseFontSize,
                isActive: isActive,
                isGenius: false,
                hasAnnotation: hasAnnotation
            )
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
        }
    }
}

fileprivate struct LyricToken {
    let text: String
    let isParenthesized: Bool
}

fileprivate func tokenizeLyricLine(_ text: String) -> [LyricToken] {
    let pattern = #"\([^\)]*\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [LyricToken(text: text, isParenthesized: false)]
    }

    var tokens: [LyricToken] = []
    var lastIdx = text.startIndex
    let nsRange = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: nsRange)

    for match in matches {
        if let matchRange = Range(match.range, in: text) {
            if lastIdx < matchRange.lowerBound {
                let prefix = String(text[lastIdx..<matchRange.lowerBound])
                tokens.append(LyricToken(text: prefix, isParenthesized: false))
            }
            let paren = String(text[matchRange])
            tokens.append(LyricToken(text: paren, isParenthesized: true))
            lastIdx = matchRange.upperBound
        }
    }

    if lastIdx < text.endIndex {
        let suffix = String(text[lastIdx...])
        tokens.append(LyricToken(text: suffix, isParenthesized: false))
    }

    return tokens.isEmpty ? [LyricToken(text: text, isParenthesized: false)] : tokens
}

fileprivate func buildStyledLyricLine(
    text: String,
    baseFontSize: CGFloat,
    isActive: Bool,
    isGenius: Bool,
    hasAnnotation: Bool
) -> Text {
    let tokens = tokenizeLyricLine(text)
    var result = Text("")

    for token in tokens {
        if token.isParenthesized {
            result = result + Text(token.text)
                .font(.system(size: max(11, baseFontSize - 3.5), weight: .medium))
                .italic()
                .foregroundColor(isActive ? (isGenius ? Color.white.opacity(0.60) : Color.white.opacity(0.55)) : Color.white.opacity(0.24))
        } else {
            result = result + Text(token.text)
                .font(.system(size: baseFontSize, weight: isGenius ? .bold : .black))
                .foregroundColor(isActive ? .white : (isGenius ? .white.opacity(0.95) : .white.opacity(0.34)))
        }
    }

    if hasAnnotation {
        result = result + Text(" ””")
            .font(.system(size: max(12, baseFontSize - 1.5), weight: .bold))
            .foregroundColor(Color.white.opacity(0.75))
    }

    return result
}

private struct WrappingHStackWordsView: View {
    var words: [LyricWord]
    var currentTime: TimeInterval
    var fontSize: CGFloat
    var accentColor: Color
    var hasAnnotation: Bool = false

    var body: some View {
        // Highlight each word based on its interpolated timestamp
        let attributed: AttributedString = {
            var result = AttributedString()
            for (idx, word) in words.enumerated() {
                var part = AttributedString(word.text + (idx < words.count - 1 ? " " : ""))
                let isSung = currentTime >= word.startTime
                part.foregroundColor = isSung ? .white : .white.opacity(0.38)
                result.append(part)
            }
            return result
        }()

        Text(attributed)
            .font(.system(size: fontSize, weight: .black))
            .shadow(color: accentColor.opacity(0.45), radius: 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lyrics Settings Sheet (Port of src/components/LyricsContextMenu.jsx)

public struct LyricsSettingsMenuSheet: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Font Size Selector (sm, base, lg, xl "A")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Размер шрифта")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))

                            HStack(spacing: 10) {
                                ForEach(LyricsFontSize.allCases) { size in
                                    let active = player.settings.lyricsFontSize == size
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            player.settings.lyricsFontSize = size
                                        }
                                    } label: {
                                        Text("A")
                                            .font(.system(size: size.pointSize * 0.65, weight: .black))
                                            .foregroundStyle(active ? .black : .white)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(active ? .white : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // 2. Source Switcher (Авто / LRCLib / Genius)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Источник текста")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))

                            LiquidGlassSegmentedPicker(
                                selection: Binding(
                                    get: { player.settings.preferredLyricsSource },
                                    set: { newSource in
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            player.settings.preferredLyricsSource = newSource
                                        }
                                    }
                                ),
                                items: LyricsSourceKind.allCases,
                                accentColor: .white,
                                label: \.rawValue
                            )
                            .frame(height: 36)
                            .onChange(of: player.settings.preferredLyricsSource) { _, _ in
                                Task { await player.loadLyricsForCurrentTrack(forceRefresh: true) }
                            }
                        }

                        // 3. Sync Mode Toggle & Style Cycler
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Режим синхронизации и стиль")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))

                            LiquidGlassSegmentedPicker(
                                selection: Binding(
                                    get: { player.settings.lyricsSyncMode },
                                    set: { newMode in
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            player.settings.lyricsSyncMode = newMode
                                        }
                                    }
                                ),
                                items: LyricsSyncMode.allCases,
                                accentColor: .white,
                                label: \.rawValue
                            )
                            .frame(height: 36)

                            LiquidGlassSegmentedPicker(
                                selection: Binding(
                                    get: { player.settings.lyricsTextStyle },
                                    set: { newStyle in
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            player.settings.lyricsTextStyle = newStyle
                                        }
                                    }
                                ),
                                items: LyricsTextStyle.allCases,
                                accentColor: .white,
                                label: \.rawValue
                            )
                            .frame(height: 36)
                        }

                        // 4. Per-Track Millisecond Offset Slider (-2000ms to +2000ms, step 25ms)
                        VStack(alignment: .leading, spacing: 8) {
                            let offset = player.currentTrackLyricsOffsetMs()
                            HStack {
                                Text("Смещение тайминга")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(Int(offset)) мс")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }

                            Slider(
                                value: Binding(
                                    get: { player.currentTrackLyricsOffsetMs() },
                                    set: { player.setCurrentTrackLyricsOffsetMs(($0 / 25.0).rounded() * 25.0) }
                                ),
                                in: -2000...2000,
                                step: 25
                            )
                            .tint(.white)
                        }

                        // 5. Reload Button
                        Button {
                            Task { await player.loadLyricsForCurrentTrack(forceRefresh: true) }
                            dismiss()
                        } label: {
                            Label("Обновить текст", systemImage: "arrow.clockwise")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .amyLiquidGlass(in: Capsule(), tint: .white, tintOpacity: 0.18)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Настройки текста")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                }
            }
        }
    }
}

// MARK: - Queue Bottom Sheet (Port of Mobile Queue Bottom Sheet in FullPlayerOverlay.jsx)

public struct QueueBottomSheetView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                List {
                    // Autoplay Switch
                    Section {
                        Toggle(isOn: $player.isAutoplayEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Автовоспроизведение (Моя волна)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("Бесконечное продолжение очереди")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .toggleStyle(.appleLiquidGlass)
                        .listRowBackground(Color.white.opacity(0.06))
                    }

                    // Currently Playing
                    if let current = player.currentTrack {
                        Section("Сейчас играет") {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: current.coverUrl ?? "")) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.white.opacity(0.12)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(current.title)
                                        .font(.system(size: 14.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(current.artist)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white.opacity(0.12))
                        }
                    }

                    // Upcoming in Queue with Drag-and-Drop Reordering
                    let upcomingCount = max(0, player.queue.count - player.currentIndex - 1)
                    Section("Далее в очереди (\(upcomingCount))") {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                            if index > player.currentIndex {
                                Button {
                                    player.playTrack(track)
                                } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Color.white.opacity(0.10)
                                        }
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.55))
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text(track.formattedDuration)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(Color.white.opacity(0.04))
                            }
                        }
                        .onMove { source, dest in
                            player.moveQueueItem(from: source, to: dest)
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                player.removeFromQueue(at: idx)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                }
            }
        }
    }
}

// MARK: - 10-Band Equalizer Modal Sheet (Port of src/components/EqualizerModal.jsx)

public struct EqualizerSheetView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Master Toggle + Reset Button
                    HStack {
                        Toggle("Эквалайзер (10 полос)", isOn: $player.settings.equalizerEnabled)
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                            .toggleStyle(.appleLiquidGlass)

                        Button("Сбросить") {
                            player.selectEqualizerPreset(.flat)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Preset Pills Row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(EqualizerPreset.allCases) { preset in
                                let active = player.settings.equalizerPreset == preset
                                Button {
                                    player.selectEqualizerPreset(preset)
                                } label: {
                                    Text(preset.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(active ? .black : .white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(active ? .white : .white.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // 10 Vertical Band Sliders (60 Hz .. 16 kHz, -12dB .. +12dB)
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(0..<10, id: \.self) { index in
                            let gain = index < player.settings.equalizerBands.count ? player.settings.equalizerBands[index] : 0
                            VStack(spacing: 8) {
                                Text(String(format: "%+.0f", gain))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(gain == 0 ? .white.opacity(0.45) : .white)

                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        Capsule()
                                            .fill(.white.opacity(0.08))
                                            .frame(width: 8)

                                        let normalized = CGFloat((gain + 12.0) / 24.0)
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white, Color(hex: "#D4D4D8")],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .frame(width: 8, height: max(8, geo.size.height * normalized))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { val in
                                                let ratio = 1.0 - min(1.0, max(0.0, val.location.y / geo.size.height))
                                                let db = Float(ratio * 24.0 - 12.0)
                                                let stepped = (db * 2.0).rounded() / 2.0
                                                player.setEqualizerBand(index, gain: stepped)
                                            }
                                    )
                                }
                                .frame(height: 170)

                                Text(EqualizerPreset.labels[index])
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)

                    // Studio Volume Normalization Toggle
                    Toggle(isOn: $player.settings.volumeNormalization) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Нормализация громкости (Studio Limiter)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Выравнивает уровень громкости между тихими и громкими треками")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .toggleStyle(.appleLiquidGlass)
                    .padding(16)
                    .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)

                    Spacer()
                }
            }
            .navigationTitle("Эквалайзер и Звук")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule()))
                }
            }
        }
    }
}

// MARK: - Native AirPlay Route Picker Wrapper

public struct AirPlayRoutePickerButton: UIViewRepresentable {
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.white.withAlphaComponent(0.65)
        picker.activeTintColor = .white
        return picker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Artist Chip Avatar with Yandex Music Card Parsing

public struct ArtistChipAvatarView: View {
    public var artistName: String
    public var fallbackAvatarUrl: String?
    @State private var avatarUrl: String? = nil

    public init(artistName: String, fallbackAvatarUrl: String? = nil) {
        self.artistName = artistName
        self.fallbackAvatarUrl = fallbackAvatarUrl
    }

    public var body: some View {
        ZStack {
            if let targetUrl = avatarUrl ?? fallbackAvatarUrl, let url = URL(string: targetUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackPlaceholder
                    @unknown default:
                        fallbackPlaceholder
                    }
                }
            } else {
                fallbackPlaceholder
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .task(id: artistName) {
            if let yandexAvatar = await YandexMusicService.shared.fetchArtistAvatar(artistName: artistName) {
                await MainActor.run {
                    self.avatarUrl = yandexAvatar
                }
            }
        }
    }

    private var fallbackPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.18))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }
}
