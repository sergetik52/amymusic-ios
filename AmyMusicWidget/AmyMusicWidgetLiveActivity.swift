import SwiftUI
#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import WidgetKit
import AppIntents

// MARK: - iOS 26 Dynamic Island & Lock Screen Live Activity Widget
// Interactive Now Playing with favorite toggling via AppIntent & Darwin IPC

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
        return .result()
    }
}

@main
struct AmyMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        AmyMusicLiveActivityWidget()
    }
}

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
