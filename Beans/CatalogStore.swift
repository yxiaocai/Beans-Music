import Foundation
import Combine

enum CatalogImportKind: String, Codable, Hashable {
    case file
    case url
}

struct CatalogSource: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: CatalogImportKind
    /// 本地文件名，或在线 JSON 的 URL 字符串
    var origin: String
    var defaultArtist: String
    var importedAt: Date
    var lastRefreshedAt: Date?
    var albumCount: Int
    var trackCount: Int

    var kindLabel: String {
        switch kind {
        case .file: return "本地文件"
        case .url: return "在线 URL"
        }
    }
}

struct CatalogAlbum: Identifiable, Hashable {
    var id: String
    var sourceID: UUID
    var sourceName: String
    var albumID: String
    var name: String
    var artist: String
    var coverURL: URL?
    var tracks: [Song]

    var subtitle: String {
        let artistPart = artist.isEmpty ? "" : artist
        if artistPart.isEmpty {
            return "\(tracks.count) 首"
        }
        return "\(artistPart) · \(tracks.count) 首"
    }
}

enum CatalogError: LocalizedError {
    case invalidJSON
    case missingAlbums
    case noTracks
    case network(String)
    case notURLSource
    case missingFile

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "不是有效的 JSON 文件"
        case .missingAlbums: return "JSON 缺少 albums 字段"
        case .noTracks: return "没有可导入的歌曲（需要 title 和播放地址）"
        case .network(let message): return message
        case .notURLSource: return "只有在线 URL 曲库可以刷新"
        case .missingFile: return "曲库文件已丢失，请重新导入"
        }
    }
}

struct CatalogParseResult {
    var albums: [CatalogAlbum]
    var songs: [Song]
}

