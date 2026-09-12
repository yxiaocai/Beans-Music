import SwiftUI

enum AppleMusicTab: String, CaseIterable, Identifiable {
    case listenNow
    case browse
    case library
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listenNow: return "现在就听"
        case .browse: return "浏览"
        case .library: return "资料库"
        case .search: return "搜索"
        }
    }

    var icon: String {
        switch self {
        case .listenNow: return "play.circle.fill"
        case .browse: return "square.grid.2x2.fill"
        case .library: return "music.note.list"
        case .search: return "magnifyingglass"
        }
    }
}

struct AppleMusicRootTabs: View {
    @Binding var selection: AppleMusicTab

    var body: some View {
        TabView(selection: $selection) {
            AppleLazyTab(isSelected: selection == .listenNow) {
                AppleListenNowView()
            }
                .tabItem { Label(AppleMusicTab.listenNow.title, systemImage: AppleMusicTab.listenNow.icon) }
                .tag(AppleMusicTab.listenNow)
            AppleLazyTab(isSelected: selection == .browse) {
                AppleBrowseView()
            }
                .tabItem { Label(AppleMusicTab.browse.title, systemImage: AppleMusicTab.browse.icon) }
                .tag(AppleMusicTab.browse)
            AppleLazyTab(isSelected: selection == .library) {
                AppleLibraryView()
            }
                .tabItem { Label(AppleMusicTab.library.title, systemImage: AppleMusicTab.library.icon) }
                .tag(AppleMusicTab.library)
            AppleLazyTab(isSelected: selection == .search) {
                AppleSearchView()
            }
                .tabItem { Label(AppleMusicTab.search.title, systemImage: AppleMusicTab.search.icon) }
                .tag(AppleMusicTab.search)
        }
        .tint(AppSkin.applePink)
    }
}

private struct AppleLazyTab<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder var content: () -> Content
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if hasAppeared || isSelected {
                content()
            } else {
                Color.clear
            }
        }
        .onAppear {
            if isSelected { hasAppeared = true }
        }
        .onChange(of: isSelected) { selected in
            if selected { hasAppeared = true }
        }
    }
}

private struct AppleScreen<Content: View>: View {
    let title: String
    var trailing: AnyView = AnyView(EmptyView())
    @ViewBuilder var content: Content

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                content
            }
            .navigationTitle(title)
            .navigationBarItems(trailing: trailing)
        }
        .navigationViewStyle(.stack)
    }
}

