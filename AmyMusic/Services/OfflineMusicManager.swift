import Foundation
import SwiftUI
import Observation

// MARK: - Downloaded Artist Summary Model

public struct DownloadedArtistSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatarUrl: String?
    public var trackCount: Int
    public var trackIds: [String]
    public var albumIds: [String]
    public var downloadedAt: Date

    public init(
        id: String,
        name: String,
        avatarUrl: String? = nil,
        trackCount: Int = 0,
        trackIds: [String] = [],
        albumIds: [String] = [],
        downloadedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.trackCount = max(trackCount, trackIds.count)
        self.trackIds = trackIds
        self.albumIds = albumIds
        self.downloadedAt = downloadedAt
    }
}

// MARK: - Offline Index Registry

public struct OfflineIndex: Codable, Sendable {
    public var tracks: [Track]
    public var albums: [ReleaseItem]
    public var playlists: [ReleaseItem]
    public var artists: [DownloadedArtistSummary]
    public var trackDownloadedAt: [String: Date]

    public init(
        tracks: [Track] = [],
        albums: [ReleaseItem] = [],
        playlists: [ReleaseItem] = [],
        artists: [DownloadedArtistSummary] = [],
        trackDownloadedAt: [String: Date] = [:]
    ) {
        self.tracks = tracks
        self.albums = albums
        self.playlists = playlists
        self.artists = artists
        self.trackDownloadedAt = trackDownloadedAt
    }
}

// MARK: - Offline Music Manager (Local Storage, Downloader & Offline Library)

@Observable
@MainActor
public final class OfflineMusicManager {
    public static let shared = OfflineMusicManager()

    // Downloaded Media Registry
    public private(set) var downloadedTracks: [Track] = []
    public private(set) var downloadedAlbums: [ReleaseItem] = []
    public private(set) var downloadedPlaylists: [ReleaseItem] = []
    public private(set) var downloadedArtists: [DownloadedArtistSummary] = []

    // Active Download State
    public private(set) var downloadingItemIds: Set<String> = []
    public private(set) var downloadProgressMap: [String: Double] = [:]
    public private(set) var currentDownloadTitle: String? = nil
    public private(set) var currentDownloadSubtitle: String? = nil

    // Storage Size
    public private(set) var totalStorageFormatted: String = "0 МБ"
    public private(set) var totalStorageBytes: Int64 = 0

    // File Directories
    private let rootFolder: URL
    private let tracksFolder: URL
    private let metadataFolder: URL
    private let lyricsFolder: URL
    private let coversFolder: URL
    private let indexFile: URL

    private var currentDownloadTask: Task<Void, Never>? = nil

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("OfflineMusic", isDirectory: true)
        self.rootFolder = root
        self.tracksFolder = root.appendingPathComponent("tracks", isDirectory: true)
        self.metadataFolder = root.appendingPathComponent("metadata", isDirectory: true)
        self.lyricsFolder = root.appendingPathComponent("lyrics", isDirectory: true)
        self.coversFolder = root.appendingPathComponent("covers", isDirectory: true)
        self.indexFile = root.appendingPathComponent("index.json")

