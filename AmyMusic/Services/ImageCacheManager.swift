import SwiftUI
import Foundation

// MARK: - Proxy-Aware Image Cache Manager
// Downloads images through the active proxy session and caches them in memory and on disk.

public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 120 * 1024 * 1024 // 120 MB RAM cache

        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDir = paths[0].appendingPathComponent("AmyMusicCoverCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    public func get(for url: URL) -> UIImage? {
        if let mem = memoryCache.object(forKey: url as NSURL) {
            return mem
        }
        let filePath = cacheDir.appendingPathComponent(cacheFilename(for: url))
        if let data = try? Data(contentsOf: filePath), let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: url as NSURL, cost: data.count)
            return img
        }
        return nil
    }

    public func load(url: URL) async -> UIImage? {
        if let cached = get(for: url) {
            return cached
        }

        do {
            let session = SoundCloudProxyManager.shared.currentSession()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
            request.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let img = UIImage(data: data) else {
                return nil
            }

            memoryCache.setObject(img, forKey: url as NSURL, cost: data.count)
            let filePath = cacheDir.appendingPathComponent(cacheFilename(for: url))
            try? data.write(to: filePath)
            return img
        } catch {
            return nil
        }
    }

    private func cacheFilename(for url: URL) -> String {
        let str = url.absoluteString
        let hash = str.utf8.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1) }
        return "\(abs(hash)).img"
    }
}

// MARK: - AmyAsyncImage: Drop-in Replacement for AsyncImage with Proxy & Caching

public struct AmyAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: ((Image) -> Content)?
    let placeholder: (() -> Placeholder)?
    let phaseContent: ((AsyncImagePhase) -> Content)?

    @State private var loadedImage: UIImage? = nil
    @State private var hasFailed: Bool = false

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.phaseContent = nil
    }

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) where Placeholder == ProgressView<EmptyView, EmptyView> {
        self.init(url: url, content: content, placeholder: { ProgressView() })
    }

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) where Placeholder == EmptyView {
        self.url = url
        self.content = nil
        self.placeholder = nil
        self.phaseContent = content
    }

    public var body: some View {
        Group {
            if let phaseContent = phaseContent {
                if let loaded = loadedImage {
                    phaseContent(.success(Image(uiImage: loaded)))
                } else if hasFailed {
                    phaseContent(.failure(URLError(.badServerResponse)))
                } else {
                    phaseContent(.empty)
                }
            } else if let loaded = loadedImage {
                content?(Image(uiImage: loaded))
            } else {
                placeholder?()
            }
        }
        .task(id: url) {
            await fetch()
        }
    }

    private func fetch() async {
        guard let url = url else {
            hasFailed = true
            return
        }

        if let cached = ImageCacheManager.shared.get(for: url) {
            self.loadedImage = cached
            return
        }

        if let img = await ImageCacheManager.shared.load(url: url) {
            self.loadedImage = img
        } else {
            self.hasFailed = true
        }
    }
}
