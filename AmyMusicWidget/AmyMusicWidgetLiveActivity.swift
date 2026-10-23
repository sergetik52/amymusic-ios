import SwiftUI
#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import WidgetKit
import AppIntents

// MARK: - iOS 26 Interactive AppIntents for Widgets & Live Activity

@available(iOS 17.0, *)
public struct ToggleLikeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Лайк"
    public static let description = IntentDescription("Добавить или убрать трек из избранного")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.amymusic.toggleLike" as CFString),
            nil,
            nil,
            true
        )
        AmyMusicSharedStore.shared.updateLikeOptimistically()
        WidgetCenter.shared.reloadTimelines(ofKind: "AmyMusicPlayerWidget")
        return .result()
    }
}

@available(iOS 17.0, *)
public struct PlayPauseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Воспроизведение / Пауза"
    public static let description = IntentDescription("Переключить воспроизведение текущего трека")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.amymusic.togglePlayPause" as CFString),
            nil,
            nil,
            true
        )
        AmyMusicSharedStore.shared.updatePlayOptimistically()
        WidgetCenter.shared.reloadTimelines(ofKind: "AmyMusicPlayerWidget")
        return .result()
    }
}

@available(iOS 17.0, *)
public struct NextTrackIntent: AppIntent {
    public static let title: LocalizedStringResource = "Следующий трек"
    public static let description = IntentDescription("Переключить на следующий трек")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.amymusic.nextTrack" as CFString),
            nil,
            nil,
            true
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "AmyMusicPlayerWidget")
        return .result()
    }
}

@available(iOS 17.0, *)
public struct PreviousTrackIntent: AppIntent {
    public static let title: LocalizedStringResource = "Предыдущий трек"
    public static let description = IntentDescription("Переключить на предыдущий трек")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.amymusic.previousTrack" as CFString),
            nil,
            nil,
            true
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "AmyMusicPlayerWidget")
        return .result()
    }
}

// MARK: - Widget Bundle Entry Point

@main
struct AmyMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        AmyMusicLiveActivityWidget()
        AmyMusicPlayerWidget()
    }
}

// MARK: - AmyMusic Home & Lock Screen Widget

struct AmyMusicWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AmyMusicWidgetSnapshot
    let coverImage: UIImage?
}

struct AmyMusicTimelineProvider: TimelineProvider {
    typealias Entry = AmyMusicWidgetEntry

