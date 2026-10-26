import Foundation

// MARK: - Multi-Source Lyrics Service (LRCLIB & Genius)

public actor LyricsService {
    public static let shared = LyricsService()

    private var memoryCache: [String: LyricsPayload] = [:]

    public func fetchLyrics(
        for track: Track,
        preferredSource: LyricsSourceKind = .auto,
        forceRefresh: Bool = false
    ) async -> LyricsPayload {
        let key = "\(track.artist.lowercased())_\(track.title.lowercased())_\(preferredSource.rawValue)"

        if forceRefresh {
            let baseKey = "\(track.artist.lowercased())_\(track.title.lowercased())"
            memoryCache = memoryCache.filter { !$0.key.contains(baseKey) }
            if let raw = track.rawTitle {
                let rawKey = "\(track.artist.lowercased())_\(raw.lowercased())"
                memoryCache = memoryCache.filter { !$0.key.contains(rawKey) }
            }
        } else if let cached = memoryCache[key] {
            return cached
        }

        let payload: LyricsPayload
        switch preferredSource {
        case .lrclib:
            payload = await fetchFromLRCLib(track: track) ?? .empty
        case .genius:
            payload = await fetchFromGenius(track: track) ?? .empty
        case .auto:
            let trackHasCyrillic = track.title.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil ||
                                  track.artist.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil

            // Parallel race between LRCLib (synced) and Genius (plain + annotations)
            async let lrcTask = fetchFromLRCLib(track: track)
            async let genTask = fetchFromGenius(track: track)

            let (lrcRes, genRes) = await (lrcTask, genTask)
            if let genRes {
                memoryCache["\(track.artist.lowercased())_\(track.title.lowercased())_\(LyricsSourceKind.genius.rawValue)"] = genRes
            }
            if let lrcRes {
                memoryCache["\(track.artist.lowercased())_\(track.title.lowercased())_\(LyricsSourceKind.lrclib.rawValue)"] = lrcRes
            }

            // Language prioritization: if song is Russian/Cyrillic, ensure lyrics are in original language
            let lrcIsCyrillic = lrcRes?.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
            let genIsCyrillic = genRes?.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil

            if trackHasCyrillic {
                if let lrc = lrcRes, lrc.status == .synced && lrcIsCyrillic {
                    payload = lrc
                } else if let gen = genRes, genIsCyrillic {
                    payload = gen
                } else if let lrc = lrcRes, lrcIsCyrillic {
                    payload = lrc
                } else if let lrc = lrcRes, lrc.status == .synced {
                    payload = lrc
                } else if let gen = genRes {
                    payload = gen
                } else if let lrc = lrcRes {
                    payload = lrc
                } else {
                    payload = .empty
                }
            } else {
                if let lrc = lrcRes, lrc.status == .synced {
                    payload = lrc
                } else if let lrc = lrcRes {
                    payload = lrc
                } else if let gen = genRes {
                    payload = gen
                } else {
                    payload = .empty
                }
            }
        }

        if payload.status != .empty {
            memoryCache[key] = payload
        }
        return payload
    }

    public func clearCache() {
        memoryCache.removeAll()
    }

    // MARK: - Candidate Pairs Generator (Multi-Artist Feat & Individual Checks)

    private struct CandidateSearchPair {
        let artist: String
        let title: String
        let isCyrillic: Bool
    }

    private func buildSearchCandidatePairs(track: Track) -> [CandidateSearchPair] {
        var pairs: [CandidateSearchPair] = []
        var seen = Set<String>()

        func addPair(_ artist: String, _ title: String) {
            let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let key = "\(a.lowercased())___\(t.lowercased())"
            if !seen.contains(key) {
                seen.insert(key)
                let isCyr = t.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil ||
                            a.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
                pairs.append(CandidateSearchPair(artist: a, title: t, isCyrillic: isCyr))
            }
        }

        let cleanTitle = cleanTextForSearch(track.title)
        let rawTitle = track.rawTitle != nil ? cleanTextForSearch(track.rawTitle!) : cleanTitle
        let primaryArtist = track.artists.first?.name ?? track.artist
        let otherArtists = track.artists.dropFirst().map(\.name)

        // Stage A: If title or rawTitle contains a dash separator, extract left and right
        // e.g. "9mice - Honey Bunny" when artist is "SOURCE MUSIC" -> extract (9mice, Honey Bunny)
        for tString in [rawTitle, cleanTitle] {
            let dashRegex = try? NSRegularExpression(pattern: #"^(.+?)\s*[-–—―~:]\s*(.+)$"#, options: .caseInsensitive)
            if let match = dashRegex?.firstMatch(in: tString, range: NSRange(tString.startIndex..., in: tString)),
               let r1 = Range(match.range(at: 1), in: tString),
               let r2 = Range(match.range(at: 2), in: tString) {
                let left = cleanTextForSearch(String(tString[r1]))
                let right = cleanTextForSearch(String(tString[r2]))
                if !left.isEmpty && !right.isEmpty {
                    addPair(left, right)
                    addPair(right, left)
                }
            }
        }

        // Stage B: Main artist + cleanTitle
        addPair(primaryArtist, cleanTitle)
        if track.artist != primaryArtist {
            addPair(track.artist, cleanTitle)
        }

        // Stage C: Featuring combinations
        if !otherArtists.isEmpty {
            addPair("\(primaryArtist) feat. \(otherArtists.joined(separator: " & "))", cleanTitle)
            addPair("\(primaryArtist) & \(otherArtists.joined(separator: " & "))", cleanTitle)
            addPair("\(primaryArtist), \(otherArtists.joined(separator: ", "))", cleanTitle)
        }

        // Stage D: Individual featured artists
        for feat in otherArtists {
            addPair(feat, cleanTitle)
        }

        // Stage E: Pure song title alone (for Genius and LRCLib search when artist is uploader or record label)
        addPair("", cleanTitle)

        // Stage F: Repeat with rawTitle if different
        if rawTitle.lowercased() != cleanTitle.lowercased() {
            addPair(primaryArtist, rawTitle)
            addPair("", rawTitle)
        }

        // Stage G: If uploader name exists and is different from artist
        if let uploader = track.uploaderName, !uploader.isEmpty, uploader != track.artist {
            addPair(uploader, cleanTitle)
        }

        return pairs
    }

    // MARK: - 1. LRCLIB (https://lrclib.net/api)

    private func fetchFromLRCLib(track: Track) async -> LyricsPayload? {
        let candidates = buildSearchCandidatePairs(track: track)
        for cand in candidates {
            if let payload = await fetchLRCLibSingle(artist: cand.artist, title: cand.title, duration: track.duration, isCyrillicSong: cand.isCyrillic) {
                return payload
            }
        }
        return nil
    }

    private func fetchLRCLibSingle(artist: String, title: String, duration: TimeInterval, isCyrillicSong: Bool) async -> LyricsPayload? {
        let headers = ["LrcLib-Client": "Amymusic (https://github.com/sergetik52/AmyMusic)"]

        // Step 1: Try /api/get with artist & title (without strict duration if strict fails)
        if !artist.isEmpty && !title.isEmpty {
            var getComp = URLComponents(string: "https://lrclib.net/api/get")
            var qItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist)
            ]
            if duration > 0 {
                qItems.append(URLQueryItem(name: "duration", value: "\(Int(duration.rounded()))"))
            }
            getComp?.queryItems = qItems

            if let url = getComp?.url,
               let dict = await requestJSONDictionary(url: url, headers: headers),
               let parsed = parseLRCLibRecord(dict, duration: duration) {
                if !isCyrillicSong || parsed.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil {
                    return parsed
                }
            }

            // Step 1b: Try /api/get WITHOUT duration (duration on streaming sites often differs by 2-5 sec)
            if duration > 0 {
                var noDurComp = URLComponents(string: "https://lrclib.net/api/get")
                noDurComp?.queryItems = [
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: artist)
                ]
                if let url = noDurComp?.url,
                   let dict = await requestJSONDictionary(url: url, headers: headers),
                   let parsed = parseLRCLibRecord(dict, duration: duration) {
                    if !isCyrillicSong || parsed.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil {
                        return parsed
                    }
                }
            }
        }

        // Step 2: Search via /api/search with track_name & artist_name
        var searchQueries: [URL] = []
        if !artist.isEmpty && !title.isEmpty {
            if var comp = URLComponents(string: "https://lrclib.net/api/search") {
                comp.queryItems = [
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: artist)
                ]
                if let u = comp.url { searchQueries.append(u) }
            }
            if var comp = URLComponents(string: "https://lrclib.net/api/search") {
                comp.queryItems = [URLQueryItem(name: "q", value: "\(artist) \(title)")]
                if let u = comp.url { searchQueries.append(u) }
            }
        }
        if !title.isEmpty {
            if var comp = URLComponents(string: "https://lrclib.net/api/search") {
                comp.queryItems = [URLQueryItem(name: "q", value: title)]
                if let u = comp.url { searchQueries.append(u) }
            }
        }

        for searchUrl in searchQueries {
            guard let arr = await requestJSONArray(url: searchUrl, headers: headers), !arr.isEmpty else {
                continue
            }

            let sorted = arr.sorted { a, b in
                if isCyrillicSong {
                    let nameA = (a["trackName"] as? String) ?? ""
                    let nameB = (b["trackName"] as? String) ?? ""
                    let cyrA = nameA.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
                    let cyrB = nameB.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
                    if cyrA != cyrB { return cyrA && !cyrB }
                }
                // Synced lyrics prioritized over plain lyrics
                let syncA = (a["syncedLyrics"] as? String) != nil
                let syncB = (b["syncedLyrics"] as? String) != nil
                if syncA != syncB { return syncA && !syncB }

                let dA = abs(((a["duration"] as? Double) ?? duration) - duration)
                let dB = abs(((b["duration"] as? Double) ?? duration) - duration)
                return dA < dB
            }

            for record in sorted {
                if let parsed = parseLRCLibRecord(record, duration: duration) {
                    if !isCyrillicSong || parsed.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil {
                        return parsed
                    }
                }
            }
        }

        return nil
    }

    private func parseLRCLibRecord(_ dict: [String: Any], duration: TimeInterval) -> LyricsPayload? {
        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = Self.parseSyncedLyrics(synced, trackDuration: duration)
            if !lines.isEmpty {
                return LyricsPayload(
                    source: "LRCLib",
                    status: .synced,
                    lines: lines,
                    plainText: lines.map(\.text).joined(separator: "\n"),
                    annotations: [:]
                )
            }
        }
        if let plain = dict["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = Self.parsePlainLyrics(plain, duration: duration)
            return LyricsPayload(
                source: "LRCLib",
                status: .plain,
                lines: lines,
                plainText: plain,
                annotations: [:]
            )
        }
        return nil
    }

    // MARK: - 2. Genius Lyrics & Annotations

    private let browserHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    ]

    private func cleanTextForSearch(_ text: String) -> String {
        var res = text
        let patterns = [
            #"\((feat\.|ft\.|prod\.|with)[^\)]*\)"#,
            #"\[(feat\.|ft\.|prod\.|with)[^\]]*\]"#,
            #"\((prod\.\s*by|produced\s*by)[^\)]*\)"#,
            #"\[(prod\.\s*by|produced\s*by)[^\]]*\]"#,
            #"\((slowed\s*\+?\s*reverb|slowed|speed\s*up|sped\s*up)[^\)]*\)"#,
            #"\[(slowed\s*\+?\s*reverb|slowed|speed\s*up|sped\s*up)[^\]]*\]"#,
            #"\[Official[^\]]*\]"#,
            #"\((Official|Official Music Video|Music Video|Lyrics?|Audio|Clip)[^\)]*\)"#,
            #"\[(Music Video|Lyrics?|HD|HQ|Audio|Visualizer|Remastered)[^\]]*\]"#,
            #"[\"“«»”]"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                res = regex.stringByReplacingMatches(in: res, range: NSRange(res.startIndex..., in: res), withTemplate: "")
            }
        }
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchFromGenius(track: Track) async -> LyricsPayload? {
        let candidates = buildSearchCandidatePairs(track: track)
        for cand in candidates {
            if let payload = await fetchGeniusSingle(artist: cand.artist, title: cand.title, duration: track.duration, isCyrillicSong: cand.isCyrillic) {
                return payload
            }
        }
        return nil
    }

    private func fetchGeniusSingle(artist: String, title: String, duration: TimeInterval, isCyrillicSong: Bool) async -> LyricsPayload? {
        var candidateQueries: [String] = []
        if !artist.isEmpty && !title.isEmpty {
            candidateQueries.append("\(artist) \(title)")
        }
        if !title.isEmpty && title != artist {
            candidateQueries.append(title)
        }

        let translationKeywords = [
            "english translation", "english lyrics", "english version",
            "translation", "romanized", "traduction", "traducción",
            "deutsche übersetzung", "deutsche", "перевод на английский",
            "lyrics in english", "translated", "italiana", "polski", "lyrics english"
        ]

        var candidateHits: [[String: Any]] = []

        for q in candidateQueries {
            // Step 1: /api/search/song
            var searchComp = URLComponents(string: "https://genius.com/api/search/song")
            searchComp?.queryItems = [
                URLQueryItem(name: "per_page", value: "10"),
                URLQueryItem(name: "q", value: q)
            ]
            if let searchUrl = searchComp?.url,
               let root = await requestJSONDictionary(url: searchUrl, headers: browserHeaders),
               let response = root["response"] as? [String: Any],
               let sections = response["sections"] as? [[String: Any]] {
                let songHits = sections.first(where: { ($0["type"] as? String) == "song" })?["hits"] as? [[String: Any]] ?? []
                let hits = songHits.compactMap { $0["result"] as? [String: Any] }
                if !hits.isEmpty {
                    candidateHits = hits
                    break
                }
            }

            // Step 2: /api/search/multi fallback
            var multiComp = URLComponents(string: "https://genius.com/api/search/multi")
            multiComp?.queryItems = [
                URLQueryItem(name: "per_page", value: "10"),
                URLQueryItem(name: "q", value: q)
            ]
            if let multiUrl = multiComp?.url,
               let root = await requestJSONDictionary(url: multiUrl, headers: browserHeaders),
               let response = root["response"] as? [String: Any],
               let sections = response["sections"] as? [[String: Any]] {
                let songHits = sections.first(where: { ($0["type"] as? String) == "song" })?["hits"] as? [[String: Any]] ?? []
                let hits = songHits.compactMap { $0["result"] as? [String: Any] }
                if !hits.isEmpty {
                    candidateHits = hits
                    break
                }
            }
        }

        if candidateHits.isEmpty {
            return nil
        }

        // Sort candidate hits: prioritize original language and avoid translations
        let sortedHits = candidateHits.sorted { a, b in
            let titleA = ((a["full_title"] as? String) ?? (a["title"] as? String) ?? "").lowercased()
            let titleB = ((b["full_title"] as? String) ?? (b["title"] as? String) ?? "").lowercased()

            let isTransA = translationKeywords.contains(where: { titleA.contains($0) })
            let isTransB = translationKeywords.contains(where: { titleB.contains($0) })

            if isTransA != isTransB {
                return !isTransA && isTransB // Non-translations come first
            }

            if isCyrillicSong {
                let hasCyrA = titleA.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
                let hasCyrB = titleB.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
                if hasCyrA != hasCyrB {
                    return hasCyrA && !hasCyrB
                }
            }

            return false
        }

        for hit in sortedHits.prefix(4) {
            guard let songUrlStr = hit["url"] as? String,
                  let songUrl = URL(string: songUrlStr) else {
                continue
            }

            var pageReq = URLRequest(url: songUrl)
            pageReq.timeoutInterval = 10
            for (k, v) in browserHeaders { pageReq.setValue(v, forHTTPHeaderField: k) }

            guard let (htmlData, resp) = try? await URLSession.shared.data(for: pageReq),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: htmlData, encoding: .utf8) else {
                continue
            }

            let extracted = Self.extractGeniusLyricsAndAnnotations(from: html)
            guard !extracted.plainText.isEmpty else { continue }

            let lyricsHasCyrillic = extracted.plainText.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
            if isCyrillicSong && !lyricsHasCyrillic && sortedHits.count > 1 {
                continue
            }

            var annotationsMap: [String: String] = [:]
            var refFragments: [(fragment: String, id: String)] = []

            if let songId = hit["id"],
               let refUrl = URL(string: "https://genius.com/api/referents?song_id=\(songId)&per_page=50&text_format=plain"),
               let refRoot = await requestJSONDictionary(url: refUrl, headers: browserHeaders),
               let refResp = refRoot["response"] as? [String: Any],
               let referents = refResp["referents"] as? [[String: Any]] {
                for ref in referents {
                    if let refId = ref["id"],
                       let anns = ref["annotations"] as? [[String: Any]],
                       let body = (anns.first?["body"] as? [String: Any])?["plain"] as? String {
                        let cleanBody = Self.cleanAnnotationText(body)
                        if !cleanBody.isEmpty {
                            let idStr = "\(refId)"
                            annotationsMap[idStr] = cleanBody

                            if let fragment = ref["fragment"] as? String, !fragment.isEmpty {
                                let cleanFrag = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                                refFragments.append((cleanFrag, idStr))
                            }
                        }
                    }
                }
            }

            // Also include extracted HTML annotations if not already present
            for (id, rawText) in extracted.annotations {
                if annotationsMap[id] == nil {
                    let clean = Self.cleanAnnotationText(rawText)
                    if !clean.isEmpty {
                        annotationsMap[id] = clean
                    }
                }
            }

            let lines = Self.parsePlainLyrics(extracted.plainText, duration: duration, refFragments: refFragments)
            return LyricsPayload(
                source: "Genius",
                status: .plain,
                lines: lines,
                plainText: extracted.plainText,
                annotations: annotationsMap
            )
        }

        return nil
    }

    /// Strips URLs, markdown links, HTML images, and markup from annotation text
    public static func cleanAnnotationText(_ raw: String) -> String {
        var text = raw

        // 1. Remove markdown images ![alt](url)
        text = text.replacingOccurrences(of: #"!\[.*?\]\([^\)]*\)"#, with: "", options: .regularExpression)

        // 2. Remove HTML images <img ...>
        text = text.replacingOccurrences(of: #"(?i)<img[^>]*>"#, with: "", options: .regularExpression)

        // 3. Convert markdown links [text](url) -> text
        text = text.replacingOccurrences(of: #"\[(.*?)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)

        // 4. Convert HTML links <a ...>text</a> -> text
        text = text.replacingOccurrences(of: #"(?i)<a[^>]*>(.*?)</a>"#, with: "$1", options: .regularExpression)

        // 5. Remove standalone URLs (http:// or https://)
        text = text.replacingOccurrences(of: #"https?://[^\s\)\>]+"#, with: "", options: .regularExpression)

        // 6. Remove remaining HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // 7. Decode HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&quot;", "\""), ("&#x27;", "'"), ("&apos;", "'"),
            ("&#39;", "'"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&#8212;", "—"), ("&#8211;", "–"), ("&#8216;", "‘"), ("&#8217;", "’"),
            ("&#8220;", "“"), ("&#8221;", "”"), ("&hellip;", "…")
        ]
        for (ent, rep) in entities {
            text = text.replacingOccurrences(of: ent, with: rep)
        }

        // 8. Collapse multiple blank lines
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Section Header & Spacing Rules

    /// Identifies structural markers like [Припев], [Куплет 1], [Chorus], [Intro], etc. to remove them and replace with stanza gaps
    public static func isSectionHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        // Remove [Текст песни ...] / Lyrics[Текст песни ...]
        if trimmed.range(of: #"(?i)(?:lyrics)?\s*\[текст\s+песни"#, options: .regularExpression) != nil {
            return true
        }

        // Bracketed headers: [Припев], [Куплет: артист], [Chorus], [Intro], [Outro], etc.
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return true
        }

        // Unbracketed markers with colon/number: "Припев:", "Куплет 1:", "Chorus:", etc.
        let pattern = #"^(припев|куплет|интро|аутро|бридж|хук|скит|соло|chorus|verse|intro|outro|bridge|pre-chorus|hook|drop|solo|refrain|interlude)[\s\d:]*$"#
        if trimmed.lowercased().range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    // MARK: - LRC & Plain Text Parsing Utilities

    /// Parses multi-timestamp LRC lines (`[mm:ss.xx]`) with section headers removed and stanza gaps added
    public static func parseSyncedLyrics(_ lrc: String, trackDuration: TimeInterval) -> [LyricLine] {
        let rawLines = lrc.components(separatedBy: .newlines)
        let pattern = #"\[(\d+):(\d{2}(?:\.\d{1,3})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var temp: [(time: TimeInterval, text: String, hasVerseGap: Bool)] = []
        var pendingVerseGap = false

        for rawLine in rawLines {
            let nsRange = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = regex.matches(in: rawLine, range: nsRange)
            guard !matches.isEmpty else {
                if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !temp.isEmpty { pendingVerseGap = true }
                }
                continue
            }

            let textStart = matches.last!.range.upperBound
            let textIndex = rawLine.index(rawLine.startIndex, offsetBy: textStart)
            var text = String(rawLine[textIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip [Текст песни ...] if present
            if text.range(of: #"(?i)\[текст\s+песни"#, options: .regularExpression) != nil {
                text = text.replacingOccurrences(of: #"(?i)^.*?(?:lyrics)?\s*\[текст\s+песни[^\]]*\]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if text.isEmpty {
                if !temp.isEmpty { pendingVerseGap = true }
                continue
            }

            // Remove headers like [Припев], [Куплет], [Chorus] and replace with a gap
            if isSectionHeader(text) {
                if !temp.isEmpty { pendingVerseGap = true }
                continue
            }

            let hasGap = pendingVerseGap
            pendingVerseGap = false

            for match in matches {
                if let minRange = Range(match.range(at: 1), in: rawLine),
                   let secRange = Range(match.range(at: 2), in: rawLine),
                   let mins = Double(rawLine[minRange]),
                   let secs = Double(rawLine[secRange]) {
                    temp.append((mins * 60.0 + secs, text, hasGap))
                }
            }
        }

        temp.sort { $0.time < $1.time }

        return temp.enumerated().map { index, item in
            let nextTime = (index + 1 < temp.count) ? temp[index + 1].time : max(item.time + 4.0, trackDuration)
            let lineSpan = max(0.8, min(6.5, nextTime - item.time - 0.15))
            let tokens = item.text.split(separator: " ").map(String.init)
            let totalWeight = max(1, tokens.reduce(0) { $0 + max(1, $1.count) })
            var currentStart = item.time

            let words: [LyricWord] = tokens.enumerated().map { wIdx, word in
                let wordWeight = Double(max(1, word.count))
                let wordDuration = lineSpan * (wordWeight / Double(totalWeight))
                let start = currentStart
                let end = start + wordDuration
                currentStart = end
                return LyricWord(
                    id: "\(index)_\(wIdx)",
                    text: word,
                    startTime: start,
                    endTime: end
                )
            }

            return LyricLine(
                id: "lrc_\(index)_\(item.time)",
                time: item.time,
                text: item.text,
                isEstimated: false,
                words: words,
                hasVerseGap: item.hasVerseGap
            )
        }
    }

    /// Parses plain text lyrics with section headers removed, stanza gaps preserved, and annotations mapped
    public static func parsePlainLyrics(
        _ plain: String,
        duration: TimeInterval,
        refFragments: [(fragment: String, id: String)] = [],
        lineAnnotations: [Int: String] = [:]
    ) -> [LyricLine] {
        let rawLines = plain.components(separatedBy: .newlines)
        var filtered: [(text: String, hasVerseGap: Bool, originalIndex: Int)] = []
        var pendingVerseGap = false

        for (idx, line) in rawLines.enumerated() {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !filtered.isEmpty { pendingVerseGap = true }
                continue
            }

            // Strip [Текст песни ...] or ...Lyrics[Текст песни ...]
            if trimmed.range(of: #"(?i)\[текст\s+песни"#, options: .regularExpression) != nil ||
               trimmed.range(of: #"(?i)lyrics\s*\["#, options: .regularExpression) != nil {
                trimmed = trimmed.replacingOccurrences(of: #"(?i)^.*?(?:lyrics)?\s*\[текст\s+песни[^\]]*\]\s*"#, with: "", options: .regularExpression)
                trimmed = trimmed.replacingOccurrences(of: #"(?i)^.*?\blyrics\b\s*\[[^\]]+\]\s*"#, with: "", options: .regularExpression)
                trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
            }

            // Remove headers like [Куплет 1], [Припев], [Chorus] and replace with a gap
            if isSectionHeader(trimmed) {
                if !filtered.isEmpty { pendingVerseGap = true }
                continue
            }

            let hasGap = pendingVerseGap
            pendingVerseGap = false
            filtered.append((trimmed, hasGap, idx))
        }

        guard !filtered.isEmpty else { return [] }
        let step = duration > 0 ? max(1.6, duration / Double(filtered.count + 1)) : 3.4

        func normString(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        return filtered.enumerated().map { idx, item in
            let itemNorm = normString(item.text)
            var matchedAnnId = lineAnnotations[idx] ?? lineAnnotations[item.originalIndex]

            if matchedAnnId == nil && !itemNorm.isEmpty {
                for rf in refFragments {
                    let fragNorm = normString(rf.fragment)
                    if !fragNorm.isEmpty && fragNorm.count >= 3 {
                        if itemNorm.contains(fragNorm) || fragNorm.contains(itemNorm) {
                            matchedAnnId = rf.id
                            break
                        }
                    }
                }
            }

            return LyricLine(
                id: "plain_\(idx)",
                time: step * (Double(idx) + 0.7),
                text: item.text,
                isEstimated: true,
                annotationId: matchedAnnId,
                hasVerseGap: item.hasVerseGap
            )
        }
    }

    /// Finds the active lyric index with `+0.08s` lookahead and custom user millisecond offset
    public static func activeLyricIndex(
        in lines: [LyricLine],
        currentTime: TimeInterval,
        offsetMs: Double = 0
    ) -> Int? {
        guard !lines.isEmpty else { return nil }
        let adjusted = currentTime + 0.08 - (offsetMs / 1000.0)
        var active: Int? = nil
        for (idx, line) in lines.enumerated() {
            if adjusted >= line.time {
                active = idx
            } else {
                break
            }
        }
        return active
    }

    // MARK: - Helpers

    private static func extractGeniusLyricsAndAnnotations(from html: String) -> (plainText: String, lines: [String], lineAnnotationIds: [Int: String], annotations: [String: String]) {
        var rawContainers: [String] = []

        // Extract complete container elements using balanced <div>...</div> depth tracking
        let markers = ["data-lyrics-container=\"true\"", "class=\"Lyrics__Container", "class=\"lyrics\""]
        for marker in markers {
            var searchStart = html.startIndex
            while searchStart < html.endIndex, let range = html.range(of: marker, range: searchStart..<html.endIndex) {
                let prefixSlice = html[html.startIndex..<range.lowerBound]
                guard let _ = prefixSlice.range(of: "<div", options: .backwards)?.lowerBound else {
                    searchStart = range.upperBound
                    continue
                }
                guard let closeAngle = html[range.lowerBound..<html.endIndex].firstIndex(of: ">") else {
                    searchStart = range.upperBound
                    continue
                }

                var depth = 1
                var curr = html.index(after: closeAngle)
                let contentStart = curr

                while curr < html.endIndex && depth > 0 {
                    let remaining = html[curr..<html.endIndex]
                    let nextOpen = remaining.range(of: "<div")
                    let nextClose = remaining.range(of: "</div>")

                    guard let closeR = nextClose else { break }

                    if let openR = nextOpen, openR.lowerBound < closeR.lowerBound {
                        depth += 1
                        curr = openR.upperBound
                    } else {
                        depth -= 1
                        if depth == 0 {
                            let containerContent = String(html[contentStart..<closeR.lowerBound])
                            rawContainers.append(containerContent)
                            searchStart = closeR.upperBound
                            break
                        }
                        curr = closeR.upperBound
                    }
                }
                if depth > 0 {
                    searchStart = range.upperBound
                }
            }
            if !rawContainers.isEmpty { break }
        }

        guard !rawContainers.isEmpty else {
            return ("", [], [:], [:])
        }

        var lineAnnotationIds: [Int: String] = [:]
        var annotations: [String: String] = [:]

        // Process containers
        var cleanedBlocks: [String] = []
        for container in rawContainers {
            var block = container

            // Strip nested exclude-from-selection, Contributors chips, and song headers
            block = block.replacingOccurrences(of: #"(?s)<div[^>]*data-exclude-from-selection="true"[\s\S]*?</div>"#, with: "", options: .regularExpression)
            block = block.replacingOccurrences(of: #"(?s)<div[^>]*class="LyricsHeader[^\"]*"[\s\S]*?</div>"#, with: "", options: .regularExpression)
            block = block.replacingOccurrences(of: #"(?s)<div[^>]*class="SongBioPreview[^\"]*"[\s\S]*?</div>"#, with: "", options: .regularExpression)

            // Extract referent annotations: <a href="/(\d+)/...">...</a>
            let linkPattern = #"<a\s+href="/(\d+)/[^"]*"[^>]*>([\s\S]*?)</a>"#
            if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) {
                let matches = linkRegex.matches(in: block, range: NSRange(block.startIndex..., in: block))
                for match in matches {
                    if let idRange = Range(match.range(at: 1), in: block),
                       let textRange = Range(match.range(at: 2), in: block) {
                        let refId = String(block[idRange])
                        let rawFrag = String(block[textRange])
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !refId.isEmpty && !rawFrag.isEmpty {
                            annotations[refId] = rawFrag
                        }
                    }
                }
            }

            // Replace <br/> with newline
            block = block.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)

            // Strip other HTML tags
            block = block.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            // Decode HTML entities
            let entities: [(String, String)] = [
                ("&amp;", "&"), ("&quot;", "\""), ("&#x27;", "'"), ("&apos;", "'"),
                ("&#39;", "'"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
                ("&#8212;", "—"), ("&#8211;", "–"), ("&#8216;", "‘"), ("&#8217;", "’"),
                ("&#8220;", "“"), ("&#8221;", "”"), ("&hellip;", "…")
            ]
            for (ent, rep) in entities {
                block = block.replacingOccurrences(of: ent, with: rep)
            }

            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBlock.isEmpty {
                cleanedBlocks.append(trimmedBlock)
            }
        }

        let combined = cleanedBlocks.joined(separator: "\n\n")
        var parsedLines: [String] = []

        for rawLine in combined.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                parsedLines.append("")
                continue
            }

            // Strip any [Текст песни ...] or ...Lyrics[Текст песни ...] anywhere in the line
            if line.range(of: #"(?i)\[текст\s+песни"#, options: .regularExpression) != nil ||
               line.range(of: #"(?i)lyrics\s*\["#, options: .regularExpression) != nil {
                line = line.replacingOccurrences(of: #"(?i)^.*?(?:lyrics)?\s*\[текст\s+песни[^\]]*\]\s*"#, with: "", options: .regularExpression)
                line = line.replacingOccurrences(of: #"(?i)^.*?\blyrics\b\s*\[[^\]]+\]\s*"#, with: "", options: .regularExpression)
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
            }

            let lower = line.lowercased()
            // Strip metadata headers and artifacts
            if lower.range(of: #"^\d+\s*(contributors?|авторов)"#, options: .regularExpression) != nil { continue }
            if lower.hasPrefix("translations") || lower.hasPrefix("переводы") { continue }
            if lower.hasPrefix("romanization") || lower.hasPrefix("романизация") { continue }
            if lower.hasPrefix("[текст песни") || lower.hasPrefix("текст песни") { continue }
            if lower.hasPrefix("read more") { continue }
            if (lower.hasSuffix("lyrics") || lower.hasSuffix("текст")) && line.count < 80 { continue }
            if lower == "embed" || (lower.hasPrefix("embed") && line.count < 12) { continue }
            if lower.contains("you might also like") { continue }

            parsedLines.append(line)
        }

        // Clean any leading empty lines or remnant headers
        while let first = parsedLines.first {
            let lower = first.lowercased()
            if lower.isEmpty ||
               lower.contains("текст песни") ||
               lower.hasSuffix("lyrics") ||
               lower.range(of: #"^\d+\s*contributor"#, options: .regularExpression) != nil {
                parsedLines.removeFirst()
            } else {
                break
            }
        }

        let finalText = parsedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (finalText, parsedLines, lineAnnotationIds, annotations)
    }

    private func requestJSONDictionary(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 8) async -> [String: Any]? {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func requestJSONArray(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 8) async -> [[String: Any]]? {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return arr
    }
}
