import UIKit

/// 远程封面磁盘+内存缓存。AsyncImage 只走 URLSession 临时缓存，杀进程就没了。
final class CoverImageCache {
    static let shared = CoverImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let io = DispatchQueue(label: "beans.cover.disk", qos: .utility)

    private init() {
        memory.countLimit = 256
        memory.totalCostLimit = 40 * 1024 * 1024
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("CoverImages", isDirectory: true)
    }

    func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: cacheKey(for: url) as NSString)
    }

    func image(for url: URL) async throws -> UIImage {
        let key = cacheKey(for: url)
        if let hit = memory.object(forKey: key as NSString) {
            return hit
        }
        let file = directory.appendingPathComponent(key)
        if let disk = await loadFromDisk(file) {
            memory.setObject(disk, forKey: key as NSString, cost: disk.cacheCost)
            return disk
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        memory.setObject(image, forKey: key as NSString, cost: image.cacheCost)
        let payload = data
        io.async {
            try? payload.write(to: file, options: [.atomic])
        }
        return image
    }

    private func loadFromDisk(_ file: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            io.async {
                continuation.resume(returning: UIImage(contentsOfFile: file.path))
            }
        }
    }

    private func cacheKey(for url: URL) -> String {
        let source = url.absoluteString
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let ext = url.pathExtension.lowercased()
        let safe = ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) ? ext : "img"
        return String(hash, radix: 16) + "." + safe
    }
}

private extension UIImage {
    var cacheCost: Int {
        Int(size.width * size.height * scale * scale * 4)
    }
}

/// 复用本地图片解码结果，避免设置页/歌词页滚动时反复从磁盘解码大图。
enum BeansImageFileCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(at path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func remove(_ path: String) {
        guard !path.isEmpty else { return }
        cache.removeObject(forKey: path as NSString)
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}
