import Foundation
import AVFoundation

// MARK: - Native SoundCloud Proxy & Anti-Blocking Manager
// Supports Personal Forward Proxies (HTTP / HTTPS / SOCKS5 with login:password@ip:port auth)
// and Cloudflare Worker reverse-proxy mirrors (e.g. ios.amymusic.ru)

public final class SoundCloudProxyManager: @unchecked Sendable {
    public static let shared = SoundCloudProxyManager()

    /// Standard direct host for SoundCloud API v2
    public static let directHost = "api-v2.soundcloud.com"

    private let lock = NSLock()
    private var cachedSession: URLSession?
    private var cachedSessionKey: String?

    private init() {}

    // MARK: - Proxy Configuration Model

    public struct ParsedProxyConfig: Equatable, Sendable {
        public enum Scheme: String, Sendable {
            case http
            case https
            case socks5
            case worker
        }

        public let scheme: Scheme
        public let host: String
        public let port: Int?
        public let username: String?
        public let password: String?

        public var isForwardProxy: Bool {
            (scheme == .http || scheme == .https || scheme == .socks5) && port != nil
        }

        public var statusDescription: String {
            switch scheme {
            case .worker:
                return "Зеркало (Cloudflare Worker): \(host)"
            case .http, .https:
                let type = scheme == .https ? "HTTPS" : "HTTP"
                if let user = username, !user.isEmpty {
                    return "\(type) Прокси: \(host):\(port ?? 8080) (логин: \(user))"
                } else {
                    return "\(type) Прокси: \(host):\(port ?? 8080) (без пароля)"
                }
            case .socks5:
                if let user = username, !user.isEmpty {
                    return "SOCKS5 Прокси: \(host):\(port ?? 1080) (логин: \(user))"
                } else {
                    return "SOCKS5 Прокси: \(host):\(port ?? 1080) (без пароля)"
                }
            }
        }

