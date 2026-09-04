import SwiftUI
import UniformTypeIdentifiers

struct CatalogAlbumCard: View {
    let album: CatalogAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                CoverImage(url: album.coverURL, size: geo.size.width, cornerRadius: 12)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.beansLabel)
                .lineLimit(2)
            Text(album.subtitle)
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct CatalogAlbumDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var catalog = CatalogStore.shared
    let albumID: String

    private var album: CatalogAlbum? {
        catalog.albums.first { $0.id == albumID }
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            if let album {
                List {
                    Section {
                        header(album)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    Section {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.identityKey) { index, song in
                            SongCell(song: song, glassRow: true) {
                                player.play(songs: album.tracks, startAt: index)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .beansScrollContentBackgroundHidden()
                .listStyle(.plain)
            } else {
                EmptyStateView(icon: "opticaldisc", text: "专辑不存在或曲库已删除")
            }
        }
        .navigationTitle(album?.name ?? "专辑")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ album: CatalogAlbum) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CoverImage(url: album.coverURL, size: 112, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text(album.name)
                        .font(BeansFont.appFont(20, .bold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(3)
                    if !album.artist.isEmpty {
                        Text(album.artist)
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                    }
                    Text("\(album.tracks.count) 首 · \(album.sourceName)")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                    player.play(songs: album.tracks, startAt: 0)
                }
                GlassButton(title: "随机播放", systemName: "shuffle") {
                    player.play(songs: album.tracks.shuffled(), startAt: 0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CatalogImportSheet: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .file
    @State private var displayName = ""
    @State private var defaultArtist = ""
    @State private var urlText = ""
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var importing = false

    enum Mode: String, CaseIterable, Identifiable {
        case file = "本地文件"
        case url = "在线 URL"
        var id: String { rawValue }
    }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            Form {
                Section {
                    Picker("导入方式", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("曲库信息") {
                    TextField("名称（可选）", text: $displayName)
                    TextField("默认艺人（可选，空 artist 时使用）", text: $defaultArtist)
                }

                if mode == .url {
                    Section("JSON 地址") {
                        TextField("https://example.com/catalog.json", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    Section {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("选择 JSON 文件", systemImage: "doc.badge.plus")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await runImport() }
                    } label: {
                        if importing {
                            ProgressView()
                        } else {
                            Text(mode == .file ? "选择文件并导入" : "从 URL 导入")
                                .font(BeansFont.appFont(16, .semibold))
                        }
                    }
                    .disabled(importing || (mode == .url && urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                } footer: {
                    Text("支持同时导入多份 catalog.json。同一来源刷新时按歌曲身份更新，不会和其他曲库合并。")
                }
            }
            .navigationTitle("导入曲库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importFile(url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runImport() async {
        if mode == .file {
            showFileImporter = true
            return
        }
        importing = true
        errorMessage = nil
        defer { importing = false }
        do {
            let source = try await catalog.importURL(urlText, displayName: displayName, defaultArtist: defaultArtist)
            ToastCenter.shared.show("已导入 \(source.trackCount) 首")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(_ url: URL) async {
        importing = true
        errorMessage = nil
        defer { importing = false }
        do {
            let source = try catalog.importFile(from: url, displayName: displayName, defaultArtist: defaultArtist)
            ToastCenter.shared.show("已导入 \(source.trackCount) 首")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CatalogSourcesSection: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var showImport = false
    @State private var pendingDelete: CatalogSource?
    @State private var editing: CatalogSource?
    @State private var refreshError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "曲库来源", trailing: "导入") {
                BeansHaptics.tap()
                showImport = true
            }
            if catalog.sources.isEmpty {
                EmptyStateView(icon: "square.and.arrow.down", text: "还没有曲库\n导入本地 JSON 或在线 URL")
            } else {
                VStack(spacing: 0) {
                    ForEach(catalog.sources) { source in
                        sourceRow(source)
                        if source.id != catalog.sources.last?.id {
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
            if let refreshError {
                Text(refreshError)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showImport) {
            CatalogImportSheet()
        }
        .sheet(item: $editing) { source in
            CatalogSourceEditSheet(source: source)
        }
        .confirmationDialog("删除曲库「\(pendingDelete?.name ?? "")」？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    catalog.remove(sourceID: pendingDelete.id)
                    ToastCenter.shared.show("已删除曲库")
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("自建歌单里已添加的歌曲仍可播放，但专辑列表会移除。")
        }
    }

    private func sourceRow(_ source: CatalogSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind == .url ? "link" : "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.beansAmber)
                .frame(width: 36, height: 36)
                .background(Color.beansGlassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(BeansFont.appFont(15, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text("\(source.kindLabel) · \(source.albumCount) 张专辑 · \(source.trackCount) 首")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                if source.kind == .url {
                    Button {
                        Task {
                            do {
                                try await catalog.refresh(sourceID: source.id)
                                ToastCenter.shared.show("已刷新「\(source.name)」")
                                refreshError = nil
                            } catch {
                                refreshError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                Button {
                    editing = source
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = source
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct CatalogSourceEditSheet: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @Environment(\.dismiss) private var dismiss
    let source: CatalogSource
    @State private var name = ""
    @State private var defaultArtist = ""

    var body: some View {
        BeansNavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("默认艺人", text: $defaultArtist)
                } footer: {
                    Text("修改默认艺人后会重新套用到该来源里 artist 为空的歌曲。")
                }
            }
            .navigationTitle("编辑曲库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        catalog.rename(sourceID: source.id, name: name, defaultArtist: defaultArtist)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = source.name
                defaultArtist = source.defaultArtist
            }
        }
    }
}

struct CatalogSongPickerSheet: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @ObservedObject private var library = LocalLibraryStore.shared
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID
    @State private var keyword = ""

    private var filtered: [Song] {
        catalog.search(keyword).songs
    }

    var body: some View {
        BeansNavigationStack {
            VStack(spacing: 0) {
                TextField("搜索已导入的歌曲", text: $keyword)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.beansGlassFill))
                    .padding(12)
                if catalog.isEmpty {
                    Spacer()
                    EmptyStateView(icon: "square.and.arrow.down", text: "先导入曲库，再挑选歌曲")
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    Text("没有匹配的歌曲")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                    Spacer()
                } else {
                    List {
                        ForEach(filtered, id: \.identityKey) { song in
                            SongCell(song: song, glassRow: true) {
                                library.addSong(song, to: playlistID)
                                BeansHaptics.success()
                                ToastCenter.shared.show("已加入歌单")
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("添加歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }
}

struct CatalogAllSongsView: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @EnvironmentObject private var player: PlayerManager
    @State private var keyword = ""

    private var songs: [Song] {
        keyword.isEmpty ? catalog.songs : catalog.search(keyword).songs
    }

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.identityKey) { index, song in
                SongCell(song: song, glassRow: true) {
                    player.play(songs: songs, startAt: index)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .beansScrollContentBackgroundHidden()
        .listStyle(.plain)
        .navigationTitle("全部歌曲")
        .searchable(text: $keyword, prompt: "搜索歌曲")
    }
}

struct CatalogAllAlbumsView: View {
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var selectedAlbumID: String?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
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
            .padding(16)
            .padding(.bottom, 120)
        }
        .navigationTitle("全部专辑")
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
