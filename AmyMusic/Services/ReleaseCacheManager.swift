import Foundation

// MARK: - Persistent Release & Playlist Tracks Cache Manager
// Caches hydrated tracks in-memory and on disk so playlists and albums open instantly
// without re-fetching, while strictly maintaining SoundCloud's original track order.

public final class ReleaseCacheManager: @unchecked Sendable {
    public static let shared = ReleaseCacheManager()

    private let lock = NSLock()
    private var memoryCache: [String: ReleaseItem] = [:]
    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDir = paths[0].appendingPathComponent("AmyMusicReleaseCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    public func cleanKey(_ id: String) -> String {
        return id
            .replacingOccurrences(of: "sc_pl_", with: "")
            .replacingOccurrences(of: "sc_album_", with: "")
            .replacingOccurrences(of: "sc_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func get(for id: String) -> ReleaseItem? {
        let key = cleanKey(id)
        guard !key.isEmpty else { return nil }

        lock.lock()
        if let mem = memoryCache[key] {
            lock.unlock()
            return mem
        }
        lock.unlock()

        // Check persistent disk cache
        let file = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: file),
              let item = try? JSONDecoder().decode(ReleaseItem.self, from: data) else {
            return nil
        }

        lock.lock()
        memoryCache[key] = item
        lock.unlock()
        return item
    }

    public func set(_ release: ReleaseItem) {
        guard !release.tracks.isEmpty else { return }
        let key = cleanKey(release.id)
        guard !key.isEmpty else { return }

        lock.lock()
        memoryCache[key] = release
        lock.unlock()

        let file = cacheDir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(release) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func clear(for id: String) {
        let key = cleanKey(id)
        guard !key.isEmpty else { return }

        lock.lock()
        memoryCache.removeValue(forKey: key)
        lock.unlock()

        let file = cacheDir.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: file)
    }
}