        /// Parses arbitrary proxy strings:
        /// - login:password@ip:port
        /// - ip:port:login:password
        /// - ip:port@login:password
        /// - http://login:password@ip:port
        /// - socks5://login:password@ip:port
        /// - ip:port
        /// - worker domain (e.g. ios.amymusic.ru)
        public static func parse(_ raw: String) -> ParsedProxyConfig? {
            var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !str.isEmpty else { return nil }

            // Take the first proxy if comma-separated
            if let commaIdx = str.firstIndex(of: ",") {
                str = String(str[..<commaIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var scheme: Scheme = .http

            let lower = str.lowercased()
            if lower.hasPrefix("socks5://") || lower.hasPrefix("socks5h://") {
                scheme = .socks5
                if let range = str.range(of: "://") {
                    str = String(str[range.upperBound...])
                }
            } else if lower.hasPrefix("https://") {
                scheme = .https
                if let range = str.range(of: "://") {
                    str = String(str[range.upperBound...])
                }
            } else if lower.hasPrefix("http://") {
                scheme = .http
                if let range = str.range(of: "://") {
                    str = String(str[range.upperBound...])
                }
            }

            // Strip trailing slash / path
            if let slashIdx = str.firstIndex(of: "/") {
                str = String(str[..<slashIdx])
            }

            var host: String = ""
            var port: Int? = nil
            var username: String? = nil
            var password: String? = nil

            if str.contains("@") {
                let parts = str.components(separatedBy: "@")
                if parts.count >= 2 {
                    let left = parts[0]
                    let right = parts[1]

                    let rightColons = right.components(separatedBy: ":")
                    let leftColons = left.components(separatedBy: ":")

                    if rightColons.count >= 2, let parsedPort = Int(rightColons.last ?? "") {
                        // Standard: login:password@ip:port
                        port = parsedPort
                        host = rightColons.dropLast().joined(separator: ":")
                        username = leftColons.first
                        if leftColons.count > 1 {
                            password = leftColons.dropFirst().joined(separator: ":")
                        }
                    } else if leftColons.count >= 2, let parsedPort = Int(leftColons.last ?? "") {
                        // Inverted: ip:port@login:password
                        port = parsedPort
                        host = leftColons.dropLast().joined(separator: ":")
                        username = rightColons.first
                        if rightColons.count > 1 {
                            password = rightColons.dropFirst().joined(separator: ":")
                        }
                    } else {
                        username = left
                        host = right
                    }
                }
            } else {
                let colons = str.components(separatedBy: ":")
                if colons.count == 4 {
                    // Universal seller format: ip:port:login:password
                    if let p = Int(colons[1]) {
                        host = colons[0]
                        port = p
                        username = colons[2]
                        password = colons[3]
                    } else {
                        host = str
                    }
                } else if colons.count == 2 {
                    if let p = Int(colons[1]) {
                        host = colons[0]
                        port = p
                    } else {
                        host = str
                    }
                } else if colons.count == 1 {
                    host = colons[0]
                    scheme = .worker
                } else {
                    host = str
                }
            }

            host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return nil }

            if port == nil {
                scheme = .worker
            }

            return ParsedProxyConfig(
                scheme: scheme,
                host: host,
                port: port,
                username: username,
                password: password
            )
        }
    }

    // MARK: - Active Config Resolution

    /// Determines the active proxy configuration based on user settings
    public func getActiveProxyConfig(settings: AppProfileSettings) -> ParsedProxyConfig? {
        guard settings.soundCloudProxyEnabled else { return nil }

        // 1. Check custom proxy field (personal proxy: login:pass@ip:port)
        let customProxy = settings.customHttpProxies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customProxy.isEmpty, let parsed = ParsedProxyConfig.parse(customProxy) {
            return parsed
        }

        // 2. Check custom domain if explicitly entered
        let domain = settings.soundCloudProxyCustomDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty, let parsed = ParsedProxyConfig.parse(domain) {
            return parsed
        }

        return nil
    }

    /// Returns the active host for SoundCloud requests
    public func getActiveHost(settings: AppProfileSettings) -> String {
        guard let config = getActiveProxyConfig(settings: settings) else {
            return Self.directHost
        }
        if config.isForwardProxy {
            // Forward proxies tunnel directly to SoundCloud
            return Self.directHost
        }
        return config.host
    }

    // MARK: - URLSession with Proxy Authentication

    /// Provides a configured URLSession for network requests
    public func session(for settings: AppProfileSettings) -> URLSession {
        guard settings.soundCloudProxyEnabled,
              let config = getActiveProxyConfig(settings: settings),
              config.isForwardProxy else {
            return URLSession.shared
        }

        let sessionKey = "\(config.scheme.rawValue):\(config.host):\(config.port ?? 0):\(config.username ?? ""):\(config.password ?? "")"

        lock.lock()
        defer { lock.unlock() }

        if let existing = cachedSession, cachedSessionKey == sessionKey {
            return existing
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 30
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        var proxyDict: [AnyHashable: Any] = [:]
        if config.scheme == .socks5 {
            proxyDict[kCFStreamPropertySOCKSProxy] = config.host
            proxyDict[kCFStreamPropertySOCKSProxyPort] = config.port ?? 1080
            if let u = config.username, !u.isEmpty {
                proxyDict[kCFStreamPropertySOCKSUser] = u
            }
            if let p = config.password, !p.isEmpty {
                proxyDict[kCFStreamPropertySOCKSPassword] = p
            }
        } else {
            proxyDict[kCFNetworkProxiesHTTPEnable] = 1
            proxyDict[kCFNetworkProxiesHTTPProxy] = config.host
            proxyDict[kCFNetworkProxiesHTTPPort] = config.port ?? 8080

            // HTTPS proxy keys for iOS CFNetwork
            proxyDict["HTTPSEnable"] = 1
            proxyDict["HTTPSProxy"] = config.host
            proxyDict["HTTPSPort"] = config.port ?? 8080
        }
        sessionConfig.connectionProxyDictionary = proxyDict

        let delegate = ProxyAuthSessionDelegate(username: config.username, password: config.password)
        let newSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

        cachedSession = newSession
        cachedSessionKey = sessionKey
        return newSession
    }

    /// Returns the currently active URLSession
    public func currentSession() -> URLSession {
        lock.lock()
        let session = cachedSession
        lock.unlock()
        return session ?? URLSession.shared
    }

    // MARK: - URL Rewriting & Request Preparation

    /// Rewrites any SoundCloud API URL (path or full URL)
    public func transformUrl(pathOrUrl: String, settings: AppProfileSettings) -> (url: URL, host: String)? {
        guard let config = getActiveProxyConfig(settings: settings) else {
            // Direct connection
            return buildDirectUrl(pathOrUrl: pathOrUrl)
        }

        if config.isForwardProxy {
            // Forward proxy: connect to real SoundCloud API through the proxy tunnel
            return buildDirectUrl(pathOrUrl: pathOrUrl)
        }

        // Reverse proxy / Worker mirror: rewrite host to mirror
        let mirrorHost = config.host
        var finalString: String
        if pathOrUrl.hasPrefix("http://") || pathOrUrl.hasPrefix("https://") {
            if let originalUrl = URL(string: pathOrUrl) {
                if originalUrl.host?.contains("soundcloud.com") == true {
                    var comps = URLComponents(url: originalUrl, resolvingAgainstBaseURL: false)
                    comps?.scheme = "https"
                    comps?.host = mirrorHost
                    finalString = comps?.string ?? pathOrUrl
                } else {
                    finalString = pathOrUrl
                }
            } else {
                finalString = pathOrUrl
            }
        } else {
            let path = pathOrUrl.hasPrefix("/") ? pathOrUrl : "/\(pathOrUrl)"
            finalString = "https://\(mirrorHost)\(path)"
        }

        guard let url = URL(string: finalString) else { return nil }
        return (url, mirrorHost)
    }

    private func buildDirectUrl(pathOrUrl: String) -> (url: URL, host: String)? {
        var finalString: String
        if pathOrUrl.hasPrefix("http://") || pathOrUrl.hasPrefix("https://") {
            finalString = pathOrUrl
        } else {
            let path = pathOrUrl.hasPrefix("/") ? pathOrUrl : "/\(pathOrUrl)"
            finalString = "https://\(Self.directHost)\(path)"
        }
        guard let url = URL(string: finalString) else { return nil }
        return (url, Self.directHost)
    }

    /// Prepares standard headers and authentication for a request
    public func prepareRequest(url: URL, settings: AppProfileSettings) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        request.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.directHost, forHTTPHeaderField: "X-Target-Host")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        // Preemptive Proxy-Authorization header for proxies that expect it without 407 challenge
        if let config = getActiveProxyConfig(settings: settings),
           config.isForwardProxy,
           let user = config.username,
           let pass = config.password,
           !user.isEmpty {
            let authString = "\(user):\(pass)"
            if let data = authString.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Proxy-Authorization")
            }
        }
        return request
    }

