import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct BeansApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BeansAppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var favorites = FavoritesStore.shared
    /// 免责声明确认状态：未确认前主界面在模糊层下方可见，确认后移除门禁
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false

    init() {
        // 闪退检测：优先初始化，检测上次异常退出并安装崩溃捕获
        _ = CrashReporter.shared
        // 尽早开始后台解析曲库，和后面的主题 / 播放器初始化重叠
        _ = CatalogStore.shared
        // 字体注册和歌词背景恢复都走后台，避免更新后第一次启动卡在启动画面
        DispatchQueue.global(qos: .utility).async {
            FontManager.reinstallIfNeeded()
            LyricBackgroundStore.restoreOnLaunch()
        }
        // 新安装默认开启高刷新率；老用户保留自己手动关闭的选择。
        HighRefreshKeeper.registerDefaults()
        HighRefreshKeeper.shared.configureFromDefaults()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if disclaimerAccepted {
                    RootView()
                        .environmentObject(auth)
                        .environmentObject(player)
                        .environmentObject(theme)
                        .environmentObject(favorites)
                        .environmentObject(CatalogStore.shared)
                        .environmentObject(AppSkinStore.shared)
                        .onOpenURL { url in
                            guard url.pathExtension.lowercased() == "json" else { return }
                            do {
                                _ = try CatalogStore.shared.importFile(from: url, displayName: nil, defaultArtist: "")
                                ToastCenter.shared.show("已导入曲库")
                            } catch {
                                ToastCenter.shared.show(error.localizedDescription)
                            }
                        }
                        .onAppear { performPendingQuickAction() }
                } else {
                    // 首次启动只画引导页，不创建主界面四 Tab，避免冷启动卡几秒
                    OnboardingView { disclaimerAccepted = true }
                        .environmentObject(theme)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { performPendingQuickAction() }
            }
            .onChange(of: disclaimerAccepted) { accepted in
                if accepted { performPendingQuickAction() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .beansQuickAction)) { _ in
                performPendingQuickAction()
            }
            #if os(macOS)
            .frame(minWidth: 980, minHeight: 640)
            .onReceive(NotificationCenter.default.publisher(for: .beansMacImportFile)) { _ in
                importCatalogFromOpenPanel()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入曲库文件…") {
                    NotificationCenter.default.post(name: .beansMacImportFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandMenu("播放") {
                Button(player.isPlaying ? "暂停" : "播放") {
                    player.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(player.currentSong == nil)
                Button("下一首") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(player.queue.isEmpty)
                Button("上一首") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(player.queue.isEmpty)
            }
        }
        #endif
        #if os(macOS)
        Window("正在播放", id: "player") {
            MacNowPlayingWindow()
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(favorites)
                .environmentObject(theme)
                .environmentObject(auth)
        }
        .defaultSize(width: 960, height: 640)
        Settings {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(player)
                .environmentObject(auth)
                .frame(minWidth: 560, minHeight: 480)
        }
        #endif
    }

    #if os(macOS)
    private func importCatalogFromOpenPanel() {
        guard let url = MacOpenPanel.pickFiles(contentTypes: [.json], multiple: false).first else { return }
        do {
            _ = try CatalogStore.shared.importFile(from: url, displayName: nil, defaultArtist: "")
            ToastCenter.shared.show("已导入曲库")
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
    #endif

    private func performPendingQuickAction() {
        guard disclaimerAccepted else { return }
        QuickActionCenter.shared.performPending(player: player, favorites: favorites)
    }
}
