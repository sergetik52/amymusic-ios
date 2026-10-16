import Foundation

// MARK: - SoundCloud API v2 Native Service (Port of src/services/soundCloudApi.js)

public actor SoundCloudService {
    public static let shared = SoundCloudService()

    private let baseURL = "https://api-v2.soundcloud.com"
    private let defaultClientId = "yNSW5UvBmb1A5j7qPUtIMuB9Itx3jsOC"
    private var customClientId: String?
    private var avatarCache: [String: String] = [:]

    // TrackDNA Genre Family Tree (matching GENRE_FAMILIES in soundCloudApi.js)
    private let genreFamilies: [String: [String]] = [
        "hip-hop": ["hip-hop", "hip hop", "rap", "trap", "cloud rap", "boom bap", "memphis"],
        "trap": ["trap", "rage", "pluggnb", "plugg", "dark trap", "hip-hop", "rap"],
        "phonk": ["phonk", "drift phonk", "house phonk", "memphis", "cowbell", "aggressive phonk"],
        "drill": ["drill", "uk drill", "ny drill", "chicago drill", "grime", "trap"],
        "electronic": ["electronic", "edm", "synthwave", "electro", "club", "dance", "bass"],
        "house": ["house", "deep house", "tech house", "bass house", "slap house", "progressive house"],
        "techno": ["techno", "hard techno", "acid techno", "industrial", "minimal", "rave"],
        "hyperpop": ["hyperpop", "glitchcore", "digicore", "sigilkore", "webcore", "electropop"],
        "rock": ["rock", "alt rock", "indie rock", "post-punk", "grunge", "punk", "metal"],
        "post-punk": ["post-punk", "coldwave", "darkwave", "new wave", "synth-pop", "doomer"],
        "pop": ["pop", "indie pop", "dance pop", "synthpop", " bedroom pop", "dream pop"],
        "r&b": ["r&b", "rnb", "soul", "neo-soul", "alternative r&b", "contemporary r&b"],
        "lofi": ["lofi", "lo-fi", "chillhop", "jazzhop", "study beats", "ambient"]
    ]

    private let moodTokens: [String: [String]] = [
        "dark": ["dark", "night", "shadow", "evil", "demon", "murder", "dead", "black", "phonk", "witch"],
        "chill": ["chill", "relax", "lofi", "calm", "soft", "sleep", "ambient", "warm", "breeze"],
        "hard": ["hard", "rage", "aggressive", "bass", "distortion", "gym", "drift", "krush"],
        "sad": ["sad", "cry", "pain", "lonely", "broken", "tears", "alone", "doomer", "melancholy"],
        "happy": ["happy", "summer", "sun", "vibe", "party", "dance", "bright", "feel good"],
        "dreamy": ["dream", "space", "cloud", "float", "angel", "ethereal", "stars", "heaven"]
    ]

    public func updateClientId(_ clientId: String?) {
        let trimmed = clientId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.customClientId = trimmed.isEmpty ? nil : trimmed
    }

    private var activeClientId: String {
        customClientId ?? defaultClientId
    }

    // MARK: - Core Request Builder

    private func requestJSON(path: String, queryItems: [URLQueryItem] = []) async throws -> Any {
        var components = URLComponents(string: path.hasPrefix("http") ? path : "\(baseURL)\(path)")
        var items = components?.queryItems ?? []
        if !items.contains(where: { $0.name == "client_id" }) {
            items.append(URLQueryItem(name: "client_id", value: activeClientId))
        }
        items.append(contentsOf: queryItems)
        components?.queryItems = items

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 14
        request.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        request.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Search Endpoints

    public func searchTracks(query: String, limit: Int = 20) async -> [Track] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        do {
            let json = try await requestJSON(
                path: "/search/tracks",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
            )
            guard let dict = json as? [String: Any],
                  let collection = dict["collection"] as? [[String: Any]] else {
                return []
            }
            return collection.compactMap { normalizeTrack($0) }
        } catch {
            return []
        }
    }

    public func searchArtists(query: String, limit: Int = 24) async -> [ArtistRef] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        do {
            let json = try await requestJSON(
                path: "/search/users",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
            )
            guard let dict = json as? [String: Any],
                  let collection = dict["collection"] as? [[String: Any]] else {
                return []
            }
            return collection.compactMap { user in
                guard let id = user["id"] else { return nil }
                let name = (user["username"] as? String) ?? (user["full_name"] as? String) ?? "Unknown"
                let avatar = upgradeArtworkUrl(user["avatar_url"] as? String)
                return ArtistRef(
                    id: "\(id)",
                    name: name,
                    avatarUrl: avatar,
                    permalinkUrl: user["permalink_url"] as? String
                )
            }
        } catch {
            return []
        }
    }

    public func searchReleases(query: String, albumsOnly: Bool = false, limit: Int = 24) async -> [ReleaseItem] {
        let endpoint = albumsOnly ? "/search/albums" : "/search/playlists"
        do {
            let json = try await requestJSON(
                path: endpoint,
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
            )
            guard let dict = json as? [String: Any],
                  let collection = dict["collection"] as? [[String: Any]] else {
                return []
            }
            return collection.compactMap { normalizePlaylist($0, forceKind: albumsOnly ? .album : .playlist) }
        } catch {
            return []
        }
    }

    // MARK: - Stream Resolution & Snippet Workaround

    public func resolveStreamUrl(for track: Track, quality: AudioQualityTier = .q320) async -> (url: String, isHls: Bool)? {
        // If track is a 30s Go+ snippet, try searching for a full non-snippet replacement first
        if track.isSnippet {
            let candidates = await searchTracks(query: "\(track.artist) \(track.title)", limit: 6)
            if let replacement = candidates.first(where: { !$0.isSnippet && $0.duration > 45 }),
               let transcoding = replacement.transcodingUrl {
                if let resolved = await fetchTranscodingUrl(transcoding) {
                    return (resolved, replacement.isHls || resolved.contains(".m3u8"))
                }
            }
        }

        if let transcoding = track.transcodingUrl,
           let resolved = await fetchTranscodingUrl(transcoding) {
            let isHls = track.isHls || resolved.contains(".m3u8") || resolved.contains("/hls/")
            return (resolved, isHls)
        }

        // Refetch fresh track object by ID if transcoding expired
        let cleanId = track.rawId.replacingOccurrences(of: "sc_", with: "")
        if let json = try? await requestJSON(path: "/tracks/\(cleanId)") as? [String: Any],
           let refreshed = normalizeTrack(json, preferredQuality: quality),
           let transcoding = refreshed.transcodingUrl,
           let resolved = await fetchTranscodingUrl(transcoding) {
            return (resolved, refreshed.isHls || resolved.contains(".m3u8"))
        }

        return nil
    }

    private func fetchTranscodingUrl(_ transcodingUrl: String) async -> String? {
        do {
            let json = try await requestJSON(path: transcodingUrl)
            if let dict = json as? [String: Any], let url = dict["url"] as? String {
                return url
            }
        } catch {}
        return nil
    }

    // MARK: - Artist Profile & Hydration

    public func fetchArtistProfile(artistId: String) async -> ArtistProfile? {
        var cleanId = artistId.replacingOccurrences(of: "sc_user_", with: "")
        var userAny: Any? = nil

        if Int(cleanId) != nil {
            userAny = try? await requestJSON(path: "/users/\(cleanId)")
        }

        // If direct numeric ID lookup fails or artistId is an artist name (e.g. "9mice", "Kai Angel")
        if userAny == nil {
            let searchRes = try? await requestJSON(
                path: "/search/users",
                queryItems: [URLQueryItem(name: "q", value: cleanId), URLQueryItem(name: "limit", value: "5")]
            )
            if let root = searchRes as? [String: Any],
               let coll = root["collection"] as? [[String: Any]],
               let matchedUser = coll.first(where: {
                   let uName = ($0["username"] as? String) ?? ""
                   return uName.caseInsensitiveCompare(cleanId) == .orderedSame
               }) ?? coll.first,
               let numericId = matchedUser["id"] {
                cleanId = "\(numericId)"
                userAny = matchedUser
            }
        }

        let tracksAny = try? await requestJSON(path: "/users/\(cleanId)/tracks", queryItems: [URLQueryItem(name: "limit", value: "200")])
        let albumsAny = try? await requestJSON(path: "/users/\(cleanId)/albums", queryItems: [URLQueryItem(name: "limit", value: "24")])
        let playlistsAny = try? await requestJSON(path: "/users/\(cleanId)/playlists", queryItems: [URLQueryItem(name: "limit", value: "24")])
        let followingsAny = try? await requestJSON(path: "/users/\(cleanId)/followings", queryItems: [URLQueryItem(name: "limit", value: "12")])

        guard let userDict = userAny as? [String: Any] else { return nil }

        let name = (userDict["username"] as? String) ?? "Артист"
        let avatar = upgradeArtworkUrl(userDict["avatar_url"] as? String)
        let visuals = (userDict["visuals"] as? [String: Any])?["visuals"] as? [[String: Any]]
        let banner = upgradeArtworkUrl(visuals?.first?["visual_url"] as? String) ?? avatar

        let rawTracks = ((tracksAny as? [String: Any])?["collection"] as? [[String: Any]]) ?? []
        let chronologicalTracks = rawTracks.compactMap { normalizeTrack($0) }
        let normalizedTracks = chronologicalTracks.sorted { $0.playbackCount > $1.playbackCount }

        let rawAlbums = ((albumsAny as? [String: Any])?["collection"] as? [[String: Any]]) ?? []
        let allReleases = rawAlbums.compactMap { normalizePlaylist($0, forceKind: .album) }
        let albums = allReleases.filter { $0.trackCount > 2 }

        // Build singles from standalone tracks (which are the predominant single release format on SoundCloud)
        let albumTrackTitles = Set(albums.flatMap { $0.tracks.map { $0.title.lowercased() } })
        var trackSingles: [ReleaseItem] = []
        for tr in chronologicalTracks {
            if !albumTrackTitles.contains(tr.title.lowercased()) {
                trackSingles.append(
                    ReleaseItem(
                        id: "sc_single_\(tr.rawId)",
                        title: tr.title,
                        artist: tr.artist,
                        artistId: "\(userDict["id"] ?? cleanId)",
                        coverUrl: tr.coverUrl ?? avatar,
                        kind: .single,
                        trackCount: 1,
                        tracks: [tr]
                    )
                )
            }
        }

        let albumSingles = allReleases.filter { $0.trackCount <= 2 }.map {
            var copy = $0
            copy.kind = .single
            return copy
        }

        var allSingles: [ReleaseItem] = []
        var seenSingleTitles = Set<String>()
        for s in (trackSingles + albumSingles) {
            let key = s.title.lowercased()
            if !seenSingleTitles.contains(key) {
                seenSingleTitles.insert(key)
                allSingles.append(s)
            }
        }

        // Determine latest releases chronologically across all albums and track singles
        struct DatedRelease {
            let item: ReleaseItem
            let date: String
        }

        var datedReleases: [DatedRelease] = []
        for (idx, rawAlb) in rawAlbums.enumerated() {
            if idx < allReleases.count {
                let rel = allReleases[idx]
                let d = (rawAlb["release_date"] as? String) ?? (rawAlb["created_at"] as? String) ?? ""
                datedReleases.append(DatedRelease(item: rel, date: d))
            }
        }
        for (idx, rawTr) in rawTracks.enumerated() {
            if idx < chronologicalTracks.count {
                let tr = chronologicalTracks[idx]
                let d = (rawTr["created_at"] as? String) ?? ""
                let single = ReleaseItem(
                    id: "sc_single_\(tr.rawId)",
                    title: tr.title,
                    artist: tr.artist,
                    artistId: "\(userDict["id"] ?? cleanId)",
                    coverUrl: tr.coverUrl ?? avatar,
                    kind: .single,
                    trackCount: 1,
                    tracks: [tr]
                )
                datedReleases.append(DatedRelease(item: single, date: d))
            }
        }

        let sortedDated = datedReleases.sorted { $0.date > $1.date }
        var latestReleasesList: [ReleaseItem] = []
        var seenReleaseIds = Set<String>()
        var seenReleaseTitles = Set<String>()

        for dr in sortedDated {
            let titleKey = dr.item.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !seenReleaseIds.contains(dr.item.id) && !seenReleaseTitles.contains(titleKey) {
                seenReleaseIds.insert(dr.item.id)
                seenReleaseTitles.insert(titleKey)
                latestReleasesList.append(dr.item)
            }
        }

        let rawPlaylists = ((playlistsAny as? [String: Any])?["collection"] as? [[String: Any]]) ?? []
        let playlists = rawPlaylists.compactMap { normalizePlaylist($0, forceKind: .playlist) }

        let rawFollowings = ((followingsAny as? [String: Any])?["collection"] as? [[String: Any]]) ?? []
        let related: [ArtistRef] = rawFollowings.compactMap { f in
            guard let id = f["id"] else { return nil }
            return ArtistRef(
                id: "\(id)",
                name: (f["username"] as? String) ?? "Artist",
                avatarUrl: upgradeArtworkUrl(f["avatar_url"] as? String)
            )
        }

        let featTracks = normalizedTracks.filter { $0.artists.count > 1 }
        var tags: [String] = []
        for t in normalizedTracks.prefix(12) {
            if let g = t.genre, !g.isEmpty, !tags.contains(g) {
                tags.append(g)
            }
        }

        return ArtistProfile(
            id: "\(userDict["id"] ?? cleanId)",
            name: name,
            username: (userDict["permalink"] as? String) ?? name,
            avatarUrl: avatar,
            bannerUrl: banner,
            bio: userDict["description"] as? String,
            city: userDict["city"] as? String,
            followersCount: (userDict["followers_count"] as? Int) ?? 0,
            trackCount: (userDict["track_count"] as? Int) ?? normalizedTracks.count,
            popularTracks: Array(normalizedTracks.prefix(20)),
            allTracks: normalizedTracks,
            latestRelease: latestReleasesList.first,
            latestReleases: latestReleasesList,
            featTracks: featTracks,
            albums: albums,
            singles: allSingles,
            playlists: playlists,
            relatedArtists: related,
            tags: Array(tags.prefix(6))
        )
    }

    public func hydrateReleaseTracks(_ release: ReleaseItem) async -> ReleaseItem {
        let cleanId = release.id
            .replacingOccurrences(of: "sc_pl_", with: "")
            .replacingOccurrences(of: "sc_album_", with: "")
            .replacingOccurrences(of: "sc_", with: "")

        var fullTracks: [Track] = release.tracks.filter { $0.title != "Без названия" }
        var stubIds: [String] = []

        if let dict = try? await requestJSON(path: "/playlists/\(cleanId)") as? [String: Any],
           let rawTracks = dict["tracks"] as? [[String: Any]] {
            fullTracks = []
            for item in rawTracks {
                if item["title"] != nil, let t = normalizeTrack(item) {
                    fullTracks.append(t)
                } else if let id = item["id"] {
                    stubIds.append("\(id)")
                }
            }
        } else {
            // Fallback: If playlist endpoint wasn't accessible directly, collect any stub IDs
            stubIds = release.tracks.compactMap { $0.title == "Без названия" ? $0.rawId : nil }
        }

        // Batch hydrate stub tracks in chunks of 50 (matching SoundCloud API /tracks?ids=...)
        if !stubIds.isEmpty {
            for chunkStart in stride(from: 0, to: stubIds.count, by: 50) {
                let chunk = Array(stubIds[chunkStart..<min(chunkStart + 50, stubIds.count)])
                if let arr = try? await requestJSON(
                    path: "/tracks",
                    queryItems: [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))]
                ) as? [[String: Any]] {
                    let hydrated = arr.compactMap { normalizeTrack($0) }
                    fullTracks.append(contentsOf: hydrated)
                }
            }
        }

        var updated = release
        updated.tracks = fullTracks
        updated.trackCount = max(fullTracks.count, release.trackCount)
        return updated
    }

    // MARK: - Algorithm 1: Personal Wave ("Моя волна" - Port of getPersonalWaveTracks)

    public func getPersonalWaveTracks(
        seeds: [WaveSeed],
        playHistory: [Track],
        likedTracks: [Track],
        dislikedTracks: [Track],
        currentTrack: Track?,
        forceFresh: Bool = false
    ) async -> [Track] {
        var dislikedIds = Set(dislikedTracks.map(\.id))

        // MARK: - Mode A: Explicit Artist Seeds Selected by User
        if !seeds.isEmpty {
            var seedNames = seeds.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if forceFresh { seedNames.shuffle() }
            var seedTracksByArtist: [String: [Track]] = [:]
            var relatedTracks: [Track] = []

            // Fetch tracks in parallel for EACH chosen artist
            await withTaskGroup(of: (String, [Track]).self) { group in
                for name in seedNames {
                    group.addTask {
                        var tracks = await self.searchTracks(query: name, limit: 30)
                        if forceFresh { tracks.shuffle() }
                        return (name, tracks)
                    }
                }
                for await (name, tracks) in group {
                    let nameLower = name.lowercased()
                    // Filter tracks that actually feature or belong to this artist
                    let matching = tracks.filter { tr in
                        !dislikedIds.contains(tr.id) &&
                        (tr.artist.lowercased().contains(nameLower) ||
                         tr.artists.contains(where: { $0.name.lowercased().contains(nameLower) }) ||
                         tr.title.lowercased().contains(nameLower))
                    }
                    seedTracksByArtist[name] = matching.isEmpty ? tracks.filter { !dislikedIds.contains($0.id) } : matching
                }
            }

            // Fetch related tracks from the top track of each seed artist for natural musical context
            let sampleTracks = forceFresh ? seedTracksByArtist.values.compactMap(\.first).shuffled() : seedTracksByArtist.values.compactMap(\.first)
            if !sampleTracks.isEmpty {
                await withTaskGroup(of: [Track].self) { group in
                    for tr in sampleTracks.prefix(6) where tr.source == .soundcloud {
                        let rawId = tr.rawId.replacingOccurrences(of: "sc_", with: "")
                        group.addTask {
                            await self.fetchRelatedTracks(trackId: rawId, limit: 12)
                        }
                    }
                    for await rel in group {
                        relatedTracks.append(contentsOf: rel.filter { !dislikedIds.contains($0.id) })
                    }
                }
            }
            if forceFresh { relatedTracks.shuffle() }

            // Interleave tracks across selected artists (Artist A, Artist B, Artist C, etc.)
            var result: [Track] = []
            var seenIds = Set<String>()
            let maxCountPerArtist = seedTracksByArtist.values.map(\.count).max() ?? 0

            for idx in 0..<maxCountPerArtist {
                for name in seedNames {
                    if let list = seedTracksByArtist[name], idx < list.count {
                        let tr = list[idx]
                        if !seenIds.contains(tr.id) {
                            seenIds.insert(tr.id)
                            result.append(tr)
                        }
                    }
                }
                // Sprinkle 1 related track after the first round of seed artist songs
                if idx > 0 && !relatedTracks.isEmpty {
                    if let rel = relatedTracks.first(where: { !seenIds.contains($0.id) }) {
                        seenIds.insert(rel.id)
                        result.append(rel)
                    }
                }
                if result.count >= 60 { break }
            }

            // Fill remaining queue with high-affinity related tracks
            for tr in relatedTracks where !seenIds.contains(tr.id) {
                seenIds.insert(tr.id)
                result.append(tr)
                if result.count >= 60 { break }
            }

            if !result.isEmpty {
                return result
            }
        }

        // MARK: - Mode B: History & Liked Tracks Personal Recommendation Fallback
        var artistWeights: [String: Double] = [:]
        var genreWeights: [String: Double] = [:]
        var dislikedArtistWeights: [String: Double] = [:]

        let sampleLiked = forceFresh ? likedTracks.shuffled() : likedTracks
        let sampleHistory = forceFresh ? playHistory.shuffled() : playHistory

        for (index, track) in sampleLiked.prefix(25).enumerated() {
            let recency = max(0.35, 1.0 - Double(index) * 0.03)
            artistWeights[track.artist.lowercased(), default: 0] += 1.25 * recency
            if let genre = track.genre?.lowercased(), !genre.isEmpty {
                genreWeights[genre, default: 0] += 1.1 * recency
            }
        }

        for (index, track) in sampleHistory.prefix(25).enumerated() {
            let recency = max(0.25, 1.0 - Double(index) * 0.035)
            artistWeights[track.artist.lowercased(), default: 0] += 0.8 * recency
            if let genre = track.genre?.lowercased(), !genre.isEmpty {
                genreWeights[genre, default: 0] += 0.75 * recency
            }
        }

        for track in dislikedTracks {
            dislikedIds.insert(track.id)
            dislikedArtistWeights[track.artist.lowercased(), default: 0] += 1.5
        }

        let topArtists = artistWeights.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        let topGenres = genreWeights.sorted { $0.value > $1.value }.prefix(4).map(\.key)

        var queries: [String] = []
        queries.append(contentsOf: topArtists)
        queries.append(contentsOf: topGenres)

        let freshDiscoverPool = [
            "OG Buda", "MAYOT", "Toxi$", "Heronwater", "Obladaet",
            "Saluki", "Big Baby Tape", "kizaru", "Scally Milano",
            "FRIENDLY THUG 52 NGG", "ALBLAK 52", "Платина",
            "Kai Angel", "9mice", "madk1d", "uglystephan", "macan", "ICEGERGERT"
        ]

        if queries.isEmpty || forceFresh {
            queries.append(contentsOf: freshDiscoverPool.shuffled().prefix(forceFresh ? 4 : 8))
        }

        if forceFresh {
            queries.shuffle()
        }

        var candidatePool: [Track] = []

        await withTaskGroup(of: [Track].self) { group in
            let seedTracks = Array(([currentTrack].compactMap { $0 } + sampleLiked.prefix(4) + sampleHistory.prefix(3)).prefix(6))
            for seedTrack in seedTracks where seedTrack.source == .soundcloud {
                let rawId = seedTrack.rawId.replacingOccurrences(of: "sc_", with: "")
                group.addTask {
                    var rel = await self.fetchRelatedTracks(trackId: rawId, limit: 15)
                    if forceFresh { rel.shuffle() }
                    return rel
                }
            }
            for q in Array(Set(queries)).prefix(8) {
                group.addTask {
                    var s = await self.searchTracks(query: q, limit: 15)
                    if forceFresh { s.shuffle() }
                    return s
                }
            }

            for await tracks in group {
                candidatePool.append(contentsOf: tracks)
            }
        }

        let historyIds = Set(playHistory.prefix(20).map(\.id))

        let scored: [(track: Track, score: Double)] = candidatePool.compactMap { track in
            guard !dislikedIds.contains(track.id) else { return nil }
            var score: Double = 0
            let artistKey = track.artist.lowercased()
            let genreKey = (track.genre ?? "").lowercased()

            if let w = artistWeights[artistKey] {
                score += min(46, w * 11.0)
            }
            if let gw = genreWeights[genreKey] {
                score += min(34, gw * 9.0)
            }
            if track.playbackCount > 0 {
                score += min(34, log10(Double(track.playbackCount)) * 5.2)
            }
            if track.likesCount > 0 {
                score += min(18, log10(Double(track.likesCount)) * 4.0)
            }
            if historyIds.contains(track.id) {
                score -= 25
            }
            if let dw = dislikedArtistWeights[artistKey] {
                score -= 42.0 * dw
            }
            if forceFresh {
                score += Double.random(in: -14.0...16.0)
            }
            return (track, score)
        }.sorted { $0.score > $1.score }

        return diversifyWaveTracks(scored.map(\.track), maxCount: 60)
    }

    // MARK: - Algorithm 2: TrackDNA 5-Dimension Wave ("Волна по треку" - Port of getTrackWaveTracks)

    public func getTrackWaveTracks(seedTrack: Track, dislikedIds: Set<String> = []) async -> [Track] {
        let seedGenre = (seedTrack.genre ?? "").lowercased()
        let seedText = "\(seedTrack.title) \(seedTrack.genre ?? "") \(seedTrack.tagList ?? "")".lowercased()

        // 1. Identify Genre Family
        let matchedFamily: [String] = genreFamilies.first(where: { key, values in
            seedGenre.contains(key) || values.contains(where: { seedText.contains($0) })
        })?.value ?? [seedGenre].filter { !$0.isEmpty }

        // 2. Identify Mood Palette
        let seedMoods = moodTokens.compactMap { mood, tokens in
            tokens.contains(where: { seedText.contains($0) }) ? mood : nil
        }

        // 3. Energy Class (0 = slow/ambient, 1 = mid, 2 = fast/hard)
        let seedEnergy: Int = {
            if seedTrack.duration > 300 || seedMoods.contains("chill") { return 0 }
            if seedTrack.duration < 135 || seedMoods.contains("hard") { return 2 }
            return 1
        }()

        // 4. Popularity Band (0 = <10k, 1 = 10k..500k, 2 = >500k)
        let seedPopBand: Int = {
            if seedTrack.playbackCount < 10_000 { return 0 }
            if seedTrack.playbackCount <= 500_000 { return 1 }
            return 2
        }()

        let rawId = seedTrack.rawId.replacingOccurrences(of: "sc_", with: "")
        async let related = fetchRelatedTracks(trackId: rawId, limit: 24)
        async let artistSearch = searchTracks(query: seedTrack.artist, limit: 16)
        async let genreSearch = searchTracks(query: "\(seedTrack.artist) \(matchedFamily.first ?? "")", limit: 16)

        let combined = await related + artistSearch + genreSearch

        let scored = combined.compactMap { candidate -> (Track, Double)? in
            guard candidate.id != seedTrack.id, !dislikedIds.contains(candidate.id) else { return nil }
            var score: Double = 0
            let candText = "\(candidate.title) \(candidate.genre ?? "") \(candidate.tagList ?? "")".lowercased()

            // Dimension 1: Genre family overlap (+50 max)
            if matchedFamily.contains(where: { candText.contains($0) }) {
                score += 50
            }
            // Dimension 2: Mood overlap (+30 max)
            let candMoods = moodTokens.compactMap { mood, tokens in
                tokens.contains(where: { candText.contains($0) }) ? mood : nil
            }
            let sharedMoods = Set(seedMoods).intersection(candMoods).count
            score += min(30, Double(sharedMoods) * 15)

            // Dimension 3: Energy class match (+25 max)
            let candEnergy = candidate.duration > 300 ? 0 : (candidate.duration < 135 ? 2 : 1)
            if candEnergy == seedEnergy { score += 25 }

            // Dimension 4: Popularity band match (+20 max)
            let candPop = candidate.playbackCount < 10_000 ? 0 : (candidate.playbackCount <= 500_000 ? 1 : 2)
            if candPop == seedPopBand { score += 20 }

            // Dimension 5: Popularity log boost (+18 max)
            if candidate.playbackCount > 0 {
                score += min(18, log10(Double(candidate.playbackCount)) * 3.2)
            }
            return (candidate, score)
        }.sorted { $0.1 > $1.1 }

        return diversifyWaveTracks(scored.map(\.0), maxCount: 40)
    }

    public func fetchRelatedTracks(trackId: String, limit: Int = 20) async -> [Track] {
        do {
            let json = try await requestJSON(
                path: "/tracks/\(trackId)/related",
                queryItems: [URLQueryItem(name: "limit", value: "\(limit)")]
            )
            guard let dict = json as? [String: Any],
                  let collection = dict["collection"] as? [[String: Any]] else {
                return []
            }
            return collection.compactMap { normalizeTrack($0) }
        } catch {
            return []
        }
    }

    private func diversifyWaveTracks(_ tracks: [Track], maxCount: Int) -> [Track] {
        var seenIds = Set<String>()
        var artistCounts: [String: Int] = [:]
        var result: [Track] = []

        for track in tracks {
            guard !seenIds.contains(track.id) else { continue }
            let artistKey = track.artist.lowercased()
            let maxPerArtist = result.count < 20 ? 2 : 4
            guard artistCounts[artistKey, default: 0] < maxPerArtist else { continue }

            seenIds.insert(track.id)
            artistCounts[artistKey, default: 0] += 1
            result.append(track)
            if result.count >= maxCount { break }
        }
        return result
    }

    // MARK: - Normalization & Metadata Cleaning

    private func normalizeTrack(_ raw: [String: Any], preferredQuality: AudioQualityTier = .q320) -> Track? {
        guard let rawId = raw["id"] else { return nil }
        let idStr = "\(rawId)"
        let rawTitle = (raw["title"] as? String) ?? "Без названия"
        let userDict = raw["user"] as? [String: Any]
        let fallbackArtist = (userDict?["username"] as? String) ?? "Неизвестный артист"
        let artistId = userDict?["id"].map { "\($0)" }
        let userAvatar = upgradeArtworkUrl(userDict?["avatar_url"] as? String)

        let cleaned = Self.parseCleanTrackInfo(rawTitle: rawTitle, fallbackArtist: fallbackArtist, primaryArtistId: artistId, primaryAvatar: userAvatar)

        let fullDurationMs = (raw["full_duration"] as? Double) ?? (raw["duration"] as? Double) ?? 0
        let durationMs = (raw["duration"] as? Double) ?? fullDurationMs
        let isSnippet = fullDurationMs > 45_000 && durationMs <= 35_000

        let artwork = upgradeArtworkUrl((raw["artwork_url"] as? String) ?? (userDict?["avatar_url"] as? String))

        // Select transcoding
        let media = raw["media"] as? [String: Any]
        let transcodings = (media?["transcodings"] as? [[String: Any]]) ?? []
        let nonSnipped = transcodings.filter { ($0["snipped"] as? Bool) != true }
        let pool = nonSnipped.isEmpty ? transcodings : nonSnipped

        let chosenTranscoding: [String: Any]? = {
            switch preferredQuality {
            case .q1411, .q320:
                return pool.first(where: { ($0["quality"] as? String) == "hq" })
                    ?? pool.first(where: { (($0["format"] as? [String: Any])?["protocol"] as? String)?.contains("progressive") == true })
                    ?? pool.first
            case .q192:
                return pool.first(where: { ($0["quality"] as? String) == "sq" }) ?? pool.first
            case .q256:
                return pool.first(where: { (($0["format"] as? [String: Any])?["protocol"] as? String)?.contains("progressive") == true })
                    ?? pool.first
            }
        }()

        let transcodingUrl = chosenTranscoding?["url"] as? String
        let protocolStr = ((chosenTranscoding?["format"] as? [String: Any])?["protocol"] as? String) ?? ""
        let isHls = protocolStr.contains("hls")

        let publisherMeta = raw["publisher_metadata"] as? [String: Any]
        let explicit = (publisherMeta?["explicit"] as? Bool) ?? false

        return Track(
            id: "sc_\(idStr)",
            rawId: idStr,
            title: cleaned.cleanTitle,
            rawTitle: cleaned.rawTitle,
            artist: cleaned.artistDisplay,
            artists: cleaned.artists,
            uploaderId: artistId,
            uploaderName: fallbackArtist,
            coverUrl: artwork,
            duration: max(fullDurationMs, durationMs) / 1000.0,
            streamUrl: nil,
            transcodingUrl: transcodingUrl,
            isHls: isHls,
            isSnippet: isSnippet,
            isExplicit: explicit,
            genre: raw["genre"] as? String,
            tagList: raw["tag_list"] as? String,
            playbackCount: (raw["playback_count"] as? Int) ?? 0,
            likesCount: (raw["likes_count"] as? Int) ?? 0,
            source: .soundcloud
        )
    }

    private func normalizePlaylist(_ raw: [String: Any], forceKind: ReleaseKind? = nil) -> ReleaseItem? {
        guard let rawId = raw["id"] else { return nil }
        let title = (raw["title"] as? String) ?? "Плейлист"
        let userDict = raw["user"] as? [String: Any]
        let artist = (userDict?["username"] as? String) ?? "AmyMusic"
        let artistId = userDict?["id"].map { "\($0)" }
        let rawTracks = (raw["tracks"] as? [[String: Any]]) ?? []
        let tracks = rawTracks.compactMap { item -> Track? in
            guard item["title"] != nil else { return nil }
            return normalizeTrack(item)
        }
        let firstTrackCover = tracks.first?.coverUrl
        let artwork = upgradeArtworkUrl(raw["artwork_url"] as? String) ?? firstTrackCover
        let isAlbum = (raw["is_album"] as? Bool) ?? false
        let kind = forceKind ?? (isAlbum ? .album : .playlist)
        let trackCount = (raw["track_count"] as? Int) ?? tracks.count

        return ReleaseItem(
            id: "sc_pl_\(rawId)",
            title: title,
            artist: artist,
            artistId: artistId,
            coverUrl: artwork,
            kind: kind,
            trackCount: trackCount,
            tracks: tracks
        )
    }

    private func upgradeArtworkUrl(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        return url
            .replacingOccurrences(of: "-large.", with: "-t500x500.")
            .replacingOccurrences(of: "-t300x300.", with: "-t500x500.")
            .replacingOccurrences(of: "-badge.", with: "-t500x500.")
    }

    /// Cleans junk tags, extracts feat/ft/with artists from title & artist, keeps creator as primary target
    public static func parseCleanTrackInfo(
        rawTitle: String,
        fallbackArtist: String,
        primaryArtistId: String?,
        primaryAvatar: String?
    ) -> (cleanTitle: String, rawTitle: String, artistDisplay: String, artists: [ArtistRef]) {
        var cleaned = rawTitle
        let junkPatterns = [
            "\\[Official[^\\]]*\\]", "\\(Official[^\\)]*\\)",
            "\\[Music Video\\]", "\\(Music Video\\)",
            "\\[Lyrics?\\]", "\\(Lyrics?\\)",
            "\\[HD\\]", "\\[HQ\\]",
            "\\[Audio\\]", "\\(Audio\\)"
        ]
        for pattern in junkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        var artistPart = fallbackArtist
        var titlePart = cleaned

        // Robust artist & title splitter for dash / separator formats (hyphen, en-dash, em-dash, horizontal bar, tilde, colon, pipe)
        let dashRegex = try? NSRegularExpression(
            pattern: #"^(.+?)(?:\s+[-–—―~:|]\s*|\s*[-–—―~:|]\s+)(.+)$"#,
            options: .caseInsensitive
        )
        if let match = dashRegex?.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            if let r1 = Range(match.range(at: 1), in: cleaned),
               let r2 = Range(match.range(at: 2), in: cleaned) {
                let left = String(cleaned[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(cleaned[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty && !right.isEmpty {
                    artistPart = left
                    titlePart = right
                }
            }
        }

        // Extract featured artists from titlePart (e.g. "(feat. Toxi$)", "[ft. OG Buda, MAYOT]", "feat. Someone")
        var featArtistNames: [String] = []
        let featTitlePatterns = [
            #"(?i)[\(\[]\s*(?:feat\.?|ft\.?|with)\s+([^\]\)]+)[\)\]]"#,
            #"(?i)\s+(?:feat\.?|ft\.?)\s+(.+)$"#
        ]

        for pattern in featTitlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: titlePart, range: NSRange(titlePart.startIndex..., in: titlePart)) {
                if let r = Range(match.range(at: 1), in: titlePart) {
                    let extracted = String(titlePart[r])
                    let rawFeats = extracted
                        .replacingOccurrences(of: " & ", with: ",")
                        .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
                        .replacingOccurrences(of: " feat. ", with: ",", options: .caseInsensitive)
                        .replacingOccurrences(of: " ft. ", with: ",", options: .caseInsensitive)
                        .components(separatedBy: CharacterSet(charactersIn: ",&×;"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    featArtistNames.append(contentsOf: rawFeats)
                }
                // Strip the feat tag from title
                titlePart = regex.stringByReplacingMatches(in: titlePart, range: NSRange(titlePart.startIndex..., in: titlePart), withTemplate: "")
            }
        }
        titlePart = titlePart.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse individual artists from artistPart (split by &, and, x, X, ×, feat., ft., with, comma, +, /)
        let artistSplitRegex = try? NSRegularExpression(
            pattern: #"(?:\s*(?:,|&|\band\b|×|\bfeat\.?\b|\bft\.?\b|\bwith\b|;)\s*|\s+(?:[xX]|\/|\+)\s+)"#,
            options: .caseInsensitive
        )
        var rawArtistNames: [String] = []
        if let splitRegex = artistSplitRegex {
            let replaced = splitRegex.stringByReplacingMatches(in: artistPart, range: NSRange(artistPart.startIndex..., in: artistPart), withTemplate: "___")
            rawArtistNames = replaced.components(separatedBy: "___")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            rawArtistNames = [artistPart]
        }

        var allNames: [String] = []
        for name in rawArtistNames + featArtistNames {
            if !allNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                allNames.append(name)
            }
        }

        if allNames.isEmpty {
            allNames = [fallbackArtist]
        }

        let artists: [ArtistRef] = allNames.map { name in
            let matchesUploader = name.caseInsensitiveCompare(fallbackArtist) == .orderedSame
            let aId = (matchesUploader && primaryArtistId != nil && !primaryArtistId!.isEmpty) ? primaryArtistId! : name
            let avatar = matchesUploader ? primaryAvatar : nil
            return ArtistRef(
                id: aId,
                name: name,
                avatarUrl: avatar
            )
        }

        let display = artists.map(\.name).joined(separator: ", ")
        return (titlePart.isEmpty ? cleaned : titlePart, cleaned, display, artists)
    }

    public static func renormalizeTrackIfNeeded(_ track: Track) -> Track {
        var tr = track
        let raw = tr.rawTitle ?? tr.title
        let cleaned = Self.parseCleanTrackInfo(
            rawTitle: raw,
            fallbackArtist: tr.artist,
            primaryArtistId: tr.artists.first?.id,
            primaryAvatar: tr.artists.first?.avatarUrl
        )
        tr.title = cleaned.cleanTitle
        tr.rawTitle = cleaned.rawTitle
        tr.artist = cleaned.artistDisplay
        tr.artists = cleaned.artists
        return tr
    }
}
