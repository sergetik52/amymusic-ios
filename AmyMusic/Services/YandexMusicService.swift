import Foundation

// MARK: - Yandex Music Native Service (Port of src/services/yandexMusicApi.js)

public actor YandexMusicService {
    public static let shared = YandexMusicService()

    private let baseURL = "https://api.music.yandex.net"
    private var oauthToken: String?
    private var artistAvatarCache: [String: String] = [:]

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
        request.timeoutInterval = 12
        request.setValue("YandexMusicAndroid/24023241", forHTTPHeaderField: "X-Yandex-Music-Client")
        request.setValue("23cabbbdc6cd418abb4b32c41195d", forHTTPHeaderField: "Client-Id")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        if let oauthToken {
            request.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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
        onProgress: @Sendable (Int, Int) -> Void
    ) async -> ReleaseItem? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Parse /albums/{id} or /users/{user}/playlists/{kind} or /playlists/{uuid}
        var rawTrackItems: [(artist: String, title: String, fallbackTrack: Track?)] = []
        var releaseTitle = "Импортированный плейлист"
        var releaseCover: String?

        if let albumMatch = trimmed.range(of: #"/albums/(\d+)"#, options: .regularExpression) {
            let albumId = String(trimmed[albumMatch]).replacingOccurrences(of: "/albums/", with: "")
            if let root = try? await requestYandex(path: "/albums/\(albumId)/with-tracks"),
               let result = root["result"] as? [String: Any] {
                releaseTitle = (result["title"] as? String) ?? releaseTitle
                releaseCover = formatYandexUri(result["coverUri"] as? String)
                let volumes = (result["volumes"] as? [[[String: Any]]]) ?? []
                for vol in volumes {
                    for tDict in vol {
                        if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                            rawTrackItems.append((t.artist, t.title, t))
                        }
                    }
                }
            }
        } else if let plUUIDMatch = trimmed.range(of: #"/playlists/([a-zA-Z0-9\.\-_]+)"#, options: .regularExpression) {
            let uuid = String(trimmed[plUUIDMatch]).replacingOccurrences(of: "/playlists/", with: "")
            if let root = try? await requestYandex(path: "/playlists/\(uuid)"),
               let result = root["result"] as? [String: Any] {
                releaseTitle = (result["title"] as? String) ?? releaseTitle
                let entries = (result["tracks"] as? [[String: Any]]) ?? []
                for entry in entries {
                    let tDict = (entry["track"] as? [String: Any]) ?? entry
                    if let t = normalizeYandexTrack(tDict, chartInfo: nil, fallbackRank: nil) {
                        rawTrackItems.append((t.artist, t.title, t))
                    }
                }
            }
        }

        // Resolve via SoundCloud search if Yandex had no direct tracks or to ensure playable streams
        if rawTrackItems.isEmpty {
            let scReleases = await SoundCloudService.shared.searchReleases(query: trimmed, limit: 1)
            if let first = scReleases.first {
                return await SoundCloudService.shared.hydrateReleaseTracks(first)
            }
            return nil
        }

        var resolvedTracks: [Track] = []
        let total = rawTrackItems.count
        for (idx, item) in rawTrackItems.enumerated() {
            onProgress(idx + 1, total)
            let matches = await SoundCloudService.shared.searchTracks(query: "\(item.artist) \(item.title)", limit: 3)
            if var best = matches.first {
                if let fallbackCover = item.fallbackTrack?.coverUrl {
                    best.coverUrl = fallbackCover
                }
                resolvedTracks.append(best)
            } else if let fallback = item.fallbackTrack {
                resolvedTracks.append(fallback)
            }
        }

        return ReleaseItem(
            id: "user_pl_\(UUID().uuidString)",
            title: releaseTitle,
            artist: "Импорт Yandex Music",
            coverUrl: releaseCover ?? resolvedTracks.first?.coverUrl,
            kind: .userPlaylist,
            trackCount: resolvedTracks.count,
            tracks: resolvedTracks
        )
    }

    // MARK: - Resolve Yandex Track via SoundCloud (Port of resolveChartTrackViaSoundCloud)

    public func resolvePlayableSoundCloudTrack(for yandexTrack: Track) async -> Track? {
        let query = "\(yandexTrack.artist) \(yandexTrack.title)"
        let results = await SoundCloudService.shared.searchTracks(query: query, limit: 5)
        guard var match = results.first(where: { !$0.isSnippet }) ?? results.first else {
            return nil
        }
        // Preserve Yandex high-res artwork & derived palette
        if let cover = yandexTrack.coverUrl {
            match.coverUrl = cover
        }
        match.palette = yandexTrack.palette
        return match
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