    /// Cleans and passes through media/artwork/stream URLs directly
    public func proxyMediaUrlIfNeeded(_ urlString: String?, settings: AppProfileSettings) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        // Keep original clean URL so media/stream loads directly without 404 mirror rewrites
        return urlString
    }

    /// Report failure hook
    public func reportFailure(host: String, settings: AppProfileSettings) {
        #if DEBUG
        print("[SoundCloudProxyManager] Host failure reported: \(host)")
        #endif
    }

    /// Real connectivity test via configured proxy or mirror
    public func testConnection(settings: AppProfileSettings) async -> (success: Bool, latencyMs: Int, error: String?) {
        let clientId = settings.soundCloudClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "yNSW5UvBmb1A5j7qPUtIMuB9Itx3jsOC" : settings.soundCloudClientId

        guard let (url, host) = transformUrl(pathOrUrl: "/search/tracks?q=test&limit=1&client_id=\(clientId)", settings: settings) else {
            return (false, 0, "Некорректный URL")
        }

        let request = prepareRequest(url: url, settings: settings)
        let session = self.session(for: settings)

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return (false, elapsed, "Нет ответа от сервера")
            }
            if http.statusCode == 407 {
                return (false, elapsed, "407: Ошибка авторизации на прокси (неверный логин/пароль)")
            }
            if (200...299).contains(http.statusCode) && !data.isEmpty {
                return (true, elapsed, nil)
            } else {
                return (false, elapsed, "HTTP \(http.statusCode) (\(host))")
            }
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return (false, elapsed, "\(error.localizedDescription)")
        }
    }
}

