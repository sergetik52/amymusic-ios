import SwiftUI
import AVKit

// MARK: - Active Audio & Bluetooth Route Tracker
@Observable
@MainActor
public final class AudioRouteTracker {
    public static let shared = AudioRouteTracker()

    public var currentDeviceName: String = "Динамик iPhone"
    public var currentDeviceIcon: String = "iphone"
    public var isBluetoothOrAirPlay: Bool = false

    private init() {
        updateRoute()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateRoute()
        }
    }

    public func updateRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        guard let output = route.outputs.first else {
            currentDeviceName = "Динамик iPhone"
            currentDeviceIcon = "iphone"
            isBluetoothOrAirPlay = false
            return
        }

        let portType = output.portType
        let portName = output.portName

        switch portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            isBluetoothOrAirPlay = true
            currentDeviceName = portName
            let lower = portName.lowercased()
            if lower.contains("max") {
                currentDeviceIcon = "airpodsmax"
            } else if lower.contains("pro") {
                currentDeviceIcon = "airpodspro"
            } else if lower.contains("airpod") {
                currentDeviceIcon = "airpods"
            } else if lower.contains("beats") {
                currentDeviceIcon = "beats.headphones"
            } else {
                currentDeviceIcon = "headphones"
            }

        case .airPlay:
            isBluetoothOrAirPlay = true
            currentDeviceName = portName
            currentDeviceIcon = "airplayaudio"

        case .headphones:
            isBluetoothOrAirPlay = true
            currentDeviceName = portName.isEmpty ? "Наушники" : portName
            currentDeviceIcon = "headphones"

        case .builtInSpeaker, .builtInReceiver:
            isBluetoothOrAirPlay = false
            currentDeviceName = "Динамик iPhone"
            currentDeviceIcon = "iphone"

        default:
            isBluetoothOrAirPlay = false
            currentDeviceName = portName.isEmpty ? "Динамик iPhone" : portName
            currentDeviceIcon = "speaker.wave.2.fill"
        }
    }
}

// MARK: - Full Player Overlay, Synced Lyrics Engine, Lyrics Context Menu, Queue Sheet & 10-Band Equalizer
// Port of src/components/FullPlayerOverlay.jsx, src/components/LyricsContextMenu.jsx & src/components/EqualizerModal.jsx

public enum FullPlayerCenterStageMode: String, CaseIterable, Identifiable {
    case song = "Песня"
    case lyrics = "Текст"

    public var id: String { rawValue }
}

