import Foundation
import SwiftUI

// MARK: - Core Track & Palette Models

public struct TrackPalette: Codable, Hashable, Sendable {
    public var base: String
    public var line: String
    public var bright: String
    public var shadow: String

    public static let defaultPalette = TrackPalette(
        base: "#18181b",
        line: "#ffffff",
        bright: "#f4f4f5",
        shadow: "#09090b"
    )

    public init(base: String, line: String, bright: String, shadow: String) {
        self.base = base
        self.line = line
        self.bright = bright
        self.shadow = shadow
    }
}

public struct ArtistRef: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatarUrl: String?
    public var permalinkUrl: String?

    public init(id: String = UUID().uuidString, name: String, avatarUrl: String? = nil, permalinkUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.permalinkUrl = permalinkUrl
    }
}

public enum TrackSource: String, Codable, Sendable {
    case soundcloud
    case yandex
}

public enum ChartProgress: String, Codable, Sendable {
    case up
    case down
    case same
    case new
}

public struct Track: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var rawId: String
    public var title: String
    public var artist: String
    public var artists: [ArtistRef]
    public var coverUrl: String?
    public var duration: TimeInterval // seconds
    public var streamUrl: String?
    public var transcodingUrl: String?
    public var isHls: Bool
    public var isSnippet: Bool
    public var isExplicit: Bool
    public var genre: String?
    public var tagList: String?
    public var playbackCount: Int
    public var likesCount: Int
    public var source: TrackSource
    public var palette: TrackPalette
    public var fetchedAt: Date?

    // Chart metadata (Yandex Top 100 / Trends)
    public var rawTitle: String?
    public var chartPosition: Int?
    public var chartProgress: ChartProgress?
    public var chartShift: Int?
    public var listenersCount: Int?
    // Uploader / Origin metadata (where the track was posted)
    public var uploaderId: String?
    public var uploaderName: String?

    public init(
        id: String,
        rawId: String? = nil,
        title: String,
        rawTitle: String? = nil,
        artist: String,
        artists: [ArtistRef] = [],
        uploaderId: String? = nil,
        uploaderName: String? = nil,
        coverUrl: String? = nil,
        duration: TimeInterval = 0,
        streamUrl: String? = nil,
        transcodingUrl: String? = nil,
        isHls: Bool = false,
        isSnippet: Bool = false,
        isExplicit: Bool = false,
        genre: String? = nil,
        tagList: String? = nil,
        playbackCount: Int = 0,
        likesCount: Int = 0,
        source: TrackSource = .soundcloud,
        palette: TrackPalette = .defaultPalette,
        fetchedAt: Date? = nil,
        chartPosition: Int? = nil,
        chartProgress: ChartProgress? = nil,
        chartShift: Int? = nil,
        listenersCount: Int? = nil
    ) {
        self.id = id
        self.rawId = rawId ?? id
        self.title = title
        self.rawTitle = rawTitle ?? title
        self.artist = artist
        self.artists = artists.isEmpty ? [ArtistRef(name: artist)] : artists
        self.uploaderId = uploaderId
        self.uploaderName = uploaderName
        self.coverUrl = coverUrl
        self.duration = duration
        self.streamUrl = streamUrl
        self.transcodingUrl = transcodingUrl
        self.isHls = isHls
        self.isSnippet = isSnippet
        self.isExplicit = isExplicit
        self.genre = genre
        self.tagList = tagList
        self.playbackCount = playbackCount
        self.likesCount = likesCount
        self.source = source
        self.palette = palette
        self.fetchedAt = fetchedAt
        self.chartPosition = chartPosition
        self.chartProgress = chartProgress
        self.chartShift = chartShift
        self.listenersCount = listenersCount
    }

    public var formattedDuration: String {
        guard duration.isFinite && duration > 0 else { return "0:00" }
        let total = Int(duration.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Releases, Playlists & Artists

public enum ReleaseKind: String, Codable, Sendable {
    case album = "Альбом"
    case single = "Сингл"
    case playlist = "Плейлист"
    case userPlaylist = "Мой плейлист"
}

public struct ReleaseItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var artistId: String?
    public var coverUrl: String?
    public var kind: ReleaseKind
    public var year: Int?
    public var releaseDateFormatted: String?
    public var trackCount: Int
    public var tracks: [Track]
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        artistId: String? = nil,
        coverUrl: String? = nil,
        kind: ReleaseKind = .album,
        year: Int? = nil,
        releaseDateFormatted: String? = nil,
        trackCount: Int = 0,
        tracks: [Track] = [],
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistId = artistId
        self.coverUrl = coverUrl
        self.kind = kind
        self.year = year
        self.releaseDateFormatted = releaseDateFormatted
        self.trackCount = max(trackCount, tracks.count)
        self.tracks = tracks
        self.isPinned = isPinned
    }
}

