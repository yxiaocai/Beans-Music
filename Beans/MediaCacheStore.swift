import Foundation

/// 音频 + 歌词缓存。
/// 策略：容量硬顶（默认 512MB）+ LRU；超过上限先删最久没听的音频。
/// 另加 30 天未访问清理，避免听过一次的文件长期占空间。
/// 歌词很小，跟音频共用同一套规则，但优先淘汰音频。
final class MediaCacheStore: ObservableObject {
    static let shared = MediaCacheStore()

    static let limitKey = "beans.mediaCache.limitMB"
    static let idleDaysKey = "beans.mediaCache.idleDays"
    static let defaultLimitMB = 512
    static let defaultIdleDays = 30
    static let limitChoices = [256, 512, 1024, 2048]

    @Published private(set) var usedBytes: Int = 0

    private struct Record: Codable {
        var identity: String
        var quality: String
        var kind: String
        var fileName: String
        var byteSize: Int
        var lastAccess: Date
        var createdAt: Date
    }

    private let io = DispatchQueue(label: "beans.media.cache", qos: .utility)
    private var records: [Record] = []
    private var inflightAudio = Set<String>()
    private let lock = NSLock()

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BMusicMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(values)
        return dir
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    var limitBytes: Int {
        let mb = UserDefaults.standard.object(forKey: Self.limitKey) as? Int ?? Self.defaultLimitMB
        return max(mb, 64) * 1024 * 1024
    }

    var idleInterval: TimeInterval {
        let days = UserDefaults.standard.object(forKey: Self.idleDaysKey) as? Int ?? Self.defaultIdleDays
        return TimeInterval(max(days, 1) * 24 * 60 * 60)
    }

    var usedDescription: String {
        Self.formatBytes(usedBytes)
    }

    private init() {
        loadIndex()
        io.async { [weak self] in
            self?.sweepLocked()
        }
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }

    static func qualityToken(_ quality: BeansAudioQuality) -> String {
        quality == .standard ? "standard" : "high"
    }

    func audioFileURL(identity: String, quality: BeansAudioQuality) -> URL? {
        let token = Self.qualityToken(quality)
        lock.lock()
        defer { lock.unlock() }
        guard let idx = records.firstIndex(where: { $0.kind == "audio" && $0.identity == identity && $0.quality == token }) else {
            return nil
        }
        let file = directory.appendingPathComponent(records[idx].fileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            records.remove(at: idx)
            persistIndexLocked()
            return nil
        }
        records[idx].lastAccess = Date()
        persistIndexLocked()
        return file
    }

