import SwiftUI

// MARK: - 流式标签布局（热搜 / 搜索历史）

@available(iOS 16, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum SearchProvider: String, CaseIterable, Identifiable {
    case netease = "网易云"
    case qq = "QQ音乐"
    case kugou = "酷狗音乐"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .netease: return "cloud.fill"
        case .qq: return "play.rectangle.fill"
        case .kugou: return "music.note"
        }
    }

    var brandImageName: String? {
        switch self {
        case .netease: return "BrandNetease"
        case .qq: return "BrandQQ"
        case .kugou: return "BrandKugou"
        }
    }
}

enum SearchResultType: String, CaseIterable, Identifiable {
    case song = "歌曲"
    case album = "专辑"
    var id: String { rawValue }
}

struct SearchView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var historyStore = SearchHistoryStore.shared

    @State private var keyword = ""
    @State private var resultType: SearchResultType = .song
    @State private var selectedAlbumID: String?

    private var trimmed: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: (songs: [Song], albums: [CatalogAlbum]) {
        catalog.search(trimmed)
    }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                TabBarAppearanceConfigurator()
                VStack(spacing: 0) {
                    header
                    searchField
                    if trimmed.isEmpty {
                        idleContent
                    } else {
                        resultTypePicker
                        resultList
                    }
                }
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("搜索")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("在已导入的曲库里查找")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.beansComment)
            TextField("歌名、专辑或艺人", text: $keyword)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    let value = trimmed
                    guard !value.isEmpty else { return }
                    historyStore.record(value)
                }
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.beansComment)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            BeansGlass(shape: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if catalog.isEmpty {
                EmptyStateView(icon: "magnifyingglass", text: "导入曲库后即可搜索")
                    .frame(maxWidth: .infinity)
            } else {
                SearchHistorySection { item in
                    keyword = item
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 190)
    }

    private var resultTypePicker: some View {
        Picker("类型", selection: $resultType) {
            ForEach(SearchResultType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultList: some View {
        if resultType == .song {
            if results.songs.isEmpty {
                EmptyStateView(icon: "music.note", text: "没有找到相关歌曲")
                    .padding(.top, 40)
                Spacer()
            } else {
                List {
                    ForEach(Array(results.songs.enumerated()), id: \.element.identityKey) { index, song in
                        SongCell(song: song, glassRow: true) {
                            historyStore.record(trimmed)
                            player.play(songs: results.songs, startAt: index)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .beansScrollContentBackgroundHidden()
                .listStyle(.plain)
                .padding(.bottom, 120)
            }
        } else {
            if results.albums.isEmpty {
                EmptyStateView(icon: "opticaldisc", text: "没有找到相关专辑")
                    .padding(.top, 40)
                Spacer()
            } else {
                List {
                    ForEach(results.albums) { album in
                        Button {
                            historyStore.record(trimmed)
                            selectedAlbumID = album.id
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: album.coverURL, size: 52, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(album.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text(album.subtitle)
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .beansScrollContentBackgroundHidden()
                .listStyle(.plain)
                .padding(.bottom, 120)
            }
        }
    }
}