public struct ArtistProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var username: String
    public var avatarUrl: String?
    public var bannerUrl: String?
    public var bio: String?
    public var city: String?
    public var followersCount: Int
    public var trackCount: Int
    public var popularTracks: [Track]
    public var allTracks: [Track]
    public var latestRelease: ReleaseItem?
    public var latestReleases: [ReleaseItem]
    public var featTracks: [Track]
    public var albums: [ReleaseItem]
    public var singles: [ReleaseItem]
    public var playlists: [ReleaseItem]
    public var relatedArtists: [ArtistRef]
    public var tags: [String]

    public init(
        id: String,
        name: String,
        username: String,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        bio: String? = nil,
        city: String? = nil,
        followersCount: Int = 0,
        trackCount: Int = 0,
        popularTracks: [Track] = [],
        allTracks: [Track] = [],
        latestRelease: ReleaseItem? = nil,
        latestReleases: [ReleaseItem] = [],
        featTracks: [Track] = [],
        albums: [ReleaseItem] = [],
        singles: [ReleaseItem] = [],
        playlists: [ReleaseItem] = [],
        relatedArtists: [ArtistRef] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.bio = bio
        self.city = city
        self.followersCount = followersCount
        self.trackCount = trackCount
        self.popularTracks = popularTracks
        self.allTracks = allTracks.isEmpty ? popularTracks : allTracks
        self.latestRelease = latestRelease
        self.latestReleases = latestReleases
        self.featTracks = featTracks
        self.albums = albums
        self.singles = singles
        self.playlists = playlists
        self.relatedArtists = relatedArtists
        self.tags = tags
    }
}

// MARK: - Wave Seeds & Audio Analysis

public struct WaveSeed: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatarUrl: String?
    public var isArtist: Bool

    public init(id: String, name: String, avatarUrl: String? = nil, isArtist: Bool = true) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isArtist = isArtist
    }
}

public struct AudioEnergy: Equatable, Sendable {
    public var bass: Double
    public var mids: Double
    public var treble: Double
    public var level: Double

    public static let zero = AudioEnergy(bass: 0, mids: 0, treble: 0, level: 0)

    public init(bass: Double, mids: Double, treble: Double, level: Double) {
        self.bass = bass
        self.mids = mids
        self.treble = treble
        self.level = level
    }
}

// MARK: - Lyrics Models

public struct LyricWord: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
}

public struct LyricLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var time: TimeInterval
    public var text: String
    public var isEstimated: Bool
    public var annotationId: String?
    public var words: [LyricWord]
    public var hasVerseGap: Bool

    public init(
        id: String = UUID().uuidString,
        time: TimeInterval,
        text: String,
        isEstimated: Bool = false,
        annotationId: String? = nil,
        words: [LyricWord] = [],
        hasVerseGap: Bool = false
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.isEstimated = isEstimated
        self.annotationId = annotationId
        self.words = words
        self.hasVerseGap = hasVerseGap
    }
}

public enum LyricsSourceKind: String, Codable, CaseIterable, Sendable {
    case auto = "Авто"
    case lrclib = "LRCLib"
    case genius = "Genius"
}

public enum LyricsStatus: String, Codable, Sendable {
    case synced
    case plain
    case empty
}

public struct LyricsPayload: Codable, Hashable, Sendable {
    public var source: String
    public var status: LyricsStatus
    public var lines: [LyricLine]
    public var plainText: String
    public var annotations: [String: String]

    public static let empty = LyricsPayload(source: "none", status: .empty, lines: [], plainText: "", annotations: [:])
}

// MARK: - Equalizer & Player Settings

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case one
    case playlist
}