struct AppleListenNowView: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var localLibrary = LocalLibraryStore.shared
    @State private var showImport = false
    @State private var showSettings = false
    @State private var selectedAlbumID: String?

    var body: some View {
        AppleScreen(title: "现在就听", trailing: AnyView(
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(AppSkin.applePink)
            }
        )) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if catalog.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if catalog.isEmpty {
                        appleEmptyImport { showImport = true }
                    } else {
                        if !player.history.isEmpty {
                            appleHorizontalSongs(title: "最近播放", songs: Array(player.history.prefix(16))) { song in
                                if let index = player.history.firstIndex(where: { $0.identityKey == song.identityKey }) {
                                    player.play(songs: player.history, startAt: index)
                                }
                            }
                        }
                        if !localLibrary.playlists.isEmpty {
                            playlistsRow
                        }
                        albumsGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 160)
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedAlbumID {
                            CatalogAlbumDetailView(albumID: selectedAlbumID)
                        }
                    },
                    isActive: Binding(get: { selectedAlbumID != nil }, set: { if !$0 { selectedAlbumID = nil } })
                ) { EmptyView() }.hidden()
            )
        }
        .sheet(isPresented: $showImport) { CatalogImportSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var playlistsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放列表")
                .font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(localLibrary.playlists) { playlist in
                        Button {
                            if !playlist.songs.isEmpty {
                                player.play(songs: playlist.songs, startAt: 0)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverImage(url: playlist.songs.first?.coverURL, size: 140, cornerRadius: 8)
                                Text(playlist.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专辑")
                .font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 18) {
                ForEach(catalog.albums.prefix(12)) { album in
                    Button { selectedAlbumID = album.id } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            GeometryReader { geo in
                                CoverImage(url: album.coverURL, size: geo.size.width, cornerRadius: 8)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            Text(album.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(2)
                            Text(album.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppleBrowseView: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var showImport = false
    @State private var selectedAlbumID: String?

    var body: some View {
        AppleScreen(title: "浏览", trailing: AnyView(
            Button { showImport = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(AppSkin.applePink)
            }
        )) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if catalog.sources.isEmpty {
                        appleEmptyImport { showImport = true }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("曲库来源")
                                .font(.title2.bold())
                            ForEach(catalog.sources) { source in
                                HStack(spacing: 12) {
                                    Image(systemName: source.kind == .url ? "link" : "doc")
                                        .foregroundStyle(AppSkin.applePink)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.name)
                                            .font(.body.weight(.semibold))
                                        Text("\(source.albumCount) 专辑 · \(source.trackCount) 首")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 18) {
                            ForEach(catalog.albums) { album in
                                Button { selectedAlbumID = album.id } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        GeometryReader { geo in
                                            CoverImage(url: album.coverURL, size: geo.size.width, cornerRadius: 8)
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        Text(album.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 160)
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedAlbumID {
                            CatalogAlbumDetailView(albumID: selectedAlbumID)
                        }
                    },
                    isActive: Binding(get: { selectedAlbumID != nil }, set: { if !$0 { selectedAlbumID = nil } })
                ) { EmptyView() }.hidden()
            )
        }
        .sheet(isPresented: $showImport) { CatalogImportSheet() }
    }
}

struct AppleLibraryView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var localLibrary = LocalLibraryStore.shared
    @State private var segment = 0
    @State private var selectedPlaylist: LocalPlaylist?
    @State private var selectedAlbumID: String?
    @State private var showCreate = false
    @State private var newName = ""
    @State private var showLiked = false

    var body: some View {
        AppleScreen(title: "资料库", trailing: AnyView(
            Button {
                newName = ""
                showCreate = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(AppSkin.applePink)
            }
        )) {
            VStack(spacing: 0) {
                Picker("分类", selection: $segment) {
                    Text("播放列表").tag(0)
                    Text("专辑").tag(1)
                    Text("歌曲").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Group {
                    if segment == 0 {
                        playlistsList
                    } else if segment == 1 {
                        albumsList
                    } else {
                        songsList
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedAlbumID {
                            CatalogAlbumDetailView(albumID: selectedAlbumID)
                        }
                    },
                    isActive: Binding(get: { selectedAlbumID != nil }, set: { if !$0 { selectedAlbumID = nil } })
                ) { EmptyView() }.hidden()
            )
        }
        .sheet(item: $selectedPlaylist) { playlist in
            LocalPlaylistDetailSheet(playlistID: playlist.id)
                .environmentObject(player)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showLiked) {
            LikedSongsSheet()
                .environmentObject(player)
                .environmentObject(favorites)
        }
        .alert("新建播放列表", isPresented: $showCreate) {
            TextField("名称", text: $newName)
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                selectedPlaylist = localLibrary.createPlaylist(name: name)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var playlistsList: some View {
        List {
            Button { showLiked = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(AppSkin.applePink, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("我喜欢")
                            .foregroundStyle(Color.primary)
                        Text("\(favorites.likedSongs.count) 首")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(localLibrary.playlists) { playlist in
                Button { selectedPlaylist = playlist } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: playlist.songs.first?.coverURL, size: 48, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .foregroundStyle(Color.primary)
                            Text("\(playlist.songs.count) 首")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var albumsList: some View {
        List {
            ForEach(catalog.albums) { album in
                Button { selectedAlbumID = album.id } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: album.coverURL, size: 48, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.name)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(album.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var songsList: some View {
        List {
            ForEach(Array(catalog.songs.enumerated()), id: \.element.identityKey) { index, song in
                Button {
                    player.play(songs: catalog.songs, startAt: index)
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: song.coverURL, size: 44, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(song.displayArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct AppleSearchView: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var historyStore = SearchHistoryStore.shared
    @State private var keyword = ""
    @State private var selectedAlbumID: String?

    private var trimmed: String { keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: (songs: [Song], albums: [CatalogAlbum]) { catalog.search(trimmed) }

    var body: some View {
        AppleScreen(title: "搜索") {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("歌曲、专辑", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if trimmed.isEmpty {
                    SearchHistorySection { keyword = $0 }
                        .padding(.horizontal, 16)
                    Spacer()
                } else {
                    List {
                        if !results.songs.isEmpty {
                            Section("歌曲") {
                                ForEach(Array(results.songs.enumerated()), id: \.element.identityKey) { index, song in
                                    Button {
                                        historyStore.record(trimmed)
                                        player.play(songs: results.songs, startAt: index)
                                    } label: {
                                        HStack(spacing: 12) {
                                            CoverImage(url: song.coverURL, size: 44, cornerRadius: 6)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(song.name).foregroundStyle(Color.primary).lineLimit(1)
                                                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !results.albums.isEmpty {
                            Section("专辑") {
                                ForEach(results.albums) { album in
                                    Button {
                                        historyStore.record(trimmed)
                                        selectedAlbumID = album.id
                                    } label: {
                                        HStack(spacing: 12) {
                                            CoverImage(url: album.coverURL, size: 44, cornerRadius: 6)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(album.name).foregroundStyle(Color.primary).lineLimit(1)
                                                Text(album.subtitle).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if results.songs.isEmpty && results.albums.isEmpty {
                            Text("没有结果")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedAlbumID {
                            CatalogAlbumDetailView(albumID: selectedAlbumID)
                        }
                    },
                    isActive: Binding(get: { selectedAlbumID != nil }, set: { if !$0 { selectedAlbumID = nil } })
                ) { EmptyView() }.hidden()
            )
        }
    }
}

private func appleEmptyImport(action: @escaping () -> Void) -> some View {
    VStack(spacing: 14) {
        Image(systemName: "square.and.arrow.down")
            .font(.system(size: 42, weight: .light))
            .foregroundStyle(AppSkin.applePink)
        Text("导入曲库开始听")
            .font(.headline)
        Text("选择本地 JSON 或粘贴在线地址")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Button("导入", action: action)
            .buttonStyle(.borderedProminent)
            .tint(AppSkin.applePink)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
}

private func appleHorizontalSongs(title: String, songs: [Song], play: @escaping (Song) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.title2.bold())
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(songs, id: \.identityKey) { song in
                    Button { play(song) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CoverImage(url: song.coverURL, size: 140, cornerRadius: 8)
                            Text(song.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                            Text(song.displayArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
