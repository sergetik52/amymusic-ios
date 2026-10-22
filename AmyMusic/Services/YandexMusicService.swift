import Foundation

// MARK: - Yandex Music Native Service (Port of src/services/yandexMusicApi.js)

public actor YandexMusicService {
    public static let shared = YandexMusicService()

    private let baseURL = "https://api.music.yandex.net"
    private var oauthToken: String?
    private var settings: AppProfileSettings = AppProfileSettings()
    private var artistAvatarCache: [String: String] = [:]

    public func updateSettings(_ settings: AppProfileSettings) {
        self.settings = settings
        updateToken(settings.yandexOAuthToken)
    }

    public func updateToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.oauthToken = trimmed.isEmpty ? nil : trimmed
    }

    private func requestYandex(path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("YandexMusicAndroid/24023241", forHTTPHeaderField: "X-Yandex-Music-Client")
        request.setValue("23cabbbdc6cd418abb4b32c41195d", forHTTPHeaderField: "Client-Id")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let oauthToken {
            request.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        }

        let session = SoundCloudProxyManager.shared.session(for: self.settings)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }

    // MARK: - Top 100 Charts (/landing3/chart)

    public func getChartTop100() async -> [Track] {
        do {
            let root = try await requestYandex(path: "/landing3/chart")
            let result = (root["result"] as? [String: Any]) ?? root
            let chartList = (result["chart"] as? [String: Any])?["tracks"] as? [[String: Any]]
                ?? (result["tracks"] as? [[String: Any]])
                ?? []

            var tracks: [Track] = []
            for (idx, entry) in chartList.enumerated() {
                let trackDict = (entry["track"] as? [String: Any]) ?? entry
                let chartInfo = (entry["chart"] as? [String: Any]) ?? entry
                if let normalized = normalizeYandexTrack(trackDict, chartInfo: chartInfo, fallbackRank: idx + 1) {
                    tracks.append(normalized)
                }
            }
            if !tracks.isEmpty {
                return tracks
            }
        } catch {}

        // Fallback to SoundCloud popular CIS/Global tracks if Yandex endpoint is unreachable
        return await SoundCloudService.shared.searchTracks(query: "top hits 2026", limit: 40)
    }

    // MARK: - Yandex Rotor Wave Stations

    public func getRotorWaveTracks(mood: String = "all", language: String = "all") async -> [Track] {
        let stationId = mood == "all" ? "activity:user:onyourwave" : "mood:\(mood)"
        var tracks: [Track] = []

        if let root = try? await requestYandex(path: "/rotor/station/\(stationId)/tracks"),
           let result = root["result"] as? [String: Any],
           let sequence = result["sequence"] as? [[String: Any]] {
            tracks = sequence.compactMap { item in
                guard let trackDict = item["track"] as? [String: Any] else { return nil }
                return normalizeYandexTrack(trackDict, chartInfo: nil, fallbackRank: nil)
            }
        }

        if tracks.count < 10 {
            tracks = await getChartTop100()
        }

        if language == "russian" {
            return tracks.filter { containsCyrillic($0.title) || containsCyrillic($0.artist) }
        } else if language == "foreign" {
            return tracks.filter { !containsCyrillic($0.title) && !containsCyrillic($0.artist) }
        }
        return tracks
    }

    // MARK: - Playlist / Album Link Importer (Port of parseYandexMusicUrl)

    public func importPlaylistFromUrl(
        _ urlString: String,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> ReleaseItem? {
        let trimmedInput = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }

        // 1. Pre-resolve redirect links (music.yandex.ru/d/..., on.soundcloud.com/...)
        var targetUrl = await SoundCloudService.resolveRedirectUrl(trimmedInput)
        targetUrl = targetUrl.components(separatedBy: "?").first ?? targetUrl

        // 2. Delegate SoundCloud URLs directly to SoundCloudService
        if targetUrl.contains("soundcloud.com") || targetUrl.contains("on.soundcloud.com") {
            return await SoundCloudService.shared.importPlaylistFromUrl(targetUrl, onProgress: onProgress)
        }

        var rawTrackItems: [(artist: String, title: String, coverUrl: String?, fallbackTrack: Track?)] = []
        var releaseTitle = "Импортированный плейлист"
        var releaseArtist = "Яндекс Музыка"
        var releaseCover: String?

        // Format A: Single Track -> /album/{albumId}/track/{trackId} or /track/{trackId}
        if let trackMatch = targetUrl.range(of: #"(?:(?:album/\d+/)?track/|tracks/)(\d+)"#, options: .regularExpression) {
            let matchedStr = String(targetUrl[trackMatch])
            let digits = matchedStr.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.last ?? ""
            if !digits.isEmpty {
                if let root = try? await requestYandex(path: "/tracks/\(digits)"),
                   let resultList = root["result"] as? [[String: Any]],
                   let tDict = resultList.first,
                   let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                    rawTrackItems.append((t.artist, t.title, t.coverUrl, t))
                    releaseTitle = t.title
                    releaseArtist = t.artist
                    releaseCover = t.coverUrl
                }
            }
        }
        // Format B: Album -> /albums?/{albumId}
        else if let albumMatch = targetUrl.range(of: #"/albums?/(\d+)"#, options: .regularExpression) {
            let matchedStr = String(targetUrl[albumMatch])
            let albumId = matchedStr.replacingOccurrences(of: "/albums/", with: "").replacingOccurrences(of: "/album/", with: "")
            if let root = try? await requestYandex(path: "/albums/\(albumId)/with-tracks"),
               let result = root["result"] as? [String: Any] {
                releaseTitle = (result["title"] as? String) ?? releaseTitle
                if let artists = (result["artists"] as? [[String: Any]])?.compactMap({ $0["name"] as? String }), !artists.isEmpty {
                    releaseArtist = artists.joined(separator: ", ")
                }
                releaseCover = formatYandexUri(result["coverUri"] as? String ?? result["ogImage"] as? String)
                let volumes = (result["volumes"] as? [[[String: Any]]]) ?? []
                for vol in volumes {
                    for tDict in vol {
                        if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                            rawTrackItems.append((t.artist, t.title, t.coverUrl, t))
                        }
                    }
                }
            }
        }
        // Format C: User Playlist -> /users/{user}/playlists/{kind}
        else if let userPlMatch = targetUrl.range(of: #"/users/([^/]+)/playlists/([0-9a-zA-Z_\-]+)"#, options: .regularExpression) {
            let sub = String(targetUrl[userPlMatch])
            let parts = sub.components(separatedBy: "/")
            if parts.count >= 5 {
                let user = parts[2]
                let kind = parts[4]
                if let root = try? await requestYandex(path: "/users/\(user)/playlists/\(kind)"),
                   let result = root["result"] as? [String: Any] {
                    releaseTitle = (result["title"] as? String) ?? releaseTitle
                    if let owner = (result["owner"] as? [String: Any])?["name"] as? String {
                        releaseArtist = owner
                    }
                    releaseCover = formatYandexUri((result["cover"] as? [String: Any])?["uri"] as? String ?? result["ogImage"] as? String)
                    let entries = (result["tracks"] as? [[String: Any]]) ?? []
                    for entry in entries {
                        let tDict = (entry["track"] as? [String: Any]) ?? entry
                        if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                            rawTrackItems.append((t.artist, t.title, t.coverUrl, t))
                        }
                    }
                }
            }
        }
        // Format D: UUID / Editorial Playlist -> /playlists/{uuid}
        else if let plUUIDMatch = targetUrl.range(of: #"/playlists/([a-zA-Z0-9\.\-_]+)"#, options: .regularExpression) {
            let uuid = String(targetUrl[plUUIDMatch]).replacingOccurrences(of: "/playlists/", with: "").replacingOccurrences(of: "/playlist/", with: "")
            let endpoints = [
                "/playlist/\(uuid)",
                "/playlists/\(uuid)",
                "/landing3/playlist?uuid=\(uuid)",
                "/users/none/playlists/\(uuid)"
            ]
            for ep in endpoints {
                if let root = try? await requestYandex(path: ep) {
                    let result = (root["result"] as? [String: Any]) ?? (root["playlist"] as? [String: Any]) ?? root
                    let entries = (result["tracks"] as? [[String: Any]]) ?? []
                    if !entries.isEmpty || result["title"] != nil {
                        releaseTitle = (result["title"] as? String) ?? releaseTitle
                        releaseCover = formatYandexUri((result["cover"] as? [String: Any])?["uri"] as? String ?? result["ogImage"] as? String)
                        for entry in entries {
                            let tDict = (entry["track"] as? [String: Any]) ?? entry
                            if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                                rawTrackItems.append((t.artist, t.title, t.coverUrl, t))
                            }
                        }
                        break
                    }
                }
            }
        }
        // Format E: Artist Top Tracks -> /artist/{artistId}
        else if let artistMatch = targetUrl.range(of: #"/artist/(\d+)"#, options: .regularExpression) {
            let artistId = String(targetUrl[artistMatch]).replacingOccurrences(of: "/artist/", with: "")
            if let root = try? await requestYandex(path: "/artists/\(artistId)/tracks", queryItems: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "pageSize", value: "50")
            ]), let result = root["result"] as? [String: Any] {
                let entries = (result["tracks"] as? [[String: Any]]) ?? []
                if let artistInfoRoot = try? await requestYandex(path: "/artists/\(artistId)/brief-info"),
                   let aRes = (artistInfoRoot["result"] as? [String: Any])?["artist"] as? [String: Any] {
                    let aName = (aRes["name"] as? String) ?? "Артист"
                    releaseTitle = "Популярное: \(aName)"
                    releaseArtist = aName
                    releaseCover = formatYandexUri((aRes["cover"] as? [String: Any])?["uri"] as? String ?? aRes["ogImage"] as? String)
                }
                for tDict in entries {
                    if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                        rawTrackItems.append((t.artist, t.title, t.coverUrl, t))
                    }
                }
            }
        }

        // Fallback: If Yandex parser found no tracks, try SoundCloud directly
        if rawTrackItems.isEmpty {
            let cleanQuery = targetUrl
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "/", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let scItem = await SoundCloudService.shared.importPlaylistFromUrl(targetUrl, onProgress: onProgress) {
                return scItem
            }
            let scReleases = await SoundCloudService.shared.searchReleases(query: cleanQuery, limit: 1)
            if let first = scReleases.first {
                return await SoundCloudService.shared.hydrateReleaseTracks(first)
            }
            return nil
        }

        // Construct the release immediately using the already parsed tracks (0.2s instant import!)
        let initialTracks = rawTrackItems.compactMap { $0.fallbackTrack }
        guard !initialTracks.isEmpty else { return nil }

        let releaseId = "yandex_pl_\(UUID().uuidString)"
        let imported = ReleaseItem(
            id: releaseId,
            title: releaseTitle,
            artist: releaseArtist,
            coverUrl: releaseCover ?? initialTracks.first?.coverUrl,
            kind: .userPlaylist,
            trackCount: initialTracks.count,
            tracks: initialTracks
        )
        ReleaseCacheManager.shared.set(imported)

        // Launch high-speed parallel SoundCloud track resolution in background (6 concurrent workers)
        Task.detached {
            await self.resolveReleaseTracksInBackground(releaseId: releaseId, tracks: initialTracks, onProgress: onProgress)
        }

        return imported
    }

    // MARK: - Parallel Background SoundCloud Track Resolution (6x Concurrency)

    public func resolveReleaseTracksInBackground(
        releaseId: String,
        tracks: [Track],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async {
        guard !tracks.isEmpty else { return }

        let total = tracks.count
        var resolvedDict: [Int: Track] = [:]

        await withTaskGroup(of: (Int, Track?).self) { group in
            var trackIndex = 0
            let maxConcurrent = 6

            // Seed initial batch of parallel workers
            while trackIndex < min(maxConcurrent, total) {
                let idx = trackIndex
                let tr = tracks[idx]
                group.addTask {
                    let resolved = await self.resolvePlayableSoundCloudTrack(for: tr)
                    return (idx, resolved)
                }
                trackIndex += 1
            }

            // Stream results and feed next tasks
            var completedCount = 0
            for await (idx, resolved) in group {
                completedCount += 1
                onProgress?(completedCount, total)
                if let resolved {
                    resolvedDict[idx] = resolved
                }

                if trackIndex < total {
                    let nextIdx = trackIndex
                    let nextTr = tracks[nextIdx]
                    group.addTask {
                        let res = await self.resolvePlayableSoundCloudTrack(for: nextTr)
                        return (nextIdx, res)
                    }
                    trackIndex += 1
                }
            }
        }

        // Update release in memory & disk cache
        if var cachedRelease = ReleaseCacheManager.shared.get(for: releaseId) {
            var updatedTracks: [Track] = []
            for (idx, orig) in tracks.enumerated() {
                if let resolved = resolvedDict[idx] {
                    updatedTracks.append(resolved)
                } else {
                    updatedTracks.append(orig)
                }
            }
            cachedRelease.tracks = updatedTracks
            ReleaseCacheManager.shared.set(cachedRelease)
        }
    }

    // MARK: - Resolve Yandex Track via SoundCloud (Port of resolveChartTrackViaSoundCloud)

    private var resolvedTrackCache: [String: Track] = [:]

    public func resolvePlayableSoundCloudTrack(for yandexTrack: Track) async -> Track? {
        if let cached = resolvedTrackCache[yandexTrack.id] {
            return cached
        }

        // 1. Full artist + title
        let q1 = "\(yandexTrack.artist) \(yandexTrack.title)"
        let res1 = await SoundCloudService.shared.searchTracks(query: q1, limit: 5)
        var matched = res1.first(where: { !$0.isSnippet }) ?? res1.first

        // 2. Primary artist + title
        if matched == nil {
            let primaryArtist = yandexTrack.artist.components(separatedBy: CharacterSet(charactersIn: ",&×/;")).first?.trimmingCharacters(in: .whitespaces) ?? yandexTrack.artist
            let q2 = "\(primaryArtist) \(yandexTrack.title)"
            let res2 = await SoundCloudService.shared.searchTracks(query: q2, limit: 5)
            matched = res2.first(where: { !$0.isSnippet }) ?? res2.first
        }

        // 3. Title only
        if matched == nil {
            let res3 = await SoundCloudService.shared.searchTracks(query: yandexTrack.title, limit: 3)
            matched = res3.first(where: { !$0.isSnippet }) ?? res3.first
        }

        guard var best = matched else { return nil }

        // Retain high-res Yandex artwork & palette
        if let cover = yandexTrack.coverUrl, !cover.isEmpty {
            best.coverUrl = cover
        }
        best.palette = yandexTrack.palette

        resolvedTrackCache[yandexTrack.id] = best
        return best
    }

    // MARK: - Artist Avatar Lookup

    public func fetchArtistAvatar(artistName: String) async -> String? {
        let key = artistName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = artistAvatarCache[key] { return cached }

        do {
            let root = try await requestYandex(
                path: "/search",
                queryItems: [
                    URLQueryItem(name: "text", value: artistName),
                    URLQueryItem(name: "type", value: "artist"),
                    URLQueryItem(name: "page", value: "0")
                ]
            )
            let result = (root["result"] as? [String: Any]) ?? root
            let artists = (result["artists"] as? [String: Any])?["results"] as? [[String: Any]]
                ?? (result["artists"] as? [[String: Any]])
                ?? []
            if let matched = artists.first(where: {
                let n = ($0["name"] as? String) ?? ""
                return n.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == key
            }) ?? artists.first {
                let coverDict = matched["cover"] as? [String: Any]
                let uri = (coverDict?["uri"] as? String) ?? (matched["ogImage"] as? String)
                if let formatted = formatYandexUri(uri) {
                    artistAvatarCache[key] = formatted
                    return formatted
                }
            }
        } catch {}

        if let scProfile = await SoundCloudService.shared.fetchArtistProfile(artistId: artistName),
           let scAvatar = scProfile.avatarUrl, !scAvatar.isEmpty {
            artistAvatarCache[key] = scAvatar
            return scAvatar
        }

        return nil
    }

    // MARK: - Helpers

    private func normalizeYandexTrack(_ raw: [String: Any], chartInfo: [String: Any]?, fallbackRank: Int?) -> Track? {
        guard let idVal = raw["id"] else { return nil }
        let title = (raw["title"] as? String) ?? "Без названия"
        let rawArtists = (raw["artists"] as? [[String: Any]]) ?? []

        let baseArtists: [ArtistRef] = rawArtists.compactMap { a in
            guard let name = a["name"] as? String else { return nil }
            let aId = a["id"].map { "\($0)" } ?? name
            let coverUri = (a["cover"] as? [String: Any])?["uri"] as? String
            return ArtistRef(id: aId, name: name, avatarUrl: formatYandexUri(coverUri))
        }

        var cleanTitle = title
        var featNames: [String] = []
        let featPatterns = [
            #"(?i)[\(\[]\s*(?:feat\.?|ft\.?|with)\s+([^\]\)]+)[\)\]]"#,
            #"(?i)\s+(?:feat\.?|ft\.?)\s+(.+)$"#
        ]
        for pattern in featPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: cleanTitle, range: NSRange(cleanTitle.startIndex..., in: cleanTitle)) {
                if let r = Range(match.range(at: 1), in: cleanTitle) {
                    let extracted = String(cleanTitle[r])
                    let rawFeats = extracted
                        .replacingOccurrences(of: " & ", with: ",")
                        .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
                        .replacingOccurrences(of: " feat. ", with: ",", options: .caseInsensitive)
                        .replacingOccurrences(of: " ft. ", with: ",", options: .caseInsensitive)
                        .components(separatedBy: CharacterSet(charactersIn: ",&×;"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    featNames.append(contentsOf: rawFeats)
                }
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, range: NSRange(cleanTitle.startIndex..., in: cleanTitle), withTemplate: "")
            }
        }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let primaryArtistId = baseArtists.first?.id ?? "yandex_unknown"
        var allArtists = baseArtists
        for feat in featNames {
            if !allArtists.contains(where: { $0.name.caseInsensitiveCompare(feat) == .orderedSame }) {
                allArtists.append(ArtistRef(id: feat, name: feat, avatarUrl: nil))
            }
        }

        let artistStr = allArtists.isEmpty ? "Неизвестный артист" : allArtists.map(\.name).joined(separator: ", ")
        let durationMs = (raw["durationMs"] as? Double) ?? 180_000
        let coverUri = (raw["coverUri"] as? String) ?? (raw["ogImage"] as? String)
        let coverUrl = formatYandexUri(coverUri)

        // Derived colors -> TrackPalette
        var palette = TrackPalette.defaultPalette
        if let derived = raw["derivedColors"] as? [String: Any] {
            let mini = (derived["miniPlayer"] as? String) ?? palette.base
            let wave = (derived["waveText"] as? String) ?? palette.bright
            let accent = (derived["accent"] as? String) ?? palette.line
            palette = TrackPalette(base: mini, line: accent, bright: wave, shadow: mini)
        }

        let position = (chartInfo?["position"] as? Int) ?? fallbackRank
        let progressStr = (chartInfo?["progress"] as? String)?.lowercased()
        let progress: ChartProgress? = {
            switch progressStr {
            case "up": return .up
            case "down": return .down
            case "new": return .new
            case "same": return .same
            default: return position != nil ? .same : nil
            }
        }()
        let shift = chartInfo?["shift"] as? Int
        let listeners = chartInfo?["listeners"] as? Int

        let explicit = ((raw["contentWarning"] as? String) == "explicit")

        return Track(
            id: "yandex_\(idVal)",
            rawId: "\(idVal)",
            title: cleanTitle.isEmpty ? title : cleanTitle,
            rawTitle: title,
            artist: artistStr,
            artists: allArtists,
            coverUrl: coverUrl,
            duration: durationMs / 1000.0,
            isExplicit: explicit,
            source: .yandex,
            palette: palette,
            chartPosition: position,
            chartProgress: progress,
            chartShift: shift,
            listenersCount: listeners
        )
    }

    private func formatYandexUri(_ uri: String?, size: String = "400x400") -> String? {
        guard let uri, !uri.isEmpty else { return nil }
        let replaced = uri.replacingOccurrences(of: "%%", with: size)
        if replaced.hasPrefix("http://") || replaced.hasPrefix("https://") {
            return replaced
        }
        return "https://\(replaced)"
    }

    private func containsCyrillic(_ text: String) -> Bool {
        text.range(of: "[\\u0400-\\u04FF]", options: .regularExpression) != nil
    }
}