public enum EqualizerPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat = "Сброс"
    case bass = "Усиление баса"
    case vocal = "Вокал / Речь"
    case rock = "Рок"
    case pop = "Поп"
    case electronic = "Электроника"
    case acoustic = "Акустика"
    case jazz = "Джаз"
    case treble = "Высокие частоты"

    public var id: String { rawValue }

    public static let frequencies: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    public static let labels: [String] = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    public var gains: [Float] {
        switch self {
        case .flat:       return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass:       return [8, 6, 4, 2, 0, 0, 0, 0, 0, 0]
        case .vocal:      return [-2, -1, 1, 3, 5, 4, 3, 1, 0, -1]
        case .rock:       return [5, 4, 2, -1, -2, 1, 3, 5, 5, 4]
        case .pop:        return [-1, 2, 4, 5, 3, 0, -1, -2, 1, 2]
        case .electronic: return [7, 5, 3, 0, -2, 2, 4, 6, 5, 4]
        case .acoustic:   return [3, 2, 1, 2, 3, 3, 4, 4, 3, 2]
        case .jazz:       return [4, 3, 1, 2, -1, -1, 0, 2, 3, 4]
        case .treble:     return [0, 0, 0, 0, 0, 2, 4, 6, 8, 9]
        }
    }
}

// MARK: - Appearance & Customization Settings

public enum ThemePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case amy = "Amy White"
    case dotify = "Dotify Green"
    case cyberpunk = "Cyberpunk"
    case midnight = "Midnight"
    case oled = "OLED Pure"
    case sunset = "Sunset"

    public var id: String { rawValue }

    public var primaryHex: String {
        switch self {
        case .amy: return "#FFFFFF"
        case .dotify: return "#1DB954"
        case .cyberpunk: return "#FF007F"
        case .midnight: return "#3B82F6"
        case .oled: return "#FFFFFF"
        case .sunset: return "#F97316"
        }
    }

    public var secondaryHex: String {
        switch self {
        case .amy: return "#E4E4E7"
        case .dotify: return "#10B981"
        case .cyberpunk: return "#00F0FF"
        case .midnight: return "#6366F1"
        case .oled: return "#A1A1AA"
        case .sunset: return "#EC4899"
        }
    }
}

public enum AudioQualityTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case q192 = "192"
    case q256 = "256"
    case q320 = "320"
    case q1411 = "1411"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .q192: return "192 kbps (Эконом)"
        case .q256: return "256 kbps (Стандарт)"
        case .q320: return "320 kbps (Высокое)"
        case .q1411: return "1411 kbps 💎 (Lossless / HQ)"
        }
    }
}

public enum LyricsTextStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case blur = "Размытие"
    case scale = "Масштаб"
    case normal = "Обычный"

    public var id: String { rawValue }
}

public enum LyricsSyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case lines = "По строкам"
    case words = "По словам"

    public var id: String { rawValue }
}

public enum LyricsFontSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case sm
    case base
    case lg
    case xl

    public var id: String { rawValue }

    public var pointSize: CGFloat {
        switch self {
        case .sm: return 18
        case .base: return 22
        case .lg: return 27
        case .xl: return 32
        }
    }
}

public enum MiniPlayerStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case liquidGlass = "Liquid Glass"
    case waveform = "Волновой"
    case classic = "Классический"

    public var id: String { rawValue }
}

public struct AppProfileSettings: Codable, Equatable, Sendable {
    public var displayName: String = "Amy Listener"
    public var username: String = "amylistener"
    public var bio: String = "У вашей музыки есть цвет"
    public var avatarDataUrl: String? = nil

    // Theme & Visuals
    public var themePreset: ThemePreset = .amy
    public var glassTintIntensity: Double = 0.38
    public var miniPlayerStyle: MiniPlayerStyle = .liquidGlass
    public var coverCornerRadius: Double = 18
    public var fullPlayerGlowEnabled: Bool = true
    public var showWaveDNAVisualizer: Bool = true

    // Lyrics
    public var lyricsFontSize: LyricsFontSize = .lg
    public var lyricsTextStyle: LyricsTextStyle = .blur
    public var lyricsSyncMode: LyricsSyncMode = .words
    public var preferredLyricsSource: LyricsSourceKind = .auto

    // Audio
    public var audioQuality: AudioQualityTier = .q320
    public var crossfadeEnabled: Bool = true
    public var crossfadeSeconds: Double = 4.0
    public var gaplessPlayback: Bool = true
    public var volumeNormalization: Bool = false
    public var audioCacheEnabled: Bool = true
    public var liveActivityEnabled: Bool = false

    // Equalizer
    public var equalizerEnabled: Bool = false
    public var equalizerPreset: EqualizerPreset = .flat
    public var equalizerBands: [Float] = EqualizerPreset.flat.gains

    // Integrations / Developer
    public var soundCloudClientId: String = "yNSW5UvBmb1A5j7qPUtIMuB9Itx3jsOC"
    public var soundCloudClientSecret: String = ""
    public var customHttpProxies: String = ""
    public var yandexOAuthToken: String = ""
}

public struct IdentifiableArtistId: Identifiable, Hashable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

