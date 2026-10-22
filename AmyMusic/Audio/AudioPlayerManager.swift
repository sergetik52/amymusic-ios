import Foundation
import AVFoundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit
import AuthenticationServices

// MARK: - Native iOS 26 Dual-Engine Audio Player, 10-Band EQ & Queue Manager
// Port of src/audio/AudioPlayerContext.jsx

@Observable
@MainActor
public final class AudioPlayerManager {
    public static let shared = AudioPlayerManager()

    // MARK: - Playback State
    public var currentTrack: Track?
    public var queue: [Track] = []
    public var originalQueue: [Track] = []
    public var currentIndex: Int = 0
    public var isPlaying: Bool = false
    public var isLoading: Bool = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var volume: Float = 0.85 {
        didSet { applyVolumeToActiveEngine() }
    }
    public var isShuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .off
    public var isAutoplayEnabled: Bool = true
    public var audioEnergy: AudioEnergy = .zero

    // MARK: - User Library & Collections State
    public var likedTracks: [Track] = []
    public var dislikedTracks: [Track] = []
    public var playHistory: [Track] = []
    public var savedReleases: [ReleaseItem] = []
    public var userPlaylists: [ReleaseItem] = []
    public var spotifyUserPlaylists: [ReleaseItem] = []
    public var isFetchingSpotifyPlaylists: Bool = false
    public var importingSpotifyPlaylistIds: Set<String> = []
    public var subscribedArtists: [ArtistRef] = []
    public var waveSeeds: [WaveSeed] = []
    public var forYouTracks: [Track] = []
    public var chartTracks: [Track] = []
    public var totalListenedSeconds: Int = 0

    // MARK: - Lyrics State
    public var currentLyrics: LyricsPayload = .empty
    public var isLyricsLoading: Bool = false
    public var lyricsOffsetsMs: [String: Double] = [:]

    // MARK: - Profile & Settings State
    public var settings: AppProfileSettings = AppProfileSettings() {
        didSet {
            saveSettings()
            applyEqualizerSettings()
            Task {
                await SoundCloudService.shared.updateSettings(settings)
                await YandexMusicService.shared.updateSettings(settings)
                await SpotifyService.shared.updateSettings(settings)
                await loadInitialRecommendations()
            }
        }
    }

    public func persistSettings() {
        saveSettings()
        Task {
            await SoundCloudService.shared.updateSettings(settings)
            await YandexMusicService.shared.updateSettings(settings)
            await SpotifyService.shared.updateSettings(settings)
            await loadInitialRecommendations()
        }
    }

    // MARK: - Dual AVPlayer Engine & Crossfade State
    private let players: [AVPlayer] = [AVPlayer(), AVPlayer()]
    private var activeEngineIdx: Int = 0
    private var isCrossfading: Bool = false
    private var crossfadeTask: Task<Void, Never>?
    private var trackLoadTask: Task<Void, Never>?
    private var didTriggerCrossfadeForCurrentTrack: Bool = false
    private var timeObserverTokens: [Any?] = [nil, nil]
    private var energyTimer: Timer?
    private var audioResourceLoader: ProxyAudioResourceLoader?
    private var listenAccumulator: Double = 0

