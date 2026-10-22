import SwiftUI
import PhotosUI

// MARK: - Settings, Profile, Audio & Integrations + Real Photo Avatar
// Port of src/components/SettingsView.jsx, ProfileSettingsModal & src/components/AvatarCropperModal.jsx

public extension UIImage {
    static func from(base64OrDataUrl: String?) -> UIImage? {
        guard let string = base64OrDataUrl, !string.isEmpty else { return nil }
        let base64String: String
        if let commaIndex = string.firstIndex(of: ",") {
            base64String = String(string[string.index(after: commaIndex)...])
        } else {
            base64String = string
        }
        guard let data = Data(base64Encoded: base64String, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        return UIImage(data: data)
    }
}

public struct ProfileAvatarView: View {
    public var avatarDataUrl: String?
    public var displayName: String
    public var size: CGFloat
    public var primaryHex: String = "#FFFFFF"
    public var secondaryHex: String = "#E4E4E7"

    public init(
        avatarDataUrl: String?,
        displayName: String,
        size: CGFloat,
        primaryHex: String = "#FFFFFF",
        secondaryHex: String = "#E4E4E7"
    ) {
        self.avatarDataUrl = avatarDataUrl
        self.displayName = displayName
        self.size = size
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
    }

    public var body: some View {
        Group {
            if let avatar = UIImage.from(base64OrDataUrl: avatarDataUrl) {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: primaryHex), Color(hex: secondaryHex)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)

                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .black))
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay {
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }
}

public enum SettingsSectionTab: String, CaseIterable, Identifiable {
    case profile = "Профиль"
    case audio = "Аудио"
    case integrations = "Интеграции"

    public var id: String { rawValue }
}

