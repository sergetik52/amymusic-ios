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

// MARK: - Shared Widget Models & Persistence

public struct WidgetQueueItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var duration: TimeInterval

    public init(id: String, title: String, artist: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

public struct AmyMusicWidgetSnapshot: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var coverUrl: String?
    public var isPlaying: Bool
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var accentHex: String
    public var isLiked: Bool
    public var queue: [WidgetQueueItem]
    public var updatedAt: Date

    public init(
        title: String,
        artist: String,
        coverUrl: String? = nil,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        accentHex: String = "#9945FF",
        isLiked: Bool = false,
        queue: [WidgetQueueItem] = [],
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.coverUrl = coverUrl
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.accentHex = accentHex
        self.isLiked = isLiked
        self.queue = queue
        self.updatedAt = updatedAt
    }

    public static let placeholder = AmyMusicWidgetSnapshot(
        title: "AmyMusic",
        artist: "Включить музыку",
        coverUrl: nil,
        isPlaying: false,
        currentTime: 0,
        duration: 0,
        accentHex: "#9945FF",
        isLiked: false,
        queue: [],
        updatedAt: Date()
    )
}

public final class AmyMusicSharedStore: @unchecked Sendable {
    public static let shared = AmyMusicSharedStore()
    private let service = "com.amymusic.shared"
    private let stateAccount = "widgetState"
    private let coverAccount = "widgetCover"
    private let accessGroup = "M5LW4HM9AJ.com.amymusic.ios"

    private init() {}

    public func saveSnapshot(_ snapshot: AmyMusicWidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            saveKeychain(data: data, account: stateAccount)
        }
    }

    public func loadSnapshot() -> AmyMusicWidgetSnapshot? {
        if let data = loadKeychain(account: stateAccount),
           let snapshot = try? JSONDecoder().decode(AmyMusicWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    public func saveCoverImageData(_ data: Data) {
        saveKeychain(data: data, account: coverAccount)
    }

    public func loadCoverImageData() -> Data? {
        return loadKeychain(account: coverAccount)
    }

    public func updateLikeOptimistically() {
        if var snap = loadSnapshot() {
            snap.isLiked.toggle()
            snap.updatedAt = Date()
            saveSnapshot(snap)
        }
    }

    public func updatePlayOptimistically() {
        if var snap = loadSnapshot() {
            snap.isPlaying.toggle()
            snap.updatedAt = Date()
            saveSnapshot(snap)
        }
    }

    private func saveKeychain(data: Data, account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKeychain(account: String) -> Data? {
        let queryWithGroup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(queryWithGroup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return data
        }
        return nil
    }
}