enum CatalogParser {
    static func parse(data: Data, sourceID: UUID, sourceName: String, defaultArtist: String) throws -> CatalogParseResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw CatalogError.invalidJSON
        }
        guard let root = object as? [String: Any],
              let albumsObject = root["albums"] as? [String: Any] else {
            throw CatalogError.missingAlbums
        }

        var albums: [CatalogAlbum] = []
        var songs: [Song] = []
        albums.reserveCapacity(albumsObject.count)

        let sortedKeys = albumsObject.keys.sorted { lhs, rhs in
            (Int(lhs) ?? 0) > (Int(rhs) ?? 0)
        }

        for albumKey in sortedKeys {
            guard let tracksRaw = albumsObject[albumKey] as? [[String: Any]] else { continue }
            var albumTracks: [Song] = []
            var albumName = ""
            var coverURL: URL?
            var albumArtist = ""

            for (offset, raw) in tracksRaw.enumerated() {
                guard let song = mapTrack(
                    raw,
                    sourceID: sourceID,
                    albumKey: albumKey,
                    fallbackIndex: offset + 1,
                    defaultArtist: defaultArtist
                ) else { continue }
                albumTracks.append(song)
                if albumName.isEmpty { albumName = song.album }
                if coverURL == nil { coverURL = song.coverURL }
                if albumArtist.isEmpty { albumArtist = song.artists }
            }

            guard !albumTracks.isEmpty else { continue }
            if albumName.isEmpty { albumName = "专辑 \(albumKey)" }
            let album = CatalogAlbum(
                id: "\(sourceID.uuidString):\(albumKey)",
                sourceID: sourceID,
                sourceName: sourceName,
                albumID: albumKey,
                name: albumName,
                artist: albumArtist,
                coverURL: coverURL,
                tracks: albumTracks
            )
            albums.append(album)
            songs.append(contentsOf: albumTracks)
        }

        guard !songs.isEmpty else { throw CatalogError.noTracks }
        return CatalogParseResult(albums: albums, songs: songs)
    }

    private static func mapTrack(
        _ raw: [String: Any],
        sourceID: UUID,
        albumKey: String,
        fallbackIndex: Int,
        defaultArtist: String
    ) -> Song? {
        let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        let audio = firstURL(raw["audio_url"], raw["default_audio_url"])
        let hq = parseURL(raw["hq_audio_url"] as? String)
        guard audio != nil || hq != nil else { return nil }

        let albumName = (raw["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let jsonArtist = (raw["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = jsonArtist.isEmpty ? defaultArtist : jsonArtist
        let albumID = stringID(raw["album_id"]) ?? albumKey
        let songIndex = intValue(raw["song_index"]) ?? fallbackIndex
        let trackID = nonempty(raw["track_id"] as? String)
            ?? nonempty(raw["like_key"] as? String)
            ?? "\(sourceID.uuidString):\(albumID):\(songIndex)"

        return Song(
            id: Song.stableID(from: "catalog-\(trackID)"),
            name: title,
            artists: artist,
            album: albumName,
            coverURL: parseURL(raw["cover_url"] as? String),
            duration: 0,
            source: .catalog,
            catalogTrackID: trackID,
            catalogSourceID: sourceID.uuidString,
            audioURL: audio ?? hq,
            hqAudioURL: hq,
            lyricsURL: parseURL(raw["lyrics_url"] as? String),
            downloadURL: parseURL(raw["download_url"] as? String),
            qualityLabel: raw["quality_label"] as? String
        )
    }

    private static func firstURL(_ values: Any?...) -> URL? {
        for value in values {
            if let url = parseURL(value as? String) { return url }
        }
        return nil
    }

    /// 兼容三种写法：全编码、全中文、中文混着 `%20`。
    /// 先彻底解码再按 path/query 重新编码，避免 `%20` 被编成 `%2520`。
    static func parseURL(_ string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        var decoded = raw
        for _ in 0..<4 {
            guard let next = decoded.removingPercentEncoding, next != decoded else { break }
            decoded = next
        }
        guard let schemeRange = decoded.range(of: "://") else {
            let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? decoded
            return URL(string: encoded)
        }
        let scheme = String(decoded[..<schemeRange.lowerBound])
        let rest = String(decoded[schemeRange.upperBound...])
        let pathStart = rest.firstIndex(of: "/")
        let host = pathStart.map { String(rest[rest.startIndex..<$0]) } ?? rest
        var remainder = pathStart.map { String(rest[$0...]) } ?? ""

        var fragment = ""
        if let hash = remainder.firstIndex(of: "#") {
            fragment = String(remainder[hash...])
            remainder = String(remainder[..<hash])
        }
        var query = ""
        if let mark = remainder.firstIndex(of: "?") {
            query = String(remainder[mark...])
            remainder = String(remainder[..<mark])
        }

        let path = remainder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remainder
        let encodedQuery = query.isEmpty ? "" : (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
        let encodedFragment = fragment.isEmpty ? "" : (fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment)
        return URL(string: "\(scheme)://\(host)\(path)\(encodedQuery)\(encodedFragment)")
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringID(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let i = any as? Int { return String(i) }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }
}

enum CatalogLyricLoader {
    static func load(from url: URL?) async -> String? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
            if let text = String(data: data, encoding: .utf16), !text.isEmpty { return text }
            return nil
        } catch {
            return nil
        }
    }
}

@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    @Published private(set) var sources: [CatalogSource] = []
    @Published private(set) var albums: [CatalogAlbum] = []
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isBusy = false

    var isEmpty: Bool { songs.isEmpty }

    private let fileManager = FileManager.default
    private let indexName = "index.json"

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("BeansCatalogs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL { rootDirectory.appendingPathComponent(indexName) }

    private init() {
        loadFromDisk()
    }

    func song(identityKey: String) -> Song? {
        songs.first { $0.identityKey == identityKey }
    }

    func albums(in sourceID: UUID) -> [CatalogAlbum] {
        albums.filter { $0.sourceID == sourceID }
    }

    func search(_ keyword: String) -> (songs: [Song], albums: [CatalogAlbum]) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (songs, albums) }
        let query = trimmed.lowercased()
        let matchedSongs = songs.filter { song in
            song.name.lowercased().contains(query)
                || song.album.lowercased().contains(query)
                || song.artists.lowercased().contains(query)
        }
        let matchedAlbums = albums.filter { album in
            album.name.lowercased().contains(query)
                || album.artist.lowercased().contains(query)
                || album.sourceName.lowercased().contains(query)
        }
        return (matchedSongs, matchedAlbums)
    }

    @discardableResult
    func importFile(from url: URL, displayName: String?, defaultArtist: String) throws -> CatalogSource {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let name = displayName?.nonempty
            ?? url.deletingPathExtension().lastPathComponent.nonempty
            ?? "本地曲库"
        return try ingest(
            data: data,
            name: name,
            kind: .file,
            origin: url.lastPathComponent,
            defaultArtist: defaultArtist
        )
    }

    @discardableResult
    func importURL(_ raw: String, displayName: String?, defaultArtist: String) async throws -> CatalogSource {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remote = CatalogParser.parseURL(trimmed), remote.scheme == "http" || remote.scheme == "https" else {
            throw CatalogError.network("请输入有效的 http(s) 地址")
        }
        let data = try await download(remote)
        let hostName = remote.host ?? "在线曲库"
        let name = displayName?.nonempty ?? hostName
        return try ingest(
            data: data,
            name: name,
            kind: .url,
            origin: remote.absoluteString,
            defaultArtist: defaultArtist
        )
    }

    func refresh(sourceID: UUID) async throws {
        guard let source = sources.first(where: { $0.id == sourceID }) else { return }
        guard source.kind == .url else { throw CatalogError.notURLSource }
        guard let remote = CatalogParser.parseURL(source.origin) else {
            throw CatalogError.network("曲库地址无效")
        }
        isBusy = true
        defer { isBusy = false }
        let data = try await download(remote)
        let parsed = try CatalogParser.parse(
            data: data,
            sourceID: source.id,
            sourceName: source.name,
            defaultArtist: source.defaultArtist
        )
        try writeCatalogData(data, sourceID: source.id)
        var updated = source
        updated.lastRefreshedAt = Date()
        updated.albumCount = parsed.albums.count
        updated.trackCount = parsed.songs.count
        replace(source: updated)
        rebuildIndex()
    }

    func remove(sourceID: UUID) {
        sources.removeAll { $0.id == sourceID }
        let dir = sourceDirectory(sourceID)
        try? fileManager.removeItem(at: dir)
        persistIndex()
        rebuildIndex()
    }

    func rename(sourceID: UUID, name: String, defaultArtist: String) {
        guard let idx = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines).nonempty ?? sources[idx].name
        sources[idx].defaultArtist = defaultArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        persistIndex()
        rebuildIndex()
    }

    private func ingest(
        data: Data,
        name: String,
        kind: CatalogImportKind,
        origin: String,
        defaultArtist: String
    ) throws -> CatalogSource {
        isBusy = true
        defer { isBusy = false }
        let sourceID = UUID()
        let parsed = try CatalogParser.parse(
            data: data,
            sourceID: sourceID,
            sourceName: name,
            defaultArtist: defaultArtist
        )
        try writeCatalogData(data, sourceID: sourceID)
        let source = CatalogSource(
            id: sourceID,
            name: name,
            kind: kind,
            origin: origin,
            defaultArtist: defaultArtist.trimmingCharacters(in: .whitespacesAndNewlines),
            importedAt: Date(),
            lastRefreshedAt: kind == .url ? Date() : nil,
            albumCount: parsed.albums.count,
            trackCount: parsed.songs.count
        )
        sources.append(source)
        persistIndex()
        rebuildIndex()
        return source
    }

    private func download(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw CatalogError.network("下载失败（HTTP \(http.statusCode)）")
            }
            return data
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.network("下载失败：\(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([CatalogSource].self, from: data) else {
            sources = []
            albums = []
            songs = []
            return
        }
        sources = list
        rebuildIndex()
    }

    private func rebuildIndex() {
        var nextAlbums: [CatalogAlbum] = []
        var nextSongs: [Song] = []
        for source in sources {
            let fileURL = catalogFileURL(source.id)
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? CatalogParser.parse(
                    data: data,
                    sourceID: source.id,
                    sourceName: source.name,
                    defaultArtist: source.defaultArtist
                  ) else {
                continue
            }
            nextAlbums.append(contentsOf: parsed.albums)
            nextSongs.append(contentsOf: parsed.songs)
        }
        albums = nextAlbums
        songs = nextSongs
    }

    private func replace(source: CatalogSource) {
        if let idx = sources.firstIndex(where: { $0.id == source.id }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        persistIndex()
    }

    private func persistIndex() {
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: indexURL, options: [.atomic])
        }
    }

    private func writeCatalogData(_ data: Data, sourceID: UUID) throws {
        let dir = sourceDirectory(sourceID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: catalogFileURL(sourceID), options: [.atomic])
    }

    private func sourceDirectory(_ id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func catalogFileURL(_ id: UUID) -> URL {
        sourceDirectory(id).appendingPathComponent("catalog.json")
    }
}

private extension String {
    var nonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var nonempty: String? { self?.nonempty }
}