    func placeholder(in context: Context) -> AmyMusicWidgetEntry {
        AmyMusicWidgetEntry(date: Date(), snapshot: .placeholder, coverImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AmyMusicWidgetEntry) -> Void) {
        let snapshot = AmyMusicSharedStore.shared.loadSnapshot() ?? .placeholder
        let coverData = AmyMusicSharedStore.shared.loadCoverImageData()
        let image = coverData.flatMap { UIImage(data: $0) }
        completion(AmyMusicWidgetEntry(date: Date(), snapshot: snapshot, coverImage: image))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AmyMusicWidgetEntry>) -> Void) {
        let snapshot = AmyMusicSharedStore.shared.loadSnapshot() ?? .placeholder
        let coverData = AmyMusicSharedStore.shared.loadCoverImageData()
        let image = coverData.flatMap { UIImage(data: $0) }
        let entry = AmyMusicWidgetEntry(date: Date(), snapshot: snapshot, coverImage: image)
        
        // Refresh every 15 mins or when notified via Darwin/WidgetCenter
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct AmyMusicPlayerWidget: Widget {
    let kind: String = "AmyMusicPlayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AmyMusicTimelineProvider()) { entry in
            AmyMusicPlayerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AmyMusic Плеер")
        .description("Интерактивный плеер и очередь воспроизведения AmyMusic")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Root View & Family Dispatcher

struct AmyMusicPlayerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: AmyMusicWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallPlayerWidgetView(entry: entry)
            case .systemMedium:
                MediumPlayerWidgetView(entry: entry)
            case .systemLarge:
                LargePlayerWidgetView(entry: entry)
            case .accessoryInline:
                InlineLockScreenWidgetView(entry: entry)
            case .accessoryCircular:
                CircularLockScreenWidgetView(entry: entry)
            case .accessoryRectangular:
                RectangularLockScreenWidgetView(entry: entry)
            default:
                MediumPlayerWidgetView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            widgetContainerBackground
        }
        .widgetURL(URL(string: "amymusic://player"))
    }

    @ViewBuilder
    private var widgetContainerBackground: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge:
            if let uiImage = entry.coverImage {
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 20)
                        .overlay(Color.black.opacity(0.68))

                    LinearGradient(
                        colors: [
                            Color(hex: entry.snapshot.accentHex).opacity(0.3),
                            Color(hex: "#09090b").opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                LinearGradient(
                    colors: [Color(hex: entry.snapshot.accentHex).opacity(0.35), Color(hex: "#09090b")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        default:
            Color.clear
        }
    }
}

// MARK: - Small (2x2) Widget View

struct SmallPlayerWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: mini album cover + like button
            HStack(alignment: .top) {
                if let uiImage = entry.coverImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(hex: entry.snapshot.accentHex).opacity(0.4), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: entry.snapshot.accentHex))
                    }
                }

                Spacer()

                Button(intent: ToggleLikeIntent()) {
                    Image(systemName: entry.snapshot.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(entry.snapshot.isLiked ? Color(hex: "#FF3B30") : Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Track title & artist
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(entry.snapshot.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
            .padding(.bottom, 8)

            // Interactive Play / Pause capsule button
            Button(intent: PlayPauseIntent()) {
                HStack(spacing: 5) {
                    Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(entry.snapshot.isPlaying ? "Пауза" : "Играть")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(Color(hex: entry.snapshot.accentHex).opacity(0.9))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}

// MARK: - Live Ticking Progress Bar & Timecodes

struct WidgetProgressBarView: View {
    let snapshot: AmyMusicWidgetSnapshot

    var body: some View {
        let duration = max(1, snapshot.duration)
        let current = min(max(0, snapshot.currentTime), duration - 0.1)
        let startDate = snapshot.updatedAt.addingTimeInterval(-current)
        let endDate = startDate.addingTimeInterval(duration)
        let isLiveTicking = snapshot.isPlaying && endDate > Date()

        VStack(spacing: 3) {
            if isLiveTicking {
                ProgressView(
                    timerInterval: startDate...endDate,
                    countsDown: false
                )
                .tint(Color(hex: snapshot.accentHex))
                .scaleEffect(y: 0.85, anchor: .center)
            } else {
                ProgressView(
                    value: min(current, duration),
                    total: duration
                )
                .tint(Color(hex: snapshot.accentHex))
                .scaleEffect(y: 0.85, anchor: .center)
            }

            HStack {
                if isLiveTicking {
                    Text(timerInterval: startDate...endDate, pauseTime: nil, countsDown: false, showsHours: duration >= 3600)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(formatTime(current))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Text(formatTime(duration))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Medium (4x2) Widget View

struct MediumPlayerWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        HStack(spacing: 14) {
            // Left: Large album cover with rounded corners and neon glow
            ZStack {
                if let uiImage = entry.coverImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 106, height: 106)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(hex: entry.snapshot.accentHex).opacity(0.35), Color.black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 106, height: 106)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Color(hex: entry.snapshot.accentHex))
                        )
                }
            }

            // Right: Track info, progress bar with timecodes, and control buttons
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(entry.snapshot.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                // Live ticking progress bar & timecodes
                WidgetProgressBarView(snapshot: entry.snapshot)

                // Interactive Buttons: Previous, Play/Pause, Next, Like
                HStack(spacing: 16) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Button(intent: PlayPauseIntent()) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: entry.snapshot.accentHex))
                                .frame(width: 34, height: 34)
                            Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(intent: ToggleLikeIntent()) {
                        Image(systemName: entry.snapshot.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(entry.snapshot.isLiked ? Color(hex: "#FF3B30") : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Large (4x4) Widget View

struct LargePlayerWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        VStack(spacing: 12) {
            // Upper half: Player Hub
            HStack(spacing: 14) {
                if let uiImage = entry.coverImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: entry.snapshot.accentHex).opacity(0.25))
                        .frame(width: 82, height: 82)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color(hex: entry.snapshot.accentHex))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(entry.snapshot.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    WidgetProgressBarView(snapshot: entry.snapshot)
                        .padding(.top, 2)
                }
            }

            // Transport controls
            HStack(spacing: 24) {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Button(intent: PlayPauseIntent()) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: entry.snapshot.accentHex))
                            .frame(width: 38, height: 38)
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(intent: ToggleLikeIntent()) {
                    Image(systemName: entry.snapshot.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(entry.snapshot.isLiked ? Color(hex: "#FF3B30") : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.vertical, 2)

            // Lower half: Up Next Queue
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: entry.snapshot.accentHex))
                    Text("ДАЛЕЕ В ОЧЕРЕДИ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(0.5)
                    Spacer()
                }

                if entry.snapshot.queue.isEmpty {
                    VStack(spacing: 4) {
                        Spacer()
                        Text("Очередь воспроизведения пуста")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(entry.snapshot.queue.prefix(4).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(hex: entry.snapshot.accentHex).opacity(0.9))
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(formatTime(item.duration))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Lock Screen Accessory Views

struct InlineLockScreenWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        if entry.snapshot.isPlaying && !entry.snapshot.title.isEmpty && entry.snapshot.title != "AmyMusic" {
            Text("🎵 \(entry.snapshot.title) • \(entry.snapshot.artist)")
        } else {
            Text("🎵 AmyMusic")
        }
    }
}

struct CircularLockScreenWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(
                value: min(entry.snapshot.currentTime, max(1, entry.snapshot.duration)),
                in: 0...max(1, entry.snapshot.duration)
            ) {
                Image(systemName: entry.snapshot.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

struct RectangularLockScreenWidgetView: View {
    let entry: AmyMusicWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.snapshot.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(entry.snapshot.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            Text(entry.snapshot.artist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(
                value: min(entry.snapshot.currentTime, max(1, entry.snapshot.duration)),
                total: max(1, entry.snapshot.duration)
            )
            .padding(.top, 2)
        }
    }
}

// MARK: - Native iOS 26 Dynamic Island & Live Activity Configuration

struct AmyMusicLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AmyMusicActivityAttributes.self) { context in
            // Lock Screen / StandBy Live Activity Banner with Liquid Glass aesthetics
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: context.state.accentHex).opacity(0.35))
                        .frame(width: 48, height: 48)
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: context.state.accentHex))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(context.state.artist)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    ProgressView(
                        value: min(context.state.currentTime, context.state.duration),
                        total: max(1, context.state.duration)
                    )
                    .tint(Color(hex: context.state.accentHex))
                    .padding(.top, 4)
                }

                Spacer()

                Button(intent: ToggleLikeIntent()) {
                    Image(systemName: context.state.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(context.state.isLiked ? .white : .white.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .activityBackgroundTint(Color(hex: "#090909").opacity(0.88))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: context.state.accentHex))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 12) {
                        Button(intent: ToggleLikeIntent()) {
                            Image(systemName: context.state.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(context.state.isLiked ? .white : .white.opacity(0.65))
                        }
                        .buttonStyle(.plain)

                        Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        value: min(context.state.currentTime, context.state.duration),
                        total: max(1, context.state.duration)
                    )
                    .tint(Color(hex: context.state.accentHex))
                    .padding(.horizontal, 12)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(Color(hex: context.state.accentHex))
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(Color(hex: context.state.accentHex))
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(Color(hex: context.state.accentHex))
            }
        }
    }
}
#endif
