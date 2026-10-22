import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Spotify Native Service
// Supports Method 2 (Official Web API with OAuth2 PKCE login) + Method 1 (Public Embed Parser fallback)
// Tracks are bridged to SoundCloud for free 320 kbps playback.

public actor SpotifyService {
    public static let shared = SpotifyService()
    public static let defaultClientId = "0c0053dd5bfd401f9a5b064273513e5e"

    private let apiBase = "https://api.spotify.com/v1"
    private let tokenUrl = "https://accounts.spotify.com/api/token"
    private let authUrl = "https://accounts.spotify.com/authorize"
    private let redirectUri = "amymusic://spotify-callback"

    private var settings: AppProfileSettings = AppProfileSettings()
    private var resolvedTrackCache: [String: Track] = [:]
    private var anonymousAccessToken: String?
    private var anonymousTokenExpiry: Date?

    public func updateSettings(_ settings: AppProfileSettings) {
        self.settings = settings
    }

    // MARK: - OAuth 2.0 PKCE Flow (Method 2: Full Account Authorization)

    public func getValidAccessToken() async -> String? {
        let token = settings.spotifyAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            if let expiry = settings.spotifyTokenExpiry, expiry < Date().addingTimeInterval(60) {
                if let refreshed = await refreshAccessToken() {
                    return refreshed
                }
            } else {
                return token
            }
        }

        if let anon = anonymousAccessToken, let exp = anonymousTokenExpiry, exp > Date().addingTimeInterval(60) {
            return anon
        }

        return nil
    }

    public func refreshAccessToken() async -> String? {
        let refreshToken = settings.spotifyRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else { return nil }

        var clientId = settings.spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientId.isEmpty {
            clientId = SpotifyService.defaultClientId
        }

        guard let url = URL(string: tokenUrl) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "client_id=\(clientId)"
        ].joined(separator: "&")
        request.httpBody = bodyParams.data(using: .utf8)

        do {
            let session = SoundCloudProxyManager.shared.session(for: self.settings)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access_token"] as? String else {
                return nil
            }

            self.settings.spotifyAccessToken = newAccess
            if let newRefresh = json["refresh_token"] as? String {
                self.settings.spotifyRefreshToken = newRefresh
            }
            if let expiresIn = json["expires_in"] as? Double {
                self.settings.spotifyTokenExpiry = Date().addingTimeInterval(expiresIn)
            }
            return newAccess
        } catch {
            return nil
        }
    }

    public struct SpotifyAuthResult: Sendable {
        public let accessToken: String
        public let refreshToken: String
        public let expiry: Date
        public let userId: String
        public let displayName: String
        public let avatarUrl: String
    }

    public func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> SpotifyAuthResult {
        guard let url = URL(string: tokenUrl) else { throw URLError(.badURL) }
        var clientId = settings.spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientId.isEmpty {
            clientId = SpotifyService.defaultClientId
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=authorization_code",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri)",
            "client_id=\(clientId)",
            "code_verifier=\(codeVerifier)"
        ].joined(separator: "&")
        request.httpBody = bodyParams.data(using: .utf8)

        let session = SoundCloudProxyManager.shared.session(for: self.settings)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw URLError(.badServerResponse)
        }

        let refresh = (json["refresh_token"] as? String) ?? ""
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let expiry = Date().addingTimeInterval(expiresIn)

        var userId = ""
        var displayName = ""
        var avatarUrl = ""

        // Fetch User Profile
        if let profile = await fetchCurrentUserProfile(token: access) {
            userId = (profile["id"] as? String) ?? ""
            displayName = (profile["display_name"] as? String) ?? ""
            if let images = profile["images"] as? [[String: Any]], let firstImg = images.first?["url"] as? String {
                avatarUrl = firstImg
            }
        }

        self.settings.spotifyAccessToken = access
        self.settings.spotifyRefreshToken = refresh
        self.settings.spotifyTokenExpiry = expiry
        self.settings.spotifyUserId = userId
        self.settings.spotifyUserDisplayName = displayName
        self.settings.spotifyUserAvatar = avatarUrl

        return SpotifyAuthResult(
            accessToken: access,
            refreshToken: refresh,
            expiry: expiry,
            userId: userId,
            displayName: displayName,
            avatarUrl: avatarUrl
        )
    }

    public func fetchCurrentUserProfile(token: String) async -> [String: Any]? {
        guard let url = URL(string: "\(apiBase)/me") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = SoundCloudProxyManager.shared.session(for: self.settings)
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - Method 2: Official Web API Fetching

    private func requestSpotifyAPI(path: String, queryItems: [URLQueryItem] = [], tokenOverride: String? = nil) async throws -> [String: Any] {
        let token: String
        if let tokenOverride, !tokenOverride.isEmpty {
            token = tokenOverride
        } else if let valid = await getValidAccessToken() {
            token = valid
        } else {
            throw URLError(.userAuthenticationRequired)
        }

        var components = URLComponents(string: "\(apiBase)\(path)")
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = SoundCloudProxyManager.shared.session(for: self.settings)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }

    private func extractInt(from value: Any?) -> Int? {
        guard let value else { return nil }
        if let intVal = value as? Int { return intVal }
        if let numVal = value as? NSNumber { return numVal.intValue }
        if let strVal = value as? String, let parsed = Int(strVal.trimmingCharacters(in: .whitespaces)) { return parsed }
        if let doubleVal = value as? Double { return Int(doubleVal) }
        return nil
    }

    private func parseTrackCount(from dict: [String: Any]) -> Int {
        if let tracksDict = dict["tracks"] as? [String: Any] {
            if let total = extractInt(from: tracksDict["total"]), total > 0 { return total }
            if let count = extractInt(from: tracksDict["count"]), count > 0 { return count }
        }
        if let itemsDict = dict["items"] as? [String: Any] {
            if let total = extractInt(from: itemsDict["total"]), total > 0 { return total }
            if let count = extractInt(from: itemsDict["count"]), count > 0 { return count }
        }
        if let total = extractInt(from: dict["total"]), total > 0 { return total }
        if let total = extractInt(from: dict["total_tracks"]), total > 0 { return total }
        if let total = extractInt(from: dict["track_count"]), total > 0 { return total }
        if let total = extractInt(from: dict["tracks"]), total > 0 { return total }
        if let items = dict["items"] as? [Any], !items.isEmpty { return items.count }
        if let tracks = dict["tracks"] as? [Any], !tracks.isEmpty { return tracks.count }
        return 0
    }

    public func fetchPlaylistTrackCount(id: String) async -> Int {
        do {
            let meta = try await requestSpotifyAPI(path: "/playlists/\(id)/tracks", queryItems: [
                URLQueryItem(name: "limit", value: "1")
            ])
            return extractInt(from: meta["total"]) ?? 0
        } catch {
            return 0
        }
    }

    public func fetchUserPlaylists() async -> [ReleaseItem] {
        var rawList: [(id: String, title: String, owner: String, coverUrl: String?, trackCount: Int)] = []
        var offset = 0
        let limit = 50

        while true {
            do {
                let root = try await requestSpotifyAPI(path: "/me/playlists", queryItems: [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)")
                ])
                let items = (root["items"] as? [[String: Any]]) ?? []
                if items.isEmpty { break }

                for dict in items {
                    guard let id = dict["id"] as? String,
                          let title = dict["name"] as? String else { continue }
                    let owner = (dict["owner"] as? [String: Any])?["display_name"] as? String ?? "Spotify"
                    let images = dict["images"] as? [[String: Any]]
                    let coverUrl = images?.first?["url"] as? String
                    let count = parseTrackCount(from: dict)

                    rawList.append((id: id, title: title, owner: owner, coverUrl: coverUrl, trackCount: count))
                }

                offset += items.count
                let total = extractInt(from: root["total"]) ?? rawList.count
                if offset >= total || items.count < limit { break }
            } catch {
                break
            }
        }

        // For any playlist where trackCount is 0, fetch exact track count from /playlists/{id}/tracks?limit=1 in parallel!
        var verifiedCounts: [String: Int] = [:]
        let needsCount = rawList.filter { $0.trackCount == 0 }

        if !needsCount.isEmpty {
            await withTaskGroup(of: (String, Int).self) { group in
                for item in needsCount {
                    let plId = item.id
                    group.addTask {
                        let cnt = await self.fetchPlaylistTrackCount(id: plId)
                        return (plId, cnt)
                    }
                }
                for await (plId, cnt) in group {
                    if cnt > 0 {
                        verifiedCounts[plId] = cnt
                    }
                }
            }
        }

        return rawList.map { item in
            let finalCount = item.trackCount > 0 ? item.trackCount : (verifiedCounts[item.id] ?? 0)
            return ReleaseItem(
                id: "spotify_pl_\(item.id)",
                title: item.title,
                artist: item.owner,
                coverUrl: item.coverUrl,
                kind: .userPlaylist,
                trackCount: finalCount,
                tracks: []
            )
        }
    }

    private func parsePlaylistTrackItem(_ item: [String: Any]) -> Track? {
        let tDict = (item["track"] as? [String: Any]) ?? (item["item"] as? [String: Any]) ?? item
        guard let tTitle = tDict["name"] as? String, !tTitle.isEmpty else { return nil }

        let rawId = (tDict["id"] as? String) ?? (tDict["uri"] as? String)?.replacingOccurrences(of: "spotify:track:", with: "") ?? UUID().uuidString
        let tId = rawId.isEmpty ? UUID().uuidString : rawId

        let rawArtists = (tDict["artists"] as? [[String: Any]]) ?? []
        let artistRefs: [ArtistRef] = rawArtists.compactMap { a in
            guard let aName = a["name"] as? String else { return nil }
            let aId = (a["id"] as? String) ?? aName
            return ArtistRef(id: aId, name: aName, avatarUrl: nil)
        }
        let artistName = artistRefs.isEmpty ? "Неизвестный артист" : artistRefs.map(\.name).joined(separator: ", ")
        let albumDict = tDict["album"] as? [String: Any]
        let albumImages = albumDict?["images"] as? [[String: Any]]
        let tCover = albumImages?.first?["url"] as? String // Exact individual track album cover
        let durationMs = extractInt(from: tDict["duration_ms"]) ?? 180_000
        let explicit = (tDict["explicit"] as? Bool) ?? false

        return Track(
            id: "spotify_\(tId)",
            rawId: tId,
            title: tTitle,
            rawTitle: tTitle,
            artist: artistName,
            artists: artistRefs,
            coverUrl: tCover,
            duration: Double(durationMs) / 1000.0,
            isExplicit: explicit,
            source: .spotify,
            palette: TrackPalette.defaultPalette
        )
    }

    private func parseAlbumTrackItem(_ tDict: [String: Any], albumArtist: String, albumCover: String?) -> Track? {
        guard let tId = tDict["id"] as? String,
              let tTitle = tDict["name"] as? String else { return nil }

        let tArtists = (tDict["artists"] as? [[String: Any]]) ?? []
        let artistRefs: [ArtistRef] = tArtists.compactMap { a in
            guard let aName = a["name"] as? String else { return nil }
            let aId = (a["id"] as? String) ?? aName
            return ArtistRef(id: aId, name: aName, avatarUrl: nil)
        }
        let trackArtist = artistRefs.isEmpty ? albumArtist : artistRefs.map(\.name).joined(separator: ", ")
        let durationMs = (tDict["duration_ms"] as? Double) ?? 180_000
        let explicit = (tDict["explicit"] as? Bool) ?? false

        return Track(
            id: "spotify_\(tId)",
            rawId: tId,
            title: tTitle,
            rawTitle: tTitle,
            artist: trackArtist,
            artists: artistRefs,
            coverUrl: albumCover,
            duration: durationMs / 1000.0,
            isExplicit: explicit,
            source: .spotify,
            palette: TrackPalette.defaultPalette
        )
    }

    public func fetchPlaylistWebAPI(id: String, tokenOverride: String? = nil) async -> (title: String, artist: String, coverUrl: String?, tracks: [Track])? {
        do {
            let root = try await requestSpotifyAPI(path: "/playlists/\(id)", tokenOverride: tokenOverride)
            let title = (root["name"] as? String) ?? "Плейлист Spotify"
            let owner = (root["owner"] as? [String: Any])?["display_name"] as? String ?? "Spotify"
            let images = root["images"] as? [[String: Any]]
            let playlistCoverUrl = images?.first?["url"] as? String

            let tracksObj = (root["tracks"] as? [String: Any]) ?? (root["items"] as? [String: Any])
            let items = (tracksObj?["items"] as? [[String: Any]]) ?? (root["items"] as? [[String: Any]]) ?? []
            var tracks: [Track] = []

            for item in items {
                if let tr = parsePlaylistTrackItem(item) {
                    tracks.append(tr)
                }
            }

            // Pagination: Fetch ALL tracks without any limit (100, 500, 1000+ tracks)
            let totalTracksCount: Int = {
                if let n = (tracksObj?["total"] as? NSNumber)?.intValue, n > 0 { return n }
                if let n = tracksObj?["total"] as? Int, n > 0 { return n }
                if let n = (root["total"] as? NSNumber)?.intValue, n > 0 { return n }
                if let n = root["total"] as? Int, n > 0 { return n }
                return 0
            }()
            var offset = items.count
            let pageSize = 50

            while true {
                if totalTracksCount > 0 && offset >= totalTracksCount { break }
                do {
                    let page = try await requestSpotifyAPI(
                        path: "/playlists/\(id)/tracks",
                        queryItems: [
                            URLQueryItem(name: "offset", value: "\(offset)"),
                            URLQueryItem(name: "limit", value: "\(pageSize)")
                        ],
                        tokenOverride: tokenOverride
                    )
                    let pageItems = (page["items"] as? [[String: Any]]) ?? []
                    if pageItems.isEmpty { break }
                    for item in pageItems {
                        if let tr = parsePlaylistTrackItem(item) {
                            tracks.append(tr)
                        }
                    }
                    offset += pageItems.count
                    if pageItems.count < pageSize { break }
                } catch {
                    print("[Spotify] fetch page error at offset \(offset): \(error)")
                    break
                }
            }

            return (title, owner, playlistCoverUrl, tracks)
        } catch {
            return nil
        }
    }

    public func fetchAlbumWebAPI(id: String, tokenOverride: String? = nil) async -> (title: String, artist: String, coverUrl: String?, tracks: [Track])? {
        do {
            let root = try await requestSpotifyAPI(path: "/albums/\(id)", tokenOverride: tokenOverride)
            let title = (root["name"] as? String) ?? "Альбом Spotify"
            let rawArtists = (root["artists"] as? [[String: Any]]) ?? []
            let artistStr = rawArtists.compactMap { $0["name"] as? String }.joined(separator: ", ")
            let images = root["images"] as? [[String: Any]]
            let coverUrl = images?.first?["url"] as? String

            let tracksObj = root["tracks"] as? [String: Any]
            let items = (tracksObj?["items"] as? [[String: Any]]) ?? []
            var tracks: [Track] = []

            for tDict in items {
                if let tr = parseAlbumTrackItem(tDict, albumArtist: artistStr, albumCover: coverUrl) {
                    tracks.append(tr)
                }
            }

            // Pagination for albums without limit
            let total = (tracksObj?["total"] as? Int) ?? items.count
            var offset = items.count

            while offset < total {
                do {
                    let page = try await requestSpotifyAPI(
                        path: "/albums/\(id)/tracks",
                        queryItems: [
                            URLQueryItem(name: "offset", value: "\(offset)"),
                            URLQueryItem(name: "limit", value: "50")
                        ],
                        tokenOverride: tokenOverride
                    )
                    let pageItems = (page["items"] as? [[String: Any]]) ?? []
                    if pageItems.isEmpty { break }
                    for tDict in pageItems {
                        if let tr = parseAlbumTrackItem(tDict, albumArtist: artistStr, albumCover: coverUrl) {
                            tracks.append(tr)
                        }
                    }
                    offset += pageItems.count
                } catch {
                    break
                }
            }

            return (title, artistStr.isEmpty ? "Spotify" : artistStr, coverUrl, tracks)
        } catch {
            return nil
        }
    }

    public func fetchTrackWebAPI(id: String, tokenOverride: String? = nil) async -> Track? {
        do {
            let tDict = try await requestSpotifyAPI(path: "/tracks/\(id)", tokenOverride: tokenOverride)
            guard let tId = tDict["id"] as? String,
                  let tTitle = tDict["name"] as? String else { return nil }

            let rawArtists = (tDict["artists"] as? [[String: Any]]) ?? []
            let artistRefs: [ArtistRef] = rawArtists.compactMap { a in
                guard let aName = a["name"] as? String else { return nil }
                let aId = (a["id"] as? String) ?? aName
                return ArtistRef(id: aId, name: aName, avatarUrl: nil)
            }
            let artistName = artistRefs.isEmpty ? "Неизвестный артист" : artistRefs.map(\.name).joined(separator: ", ")
            let albumDict = tDict["album"] as? [String: Any]
            let albumImages = albumDict?["images"] as? [[String: Any]]
            let tCover = albumImages?.first?["url"] as? String
            let durationMs = (tDict["duration_ms"] as? Double) ?? 180_000
            let explicit = (tDict["explicit"] as? Bool) ?? false

            return Track(
                id: "spotify_\(tId)",
                rawId: tId,
                title: tTitle,
                rawTitle: tTitle,
                artist: artistName,
                artists: artistRefs,
                coverUrl: tCover,
                duration: durationMs / 1000.0,
                isExplicit: explicit,
                source: .spotify,
                palette: TrackPalette.defaultPalette
            )
        } catch {
            return nil
        }
    }

    // MARK: - Method 1: Public Embed Fallback Parser (No Auth / Registration Needed!)

    public func fetchEmbedRelease(type: String, id: String) async -> (title: String, artist: String, coverUrl: String?, tracks: [Track])? {
        guard let url = URL(string: "https://open.spotify.com/embed/\(type)/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("ru,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let session = SoundCloudProxyManager.shared.session(for: self.settings)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Extract JSON from <script id="__NEXT_DATA__" type="application/json">...</script>
        guard let scriptStart = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let scriptEnd = html[scriptStart.upperBound...].range(of: "</script>") else {
            return nil
        }

        let jsonString = String(html[scriptStart.upperBound..<scriptEnd.lowerBound])
        guard let jsonData = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let stateData = state["data"] as? [String: Any] else {
            return nil
        }

        // If embed contains anonymous access token in settings.session, save it and fetch official Web API with full pagination!
        if let settingsObj = stateData["settings"] as? [String: Any],
           let sessionObj = settingsObj["session"] as? [String: Any],
           let anonToken = sessionObj["accessToken"] as? String, !anonToken.isEmpty {
            self.anonymousAccessToken = anonToken
            if let expMs = sessionObj["accessTokenExpirationTimestampMs"] as? Double {
                self.anonymousTokenExpiry = Date(timeIntervalSince1970: expMs / 1000.0)
            } else {
                self.anonymousTokenExpiry = Date().addingTimeInterval(3600)
            }

            if type == "playlist" {
                if let full = await fetchPlaylistWebAPI(id: id, tokenOverride: anonToken) {
                    return full
                }
            } else if type == "album" {
                if let full = await fetchAlbumWebAPI(id: id, tokenOverride: anonToken) {
                    return full
                }
            }
        }

        guard let entity = stateData["entity"] as? [String: Any] else { return nil }

        let title = (entity["title"] as? String) ?? (entity["name"] as? String) ?? "Spotify \(type.capitalized)"
        let subtitle = (entity["subtitle"] as? String) ?? "Spotify"
        let coverSources = (entity["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]]
        let playlistCoverUrl = coverSources?.first?["url"] as? String

        let rawTracks = (entity["trackList"] as? [[String: Any]]) ?? []
        var tracks: [Track] = []

        for (idx, tDict) in rawTracks.enumerated() {
            guard let tTitle = tDict["title"] as? String else { continue }
            let tArtist = (tDict["subtitle"] as? String) ?? subtitle
            let durationMs = (tDict["duration"] as? Double) ?? 180_000
            let explicit = (tDict["isExplicit"] as? Bool) ?? false
            let uri = (tDict["uri"] as? String) ?? "spotify:track:\(idx)"
            let tId = uri.replacingOccurrences(of: "spotify:track:", with: "")

            let artistRefs = tArtist.components(separatedBy: CharacterSet(charactersIn: ",/&")).map {
                let clean = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return ArtistRef(id: clean, name: clean, avatarUrl: nil)
            }

            // Do NOT use playlistCoverUrl for tracks! Leave nil if no track cover is found, so SoundCloud will provide the real track artwork!
            var trackCover: String? = nil
            if let album = tDict["album"] as? [String: Any],
               let images = album["images"] as? [[String: Any]],
               let u = images.first?["url"] as? String {
                trackCover = u
            }

            tracks.append(Track(
                id: "spotify_\(tId)",
                rawId: tId,
                title: tTitle,
                rawTitle: tTitle,
                artist: tArtist,
                artists: artistRefs,
                coverUrl: trackCover,
                duration: durationMs / 1000.0,
                isExplicit: explicit,
                source: .spotify,
                palette: TrackPalette.defaultPalette
            ))
        }

        return (title, subtitle, playlistCoverUrl, tracks)
    }

    // MARK: - Playlist / Album Link Importer (0.2s Instant Import + Parallel SoundCloud Resolution)

    public func importPlaylistFromUrl(
        _ urlString: String,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> ReleaseItem? {
        let trimmedInput = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }

        // Pre-resolve shortlinks (e.g. spotify.link/...)
        var targetUrl = await SoundCloudService.resolveRedirectUrl(trimmedInput)
        targetUrl = targetUrl.components(separatedBy: "?").first ?? targetUrl

        var releaseTitle = "Spotify Плейлист"
        var releaseArtist = "Spotify"
        var releaseCover: String?
        var rawTracks: [Track] = []

        // Format 1: Track -> open.spotify.com/track/{id}
        if let trackMatch = targetUrl.range(of: #"open\.spotify\.com/track/([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let matchedStr = String(targetUrl[trackMatch])
            let trackId = matchedStr.replacingOccurrences(of: "open.spotify.com/track/", with: "")

            var singleTrack: Track? = nil
            if await getValidAccessToken() != nil {
                singleTrack = await fetchTrackWebAPI(id: trackId)
            }
            if singleTrack == nil {
                if let embed = await fetchEmbedRelease(type: "track", id: trackId) {
                    singleTrack = embed.tracks.first
                    releaseTitle = embed.title
                    releaseArtist = embed.artist
                    releaseCover = embed.coverUrl
                }
            }
            if let single = singleTrack {
                rawTracks = [single]
                releaseTitle = single.title
                releaseArtist = single.artist
                releaseCover = single.coverUrl
            }
        }
        // Format 2: Album -> open.spotify.com/album/{id}
        else if let albumMatch = targetUrl.range(of: #"open\.spotify\.com/album/([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let matchedStr = String(targetUrl[albumMatch])
            let albumId = matchedStr.replacingOccurrences(of: "open.spotify.com/album/", with: "")

            var result: (title: String, artist: String, coverUrl: String?, tracks: [Track])? = nil
            if await getValidAccessToken() != nil {
                result = await fetchAlbumWebAPI(id: albumId)
            }
            if result == nil {
                result = await fetchEmbedRelease(type: "album", id: albumId)
            }
            if let r = result {
                releaseTitle = r.title
                releaseArtist = r.artist
                releaseCover = r.coverUrl
                rawTracks = r.tracks
            }
        }
        // Format 3: Playlist -> open.spotify.com/playlist/{id}
        else if let plMatch = targetUrl.range(of: #"open\.spotify\.com/playlist/([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let matchedStr = String(targetUrl[plMatch])
            let plId = matchedStr.replacingOccurrences(of: "open.spotify.com/playlist/", with: "")
            return await importSpotifyPlaylistById(plId, onProgress: onProgress)
        }

        guard !rawTracks.isEmpty else { return nil }

        let releaseId = "spotify_pl_\(UUID().uuidString)"
        let imported = ReleaseItem(
            id: releaseId,
            title: releaseTitle,
            artist: releaseArtist,
            coverUrl: releaseCover ?? rawTracks.first?.coverUrl,
            kind: .userPlaylist,
            trackCount: rawTracks.count,
            tracks: rawTracks
        )
        ReleaseCacheManager.shared.set(imported)

        // Launch high-speed background SoundCloud stream resolution (6 concurrent workers)
        Task.detached {
            await self.resolveReleaseTracksInBackground(releaseId: releaseId, tracks: rawTracks, onProgress: onProgress)
        }

        return imported
    }

    public func importSpotifyPlaylistById(
        _ playlistId: String,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> ReleaseItem? {
        let cleanId = playlistId.replacingOccurrences(of: "spotify_pl_", with: "").replacingOccurrences(of: "spotify:playlist:", with: "")
        var releaseTitle = "Spotify Плейлист"
        var releaseArtist = "Spotify"
        var releaseCover: String?
        var rawTracks: [Track] = []

        var result: (title: String, artist: String, coverUrl: String?, tracks: [Track])? = nil
        if await getValidAccessToken() != nil {
            result = await fetchPlaylistWebAPI(id: cleanId)
        }
        if result == nil {
            result = await fetchEmbedRelease(type: "playlist", id: cleanId)
        }
        if let r = result {
            releaseTitle = r.title
            releaseArtist = r.artist
            releaseCover = r.coverUrl
            rawTracks = r.tracks
        }

        guard !rawTracks.isEmpty else { return nil }

        let releaseId = "spotify_pl_\(cleanId)"
        let imported = ReleaseItem(
            id: releaseId,
            title: releaseTitle,
            artist: releaseArtist,
            coverUrl: releaseCover ?? rawTracks.first?.coverUrl,
            kind: .userPlaylist,
            trackCount: rawTracks.count,
            tracks: rawTracks
        )
        ReleaseCacheManager.shared.set(imported)

        // Launch high-speed background SoundCloud stream resolution (6 concurrent workers)
        Task.detached {
            await self.resolveReleaseTracksInBackground(releaseId: releaseId, tracks: rawTracks, onProgress: onProgress)
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

            while trackIndex < min(maxConcurrent, total) {
                let idx = trackIndex
                let tr = tracks[idx]
                group.addTask {
                    let resolved = await self.resolvePlayableSoundCloudTrack(for: tr)
                    return (idx, resolved)
                }
                trackIndex += 1
            }

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

    // MARK: - Resolve Spotify Track via SoundCloud API (Playable Stream Bridge)

    public func resolvePlayableSoundCloudTrack(for spotifyTrack: Track) async -> Track? {
        if let cached = resolvedTrackCache[spotifyTrack.id] {
            return cached
        }

        // 1. Full artist + title
        let q1 = "\(spotifyTrack.artist) \(spotifyTrack.title)"
        let res1 = await SoundCloudService.shared.searchTracks(query: q1, limit: 5)
        var matched = res1.first(where: { !$0.isSnippet }) ?? res1.first

        // 2. Primary artist + clean title
        if matched == nil {
            let primaryArtist = spotifyTrack.artist.components(separatedBy: CharacterSet(charactersIn: ",&×/;")).first?.trimmingCharacters(in: .whitespaces) ?? spotifyTrack.artist
            let cleanTitle = spotifyTrack.title.replacingOccurrences(of: #"(?i)[\(\[].*?[\)\]]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let q2 = "\(primaryArtist) \(cleanTitle)"
            let res2 = await SoundCloudService.shared.searchTracks(query: q2, limit: 5)
            matched = res2.first(where: { !$0.isSnippet }) ?? res2.first
        }

        // 3. Title only
        if matched == nil {
            let res3 = await SoundCloudService.shared.searchTracks(query: spotifyTrack.title, limit: 3)
            matched = res3.first(where: { !$0.isSnippet }) ?? res3.first
        }

        guard var best = matched else { return nil }

        // Retain Spotify high-res album cover & palette
        if let cover = spotifyTrack.coverUrl, !cover.isEmpty {
            best.coverUrl = cover
        }
        best.palette = spotifyTrack.palette

        resolvedTrackCache[spotifyTrack.id] = best
        return best
    }
}

// MARK: - PKCE Helper for Spotify OAuth2

public enum SpotifyPKCE {
    public static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - ASWebAuthenticationSession Context Provider

@MainActor
public final class SpotifyAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = SpotifyAuthPresentationContext()

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