        createDirectoriesIfNeeded()
        loadIndex()
        recalculateStorageSize()
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        let dirs = [rootFolder, tracksFolder, metadataFolder, lyricsFolder, coversFolder]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Index Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFile),
              let index = try? JSONDecoder().decode(OfflineIndex.self, from: data) else {
            return
        }
        // Verify audio file actually exists on disk for each track
        let fm = FileManager.default
        let verifiedTracks = index.tracks.filter { track in
            let path = trackFilePath(for: track.id).path
            return fm.fileExists(atPath: path)
        }

        self.downloadedTracks = verifiedTracks
        self.downloadedAlbums = index.albums
        self.downloadedPlaylists = index.playlists
        self.downloadedArtists = index.artists
    }

    private func saveIndex() {
        let index = OfflineIndex(
            tracks: downloadedTracks,
            albums: downloadedAlbums,
            playlists: downloadedPlaylists,
            artists: downloadedArtists,
            trackDownloadedAt: [:]
        )
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexFile, options: .atomic)
        }
        recalculateStorageSize()
    }

    public func recalculateStorageSize() {
        let fm = FileManager.default
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: rootFolder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    total += Int64(size)
                }
            }
        }
        self.totalStorageBytes = total
        self.totalStorageFormatted = Self.formatBytes(total)
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.1f ГБ", mb / 1024.0)
        } else if mb >= 1.0 {
            return String(format: "%.1f МБ", mb)
        } else if bytes > 0 {
            return String(format: "%.0f КБ", Double(bytes) / 1024.0)
        }
        return "0 МБ"
    }

    // MARK: - Path Helpers

    public func trackFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return tracksFolder.appendingPathComponent("\(safeId).mp3")
    }

    public func coverFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return coversFolder.appendingPathComponent("\(safeId).jpg")
    }

    public func lyricsFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return lyricsFolder.appendingPathComponent("\(safeId).json")
    }

    public func metadataFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return metadataFolder.appendingPathComponent("\(safeId).json")
    }

    private func sanitizeId(_ raw: String) -> String {
        return raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }

    // MARK: - Query Status

    public func isTrackDownloaded(_ trackId: String) -> Bool {
        let path = trackFilePath(for: trackId).path
        return FileManager.default.fileExists(atPath: path) && downloadedTracks.contains(where: { $0.id == trackId })
    }

    public func isReleaseDownloaded(_ releaseId: String) -> Bool {
        if let album = downloadedAlbums.first(where: { $0.id == releaseId }) {
            return !album.tracks.isEmpty && album.tracks.allSatisfy { isTrackDownloaded($0.id) }
        }
        if let pl = downloadedPlaylists.first(where: { $0.id == releaseId }) {
            return !pl.tracks.isEmpty && pl.tracks.allSatisfy { isTrackDownloaded($0.id) }
        }
        return false
    }

    public func isArtistDownloaded(_ artistId: String) -> Bool {
        guard let summary = downloadedArtists.first(where: { $0.id == artistId }) else { return false }
        return !summary.trackIds.isEmpty && summary.trackIds.allSatisfy { isTrackDownloaded($0) }
    }

    public func isDownloading(_ id: String) -> Bool {
        downloadingItemIds.contains(id)
    }

    public func downloadProgress(for id: String) -> Double? {
        downloadProgressMap[id]
    }

    public func localAudioFileUrl(for trackId: String) -> URL? {
        let url = trackFilePath(for: trackId)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    public func localLyrics(for trackId: String) -> LyricsPayload? {
        let url = lyricsFilePath(for: trackId)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LyricsPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    // MARK: - Download Single Track

    @discardableResult
    public func downloadTrack(_ track: Track) async -> Bool {
        let trackId = track.id
        guard !isTrackDownloaded(trackId) else { return true }

        downloadingItemIds.insert(trackId)
        downloadProgressMap[trackId] = 0.05
        currentDownloadTitle = track.title
        currentDownloadSubtitle = track.artist

        defer {
            downloadingItemIds.remove(trackId)
            downloadProgressMap.removeValue(forKey: trackId)
            if downloadingItemIds.isEmpty {
                currentDownloadTitle = nil
                currentDownloadSubtitle = nil
            }
        }

        // 1. Resolve Audio Stream URL
        var targetTrack = track
        if targetTrack.source == .yandex {
            if let bridged = await YandexMusicService.shared.resolvePlayableSoundCloudTrack(for: targetTrack) {
                targetTrack = bridged
            }
        } else if targetTrack.source == .spotify {
            if let bridged = await SpotifyService.shared.resolvePlayableSoundCloudTrack(for: targetTrack) {
                targetTrack = bridged
            }
        }

        guard let resolved = await SoundCloudService.shared.resolveStreamUrl(for: targetTrack) else {
            return false
        }

        downloadProgressMap[trackId] = 0.20

        // 2. Download Audio Stream
        let destUrl = trackFilePath(for: trackId)
        let downloadSuccess: Bool
        if resolved.isHls {
            downloadSuccess = await downloadHlsStream(m3u8UrlString: resolved.url, destinationUrl: destUrl, trackId: trackId)
        } else {
            downloadSuccess = await downloadProgressiveFile(urlString: resolved.url, destinationUrl: destUrl, trackId: trackId)
        }

        guard downloadSuccess else { return false }
        downloadProgressMap[trackId] = 0.85

        // 3. Cache Cover Artwork locally
        if let coverUrlStr = track.coverUrl, let coverUrl = URL(string: coverUrlStr) {
            let coverDest = coverFilePath(for: trackId)
            if let (tempCover, _) = try? await URLSession.shared.download(from: coverUrl) {
                try? FileManager.default.removeItem(at: coverDest)
                try? FileManager.default.moveItem(at: tempCover, to: coverDest)
            }
        }

        // 4. Download & Cache Lyrics locally
        let lyrics = await LyricsService.shared.fetchLyrics(for: track)
        if lyrics.status != .empty, let lyricsData = try? JSONEncoder().encode(lyrics) {
            try? lyricsData.write(to: lyricsFilePath(for: trackId), options: .atomic)
        }

        // 5. Save Track Metadata JSON
        var localTrack = track
        localTrack.streamUrl = destUrl.absoluteString
        localTrack.fetchedAt = Date()
        if let metaData = try? JSONEncoder().encode(localTrack) {
            try? metaData.write(to: metadataFilePath(for: trackId), options: .atomic)
        }

        // 6. Update Registry
        if !downloadedTracks.contains(where: { $0.id == track.id }) {
            downloadedTracks.insert(localTrack, at: 0)
        }
        saveIndex()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }

    private func downloadProgressiveFile(urlString: String, destinationUrl: URL, trackId: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            let (tempUrl, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return false
            }
            try? FileManager.default.removeItem(at: destinationUrl)
            try FileManager.default.moveItem(at: tempUrl, to: destinationUrl)
            return true
        } catch {
            return false
        }
    }

    private func downloadHlsStream(m3u8UrlString: String, destinationUrl: URL, trackId: String) async -> Bool {
        guard let m3u8Url = URL(string: m3u8UrlString) else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: m3u8Url)
            guard let playlistText = String(data: data, encoding: .utf8) else { return false }

            let lines = playlistText.components(separatedBy: .newlines)
            var segmentUrls: [URL] = []
            let baseUrl = m3u8Url.deletingLastPathComponent()

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                if let fullUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                    segmentUrls.append(fullUrl)
                }
            }

            guard !segmentUrls.isEmpty else { return false }

            // Download each audio segment and concatenate into one contiguous file
            var assembledData = Data()
            for (idx, segUrl) in segmentUrls.enumerated() {
                let (segData, _) = try await URLSession.shared.data(from: segUrl)
                assembledData.append(segData)
                let p = 0.20 + (0.65 * (Double(idx + 1) / Double(segmentUrls.count)))
                downloadProgressMap[trackId] = p
            }

            guard !assembledData.isEmpty else { return false }
            try? FileManager.default.removeItem(at: destinationUrl)
            try assembledData.write(to: destinationUrl, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Download Album or Playlist

    public func downloadRelease(_ release: ReleaseItem) async {
        let releaseId = release.id
        guard !downloadingItemIds.contains(releaseId) else { return }

        downloadingItemIds.insert(releaseId)
        currentDownloadTitle = release.title
        currentDownloadSubtitle = release.artist

        defer {
            downloadingItemIds.remove(releaseId)
            downloadProgressMap.removeValue(forKey: releaseId)
            if downloadingItemIds.isEmpty {
                currentDownloadTitle = nil
                currentDownloadSubtitle = nil
            }
        }

        let total = release.tracks.count
        guard total > 0 else { return }

        for (index, track) in release.tracks.enumerated() {
            currentDownloadSubtitle = "\(release.artist) • \(index + 1) из \(total)"
            downloadProgressMap[releaseId] = Double(index) / Double(total)
            await downloadTrack(track)
        }

        // Register in downloaded releases
        if release.kind == .album || release.kind == .single {
            if !downloadedAlbums.contains(where: { $0.id == release.id }) {
                downloadedAlbums.insert(release, at: 0)
            }
        } else {
            if !downloadedPlaylists.contains(where: { $0.id == release.id }) {
                downloadedPlaylists.insert(release, at: 0)
            }
        }

        saveIndex()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Download Artist Card (Popular Tracks + Albums & Singles)

    public func downloadArtist(
        artistId: String,
        name: String,
        avatarUrl: String?,
        profile: ArtistProfile?
    ) async {
        guard !downloadingItemIds.contains(artistId) else { return }

        downloadingItemIds.insert(artistId)
        currentDownloadTitle = name
        currentDownloadSubtitle = "Подготовка треков артиста..."

        defer {
            downloadingItemIds.remove(artistId)
            downloadProgressMap.removeValue(forKey: artistId)
            if downloadingItemIds.isEmpty {
                currentDownloadTitle = nil
                currentDownloadSubtitle = nil
            }
        }

        // Gather all artist tracks (popular + all releases)
        var allTracksToDownload: [Track] = []
        var albumIds: [String] = []

        if let profile {
            allTracksToDownload.append(contentsOf: profile.popularTracks)
            for album in profile.albums + profile.singles {
                albumIds.append(album.id)
                allTracksToDownload.append(contentsOf: album.tracks)
                if !downloadedAlbums.contains(where: { $0.id == album.id }) {
                    downloadedAlbums.append(album)
                }
            }
        }

        // Deduplicate tracks
        var uniqueTracks: [Track] = []
        var seenIds = Set<String>()
        for t in allTracksToDownload {
            if !seenIds.contains(t.id) {
                seenIds.insert(t.id)
                uniqueTracks.append(t)
            }
        }

        let total = uniqueTracks.count
        guard total > 0 else { return }

        for (idx, track) in uniqueTracks.enumerated() {
            currentDownloadSubtitle = "\(name) • \(idx + 1) из \(total)"
            downloadProgressMap[artistId] = Double(idx) / Double(total)
            await downloadTrack(track)
        }

        let summary = DownloadedArtistSummary(
            id: artistId,
            name: name,
            avatarUrl: avatarUrl,
            trackCount: uniqueTracks.count,
            trackIds: uniqueTracks.map(\.id),
            albumIds: albumIds,
            downloadedAt: Date()
        )

        downloadedArtists.removeAll { $0.id == artistId }
        downloadedArtists.insert(summary, at: 0)

        saveIndex()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Deletion

    public func deleteTrack(id: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: trackFilePath(for: id))
        try? fm.removeItem(at: coverFilePath(for: id))
        try? fm.removeItem(at: lyricsFilePath(for: id))
        try? fm.removeItem(at: metadataFilePath(for: id))

        downloadedTracks.removeAll { $0.id == id }

        // Update albums and playlists if needed
        downloadedAlbums = downloadedAlbums.filter { album in
            album.tracks.contains { isTrackDownloaded($0.id) }
        }
        downloadedPlaylists = downloadedPlaylists.filter { pl in
            pl.tracks.contains { isTrackDownloaded($0.id) }
        }
        downloadedArtists = downloadedArtists.filter { artist in
            artist.trackIds.contains { isTrackDownloaded($0) }
        }

        saveIndex()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func deleteRelease(id: String) {
        if let album = downloadedAlbums.first(where: { $0.id == id }) {
            for t in album.tracks {
                // If track is not part of other downloaded items, remove it
                deleteTrack(id: t.id)
            }
            downloadedAlbums.removeAll { $0.id == id }
        } else if let pl = downloadedPlaylists.first(where: { $0.id == id }) {
            for t in pl.tracks {
                deleteTrack(id: t.id)
            }
            downloadedPlaylists.removeAll { $0.id == id }
        }
        saveIndex()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func deleteArtist(id: String) {
        if let artist = downloadedArtists.first(where: { $0.id == id }) {
            for trackId in artist.trackIds {
                deleteTrack(id: trackId)
            }
            downloadedArtists.removeAll { $0.id == id }
        }
        saveIndex()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func deleteAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: rootFolder)
        createDirectoriesIfNeeded()
        downloadedTracks.removeAll()
        downloadedAlbums.removeAll()
        downloadedPlaylists.removeAll()
        downloadedArtists.removeAll()
        saveIndex()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
