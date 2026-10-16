import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
#endif

// MARK: - Native iOS 26 Dynamic Island & Live Activity (Port of src/components/GameOverlay.jsx)

#if canImport(ActivityKit)
public struct AmyMusicActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var coverUrl: String?
        public var isPlaying: Bool
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var accentHex: String
        public var bassLevel: Double
        public var isLiked: Bool
    }

    public var sessionName: String = "AmyMusic"
    public init() {}
}
#endif

@MainActor
public final class AmyMusicLiveActivityController {
    public static let shared = AmyMusicLiveActivityController()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<AmyMusicActivityAttributes>?
    #endif

    public func update(
        track: Track,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        energy: AudioEnergy,
        isLiked: Bool = false
    ) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = AmyMusicActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            coverUrl: track.coverUrl,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: max(1, duration),
            accentHex: track.palette.line,
            bassLevel: energy.bass,
            isLiked: isLiked
        )

        if let activity = currentActivity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            do {
                let attributes = AmyMusicActivityAttributes()
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // Live Activity not supported in current simulator/environment
            }
        }
        #endif
    }

    public func end() {
        #if canImport(ActivityKit)
        if let activity = currentActivity {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
        #endif
    }

    public func endAll() {
        #if canImport(ActivityKit)
        for act in Activity<AmyMusicActivityAttributes>.activities {
            Task {
                await act.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        #endif
    }
}