    // MARK: - AVAudioEngine 10-Band EQ Graph
    private let audioEngine = AVAudioEngine()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 10)

    private let persistenceKey = "amymusic.ios26.state.v1"
    private let settingsKey = "amymusic.ios26.settings.v1"

    public init() {
        loadSettings()
        loadPersistedState()
        configureAudioSession()
        configureEqualizerBands()
        setupPlayerObservers()
        setupRemoteTransportControls()
        startEnergyLoop()

        Task {
            await SoundCloudService.shared.updateSettings(settings)
            await YandexMusicService.shared.updateSettings(settings)
            await SpotifyService.shared.updateSettings(settings)
            await loadInitialRecommendations()
            if !settings.spotifyAccessToken.isEmpty {
                await loadSpotifyPlaylists()
            }
        }
    }

    // MARK: - Audio Session & Remote Command Center (Lock Screen / AirPods / CarPlay)

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true, options: [])
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            print("[AmyMusic:audio] AVAudioSession setup error: \(error)")
        }
    }

    private func configureEqualizerBands() {
        for (idx, freq) in EqualizerPreset.frequencies.enumerated() where idx < eqNode.bands.count {
            let band = eqNode.bands[idx]
            band.frequency = freq
            if idx == 0 {
                band.filterType = .lowShelf
                band.bandwidth = 1.0
            } else if idx == EqualizerPreset.frequencies.count - 1 {
                band.filterType = .highShelf
                band.bandwidth = 1.0
            } else {
                band.filterType = .parametric
                band.bandwidth = 1.4
            }
            band.bypass = !settings.equalizerEnabled
            band.gain = settings.equalizerEnabled && idx < settings.equalizerBands.count ? settings.equalizerBands[idx] : 0
        }
    }

    public func applyEqualizerSettings() {
        eqNode.bypass = !settings.equalizerEnabled
        for (idx, band) in eqNode.bands.enumerated() {
            band.bypass = !settings.equalizerEnabled
            if idx < settings.equalizerBands.count {
                band.gain = min(12, max(-12, settings.equalizerBands[idx]))
            }
        }
    }

    public func selectEqualizerPreset(_ preset: EqualizerPreset) {
        settings.equalizerPreset = preset
        settings.equalizerBands = preset.gains
        settings.equalizerEnabled = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func setEqualizerBand(_ index: Int, gain: Float) {
        guard index >= 0 && index < settings.equalizerBands.count else { return }
        settings.equalizerBands[index] = min(12, max(-12, gain))
        settings.equalizerEnabled = true
    }

    private func setupPlayerObservers() {
        for idx in 0..<2 {
            let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
            let player = players[idx]
            timeObserverTokens[idx] = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
                Task { @MainActor [weak self] in
                    guard let self, self.activeEngineIdx == idx else { return }
                    let secs = cmTime.seconds
                    guard secs.isFinite && secs >= 0 else { return }
                    let delta = max(0, secs - self.currentTime)
                    if delta > 0 && delta < 1.5 && self.isPlaying {
                        self.listenAccumulator += delta
                        if self.listenAccumulator >= 1.0 {
                            let whole = Int(self.listenAccumulator)
                            self.totalListenedSeconds += whole
                            self.listenAccumulator -= Double(whole)
                        }
                    }
                    self.currentTime = secs

                    if let itemDur = player.currentItem?.duration.seconds, itemDur.isFinite && itemDur > 0 {
                        let diff = abs(self.duration - itemDur)
                        self.duration = itemDur
                        if diff > 1.5 {
                            self.updateNowPlayingInfo()
                        }
                    }

                    // Check crossfade trigger (1-12s before end)
                    if self.settings.crossfadeEnabled,
                       !self.didTriggerCrossfadeForCurrentTrack,
                       !self.isCrossfading,
                       self.duration > 20,
                       secs >= self.duration - self.settings.crossfadeSeconds {
                        self.didTriggerCrossfadeForCurrentTrack = true
                        self.triggerCrossfadeToNext()
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                guard let self,
                      let endedItem = note.object as? AVPlayerItem,
                      endedItem == self.players[self.activeEngineIdx].currentItem else { continue }
                self.handleTrackEnded()
            }
        }

        // Inter-process Darwin notification listener from Dynamic Island & Live Activity Widgets
        let notifyCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            notifyCenter,
            observer,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let manager = Unmanaged<AudioPlayerManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    manager.toggleLikeCurrent()
                }
            },
            "com.amymusic.toggleLike" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func setupRemoteTransportControls() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: posEvent.positionTime) }
            return .success
        }

        // Lock Screen & Dynamic Island Favorite/Like Toggle
        center.likeCommand.isEnabled = true
        center.likeCommand.localizedTitle = "В избранное"
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let track = self?.currentTrack {
                    self?.toggleLike(track)
                }
            }
            return .success
        }

        center.dislikeCommand.isEnabled = true
        center.dislikeCommand.localizedTitle = "Не нравится"
        center.dislikeCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let track = self?.currentTrack {
                    self?.dislikeTrack(track)
                }
            }
            return .success
        }
    }

    nonisolated private static func createMediaArtwork(from image: UIImage) -> MPMediaItemArtwork {
        let size = image.size
        let validSize = CGSize(
            width: max(1, size.width),
            height: max(1, size.height)
        )
        return MPMediaItemArtwork(boundsSize: validSize) { _ in image }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            AmyMusicLiveActivityController.shared.endAll()
            return
        }

        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        let playDuration = max(1, duration > 0 ? duration : track.duration)
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: playDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let genre = track.genre, !genre.isEmpty {
            info[MPMediaItemPropertyGenre] = genre
        }

        // Check if artwork is already in cache for instant display
        var artworkApplied = false
        if let coverUrlStr = track.coverUrl, let url = URL(string: coverUrlStr) {
            let request = URLRequest(url: url)
            if let cached = URLCache.shared.cachedResponse(for: request),
               let cachedImg = UIImage(data: cached.data) {
                let artwork = Self.createMediaArtwork(from: cachedImg)
                info[MPMediaItemPropertyArtwork] = artwork
                artworkApplied = true
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Sync Lock Screen & Dynamic Island Like State
        let liked = isLiked(track)
        let center = MPRemoteCommandCenter.shared()
        center.likeCommand.isEnabled = true
        center.likeCommand.isActive = liked
        center.likeCommand.localizedTitle = liked ? "Удалить из избранного" : "В избранное"
        center.dislikeCommand.isEnabled = true
        center.dislikeCommand.localizedTitle = "Не нравится"

        if !artworkApplied, let coverUrlStr = track.coverUrl, let url = URL(string: coverUrlStr) {
            let targetId = track.id
            let request = URLRequest(url: url)
            Task {
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let image = UIImage(data: data) {
                    URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
                    guard self.currentTrack?.id == targetId else { return }
                    let artwork = Self.createMediaArtwork(from: image)
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }
        }

        if settings.liveActivityEnabled {
            AmyMusicLiveActivityController.shared.update(
                track: track,
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: max(duration, track.duration),
                energy: audioEnergy,
                isLiked: liked
            )
        } else {
            AmyMusicLiveActivityController.shared.endAll()
        }
    }

    // MARK: - Playback Controls & Crossfade

    public func playTrack(_ track: Track, in newQueue: [Track]? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cleanTrack = SoundCloudService.renormalizeTrackIfNeeded(track)
        let cleanQueue = newQueue?.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
        if let cleanQueue, !cleanQueue.isEmpty {
            self.originalQueue = cleanQueue
            if isShuffleEnabled {
                var rest = cleanQueue.filter { $0.id != cleanTrack.id }
                rest.shuffle()
                self.queue = [cleanTrack] + rest
                self.currentIndex = 0
            } else {
                self.queue = cleanQueue
                self.currentIndex = cleanQueue.firstIndex(where: { $0.id == cleanTrack.id }) ?? 0
            }
        } else if let idx = queue.firstIndex(where: { $0.id == cleanTrack.id }) {
            self.currentIndex = idx
        } else {
            self.queue.insert(cleanTrack, at: min(currentIndex + 1, queue.count))
            self.currentIndex = min(currentIndex + 1, queue.count - 1)
        }

        loadAndStartTrack(cleanTrack, useCrossfade: false)
    }

    public func togglePlay() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if currentTrack == nil {
            Task { await startPersonalWave() }
            return
        }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func play() {
        guard currentTrack != nil else { return }
        players[activeEngineIdx].play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    public func pause() {
        players[0].pause()
        players[1].pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    public func next() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        guard !queue.isEmpty else { return }

        if repeatMode == .one, let current = currentTrack {
            seek(to: 0)
            play()
            return
        }

        let nextIdx = currentIndex + 1
        if nextIdx < queue.count {
            currentIndex = nextIdx
            loadAndStartTrack(queue[nextIdx], useCrossfade: false)
        } else if repeatMode == .playlist {
            currentIndex = 0
            loadAndStartTrack(queue[0], useCrossfade: false)
        } else if isAutoplayEnabled, let current = currentTrack {
            Task {
                await extendQueueWithTrackWave(from: current, playImmediately: true)
            }
        }
    }

    public func previous() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if currentTime > 3.5 {
            seek(to: 0)
            return
        }
        let prevIdx = currentIndex - 1
        if prevIdx >= 0 && prevIdx < queue.count {
            currentIndex = prevIdx
            loadAndStartTrack(queue[prevIdx], useCrossfade: false)
        } else {
            seek(to: 0)
        }
    }

    public func seek(to seconds: TimeInterval) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        players[activeEngineIdx].seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        updateNowPlayingInfo()
    }

    private func loadAndStartTrack(_ track: Track, useCrossfade: Bool) {
        trackLoadTask?.cancel()
        if !useCrossfade {
            crossfadeTask?.cancel()
            isCrossfading = false
        }
        didTriggerCrossfadeForCurrentTrack = false
        isLoading = true
        currentTrack = track
        currentTime = 0
        duration = track.duration

        // Immediately update Lock Screen, Control Center, Dynamic Island & Apple Watch
        updateNowPlayingInfo()

        // Record in play history
        playHistory.removeAll { $0.id == track.id }
        playHistory.insert(track, at: 0)
        if playHistory.count > 100 { playHistory = Array(playHistory.prefix(100)) }
        persistState()

        // Extract dynamic cover palette & load lyrics in parallel
        Task {
            let extractedPalette = await PaletteExtractor.shared.extractPalette(from: track.coverUrl)
            if self.currentTrack?.id == track.id {
                self.currentTrack?.palette = extractedPalette
            }
        }

        Task {
            await loadLyricsForCurrentTrack(forceRefresh: false)
        }

        // Auto-extend queue if near the end
        if isAutoplayEnabled && currentIndex >= queue.count - 2 {
            Task {
                await extendQueueWithTrackWave(from: track, playImmediately: false)
            }
        }

        trackLoadTask = Task {
            guard let streamUrl = await resolvePlayableUrl(for: track) else {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                // Automatically skip unresolvable track
                if self.queue.count > 1 && !useCrossfade {
                    self.next()
                }
                return
            }
            let asset: AVURLAsset
            if let proxyConfig = SoundCloudProxyManager.shared.getActiveProxyConfig(settings: self.settings),
               proxyConfig.isForwardProxy,
               !track.isHls {
                var comps = URLComponents(url: streamUrl, resolvingAgainstBaseURL: false)
                comps?.scheme = ProxyAudioResourceLoader.customScheme
                if let proxiedUrl = comps?.url {
                    let proxiedAsset = AVURLAsset(url: proxiedUrl)
                    let currentSession = SoundCloudProxyManager.shared.session(for: self.settings)
                    let loader = ProxyAudioResourceLoader {
                        currentSession
                    }
                    let queue = DispatchQueue(label: "com.amymusic.audioloader", qos: .userInitiated)
                    self.audioResourceLoader = loader
                    proxiedAsset.resourceLoader.setDelegate(loader, queue: queue)
                    asset = proxiedAsset
                } else {
                    asset = AVURLAsset(url: streamUrl)
                }
            } else {
                asset = AVURLAsset(url: streamUrl)
            }
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 20

            let targetIdx = useCrossfade ? (1 - self.activeEngineIdx) : self.activeEngineIdx
            let oldIdx = self.activeEngineIdx

            if !useCrossfadingOrSingle(useCrossfade: useCrossfade, oldIdx: oldIdx, targetIdx: targetIdx, item: item) {
                return
            }

            // Pre-resolve upcoming 3 tracks in background (matching AudioPlayerContext.jsx)
            self.prefetchUpcomingTracks()
        }
    }

    private func useCrossfadingOrSingle(useCrossfade: Bool, oldIdx: Int, targetIdx: Int, item: AVPlayerItem) -> Bool {
        if useCrossfade && oldIdx != targetIdx {
            isCrossfading = true
            let incoming = players[targetIdx]
            let outgoing = players[oldIdx]
            incoming.replaceCurrentItem(with: item)
            incoming.volume = 0
            incoming.play()
            activeEngineIdx = targetIdx
            isPlaying = true
            isLoading = false
            updateNowPlayingInfo()

            let fadeSeconds = max(1.0, settings.crossfadeSeconds)
            let steps = 20
            let stepDuration = fadeSeconds / Double(steps)

            crossfadeTask = Task {
                for step in 1...steps {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
                    let progress = Float(step) / Float(steps)
                    incoming.volume = progress * self.volume
                    outgoing.volume = (1.0 - progress) * self.volume
                }
                outgoing.pause()
                outgoing.replaceCurrentItem(with: nil)
                incoming.volume = self.volume
                self.isCrossfading = false
                self.updateNowPlayingInfo()
            }
        } else {
            let otherIdx = 1 - activeEngineIdx
            players[otherIdx].pause()
            players[otherIdx].replaceCurrentItem(with: nil)

            let active = players[activeEngineIdx]
            active.replaceCurrentItem(with: item)
            active.volume = volume
            active.play()
            isPlaying = true
            isLoading = false
            updateNowPlayingInfo()
        }
        return true
    }

    private func triggerCrossfadeToNext() {
        let nextIdx = currentIndex + 1
        guard nextIdx < queue.count else { return }
        isCrossfading = true
        currentIndex = nextIdx
        loadAndStartTrack(queue[nextIdx], useCrossfade: true)
    }

    private func handleTrackEnded() {
        guard !isCrossfading else { return }
        if repeatMode == .one {
            seek(to: 0)
            play()
        } else {
            next()
        }
    }

    private func resolvePlayableUrl(for track: Track) async -> URL? {
        // Check if existing streamUrl is still fresh (< 90 seconds old)
        if let existing = track.streamUrl,
           let fetchedAt = track.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < 90,
           let url = URL(string: existing) {
            return url
        }

        if track.source == .yandex || track.source == .spotify {
            let bridged: Track?
            if track.source == .yandex {
                bridged = await YandexMusicService.shared.resolvePlayableSoundCloudTrack(for: track)
            } else {
                bridged = await SpotifyService.shared.resolvePlayableSoundCloudTrack(for: track)
            }
            if let bridged,
               let resolved = await SoundCloudService.shared.resolveStreamUrl(for: bridged, quality: settings.audioQuality),
               let url = URL(string: resolved.url) {
                return url
            }
            return nil
        }

        if let resolved = await SoundCloudService.shared.resolveStreamUrl(for: track, quality: settings.audioQuality),
           let url = URL(string: resolved.url) {
            if let idx = queue.firstIndex(where: { $0.id == track.id }) {
                queue[idx].streamUrl = resolved.url
                queue[idx].isHls = resolved.isHls
                queue[idx].fetchedAt = Date()
            }
            return url
        }
        return nil
    }

    private func prefetchUpcomingTracks() {
        let start = currentIndex + 1
        let end = min(queue.count, start + 4)
        guard start < end else { return }
        let slice = Array(queue[start..<end])

        Task {
            for upcoming in slice {
                if let fetchedAt = upcoming.fetchedAt, Date().timeIntervalSince(fetchedAt) < 60 {
                    continue
                }
                var target = upcoming
                if target.source == .yandex {
                    if let bridged = await YandexMusicService.shared.resolvePlayableSoundCloudTrack(for: target) {
                        target = bridged
                    }
                } else if target.source == .spotify {
                    if let bridged = await SpotifyService.shared.resolvePlayableSoundCloudTrack(for: target) {
                        target = bridged
                    }
                }
                if let resolved = await SoundCloudService.shared.resolveStreamUrl(for: target, quality: settings.audioQuality) {
                    if let idx = self.queue.firstIndex(where: { $0.id == upcoming.id }) {
                        self.queue[idx].streamUrl = resolved.url
                        self.queue[idx].isHls = resolved.isHls
                        self.queue[idx].fetchedAt = Date()
                    }
                }
            }
        }
    }

    // MARK: - Spotify OAuth2 Authorization

    public func startSpotifyLogin() async throws {
        var clientId = settings.spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientId.isEmpty {
            clientId = SpotifyService.defaultClientId
            self.settings.spotifyClientId = clientId
        }

        let verifier = SpotifyPKCE.generateCodeVerifier()
        let challenge = SpotifyPKCE.generateCodeChallenge(from: verifier)
        let redirectUri = "amymusic://spotify-callback"
        let scope = "user-read-private playlist-read-private playlist-read-collaborative user-library-read"

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        guard let authUrl = components.url else { throw URLError(.badURL) }

        let callbackUrl = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authUrl,
                callbackURLScheme: "amymusic"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            session.presentationContextProvider = SpotifyAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }

        guard let components = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw URLError(.badServerResponse)
        }

        let auth = try await SpotifyService.shared.exchangeCodeForToken(code: code, codeVerifier: verifier)
        self.settings.spotifyAccessToken = auth.accessToken
        self.settings.spotifyRefreshToken = auth.refreshToken
        self.settings.spotifyTokenExpiry = auth.expiry
        self.settings.spotifyUserId = auth.userId
        self.settings.spotifyUserDisplayName = auth.displayName
        self.settings.spotifyUserAvatar = auth.avatarUrl
        self.persistSettings()

        await self.loadSpotifyPlaylists()
    }

    public func logoutSpotify() {
        settings.spotifyAccessToken = ""
        settings.spotifyRefreshToken = ""
        settings.spotifyTokenExpiry = nil
        settings.spotifyUserDisplayName = ""
        settings.spotifyUserAvatar = ""
        settings.spotifyUserId = ""
        spotifyUserPlaylists = []
        importingSpotifyPlaylistIds = []

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("spotify.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        persistSettings()
    }

    public func loadSpotifyPlaylists() async {
        guard !settings.spotifyAccessToken.isEmpty else {
            self.spotifyUserPlaylists = []
            return
        }
        self.isFetchingSpotifyPlaylists = true
        let playlists = await SpotifyService.shared.fetchUserPlaylists()
        self.spotifyUserPlaylists = playlists
        self.isFetchingSpotifyPlaylists = false
    }

    public func importSpotifyUserPlaylist(_ item: ReleaseItem) async {
        let spotifyId = item.id.replacingOccurrences(of: "spotify_pl_", with: "")
        importingSpotifyPlaylistIds.insert(item.id)
        defer { importingSpotifyPlaylistIds.remove(item.id) }

        // Clear previous disk cache for this playlist so it doesn't get stuck on old 100 tracks
        ReleaseCacheManager.shared.clear(for: item.id)
        ReleaseCacheManager.shared.clear(for: "spotify_pl_\(spotifyId)")
        ReleaseCacheManager.shared.clear(for: spotifyId)

        // Ensure SpotifyService has fresh settings and credentials
        await SpotifyService.shared.updateSettings(self.settings)

        if let imported = await SpotifyService.shared.importSpotifyPlaylistById(spotifyId) {
            if let existingIdx = self.userPlaylists.firstIndex(where: {
                $0.id == imported.id || $0.id == "spotify_pl_\(spotifyId)" || ($0.title == imported.title && $0.artist == imported.artist)
            }) {
                self.userPlaylists[existingIdx] = imported
            } else {
                self.userPlaylists.insert(imported, at: 0)
            }
            if let spIdx = self.spotifyUserPlaylists.firstIndex(where: { $0.id == item.id || $0.id == "spotify_pl_\(spotifyId)" }) {
                self.spotifyUserPlaylists[spIdx].trackCount = imported.trackCount
            }
            self.persistState()
        }
    }

    private func applyVolumeToActiveEngine() {
        players[activeEngineIdx].volume = volume
    }

    // MARK: - Wave & Recommendations Generation

    public func loadInitialRecommendations(forceFresh: Bool = false) async {
        async let waveTask = SoundCloudService.shared.getPersonalWaveTracks(
            seeds: waveSeeds,
            playHistory: playHistory,
            likedTracks: likedTracks,
            dislikedTracks: dislikedTracks,
            currentTrack: currentTrack,
            forceFresh: forceFresh
        )
        async let chartsTask = YandexMusicService.shared.getChartTop100()

        let (wave, charts) = await (waveTask, chartsTask)
        if !wave.isEmpty {
            self.forYouTracks = wave
            if self.currentTrack == nil {
                self.queue = wave
                self.originalQueue = wave
                self.currentTrack = wave.first
            }
        }
        if !charts.isEmpty {
            self.chartTracks = charts
        }
    }

    public func startPersonalWave() async {
        isLoading = true
        let tracks = await SoundCloudService.shared.getPersonalWaveTracks(
            seeds: waveSeeds,
            playHistory: playHistory,
            likedTracks: likedTracks,
            dislikedTracks: dislikedTracks,
            currentTrack: currentTrack
        )
        isLoading = false
        guard let first = tracks.first else { return }
        forYouTracks = tracks
        playTrack(first, in: tracks)
    }

    public func startTrackWave(for seedTrack: Track) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isLoading = true
        let dislikedIds = Set(dislikedTracks.map(\.id))
        let wave = await SoundCloudService.shared.getTrackWaveTracks(seedTrack: seedTrack, dislikedIds: dislikedIds)
        isLoading = false
        let fullQueue = [seedTrack] + wave
        playTrack(seedTrack, in: fullQueue)
    }

    private func extendQueueWithTrackWave(from seed: Track, playImmediately: Bool) async {
        let dislikedIds = Set(dislikedTracks.map(\.id))
        let existingIds = Set(queue.suffix(50).map(\.id))
        let wave = await SoundCloudService.shared.getTrackWaveTracks(seedTrack: seed, dislikedIds: dislikedIds)
        let unique = wave.filter { !existingIds.contains($0.id) }
        guard !unique.isEmpty else { return }
        queue.append(contentsOf: unique)
        originalQueue.append(contentsOf: unique)
        if playImmediately {
            next()
        }
    }

    // MARK: - Queue, Shuffle, Repeat, Likes & Playlists Operations

    public func toggleShuffle() {
        UISelectionFeedbackGenerator().selectionChanged()
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            originalQueue = queue
            if let current = currentTrack {
                var rest = queue.filter { $0.id != current.id }
                rest.shuffle()
                queue = [current] + rest
                currentIndex = 0
            } else {
                queue.shuffle()
            }
        } else {
            queue = originalQueue
            if let current = currentTrack,
               let restoredIdx = queue.firstIndex(where: { $0.id == current.id }) {
                currentIndex = restoredIdx
            }
        }
    }

    public func cycleRepeatMode() {
        UISelectionFeedbackGenerator().selectionChanged()
        switch repeatMode {
        case .off: repeatMode = .playlist
        case .playlist: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    public func isLiked(_ track: Track?) -> Bool {
        guard let track else { return false }
        return likedTracks.contains(where: { $0.id == track.id })
    }

    public func toggleLikeCurrent() {
        if let current = currentTrack {
            toggleLike(current)
        }
    }

    public func toggleLike(_ track: Track) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let idx = likedTracks.firstIndex(where: { $0.id == track.id }) {
            likedTracks.remove(at: idx)
        } else {
            likedTracks.insert(track, at: 0)
            dislikedTracks.removeAll { $0.id == track.id }
        }
        persistState()
        if currentTrack?.id == track.id {
            updateNowPlayingInfo()
        }
    }

    public func dislikeTrack(_ track: Track) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if !dislikedTracks.contains(where: { $0.id == track.id }) {
            dislikedTracks.insert(track, at: 0)
        }
        likedTracks.removeAll { $0.id == track.id }
        queue.removeAll { $0.id == track.id && $0.id != currentTrack?.id }
        persistState()
        if currentTrack?.id == track.id {
            next()
        }
    }

    public func playNextInQueue(_ track: Track) {
        UISelectionFeedbackGenerator().selectionChanged()
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertIndex)
        originalQueue.insert(track, at: min(insertIndex, originalQueue.count))
    }

    public func addToQueueEnd(_ track: Track) {
        UISelectionFeedbackGenerator().selectionChanged()
        queue.append(track)
        originalQueue.append(track)
    }

    public func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        }
    }

    public func moveQueueItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if let current = currentTrack,
           let newIdx = queue.firstIndex(where: { $0.id == current.id }) {
            currentIndex = newIdx
        }
    }

    public func toggleSavedRelease(_ release: ReleaseItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = savedReleases.firstIndex(where: { $0.id == release.id }) {
            savedReleases.remove(at: idx)
        } else {
            savedReleases.insert(release, at: 0)
        }
        persistState()
    }

    public func createUserPlaylist(title: String, coverUrl: String? = nil, tracks: [Track] = []) {
        let newPl = ReleaseItem(
            id: "user_pl_\(UUID().uuidString)",
            title: title.isEmpty ? "Мой плейлист #\(userPlaylists.count + 1)" : title,
            artist: settings.displayName,
            coverUrl: coverUrl ?? tracks.first?.coverUrl,
            kind: .userPlaylist,
            trackCount: tracks.count,
            tracks: tracks
        )
        userPlaylists.insert(newPl, at: 0)
        persistState()
    }

    public func deleteUserPlaylist(id: String) {
        guard id != "liked_tracks_special" && id != "liked" else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        userPlaylists.removeAll { $0.id == id }
        savedReleases.removeAll { $0.id == id }
        persistState()
    }

    public func toggleArtistSubscription(_ artist: ArtistRef) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = subscribedArtists.firstIndex(where: { $0.id == artist.id || $0.name.lowercased() == artist.name.lowercased() }) {
            subscribedArtists.remove(at: idx)
        } else {
            subscribedArtists.insert(artist, at: 0)
        }
        persistState()
    }

    public func isSubscribed(to artist: ArtistRef) -> Bool {
        subscribedArtists.contains { $0.id == artist.id || $0.name.lowercased() == artist.name.lowercased() }
    }

    // MARK: - Lyrics Loading & Offset Management

    public func loadLyricsForCurrentTrack(forceRefresh: Bool = false) async {
        guard let track = currentTrack else {
            currentLyrics = .empty
            return
        }
        isLyricsLoading = true
        let payload = await LyricsService.shared.fetchLyrics(
            for: track,
            preferredSource: settings.preferredLyricsSource,
            forceRefresh: forceRefresh
        )
        if currentTrack?.id == track.id {
            currentLyrics = payload
            isLyricsLoading = false
        }
    }

    public func currentTrackLyricsOffsetMs() -> Double {
        guard let id = currentTrack?.id else { return 0 }
        return lyricsOffsetsMs[id] ?? 0
    }

    public func setCurrentTrackLyricsOffsetMs(_ offset: Double) {
        guard let id = currentTrack?.id else { return }
        lyricsOffsetsMs[id] = min(2000, max(-2000, offset))
        persistState()
    }

    // MARK: - Real-Time Audio Energy Simulation & Envelope Loop (Port of useAudioEnergy)

    private func startEnergyLoop() {
        energyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isPlaying else {
                    if self.audioEnergy != .zero {
                        self.audioEnergy = AudioEnergy(
                            bass: self.audioEnergy.bass * 0.75,
                            mids: self.audioEnergy.mids * 0.75,
                            treble: self.audioEnergy.treble * 0.75,
                            level: self.audioEnergy.level * 0.75
                        )
                    }
                    return
                }
                let t = Date().timeIntervalSinceReferenceDate
                // Reactive multi-band envelope modulated by playback time and EQ bass boost
                let eqBassGain = Double(max(0, self.settings.equalizerBands.first ?? 0)) / 12.0
                let rawBass = min(1.0, max(0.08, 0.48 + 0.36 * sin(t * 7.2) * cos(t * 3.1) + eqBassGain * 0.2))
                let rawMids = min(1.0, max(0.06, 0.42 + 0.30 * sin(t * 5.4 + 1.1)))
                let rawTreble = min(1.0, max(0.05, 0.35 + 0.25 * cos(t * 9.3 + 0.5)))
                let level = min(1.0, rawBass * 0.58 + rawMids * 0.30 + rawTreble * 0.18)

                // Smooth with 0.68 time constant matching AnalyserNode smoothingTimeConstant = 0.68
                let b = self.audioEnergy.bass * 0.68 + rawBass * 0.32
                let m = self.audioEnergy.mids * 0.68 + rawMids * 0.32
                let tr = self.audioEnergy.treble * 0.68 + rawTreble * 0.32
                let lv = self.audioEnergy.level * 0.68 + level * 0.32

                self.audioEnergy = AudioEnergy(bass: b, mids: m, treble: tr, level: lv)
            }
        }
    }

    // MARK: - Persistence

    private struct PersistedBlob: Codable {
        var likedTracks: [Track]
        var dislikedTracks: [Track]
        var playHistory: [Track]
        var savedReleases: [ReleaseItem]
        var userPlaylists: [ReleaseItem]
        var subscribedArtists: [ArtistRef]
        var waveSeeds: [WaveSeed]
        var totalListenedSeconds: Int
        var lyricsOffsetsMs: [String: Double]
    }

    public func persistState() {
        let blob = PersistedBlob(
            likedTracks: likedTracks,
            dislikedTracks: dislikedTracks,
            playHistory: playHistory,
            savedReleases: savedReleases,
            userPlaylists: userPlaylists,
            subscribedArtists: subscribedArtists,
            waveSeeds: waveSeeds,
            totalListenedSeconds: totalListenedSeconds,
            lyricsOffsetsMs: lyricsOffsetsMs
        )
        if let data = try? JSONEncoder().encode(blob) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadPersistedState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let blob = try? JSONDecoder().decode(PersistedBlob.self, from: data) else {
            return
        }
        likedTracks = blob.likedTracks.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
        dislikedTracks = blob.dislikedTracks.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
        playHistory = blob.playHistory.map { SoundCloudService.renormalizeTrackIfNeeded($0) }
        savedReleases = blob.savedReleases
        userPlaylists = blob.userPlaylists
        subscribedArtists = blob.subscribedArtists
        waveSeeds = blob.waveSeeds
        totalListenedSeconds = blob.totalListenedSeconds
        lyricsOffsetsMs = blob.lyricsOffsetsMs
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppProfileSettings.self, from: data) {
            var s = decoded
            if s.soundCloudProxyCustomDomain == "ios.amymusic.ru" {
                s.soundCloudProxyCustomDomain = ""
            }
            if s.spotifyClientId.isEmpty || s.spotifyClientId == "88974a2b71d846d5aa4f80631542e021" {
                s.spotifyClientId = "0c0053dd5bfd401f9a5b064273513e5e"
            }
            settings = s
        } else {
            settings = AppProfileSettings()
        }
    }
}
