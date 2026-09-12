#if os(macOS)
import SwiftUI

// MARK: - 桌面壳：侧边栏 + 工具栏 + 底栏播放条，不再套用 iPhone 页面

struct MacRootView: View {
    @Binding var selection: RootTab
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("资料库") {
                    Label("主页", systemImage: "house.fill").tag(RootTab.discover)
                    Label("搜索", systemImage: "magnifyingglass").tag(RootTab.search)
                    Label("音乐库", systemImage: "music.note.list").tag(RootTab.library)
                }
                Section {
                    Label("设置", systemImage: "gearshape").tag(RootTab.profile)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 200, max: 260)
            .navigationTitle("BMusic")
        } detail: {
            NavigationStack {
                Group {
                    switch selection {
                    case .discover: MacHomeView()
                    case .search: MacSearchView()
                    case .library: MacLibraryView()
                    case .profile: MacSettingsHubView()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacPlaybackBar()
        }
        .overlay(alignment: .bottom) {
            ToastView(center: ToastCenter.shared)
                .padding(.bottom, 72)
        }
        .frame(minWidth: 1040, minHeight: 660)
        .background(MacWindowBackground())
        .environmentObject(player.clock)
    }
}

struct MacWindowBackground: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Group {
            if let image = theme.customBackgroundImage, theme.backgroundSyncAll {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.18))
            } else if theme.backgroundSyncAll, let color = theme.customBackground {
                color.opacity(0.35)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 主页

struct MacHomeView: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var showImport = false

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 196), spacing: 18)]

    var body: some View {
        Group {
            if catalog.isLoading {
                ProgressView("正在加载曲库…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if catalog.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("还没有曲库")
                        .font(.title2.weight(.semibold))
                    Text("从本地 JSON 或在线 URL 导入后即可播放")
                        .foregroundStyle(.secondary)
                    Button("导入曲库") { showImport = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !player.history.isEmpty {
                            recentSection
                        }
                        albumsSection
                    }
                    .padding(24)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("主页")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImport = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationDestination(for: String.self) { albumID in
            CatalogAlbumDetailView(albumID: albumID)
        }
        .sheet(isPresented: $showImport) {
            CatalogImportSheet()
                .frame(minWidth: 480, minHeight: 420)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近播放")
                .font(.title2.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(player.history.prefix(16).enumerated()), id: \.element.identityKey) { _, song in
                        Button {
                            if let index = player.history.firstIndex(where: { $0.identityKey == song.identityKey }) {
                                player.play(songs: player.history, startAt: index)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverImage(url: song.coverURL, size: 120, cornerRadius: 10)
                                Text(song.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)
                                Text(song.displayArtist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专辑")
                .font(.title2.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(catalog.albums) { album in
                    NavigationLink(value: album.id) {
                        CatalogAlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 搜索

struct MacSearchView: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var keyword = ""

    private var trimmed: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: (songs: [Song], albums: [CatalogAlbum]) {
        catalog.search(trimmed)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView("搜索曲库", systemImage: "magnifyingglass", description: Text("按歌曲、专辑或艺人查找"))
            } else if results.songs.isEmpty && results.albums.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                List {
                    if !results.albums.isEmpty {
                        Section("专辑") {
                            ForEach(results.albums.prefix(20)) { album in
                                NavigationLink(value: album.id) {
                                    HStack(spacing: 12) {
                                        CoverImage(url: album.coverURL, size: 44, cornerRadius: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(album.name).lineLimit(1)
                                            Text(album.subtitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !results.songs.isEmpty {
                        Section("歌曲") {
                            ForEach(Array(results.songs.prefix(80).enumerated()), id: \.element.identityKey) { _, song in
                                Button {
                                    if let index = catalog.songs.firstIndex(where: { $0.identityKey == song.identityKey }) {
                                        player.play(songs: catalog.songs, startAt: index)
                                    } else {
                                        player.play(songs: [song], startAt: 0)
                                    }
                                } label: {
                                    SongCell(song: song)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .navigationDestination(for: String.self) { albumID in
                    CatalogAlbumDetailView(albumID: albumID)
                }
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "歌曲、专辑、艺人")
    }
}

// MARK: - 音乐库

struct MacLibraryView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var localLibrary = LocalLibraryStore.shared
    @State private var showImport = false

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 196), spacing: 18)]

    var body: some View {
        List {
            Section("资料库") {
                NavigationLink {
                    MacSongListView(title: "我喜欢", songs: favorites.likedSongs)
                } label: {
                    Label("我喜欢", systemImage: "heart.fill")
                }
                NavigationLink {
                    MacSongListView(title: "全部歌曲", songs: catalog.songs)
                } label: {
                    Label("全部歌曲", systemImage: "music.note")
                }
            }
            if !localLibrary.playlists.isEmpty {
                Section("歌单") {
                    ForEach(localLibrary.playlists) { playlist in
                        NavigationLink {
                            MacSongListView(title: playlist.name, songs: playlist.songs)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                }
            }
            if !catalog.albums.isEmpty {
                Section("专辑") {
                    ForEach(catalog.albums.prefix(40)) { album in
                        NavigationLink(value: album.id) {
                            HStack(spacing: 10) {
                                CoverImage(url: album.coverURL, size: 36, cornerRadius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name).lineLimit(1)
                                    Text(album.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("音乐库")
        .navigationDestination(for: String.self) { albumID in
            CatalogAlbumDetailView(albumID: albumID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImport = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showImport) {
            CatalogImportSheet()
                .frame(minWidth: 480, minHeight: 420)
        }
    }
}

struct MacSongListView: View {
    @EnvironmentObject private var player: PlayerManager
    let title: String
    let songs: [Song]

    var body: some View {
        Group {
            if songs.isEmpty {
                ContentUnavailableView("还没有歌曲", systemImage: "music.note")
            } else {
                List {
                    ForEach(Array(songs.enumerated()), id: \.element.identityKey) { index, song in
                        Button {
                            player.play(songs: songs, startAt: index)
                        } label: {
                            SongCell(song: song)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if !songs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("播放全部") { player.play(songs: songs, startAt: 0) }
                }
            }
        }
    }
}

// MARK: - 设置

struct MacSettingsHubView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        Form {
            Section("曲库") {
                CatalogSourcesSection()
            }
            Section("播放") {
                Button("播放历史") { showHistory = true }
            }
            Section("外观与高级设置") {
                Button("打开设置…") { showSettings = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(player)
                .frame(minWidth: 640, minHeight: 560)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .frame(minWidth: 480, minHeight: 520)
        }
    }
}

// MARK: - 底栏播放条（Music.app 风格，不是手机悬浮胶囊）

struct MacPlaybackBar: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 16) {
            Button {
                guard player.currentSong != nil else { return }
                openWindow(id: "player")
            } label: {
                HStack(spacing: 10) {
                    CoverImage(url: player.currentSong?.coverURL, size: 44, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentSong?.name ?? "未在播放")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(player.currentSong?.displayArtist ?? "从资料库选一首歌")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 120, maxWidth: 240, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .disabled(player.currentSong == nil)

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                HStack(spacing: 18) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(player.queue.isEmpty)
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 28)
                    }
                    .disabled(player.currentSong == nil)
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(player.queue.isEmpty)
                }
                .buttonStyle(.borderless)
                HStack(spacing: 8) {
                    Text(beansTimeString(clock.progress))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { clock.progress },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(clock.duration, 0.1)
                    )
                    .disabled(player.currentSong == nil || clock.duration <= 0)
                    Text(beansTimeString(clock.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                }
                .frame(minWidth: 280, maxWidth: 420)
            }

            Spacer(minLength: 8)

            if let song = player.currentSong {
                Button {
                    Task { _ = await favorites.toggle(song) }
                } label: {
                    Image(systemName: favorites.isLiked(song) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isLiked(song) ? Color.pink : Color.secondary)
                }
                .buttonStyle(.borderless)
            }

            Button {
                guard player.currentSong != nil else { return }
                openWindow(id: "player")
            } label: {
                Image(systemName: "quote.bubble")
            }
            .buttonStyle(.borderless)
            .disabled(player.currentSong == nil)
            .help("歌词与正在播放")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - 正在播放窗口（封面 + 歌词，桌面双栏）

struct MacNowPlayingWindow: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var lyrics: [LyricLine] = []

    private var song: Song? { player.currentSong }

    private var currentLineIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let t = clock.progress
        var answer: Int?
        for (i, line) in lyrics.enumerated() {
            if line.time <= t { answer = i } else { break }
        }
        return answer
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 18) {
                CoverImage(url: song?.coverURL, size: 280, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                VStack(spacing: 6) {
                    Text(song?.name ?? "未在播放")
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(song?.displayArtist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 28) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title2)
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title2)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(song == nil)
                if let song {
                    Button {
                        Task { _ = await favorites.toggle(song) }
                    } label: {
                        Image(systemName: favorites.isLiked(song) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isLiked(song) ? Color.pink : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
            }
            .padding(28)
            .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)
            .frame(maxHeight: .infinity)

            Group {
                if lyrics.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "quote.bubble")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                                    let current = index == currentLineIndex
                                    Text(line.text.isEmpty ? " " : line.text)
                                        .font(current ? .title3.weight(.bold) : .body)
                                        .foregroundStyle(current ? Color.primary : Color.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                            .padding(28)
                        }
                        .onChange(of: currentLineIndex) { index in
                            if let index, lyrics.indices.contains(index) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(lyrics[index].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 360)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: song?.identityKey) {
            await loadLyrics()
        }
    }

    private func loadLyrics() async {
        lyrics = []
        guard let song else { return }
        let identity = song.identityKey
        let raw: String?
        if song.source == .catalog {
            raw = await CatalogLyricLoader.load(from: song.lyricsURL, identity: song.identityKey)
        } else {
            raw = nil
        }
        guard player.currentSong?.identityKey == identity else { return }
        if let raw { lyrics = LyricParser.parse(raw) }
    }
}
#endif
