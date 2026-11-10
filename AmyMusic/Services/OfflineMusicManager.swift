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

    // MARK: - Index Persistence & Integrity Check

    public func isAudioFileValid(at url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let attr = try? fm.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64, size >= 100_000 else {
            return false
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let header = handle.readData(ofLength: 64)
        handle.closeFile()
        guard header.count >= 4 else { return false }

        // Valid MP3: starts with ID3 ('I', 'D', '3')
        if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
            return true
        }
        // Valid MP3: MPEG sync bits (11 bits set: 0xFF, 0xEx or 0xFx)
        if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
            return true
        }
        // Valid M4A / MP4 / AAC: [4 bytes size] 'ftyp'
        if header.count >= 8 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70 {
            return true
        }
        // Valid CMAF / fMP4 segment: [4 bytes size] 'styp', 'moov', 'moof', 'mdat'
        if header.count >= 8 {
            let tag = String(bytes: header[4...7], encoding: .ascii) ?? ""
            if tag == "styp" || tag == "moov" || tag == "moof" || tag == "mdat" {
                return true
            }
        }
        // Valid MPEG-TS: starts with 0x47 sync byte
        if header[0] == 0x47 {
            return true
        }
        // Valid ADTS AAC: starts with 0xFF, 0xF1 or 0xFF, 0xF9
        if header[0] == 0xFF && (header[1] & 0xF6) == 0xF0 {
            return true
        }
        // Valid Ogg / Opus / Vorbis ('O', 'g', 'g', 'S')
        if header[0] == 0x4F && header[1] == 0x47 && header[2] == 0x47 && header[3] == 0x53 {
            return true
        }
        // Valid FLAC ('f', 'L', 'a', 'C')
        if header[0] == 0x66 && header[1] == 0x4C && header[2] == 0x61 && header[3] == 0x43 {
            return true
        }

        // Rejection check: ensure it is not an HTML block page or error JSON
        let sample = String(data: header, encoding: .utf8)?.lowercased() ?? ""
        if sample.contains("<html") || sample.contains("<!doc") || sample.contains("{\"err") || sample.contains("#extm3u") {
            return false
        }
        return true
    }

    private func cleanupAndMigrateTracks() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: tracksFolder, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for item in items {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let dirName = item.lastPathComponent
                    let targetM4a = tracksFolder.appendingPathComponent("\(dirName).m4a")
                    let initFile = item.appendingPathComponent("init.mp4")
                    if fm.fileExists(atPath: initFile.path), let initData = try? Data(contentsOf: initFile) {
                        if let segFiles = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                            let segs = segFiles.filter { $0.lastPathComponent.hasPrefix("seg_") }
                                .sorted { a, b in
                                    let numA = Int(a.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "seg_", with: "")) ?? 0
                                    let numB = Int(b.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "seg_", with: "")) ?? 0
                                    return numA < numB
                                }
                            if !segs.isEmpty {
                                var assembled = initData
                                for seg in segs {
                                    if let segData = try? Data(contentsOf: seg) {
                                        assembled.append(segData)
                                    }
                                }
                                if assembled.count >= 100_000 {
                                    try? assembled.write(to: targetM4a, options: .atomic)
                                }
                            }
                        }
                    }
                    // Remove old segment directory after migration
                    try? fm.removeItem(at: item)
                } else {
                    let ext = item.pathExtension.lowercased()
                    if ext == "mp3" || ext == "m4a" {
                        if !isAudioFileValid(at: item) {
                            try? fm.removeItem(at: item)
                        }
                    }
                }
            }
        }
    }

    private func loadIndex() {
        cleanupAndMigrateTracks()
        guard let data = try? Data(contentsOf: indexFile),
              let index = try? JSONDecoder().decode(OfflineIndex.self, from: data) else {
            return
        }
        let fm = FileManager.default
        var verifiedTracks = index.tracks.filter { track in
            let m4a = m4aFilePath(for: track.id)
            let mp3 = trackFilePath(for: track.id)
            return (fm.fileExists(atPath: m4a.path) && isAudioFileValid(at: m4a))
                || (fm.fileExists(atPath: mp3.path) && isAudioFileValid(at: mp3))
        }

        // Recover any tracks that have metadata JSON and valid audio on disk
        if let metaFiles = try? fm.contentsOfDirectory(at: metadataFolder, includingPropertiesForKeys: nil) {
            for metaFile in metaFiles where metaFile.pathExtension == "json" {
                let trackId = metaFile.deletingPathExtension().lastPathComponent
                if !verifiedTracks.contains(where: { $0.id == trackId }) {
                    let m4a = m4aFilePath(for: trackId)
                    let mp3 = trackFilePath(for: trackId)
                    if (fm.fileExists(atPath: m4a.path) && isAudioFileValid(at: m4a))
                        || (fm.fileExists(atPath: mp3.path) && isAudioFileValid(at: mp3)) {
                        if let metaData = try? Data(contentsOf: metaFile),
                           let recovered = try? JSONDecoder().decode(Track.self, from: metaData) {
                            verifiedTracks.append(recovered)
                        }
                    }
                }
            }
        }

        self.downloadedTracks = verifiedTracks.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
        self.downloadedAlbums = index.albums.map { alb in
            var a = alb
            a.tracks = alb.tracks.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
            return a
        }
        self.downloadedPlaylists = index.playlists.map { pl in
            var p = pl
            p.tracks = pl.tracks.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
            return p
        }
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

    public func m4aFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return tracksFolder.appendingPathComponent("\(safeId).m4a")
    }

    public func hlsFolderPath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return tracksFolder.appendingPathComponent(safeId, isDirectory: true)
    }

    public func hlsPlaylistPath(for trackId: String) -> URL {
        return hlsFolderPath(for: trackId).appendingPathComponent("playlist.m3u8")
    }

    public func coverFilePath(for trackId: String) -> URL {
        let safeId = sanitizeId(trackId)
        return coversFolder.appendingPathComponent("\(safeId).jpg")
    }

    public func localCoverUrl(for trackId: String) -> URL? {
        let file = coverFilePath(for: trackId)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
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
        return localAudioFileUrl(for: trackId) != nil
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
        let m4a = m4aFilePath(for: trackId)
        if FileManager.default.fileExists(atPath: m4a.path), isAudioFileValid(at: m4a) {
            return m4a
        }
        let mp3 = trackFilePath(for: trackId)
        if FileManager.default.fileExists(atPath: mp3.path), isAudioFileValid(at: mp3) {
            return mp3
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

        // 1. Resolve Audio Stream URL (prefers progressive MP3 for instant native download)
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

        guard let resolved = await SoundCloudService.shared.resolveDownloadStreamUrl(for: targetTrack) else {
            return false
        }

        downloadProgressMap[trackId] = 0.20

        // 2. Download Audio Stream
        let isHls = resolved.isHls
        let downloadSuccess: Bool
        let destUrl: URL
        if isHls {
            let m4aUrl = m4aFilePath(for: trackId)
            destUrl = m4aUrl
            downloadSuccess = await downloadHlsStream(m3u8UrlString: resolved.url, destinationFile: m4aUrl, trackId: trackId)
        } else {
            destUrl = trackFilePath(for: trackId)
            downloadSuccess = await downloadProgressiveFile(urlString: resolved.url, destinationUrl: destUrl, trackId: trackId)
        }

        guard downloadSuccess else { return false }
        downloadProgressMap[trackId] = 0.90

        // 3. Cache Cover Artwork & Lyrics concurrently in background (non-blocking)
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            if let coverUrlStr = track.coverUrl, let coverUrl = URL(string: coverUrlStr) {
                let coverDest = self.coverFilePath(for: trackId)
                let session = SoundCloudProxyManager.shared.session(for: AudioPlayerManager.shared.settings)
                if let (tempCover, _) = try? await session.download(from: coverUrl) {
                    try? FileManager.default.removeItem(at: coverDest)
                    try? FileManager.default.moveItem(at: tempCover, to: coverDest)
                }
            }
            let lyrics = await LyricsService.shared.fetchLyrics(for: track)
            if lyrics.status != .empty, let lyricsData = try? JSONEncoder().encode(lyrics) {
                try? lyricsData.write(to: self.lyricsFilePath(for: trackId), options: .atomic)
            }
        }

        // 4. Save Track Metadata JSON
        var localTrack = track
        localTrack.streamUrl = destUrl.absoluteString
        localTrack.fetchedAt = Date()
        if let metaData = try? JSONEncoder().encode(localTrack) {
            try? metaData.write(to: metadataFilePath(for: trackId), options: .atomic)
        }

        // 5. Update Registry
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
            let session = SoundCloudProxyManager.shared.session(for: AudioPlayerManager.shared.settings)
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (tempUrl, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempUrl)
                return false
            }

            // Validate file size: audio file must be >= 100KB
            let attr = try FileManager.default.attributesOfItem(atPath: tempUrl.path)
            guard let size = attr[.size] as? Int64, size >= 100_000 else {
                try? FileManager.default.removeItem(at: tempUrl)
                return false
            }

            // Validate file header: must NOT be HTML block page or error JSON or HLS playlist
            if let handle = try? FileHandle(forReadingFrom: tempUrl) {
                let header = handle.readData(ofLength: 512)
                handle.closeFile()
                if let str = String(data: header, encoding: .utf8)?.lowercased() {
                    if str.contains("<!doctype") || str.contains("<html") || str.contains("{\"error\"") || str.contains("#extm3u") {
                        try? FileManager.default.removeItem(at: tempUrl)
                        return false
                    }
                }
            }

            try? FileManager.default.removeItem(at: destinationUrl)
            try FileManager.default.moveItem(at: tempUrl, to: destinationUrl)
            return true
        } catch {
            return false
        }
    }

    private func downloadHlsStream(m3u8UrlString: String, destinationFile: URL, trackId: String) async -> Bool {
        guard let m3u8Url = URL(string: m3u8UrlString) else { return false }
        let session = SoundCloudProxyManager.shared.session(for: AudioPlayerManager.shared.settings)
        do {
            var m3u8Req = URLRequest(url: m3u8Url)
            m3u8Req.timeoutInterval = 15
            let (data, _) = try await session.data(for: m3u8Req)
            guard let playlistText = String(data: data, encoding: .utf8) else { return false }

            let lines = playlistText.components(separatedBy: .newlines)
            let baseUrl = m3u8Url.deletingLastPathComponent()

            var initSegmentUrl: URL? = nil
            var segmentUrls: [URL] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                // Check for #EXT-X-MAP:URI="init.mp4" (Crucial for CMAF fragmented MP4 audio)
                if trimmed.hasPrefix("#EXT-X-MAP:") {
                    if let uriRange = trimmed.range(of: "URI=\"") {
                        let afterUri = trimmed[uriRange.upperBound...]
                        if let quoteEnd = afterUri.firstIndex(of: "\"") {
                            let rawUri = String(afterUri[..<quoteEnd])
                            if let fullMapUrl = URL(string: rawUri, relativeTo: baseUrl)?.absoluteURL {
                                initSegmentUrl = fullMapUrl
                                continue
                            }
                        }
                    }
                }

                if !trimmed.hasPrefix("#") {
                    // Audio segment URL
                    if let fullSegUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                        segmentUrls.append(fullSegUrl)
                    }
                }
            }

            guard !segmentUrls.isEmpty else { return false }

            // 1. Download init.mp4 if present
            var initData: Data? = nil
            if let initSegmentUrl {
                var initReq = URLRequest(url: initSegmentUrl)
                initReq.timeoutInterval = 20
                if let (data, resp) = try? await session.data(for: initReq),
                   let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   !data.isEmpty {
                    initData = data
                } else {
                    return false
                }
            }

            // 2. Download all media segments concurrently (batches of 6)
            var assembledChunks: [Data?] = Array(repeating: nil, count: segmentUrls.count)
            let concurrency = 6

            for batchIndices in stride(from: 0, to: segmentUrls.count, by: concurrency).map({
                Array($0..<min($0 + concurrency, segmentUrls.count))
            }) {
                await withTaskGroup(of: (Int, Data?).self) { group in
                    for idx in batchIndices {
                        let segUrl = segmentUrls[idx]
                        group.addTask {
                            var segReq = URLRequest(url: segUrl)
                            segReq.timeoutInterval = 20
                            if let (segData, resp) = try? await session.data(for: segReq),
                               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                               !segData.isEmpty {
                                return (idx, segData)
                            }
                            return (idx, nil)
                        }
                    }
                    for await (idx, segData) in group {
                        assembledChunks[idx] = segData
                    }
                }
            }

            // 3. Assemble init segment + media chunks into a single valid fMP4 / m4a file
            var assembledData = Data()
            if let initData {
                assembledData.append(initData)
            }
            for chunk in assembledChunks {
                guard let chunk, !chunk.isEmpty else { return false }
                assembledData.append(chunk)
            }

            guard assembledData.count >= 100_000 else { return false }

            try? FileManager.default.removeItem(at: destinationFile)
            try assembledData.write(to: destinationFile, options: .atomic)

            guard isAudioFileValid(at: destinationFile) else {
                try? FileManager.default.removeItem(at: destinationFile)
                return false
            }

            return true
        } catch {
            return false
        }
    }

    // MARK: - Fast Parallel Batch Downloader (3 Concurrent Workers)

    private func downloadTracksBatch(
        tracks: [Track],
        parentId: String,
        parentTitle: String,
        concurrency: Int = 3
    ) async {
        let total = tracks.count
        guard total > 0 else { return }

        // Filter out already downloaded tracks
        let remaining = tracks.filter { !isTrackDownloaded($0.id) }
        var completedCount = total - remaining.count
        downloadProgressMap[parentId] = Double(completedCount) / Double(total)

        guard !remaining.isEmpty else { return }

        // Process in concurrent batches of `concurrency` (3 simultaneous downloads)
        for chunk in stride(from: 0, to: remaining.count, by: concurrency).map({
            Array(remaining[$0..<min($0 + concurrency, remaining.count)])
        }) {
            await withTaskGroup(of: Bool.self) { group in
                for track in chunk {
                    group.addTask {
                        await OfflineMusicManager.shared.downloadTrack(track)
                    }
                }
                for await _ in group {
                    completedCount += 1
                    self.currentDownloadSubtitle = "\(parentTitle) • \(completedCount) из \(total)"
                    self.downloadProgressMap[parentId] = Double(completedCount) / Double(total)
                }
            }
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

        let tracks = release.tracks
        guard !tracks.isEmpty else { return }

        await downloadTracksBatch(tracks: tracks, parentId: releaseId, parentTitle: release.title, concurrency: 3)

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

        await downloadTracksBatch(tracks: uniqueTracks, parentId: artistId, parentTitle: name, concurrency: 3)

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
        try? fm.removeItem(at: m4aFilePath(for: id))
        try? fm.removeItem(at: hlsFolderPath(for: id))
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

    public func refreshAllOfflineTracks() async {
        var trackDict: [String: Track] = [:]
        for t in downloadedTracks { trackDict[t.id] = t }
        for a in downloadedAlbums {
            for t in a.tracks { trackDict[t.id] = t }
        }
        for p in downloadedPlaylists {
            for t in p.tracks { trackDict[t.id] = t }
        }

        let fm = FileManager.default
        if let metaFiles = try? fm.contentsOfDirectory(at: metadataFolder, includingPropertiesForKeys: nil) {
            for metaFile in metaFiles where metaFile.pathExtension == "json" {
                let trackId = metaFile.deletingPathExtension().lastPathComponent
                if trackDict[trackId] == nil,
                   let data = try? Data(contentsOf: metaFile),
                   let tr = try? JSONDecoder().decode(Track.self, from: data) {
                    trackDict[trackId] = tr
                }
            }
        }

        let rawIds = trackDict.values.map { $0.rawId.isEmpty ? $0.id.replacingOccurrences(of: "sc_", with: "") : $0.rawId }
        let freshMap = await SoundCloudService.shared.fetchTracks(rawIds: rawIds)

        for (id, oldTrack) in trackDict {
            var updated = freshMap[oldTrack.rawId] ?? freshMap[id] ?? SoundCloudService.renormalizeTrackIfNeeded(oldTrack)
            if let localUrl = localAudioFileUrl(for: id) {
                updated.streamUrl = localUrl.absoluteString
            } else {
                updated.streamUrl = nil
            }
            trackDict[id] = updated

            if let metaData = try? JSONEncoder().encode(updated) {
                try? metaData.write(to: metadataFilePath(for: id), options: .atomic)
            }
        }

        self.downloadedTracks = downloadedTracks.compactMap { trackDict[$0.id] ?? SoundCloudService.renormalizeTrackIfNeeded($0) }
        self.downloadedAlbums = downloadedAlbums.map { alb in
            var a = alb
            a.tracks = alb.tracks.compactMap { trackDict[$0.id] ?? SoundCloudService.renormalizeTrackIfNeeded($0) }
            return a
        }
        self.downloadedPlaylists = downloadedPlaylists.map { pl in
            var p = pl
            p.tracks = pl.tracks.compactMap { trackDict[$0.id] ?? SoundCloudService.renormalizeTrackIfNeeded($0) }
            return p
        }

        // Re-download audio for any offline metadata item if its audio is missing
        for (id, tr) in trackDict {
            if localAudioFileUrl(for: id) == nil {
                await downloadTrack(tr)
            }
        }

        saveIndex()
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

// MARK: - Track Offline Cover Extension

extension Track {
    @MainActor
    public var effectiveCoverUrl: URL? {
        if let local = OfflineMusicManager.shared.localCoverUrl(for: id) {
            return local
        }
        guard let coverUrl, let url = URL(string: coverUrl) else { return nil }
        return url
    }
}