// MARK: - Proxy Authentication Session Delegate

final class ProxyAuthSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let username: String?
    let password: String?

    init(username: String?, password: String?) {
        self.username = username
        self.password = password
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.isProxy() {
            if let u = username, let p = password, !u.isEmpty {
                let cred = URLCredential(user: u, password: p, persistence: .forSession)
                completionHandler(.useCredential, cred)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.isProxy() {
            if let u = username, let p = password, !u.isEmpty {
                let cred = URLCredential(user: u, password: p, persistence: .forSession)
                completionHandler(.useCredential, cred)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - AVPlayer Proxy Audio Resource Loader
// Pours audio stream chunks through the user's authenticated proxy session with range headers

public final class ProxyAudioResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    public static let customScheme = "amymusic-proxy"
    private let sessionProvider: @Sendable () -> URLSession
    private var activeTasks: [AVAssetResourceLoadingRequest: URLSessionDataTask] = [:]
    private let lock = NSLock()

    public init(sessionProvider: @escaping @Sendable () -> URLSession) {
        self.sessionProvider = sessionProvider
        super.init()
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.customScheme else {
            return false
        }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "https"
        guard let targetUrl = comps?.url else { return false }

        var request = URLRequest(url: targetUrl)
        request.timeoutInterval = 25
        request.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        request.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        if let dataRequest = loadingRequest.dataRequest {
            let offset = dataRequest.requestedOffset
            let length = dataRequest.requestedLength
            if length > 0 {
                let end = offset + Int64(length) - 1
                request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            } else {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            }
        }

        let session = sessionProvider()
        let task = session.dataTask(with: request) { [weak self, weak loadingRequest] data, response, error in
            guard let self, let loadingRequest else { return }

            self.lock.lock()
            self.activeTasks.removeValue(forKey: loadingRequest)
            self.lock.unlock()

            if let error = error as? URLError, error.code == .cancelled {
                return
            }

            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }

            if let http = response as? HTTPURLResponse {
                if let contentInfo = loadingRequest.contentInformationRequest {
                    contentInfo.contentType = http.mimeType ?? "audio/mpeg"
                    contentInfo.isByteRangeAccessSupported = true

                    if let contentRange = (http.allHeaderFields["Content-Range"] ?? http.allHeaderFields["content-range"]) as? String,
                       let totalStr = contentRange.components(separatedBy: "/").last,
                       let total = Int64(totalStr) {
                        contentInfo.contentLength = total
                    } else if http.expectedContentLength > 0 {
                        contentInfo.contentLength = http.expectedContentLength
                    }
                }
            }

            if let data = data, let dataRequest = loadingRequest.dataRequest {
                dataRequest.respond(with: data)
            }

            loadingRequest.finishLoading()
        }

        lock.lock()
        activeTasks[loadingRequest] = task
        lock.unlock()

        task.resume()
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        lock.lock()
        let task = activeTasks.removeValue(forKey: loadingRequest)
        lock.unlock()
        task?.cancel()
    }
}