public struct SettingsAndProfileView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var activeSection: SettingsSectionTab = .profile
    @State private var isAvatarCropperOpen: Bool = false
    @State private var testProxyStatus: String? = nil
    @State private var isTestingProxy: Bool = false
    @State private var isLoggingInSpotify: Bool = false
    @State private var spotifyLoginError: String? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Top Pill Tabs with Native Apple Liquid Glass Segmented Control
                    Picker("Раздел настроек", selection: $activeSection) {
                        ForEach(SettingsSectionTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            switch activeSection {
                            case .profile:
                                profileTabContent
                            case .audio:
                                audioTabContent
                            case .integrations:
                                integrationsTabContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 50)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $isAvatarCropperOpen) {
                AvatarCropperSheetView(player: player)
            }
        }
    }

    // MARK: - 1. Profile Tab

    private var profileTabContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 16) {
                Button {
                    isAvatarCropperOpen = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(
                            avatarDataUrl: player.settings.avatarDataUrl,
                            displayName: player.settings.displayName,
                            size: 104,
                            primaryHex: player.settings.themePreset.primaryHex,
                            secondaryHex: player.settings.themePreset.secondaryHex
                        )

                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .background(Circle().fill(.black))
                    }
                }
                .buttonStyle(.plain)

                if player.settings.avatarDataUrl != nil {
                    Button(role: .destructive) {
                        player.settings.avatarDataUrl = nil
                        player.persistState()
                    } label: {
                        Label("Удалить фото", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Отображаемое имя")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))

                    TextField("Имя профиля", text: $player.settings.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(13)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .onChange(of: player.settings.displayName) { _, _ in
                            player.persistState()
                        }

                    Text("О себе")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))

                    TextField("У вашей музыки есть цвет", text: $player.settings.bio)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(13)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .onChange(of: player.settings.bio) { _, _ in
                            player.persistState()
                        }
                }
            }
            .padding(20)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Listening Statistics Card
            HStack(spacing: 14) {
                StatPillCard(
                    title: "Прослушано",
                    value: "\(player.totalListenedSeconds / 3600)ч \((player.totalListenedSeconds % 3600) / 60)м",
                    icon: "headphones"
                )
                StatPillCard(
                    title: "Любимые",
                    value: "\(player.likedTracks.count) тр.",
                    icon: "heart.fill"
                )
                StatPillCard(
                    title: "История",
                    value: "\(player.playHistory.count) тр.",
                    icon: "clock.fill"
                )
            }
        }
    }

    // MARK: - 2. Audio Tab (192 / 256 / 320 / 1411 kbps + Crossfade)

    private var audioTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Качество аудиопотока")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)

                ForEach(AudioQualityTier.allCases) { tier in
                    let active = player.settings.audioQuality == tier
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        player.settings.audioQuality = tier
                        player.persistState()
                    } label: {
                        HStack {
                            Text(tier.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(active ? .white : .white.opacity(0.35))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(active ? Color.white.opacity(0.18) : .white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Плавный переход (Crossfade)", isOn: $player.settings.crossfadeEnabled)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .toggleStyle(.appleLiquidGlass)
                    .onChange(of: player.settings.crossfadeEnabled) { _, _ in
                        player.persistState()
                    }

                if player.settings.crossfadeEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Длительность перехода")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                            Spacer()
                            Text("\(Int(player.settings.crossfadeSeconds)) сек")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Slider(value: $player.settings.crossfadeSeconds, in: 1...12, step: 1)
                            .tint(.white)
                            .onChange(of: player.settings.crossfadeSeconds) { _, _ in
                                player.persistState()
                            }
                    }
                }

                Toggle("Воспроизведение без пауз (Gapless)", isOn: $player.settings.gaplessPlayback)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .toggleStyle(.appleLiquidGlass)
                    .onChange(of: player.settings.gaplessPlayback) { _, _ in
                        player.persistState()
                    }

                Toggle("Нормализация громкости", isOn: $player.settings.volumeNormalization)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .toggleStyle(.appleLiquidGlass)
                    .onChange(of: player.settings.volumeNormalization) { _, _ in
                        player.persistState()
                    }
            }
            .padding(18)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: - 3. Integrations / Developer Tab

    private var integrationsTabContent: some View {
        VStack(spacing: 16) {
            // MARK: - Proxy & Anti-Blocking
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Прокси и обход блокировок")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("Маршрутизация запросов к SoundCloud через ваш личный прокси или встроенное зеркало. Позволяет слушать музыку в РФ без VPN.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(2)

                Toggle("Включить обход / прокси", isOn: $player.settings.soundCloudProxyEnabled)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .toggleStyle(.appleLiquidGlass)
                    .onChange(of: player.settings.soundCloudProxyEnabled) { _, _ in
                        player.persistSettings()
                    }

                if player.settings.soundCloudProxyEnabled {
                    // MARK: Personal Proxy Input (login:password@ip:port)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Личный прокси (HTTP / SOCKS5)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))

                            Spacer()

                            if let clip = UIPasteboard.general.string, !clip.isEmpty {
                                Button {
                                    player.settings.customHttpProxies = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                    player.persistSettings()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard")
                                        Text("Вставить")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("login:password@ip:port", text: $player.settings.customHttpProxies)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: player.settings.customHttpProxies) { _, _ in
                                    player.persistSettings()
                                }

                            if !player.settings.customHttpProxies.isEmpty {
                                Button {
                                    player.settings.customHttpProxies = ""
                                    player.persistSettings()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                        // Real-time parsed proxy status badge
                        let rawProxy = player.settings.customHttpProxies.trimmingCharacters(in: .whitespacesAndNewlines)
                        let parsed = SoundCloudProxyManager.ParsedProxyConfig.parse(rawProxy)

                        if !rawProxy.isEmpty {
                            if let parsed = parsed, parsed.isForwardProxy {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                    Text(parsed.statusDescription)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                    Text("Форматы: login:pass@ip:port или ip:port:login:pass")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                }
                                .padding(.top, 2)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "globe.europe.africa.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.cyan)
                                Text("Личный прокси не задан (прямое подключение)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.top, 2)
                        }
                    }

                    // MARK: Test connection button
                    Button {
                        player.persistSettings()
                        isTestingProxy = true
                        testProxyStatus = nil
                        Task {
                            let res = await SoundCloudProxyManager.shared.testConnection(settings: player.settings)
                            isTestingProxy = false
                            if res.success {
                                testProxyStatus = "✓ Соединение успешно (\(res.latencyMs) мс)"
                            } else {
                                testProxyStatus = "⚠️ \(res.error ?? "Не удалось подключиться")"
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingProxy {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                            }
                            Text(isTestingProxy ? "Проверка соединения..." : "Проверить связь с SoundCloud")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(isTestingProxy)

                    if let status = testProxyStatus {
                        HStack(spacing: 6) {
                            Image(systemName: status.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                            Text(status)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(status.contains("✓") ? .green : .orange)
                        .padding(.top, 2)
                    }
                }
            }
            .padding(18)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            // MARK: - Standard SoundCloud & Yandex
            VStack(alignment: .leading, spacing: 14) {
                Text("SoundCloud API v2 & Yandex Music")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SoundCloud Client ID")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("Client ID", text: $player.settings.soundCloudClientId)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: player.settings.soundCloudClientId) { _, _ in
                            player.persistState()
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Yandex Music OAuth Token (опционально для Персональной Ротор-волны)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    SecureField("y0_AgAAAA...", text: $player.settings.yandexOAuthToken)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: player.settings.yandexOAuthToken) { _, _ in
                            player.persistState()
                        }
                }
            }
            .padding(18)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            // MARK: - Spotify Integration (OAuth2 PKCE & Web API)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text("Spotify")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("Перенос ваших плейлистов и альбомов со Spotify. Треки связываются с SoundCloud и играют бесплатно в 320 kbps.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(2)

                if !player.settings.spotifyAccessToken.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            if !player.settings.spotifyUserAvatar.isEmpty, let url = URL(string: player.settings.spotifyUserAvatar) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.green.opacity(0.3)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.green)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(player.settings.spotifyUserDisplayName.isEmpty ? "Пользователь Spotify" : player.settings.spotifyUserDisplayName)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 13))
                                }
                                Text("Аккаунт подключен • Доступ ко всем трекам")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.green.opacity(0.9))
                            }

                            Spacer()

                            Button {
                                player.logoutSpotify()
                            } label: {
                                Text("Выйти")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.red.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                        // MARK: - Playlists Transfer Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ваши плейлисты Spotify")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundStyle(.white)
                                    Text("Перенос плейлистов со всеми треками (без лимита 100)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Button {
                                    Task { await player.loadSpotifyPlaylists() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(8)
                                        .background(.white.opacity(0.08), in: Circle())
                                }
                            }

                            if player.isFetchingSpotifyPlaylists {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.green)
                                    Text("Загрузка ваших плейлистов...")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                            } else if player.spotifyUserPlaylists.isEmpty {
                                VStack(spacing: 8) {
                                    Text("Плейлисты не загружены или список пуст")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Button("Загрузить плейлисты") {
                                        Task { await player.loadSpotifyPlaylists() }
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.green)
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(player.spotifyUserPlaylists) { pl in
                                        let isImportingThis = player.importingSpotifyPlaylistIds.contains(pl.id)
                                        let cleanPlId = pl.id.replacingOccurrences(of: "spotify_pl_", with: "")
                                        let isAlreadyImported = player.userPlaylists.contains(where: {
                                            $0.id == pl.id || $0.id == "spotify_pl_\(cleanPlId)" || ($0.title == pl.title && $0.artist == pl.artist)
                                        })

                                        HStack(spacing: 12) {
                                            if let cUrl = pl.coverUrl, let url = URL(string: cUrl) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().scaledToFill()
                                                    } else {
                                                        Color.white.opacity(0.1)
                                                    }
                                                }
                                                .frame(width: 46, height: 46)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            } else {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(.white.opacity(0.1))
                                                    .frame(width: 46, height: 46)
                                                    .overlay {
                                                        Image(systemName: "music.note")
                                                            .foregroundStyle(.white.opacity(0.5))
                                                    }
                                            }

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(pl.title)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                let countStr = pl.trackCount > 0 ? (pl.trackCount % 10 == 1 && pl.trackCount % 100 != 11 ? "\(pl.trackCount) трек" : ((pl.trackCount % 10 >= 2 && pl.trackCount % 10 <= 4 && (pl.trackCount % 100 < 10 || pl.trackCount % 100 >= 20)) ? "\(pl.trackCount) трека" : "\(pl.trackCount) треков")) : "Плейлист"
                                                Text("\(countStr) • \(pl.artist)")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.55))
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            if isImportingThis {
                                                ProgressView()
                                                    .tint(.green)
                                                    .padding(.horizontal, 8)
                                            } else {
                                                let existing = player.userPlaylists.first(where: {
                                                    $0.id == pl.id || $0.id == "spotify_pl_\(cleanPlId)" || ($0.title == pl.title && $0.artist == pl.artist)
                                                })
                                                let hasIncompleteTracks = existing != nil && (existing?.trackCount ?? 0) < pl.trackCount

                                                Button {
                                                    Task {
                                                        await player.importSpotifyUserPlaylist(pl)
                                                    }
                                                } label: {
                                                    if hasIncompleteTracks {
                                                        HStack(spacing: 5) {
                                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                            Text("Обновить (\(pl.trackCount))")
                                                        }
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.black)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 7)
                                                        .background(Color.green, in: Capsule())
                                                    } else if isAlreadyImported {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "checkmark.circle.fill")
                                                            Text("В коллекции")
                                                        }
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.green)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(.green.opacity(0.14), in: Capsule())
                                                    } else {
                                                        HStack(spacing: 5) {
                                                            Image(systemName: "arrow.down.circle.fill")
                                                            Text("Перенести")
                                                        }
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.black)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 7)
                                                        .background(Color.green, in: Capsule())
                                                    }
                                                }
                                            }
                                        }
                                        .padding(10)
                                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            Text("Client ID встроен: готов к подключению")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        }

                        Button {
                            isLoggingInSpotify = true
                            spotifyLoginError = nil
                            Task {
                                do {
                                    try await player.startSpotifyLogin()
                                    await MainActor.run {
                                        isLoggingInSpotify = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        isLoggingInSpotify = false
                                        spotifyLoginError = "Ошибка входа: \(error.localizedDescription)"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoggingInSpotify {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                Text(isLoggingInSpotify ? "Подключение к Spotify..." : "Войти через Spotify")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                        }
                        .disabled(isLoggingInSpotify)

                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("По умолчанию используется встроенный проверенный Client ID. Вы можете указать собственный при необходимости.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineSpacing(2)

                                HStack(spacing: 8) {
                                    TextField("Client ID...", text: $player.settings.spotifyClientId)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(10)
                                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                        .onChange(of: player.settings.spotifyClientId) { _, _ in
                                            player.persistSettings()
                                        }

                                    if UIPasteboard.general.hasStrings {
                                        Button {
                                            if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                                player.settings.spotifyClientId = pasted
                                                player.persistSettings()
                                            }
                                        } label: {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(10)
                                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text("Настройки Client ID (дополнительно)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        HStack {
                            Button {
                                player.logoutSpotify()
                                spotifyLoginError = nil
                            } label: {
                                Text("Сбросить сессию и куки Spotify")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .underline()
                            }
                            Spacer()
                        }

                        if let error = spotifyLoginError {
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                                .lineSpacing(2)
                        }
                    }
                }
            }
            .padding(18)
            .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct StatPillCard: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .amyLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Interactive Circular Pan-and-Zoom Avatar Cropper (Port of AvatarCropperModal.jsx)

@MainActor
public struct AvatarCropperSheetView: View {
    @Bindable var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragCurrent: CGSize = .zero

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.amyBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white.opacity(0.05))
                            .frame(width: 280, height: 280)

                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 248, height: 248)
                                .scaleEffect(zoomScale)
                                .offset(x: panOffset.width + dragCurrent.width, y: panOffset.height + dragCurrent.height)
                                .clipShape(Circle())
                                .gesture(
                                    DragGesture()
                                        .onChanged { val in
                                            dragCurrent = val.translation
                                        }
                                        .onEnded { val in
                                            panOffset.width += val.translation.width
                                            panOffset.height += val.translation.height
                                            dragCurrent = .zero
                                        }
                                )
                        } else {
                            Circle()
                                .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .frame(width: 248, height: 248)
                                .overlay {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.white.opacity(0.5))
                                        Text("Выберите фото")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                        }
                    }

                    if selectedImage != nil {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Масштаб")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(Int(zoomScale * 100))%")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Slider(value: $zoomScale, in: 0.5...3.0)
                                .tint(.white)
                        }
                        .padding(.horizontal, 28)
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(selectedImage == nil ? "Выбрать фото из галереи" : "Выбрать другое фото", systemImage: "photo.on.rectangle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .amyLiquidGlass(in: Capsule(), tint: .white, tintOpacity: 0.2)
                    .padding(.horizontal, 28)
                }
            }
            .navigationTitle("Фото профиля")
            .navigationBarTitleDisplayMode(.inline)
            .appleLiquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveCroppedAvatar()
                    }
                    .fontWeight(.bold)
                    .disabled(selectedImage == nil)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        selectedImage = img
                        zoomScale = 1.0
                        panOffset = .zero
                        dragCurrent = .zero
                    }
                }
            }
        }
    }

    private func saveCroppedAvatar() {
        guard let source = selectedImage else {
            dismiss()
            return
        }
        let outputSize = CGSize(width: 320, height: 320)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let rendered = renderer.image { ctx in
            let center = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
            let previewDim: CGFloat = 248
            let factor = outputSize.width / previewDim

            let aspectW = source.size.width
            let aspectH = source.size.height
            let baseScale = previewDim / min(aspectW, aspectH)

            let targetW = aspectW * baseScale * zoomScale * factor
            let targetH = aspectH * baseScale * zoomScale * factor

            let finalOffsetX = (panOffset.width + dragCurrent.width) * factor
            let finalOffsetY = (panOffset.height + dragCurrent.height) * factor

            let originX = center.x - targetW / 2 + finalOffsetX
            let originY = center.y - targetH / 2 + finalOffsetY

            ctx.cgContext.addEllipse(in: CGRect(origin: .zero, size: outputSize))
            ctx.cgContext.clip()

            source.draw(in: CGRect(x: originX, y: originY, width: targetW, height: targetH))
        }

        if let jpegData = rendered.jpegData(compressionQuality: 0.85) {
            let base64 = jpegData.base64EncodedString()
            player.settings.avatarDataUrl = "data:image/jpeg;base64,\(base64)"
            player.persistState()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
