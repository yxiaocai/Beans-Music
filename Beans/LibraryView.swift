import SwiftUI

enum LibraryProvider: String, CaseIterable, Identifiable {
    case netease = "网易云"
    case qq = "QQ音乐"
    case kugou = "酷狗"

    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var localLibrary = LocalLibraryStore.shared

    @State private var showCreate = false
    @State private var newName = ""
    @State private var selectedPlaylist: LocalPlaylist?
    @State private var selectedAlbumID: String?
    @State private var showAllSongs = false
    @State private var showAllAlbums = false
    @State private var showLiked = false
    @State private var showImport = false

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                TabBarAppearanceConfigurator()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        likedSection
                        playlistsSection
                        albumsSection
                        songsPreview
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 190)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationBarHidden(true)
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedAlbumID {
                            CatalogAlbumDetailView(albumID: selectedAlbumID)
                        }
                    },
                    isActive: Binding(
                        get: { selectedAlbumID != nil },
                        set: { if !$0 { selectedAlbumID = nil } }
                    )
                ) { EmptyView() }
                .hidden()
            )
            .background(
                NavigationLink(destination: CatalogAllSongsView(), isActive: $showAllSongs) { EmptyView() }.hidden()
            )
            .background(
                NavigationLink(destination: CatalogAllAlbumsView(), isActive: $showAllAlbums) { EmptyView() }.hidden()
            )
        }
        .alert("新建歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                selectedPlaylist = localLibrary.createPlaylist(name: name)
                newName = ""
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("歌单保存在本机，歌曲从已导入曲库中挑选")
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
        .sheet(isPresented: $showImport) {
            CatalogImportSheet()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("音乐库")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(catalog.isEmpty ? "导入曲库后即可建立歌单" : "歌单、专辑与歌曲")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
            GlassIconButton(systemName: "plus") {
                BeansHaptics.tap()
                newName = ""
                showCreate = true
            }
        }
        .padding(.top, 8)
    }

    private var likedSection: some View {
        Button {
            showLiked = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color.pink.opacity(0.85), Color.beansAmber.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("我喜欢")
                        .font(BeansFont.appFont(16, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text("\(favorites.likedSongs.count) 首 · 系统歌单")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.6))
            }
            .padding(14)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "自建歌单", trailing: "新建") {
                newName = ""
                showCreate = true
            }
            if localLibrary.playlists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "还没有歌单\n从已导入的歌曲里挑选收藏")
            } else {
                VStack(spacing: 0) {
                    ForEach(localLibrary.playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                localLibrary.deletePlaylist(id: playlist.id)
                                ToastCenter.shared.show("已删除歌单")
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                        if playlist.id != localLibrary.playlists.last?.id {
                            Divider().overlay(Color.beansComment.opacity(0.12))
                        }
                    }
                }
                .padding(.vertical, 6)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func playlistRow(_ playlist: LocalPlaylist) -> some View {
        HStack(spacing: 12) {
            playlistCover(playlist)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(BeansFont.appFont(15, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text("\(playlist.songs.count) 首 · 本机")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.beansComment.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func playlistCover(_ playlist: LocalPlaylist) -> some View {
        let covers = playlist.songs.prefix(4).compactMap(\.coverURL)
        if covers.count >= 4 {
            let size: CGFloat = 27
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    CoverImage(url: covers[0], size: size, cornerRadius: 4)
                    CoverImage(url: covers[1], size: size, cornerRadius: 4)
                }
                HStack(spacing: 1) {
                    CoverImage(url: covers[2], size: size, cornerRadius: 4)
                    CoverImage(url: covers[3], size: size, cornerRadius: 4)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            CoverImage(url: playlist.songs.first?.coverURL, size: 56, cornerRadius: 12)
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "专辑", trailing: catalog.albums.isEmpty ? nil : "全部") {
                showAllAlbums = true
            }
            if catalog.albums.isEmpty {
                EmptyStateView(icon: "opticaldisc", text: "导入曲库后这里会列出专辑")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(catalog.albums.prefix(12)) { album in
                            Button {
                                selectedAlbumID = album.id
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverImage(url: album.coverURL, size: 120, cornerRadius: 12)
                                    Text(album.name)
                                        .font(BeansFont.appFont(13, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(2)
                                        .frame(width: 120, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var songsPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "歌曲", trailing: catalog.songs.isEmpty ? nil : "全部") {
                showAllSongs = true
            }
            if catalog.songs.isEmpty {
                Button {
                    showImport = true
                } label: {
                    EmptyStateView(icon: "square.and.arrow.down", text: "点这里导入 JSON 曲库")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(catalog.songs.prefix(8).enumerated()), id: \.element.identityKey) { index, song in
                        SongCell(song: song) {
                            player.play(songs: catalog.songs, startAt: index)
                        }
                        .padding(.horizontal, 10)
                    }
                }
                .padding(.vertical, 6)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }
}

struct LikedSongsSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BeansNavigationStack {
            Group {
                if favorites.likedSongs.isEmpty {
                    EmptyStateView(icon: "heart", text: "还没有喜欢的歌曲\n在播放器里点红心即可收藏")
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    player.play(songs: favorites.likedSongs, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    player.play(songs: favorites.likedSongs.shuffled(), startAt: 0)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        Section {
                            ForEach(Array(favorites.likedSongs.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: favorites.likedSongs, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        favorites.removeCatalogFavorite(song)
                                    } label: {
                                        Label("取消喜欢", systemImage: "heart.slash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("我喜欢")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }
}