public struct FullPlayerOverlayView: View {
    @Bindable var player: AudioPlayerManager
    @Binding var isPresented: Bool
    var onOpenArtist: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var stageMode: FullPlayerCenterStageMode = .song
    @State private var isLyricsConfigOpen: Bool = false
    @State private var isQueueOpen: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var dragDismissOffset: CGFloat = 0
    @State private var routeTracker = AudioRouteTracker.shared

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
                // Pure transparent obsidian background (independent of cover art)
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Bar: Non-overlapping layout with Circular Down Arrow + Centered Liquid Glass Switcher + Right Action Controls
                    HStack(alignment: .center, spacing: 8) {
                        // 1. Left Dismiss: Circular Down Arrow (No text)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isPresented = false
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .contentShape(Circle())
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                        .zIndex(50)

                        Spacer(minLength: 4)

                        // 2. Active Audio / Bluetooth Route Indicator (Tapping opens AirPlay / Bluetooth picker)
                        ZStack {
                            HStack(spacing: 6) {
                                Image(systemName: routeTracker.currentDeviceIcon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(routeTracker.isBluetoothOrAirPlay ? Color(hex: "#007AFF") : .white.opacity(0.85))

                                Text(routeTracker.currentDeviceName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .amyLiquidGlass(
                                in: Capsule(),
                                tint: routeTracker.isBluetoothOrAirPlay ? Color(hex: "#007AFF").opacity(0.22) : nil,
                                interactive: true
                            )

                            // Invisible AirPlay picker button overlay so tapping opens route selector
                            AirPlayRoutePickerButton()
                                .frame(height: 36)
                                .opacity(0.015)
                        }
                        .frame(maxWidth: 220)

                        Spacer(minLength: 4)

                        // 3. Right Action Controls (Lyrics Settings when in lyrics mode, symmetrical balance)
                        Group {
                            if stageMode == .lyrics {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isLyricsConfigOpen = true
                                } label: {
                                    Image(systemName: "textformat.size")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(AppleLiquidGlassButtonStyle(shape: Circle()))
                            } else {
                                Color.clear
                                    .frame(width: 42, height: 42)
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

                        AmyAsyncImage(url: URL(string: track?.coverUrl ?? "")) { img in
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

                        // Native Apple Media Scrubber (Safari Video & Control Center Style)
                        AppleMediaScrubberView(
                            currentTime: player.currentTime,
                            duration: totalDuration,
                            isScrubbing: $isScrubbing,
                            scrubTime: $scrubTime,
                            onCommit: { target in
                                player.seek(to: target)
                            }
                        )

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

                        // Bottom Utility Row: Repeat, AirPlay, Lyrics Toggle (Center), Queue, Shuffle
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

                            // Center Lyrics Toggle Button (shows lyrics on tap, shows cover on second tap)
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    stageMode = (stageMode == .lyrics) ? .song : .lyrics
                                }
                            } label: {
                                Image(systemName: stageMode == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(stageMode == .lyrics ? .white : .white.opacity(0.70))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AppleLiquidGlassButtonStyle(
                                shape: Circle(),
                                tintColor: stageMode == .lyrics ? Color(hex: player.settings.themePreset.primaryHex).opacity(0.40) : nil,
                                isFilledAccent: stageMode == .lyrics
                            ))

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

// MARK: - Native Apple Media Scrubber (Safari Video & Control Center Style)
// MARK: - Native Apple Media Scrubber (Safari Video & Control Center Style)
public struct AppleMediaScrubberView: View {
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    @Binding public var isScrubbing: Bool
    @Binding public var scrubTime: TimeInterval
    public let onCommit: (TimeInterval) -> Void

    @State private var showRemainingTime: Bool = true
    @State private var localDragProgress: CGFloat? = nil

    public var body: some View {
        let safeDuration = max(1.0, duration)
        // Instant 120Hz drag tracking: localDragProgress eliminates timer updates and prevents jitter
        let progress: CGFloat = {
            if let drag = localDragProgress {
                return min(max(0.0, drag), 1.0)
            } else if isScrubbing {
                return min(max(0.0, CGFloat(scrubTime / safeDuration)), 1.0)
            } else {
                return min(max(0.0, CGFloat(currentTime / safeDuration)), 1.0)
            }
        }()

        let activeTime = safeDuration * Double(progress)

        VStack(spacing: 8) {
            // Interactive Scrubber Bar
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let height = proxy.size.height
                let currentTrackHeight: CGFloat = isScrubbing ? 9.0 : 4.5
                let thumbDiameter: CGFloat = isScrubbing ? 16.0 : 7.0
                let currentProgressX = min(max(0.0, width * progress), width)

                ZStack(alignment: .leading) {
                    // 1. Inactive Background Track (Translucent pill)
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: currentTrackHeight)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: currentTrackHeight)

                    // 2. Active Elapsed Track (Solid white pill - follows finger with 0ms delay)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: currentProgressX, height: currentTrackHeight)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: currentTrackHeight)

                    // 3. Apple Scrubber Thumb Knob (Centered on progress point so diameter expansion never shifts its center)
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: Color.black.opacity(isScrubbing ? 0.35 : 0.15), radius: isScrubbing ? 4 : 2, x: 0, y: 1)
                        .position(x: min(max(thumbDiameter / 2, currentProgressX), width - thumbDiameter / 2), y: height / 2)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: thumbDiameter)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let clamped = min(max(0.0, val.location.x / width), 1.0)
                            localDragProgress = clamped
                            scrubTime = safeDuration * Double(clamped)

                            if !isScrubbing {
                                isScrubbing = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        .onEnded { val in
                            let clamped = min(max(0.0, val.location.x / width), 1.0)
                            let finalTarget = safeDuration * Double(clamped)

                            localDragProgress = nil
                            onCommit(finalTarget)
                            isScrubbing = false
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                )
            }
            .frame(height: 32)

            // Timestamps: Left Elapsed, Right Remaining (tap to toggle duration)
            HStack {
                Text(formatTime(activeTime))

                Spacer()

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showRemainingTime.toggle()
                } label: {
                    if showRemainingTime {
                        let remaining = max(0.0, safeDuration - activeTime)
                        Text("-\(formatTime(remaining))")
                    } else {
                        Text(formatTime(safeDuration))
                    }
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.60))
        }
    }

    private func formatTime(_ secs: TimeInterval) -> String {
        guard secs.isFinite && secs >= 0 else { return "0:00" }
        let s = Int(secs.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
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
            KaraokeActiveLineView(
                line: line,
                fontSize: baseFontSize,
                accentColor: Color(hex: palette.bright),
                hasAnnotation: hasAnnotation,
                player: player
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
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

// MARK: - WordFlowLayout for Native Apple Music Karaoke Flow
private struct WordFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6.5
    var verticalSpacing: CGFloat = 6.0

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
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
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
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }
    }
}

// MARK: - Native Apple Music Karaoke Word (No background box, silky glyph fill, permanent volume elevation)
private struct KaraokeWordView: View {
    let word: LyricWord
    let currentTime: TimeInterval
    let fontSize: CGFloat
    let accentColor: Color
    let isParenthesized: Bool

    var body: some View {
        let duration = max(0.08, word.endTime - word.startTime)
        let rawProgress = (currentTime - word.startTime) / duration
        let progress = min(max(0.0, rawProgress), 1.0)
        let isReached = currentTime >= word.startTime
        let isActivelySinging = rawProgress >= 0.0 && rawProgress < 1.0

        let font: Font = isParenthesized
            ? .system(size: max(12, fontSize - 2.5), weight: isReached ? .heavy : .bold, design: .rounded).italic()
            : .system(size: fontSize, weight: isReached ? .heavy : .bold, design: .rounded)

        // Gradient stops for smooth left-to-right fill applied directly to the font glyphs:
        let stops: [Gradient.Stop] = {
            if progress <= 0.0 {
                let dim = isParenthesized ? 0.22 : 0.32
                return [
                    .init(color: .white.opacity(dim), location: 0.0),
                    .init(color: .white.opacity(dim), location: 1.0)
                ]
            } else if progress >= 1.0 {
                return [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 1.0)
                ]
            } else {
                let feather: CGFloat = 0.16
                let start = max(0.0, CGFloat(progress) - feather / 2)
                let end = min(1.0, CGFloat(progress) + feather / 2)
                let dim = isParenthesized ? 0.22 : 0.32

                return [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: start),
                    .init(color: .white.opacity(dim), location: end),
                    .init(color: .white.opacity(dim), location: 1.0)
                ]
            }
        }()

        Text(word.text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    stops: stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Color.black.opacity(isReached ? 0.45 : 0.18), radius: 3, x: 0, y: 1.5)
            .shadow(
                color: isActivelySinging ? accentColor.opacity(0.60) : (isReached ? accentColor.opacity(0.20) : .clear),
                radius: isActivelySinging ? 8 : 4,
                x: 0,
                y: 0
            )
            .scaleEffect(isReached ? 1.06 : 1.0, anchor: .bottomLeading)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isReached)
    }
}

// MARK: - Active Karaoke Line with 60/120Hz ProMotion Smooth Timeline Synchronization
private struct KaraokeActiveLineView: View {
    let line: LyricLine
    let fontSize: CGFloat
    let accentColor: Color
    let hasAnnotation: Bool
    var player: AudioPlayerManager

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { _ in
            let offsetSeconds = player.currentTrackLyricsOffsetMs() / 1000.0
            let adjustedTime = player.preciseCurrentTime() + 0.08 - offsetSeconds

            WordFlowLayout(horizontalSpacing: 6.5, verticalSpacing: 6.0) {
                ForEach(line.words) { word in
                    let isParen = word.text.contains("(") || word.text.contains(")")
                    KaraokeWordView(
                        word: word,
                        currentTime: adjustedTime,
                        fontSize: fontSize,
                        accentColor: accentColor,
                        isParenthesized: isParen
                    )
                }

                if hasAnnotation {
                    Text(" ””")
                        .font(.system(size: max(13, fontSize - 2), weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: accentColor.opacity(0.50), radius: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

                            Picker("Источник текста", selection: $player.settings.preferredLyricsSource) {
                                ForEach(LyricsSourceKind.allCases) { src in
                                    Text(src.rawValue).tag(src)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: player.settings.preferredLyricsSource) { _, _ in
                                Task { await player.loadLyricsForCurrentTrack(forceRefresh: true) }
                            }
                        }

                        // 3. Sync Mode Switcher
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Режим синхронизации")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))

                            Picker("Режим синхронизации", selection: $player.settings.lyricsSyncMode) {
                                ForEach(LyricsSyncMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // 4. Style Switcher
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Стиль отображения текста")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))

                            Picker("Стиль отображения текста", selection: $player.settings.lyricsTextStyle) {
                                ForEach(LyricsTextStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
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
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await player.loadLyricsForCurrentTrack(forceRefresh: true) }
                            dismiss()
                        } label: {
                            Label("Обновить текст", systemImage: "arrow.clockwise")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(AppleLiquidGlassButtonStyle(shape: Capsule(), tintColor: .white, isFilledAccent: true))
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
                        .fontWeight(.bold)
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
                                AmyAsyncImage(url: URL(string: current.coverUrl ?? "")) { img in
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
                                        AmyAsyncImage(url: URL(string: track.coverUrl ?? "")) { img in
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
                        .fontWeight(.bold)
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
                        .fontWeight(.bold)
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
                AmyAsyncImage(url: url) { phase in
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
