import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var skinStore = AppSkinStore.shared

    @State private var showImport = false
    @State private var selectedAlbumID: String?
    @State private var showHistory = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let _ = theme.accent
        let _ = skinStore.skin
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.customBackground, homeMode: true)
                TabBarAppearanceConfigurator()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if catalog.isEmpty {
                            emptyCard
                        } else {
                            if !player.history.isEmpty {
                                recentSection
                            }
                            albumsSection
                        }
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
        }
        .sheet(isPresented: $showImport) {
            CatalogImportSheet()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("主页")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(catalog.isEmpty ? "导入曲库开始播放" : "\(catalog.albums.count) 张专辑 · \(catalog.songs.count) 首")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
            GlassIconButton(systemName: "square.and.arrow.down") {
                BeansHaptics.tap()
                showImport = true
            }
        }
        .padding(.top, 8)
    }

    private var emptyCard: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "square.and.arrow.down.on.square", text: "还没有曲库\n从本地 JSON 文件或在线 URL 导入")
            GlassButton(title: "导入曲库", systemName: "plus", prominent: true) {
                showImport = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近播放", trailing: "全部") {
                showHistory = true
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(player.history.prefix(12).enumerated()), id: \.element.identityKey) { _, song in
                        Button {
                            if let index = player.history.firstIndex(where: { $0.identityKey == song.identityKey }) {
                                player.play(songs: player.history, startAt: index)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverImage(url: song.coverURL, size: 108, cornerRadius: 12)
                                Text(song.name)
                                    .font(BeansFont.appFont(13, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                    .frame(width: 108, alignment: .leading)
                                Text(song.displayArtist)
                                    .font(BeansFont.appFont(11))
                                    .foregroundStyle(Color.beansComment)
                                    .lineLimit(1)
                                    .frame(width: 108, alignment: .leading)
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
            SectionHeader(title: "专辑")
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(catalog.albums) { album in
                    Button {
                        selectedAlbumID = album.id
                    } label: {
                        CatalogAlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