    func prefetchAudio(from remote: URL, identity: String, quality: BeansAudioQuality) {
        let token = Self.qualityToken(quality)
        let key = "\(identity)|\(token)"
        lock.lock()
        if inflightAudio.contains(key) || records.contains(where: { $0.kind == "audio" && $0.identity == identity && $0.quality == token }) {
            lock.unlock()
            return
        }
        inflightAudio.insert(key)
        lock.unlock()

        io.async { [weak self] in
            defer {
                self?.lock.lock()
                self?.inflightAudio.remove(key)
                self?.lock.unlock()
            }
            guard let self else { return }
            let task = URLSession.shared.downloadTask(with: remote) { temp, response, _ in
                guard let temp else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    try? FileManager.default.removeItem(at: temp)
                    return
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? 0
                guard size > 16_384, self.isLikelyAudio(temp) else {
                    try? FileManager.default.removeItem(at: temp)
                    return
                }
                let ext = remote.pathExtension.lowercased()
                let safeExt = ["m4a", "mp3", "aac", "wav", "flac"].contains(ext) ? ext : "m4a"
                let name = "a_\(self.hashKey(identity))_\(token).\(safeExt)"
                let dest = self.directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: temp, to: dest)
                } catch {
                    try? FileManager.default.copyItem(at: temp, to: dest)
                    try? FileManager.default.removeItem(at: temp)
                }
                self.lock.lock()
                self.records.removeAll { $0.kind == "audio" && $0.identity == identity && $0.quality == token }
                self.records.append(Record(
                    identity: identity,
                    quality: token,
                    kind: "audio",
                    fileName: name,
                    byteSize: size,
                    lastAccess: Date(),
                    createdAt: Date()
                ))
                self.enforceLimitLocked()
                self.persistIndexLocked()
                let used = self.records.reduce(0) { $0 + $1.byteSize }
                self.lock.unlock()
                DispatchQueue.main.async { self.usedBytes = used }
            }
            task.resume()
        }
    }

    func lyrics(identity: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = records.firstIndex(where: { $0.kind == "lyrics" && $0.identity == identity }) else { return nil }
        let file = directory.appendingPathComponent(records[idx].fileName)
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
              !text.isEmpty else {
            records.remove(at: idx)
            persistIndexLocked()
            return nil
        }
        records[idx].lastAccess = Date()
        persistIndexLocked()
        return text
    }

    func saveLyrics(_ text: String, identity: String) {
        let data = Data(text.utf8)
        guard !data.isEmpty else { return }
        let name = "l_\(hashKey(identity)).lrc"
        let dest = directory.appendingPathComponent(name)
        io.async { [weak self] in
            guard let self else { return }
            try? data.write(to: dest, options: [.atomic])
            self.lock.lock()
            self.records.removeAll { $0.kind == "lyrics" && $0.identity == identity }
            self.records.append(Record(
                identity: identity,
                quality: "",
                kind: "lyrics",
                fileName: name,
                byteSize: data.count,
                lastAccess: Date(),
                createdAt: Date()
            ))
            self.enforceLimitLocked()
            self.persistIndexLocked()
            let used = self.records.reduce(0) { $0 + $1.byteSize }
            self.lock.unlock()
            DispatchQueue.main.async { self.usedBytes = used }
        }
    }

    func applyLimitChange() {
        io.async { [weak self] in
            self?.sweepLocked()
        }
    }

    func clearAll() {
        lock.lock()
        let names = records.map(\.fileName)
        records = []
        persistIndexLocked()
        lock.unlock()
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        DispatchQueue.main.async { self.usedBytes = 0 }
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([Record].self, from: data) {
            records = list
        }
        usedBytes = records.reduce(0) { $0 + $1.byteSize }
    }

    private func persistIndexLocked() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL, options: [.atomic])
        }
    }

    private func sweepLocked() {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-idleInterval)
        var keep: [Record] = []
        for rec in records {
            let file = directory.appendingPathComponent(rec.fileName)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            if rec.lastAccess < cutoff {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            keep.append(rec)
        }
        records = keep
        enforceLimitLocked()
        persistIndexLocked()
        let used = records.reduce(0) { $0 + $1.byteSize }
        lock.unlock()
        DispatchQueue.main.async { self.usedBytes = used }
    }

    private func enforceLimitLocked() {
        var total = records.reduce(0) { $0 + $1.byteSize }
        guard total > limitBytes else { return }
        let ordered = records.enumerated().sorted { lhs, rhs in
            if lhs.element.kind != rhs.element.kind {
                return lhs.element.kind == "audio" && rhs.element.kind == "lyrics"
            }
            return lhs.element.lastAccess < rhs.element.lastAccess
        }
        var removeIdentities: Set<Int> = []
        for item in ordered {
            guard total > limitBytes else { break }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.element.fileName))
            total -= item.element.byteSize
            removeIdentities.insert(item.offset)
        }
        records = records.enumerated().compactMap { removeIdentities.contains($0.offset) ? nil : $0.element }
    }

    private func isLikelyAudio(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 16)
        guard head.count >= 8 else { return false }
        let bytes = [UInt8](head)
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return true }
        if bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 { return true }
        if let tag = String(data: head.subdata(in: 4..<8), encoding: .ascii), tag == "ftyp" { return true }
        return false
    }

    private func hashKey(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
