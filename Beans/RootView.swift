import SwiftUI
import UIKit

enum RootTab: String, CaseIterable, Identifiable {
    case discover
    case search
    case library
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "主页"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .profile: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .profile: return "person.crop.circle"
        }
    }
}

/// 只构建当前选中（以及曾经打开过）的 Tab，避免更新后第一次启动同时实例化四个页面。
private struct LazyTabContent<Content: View>: View {
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

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var skinStore = AppSkinStore.shared
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var selection: RootTab = .discover
    @State private var appleSelection: AppleMusicTab = .listenNow
    @State private var showPlayer = false
    /// 底栏是否显示文字（关闭后只显示图标）
    @AppStorage("beans.tabLabelsVisible") private var tabLabelsVisible = true
    /// 可选高刷新率，默认开启；需要省电时可在设置里关闭。
    @AppStorage("beans.enableHighRefresh") private var enableHighRefresh = true
    @AppStorage("beans.legacyTabCornerRadius") private var legacyTabCornerRadius = 32.0
    @AppStorage("beans.legacyTabWidth") private var legacyTabWidth = 356.0
    @AppStorage("beans.legacyTabOffsetX") private var legacyTabOffsetX = 0.0
    @AppStorage("beans.legacyTabOffsetY") private var legacyTabOffsetY = 0.0
    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var usesSystemFloatingTabBar: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private var miniPlayerBottomPadding: CGFloat {
        usesSystemFloatingTabBar ? 62 : 80
    }

    private var legacyTabResolvedCornerRadius: CGFloat {
        CGFloat(legacyTabCornerRadius)
    }

    private var legacyTabResolvedWidth: CGFloat {
        min(CGFloat(legacyTabWidth), max(300, UIScreen.main.bounds.width - 28))
    }

    var body: some View {
        let _ = theme.accent
        let _ = skinStore.skin
        ZStack {
            // 系统原生 TabView：iOS 26 上 UITabBar 自动使用原生液态玻璃，
            // 按压折射反馈、拖动效果、高光均由系统渲染（与应用商店等系统 App 一致）。
            // 背景（壁纸/背景色）由每个 tab 页面内部的 GlassBackdrop 渲染，
            // 因为系统 TabView 的内容层会盖住 RootView 底层的 ZStack 背景。
            Group {
                if skinStore.isAppleMusic {
                    AppleMusicRootTabs(selection: $appleSelection)
                } else {
                    TabView(selection: $selection) {
                        LazyTabContent(isSelected: selection == .discover) {
                            DiscoverView()
                        }
                            .tabItem { Label(tabLabelsVisible ? "主页" : "", systemImage: "house.fill") }
                            .tag(RootTab.discover)
                        LazyTabContent(isSelected: selection == .search) {
                            SearchView()
                        }
                            .tabItem { Label(tabLabelsVisible ? "搜索" : "", systemImage: "magnifyingglass") }
                            .tag(RootTab.search)
                        LazyTabContent(isSelected: selection == .library) {
                            LibraryView()
                        }
                            .tabItem { Label(tabLabelsVisible ? "音乐库" : "", systemImage: "music.note.list") }
                            .tag(RootTab.library)
                        LazyTabContent(isSelected: selection == .profile) {
                            ProfileView()
                        }
                            .tabItem { Label(tabLabelsVisible ? "我的" : "", systemImage: "person.crop.circle") }
                            .tag(RootTab.profile)
                    }
                    .tint(Color.beansAmber)
                    .background {
                        TabBarAppearanceConfigurator(hidesSystemTabBarOnLegacy: !usesSystemFloatingTabBar)
                    }
                }
            }

            if !usesSystemFloatingTabBar && !skinStore.isAppleMusic {
                legacyFloatingTabBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(8)
            }

            // 迷你播放器：悬浮在系统 TabBar 上方
            VStack(spacing: 0) {
                Spacer()
                if player.currentSong != nil {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .environmentObject(player.clock)
                        .padding(.horizontal, 12)
                        .padding(.bottom, miniPlayerBottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(themeMode.colorScheme)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(isPresented: $showPlayer)
                .environmentObject(favorites)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(auth)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: player.currentSong?.id)
        .animation(.easeInOut(duration: 0.22), value: selection)
        .overlay(alignment: .bottom) {
            ToastView(center: ToastCenter.shared)
        }
        .onAppear {
            CrashReporter.shared.markLaunchCompleted()
            HighRefreshKeeper.shared.configure(enabled: enableHighRefresh)
        }
        .onChange(of: enableHighRefresh) { enabled in
            HighRefreshKeeper.shared.configure(enabled: enabled)
        }
    }

    private var legacyFloatingTabBar: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    BeansHaptics.select()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    let selected = selection == tab
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: selected ? .semibold : .medium))
                            .symbolRenderingMode(.hierarchical)
                        if tabLabelsVisible {
                            Text(tab.title)
                                .font(BeansFont.appFont(10, selected ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                    .foregroundStyle(selected ? Color.beansAmber : Color.beansLabel.opacity(0.70))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(Color.beansAmber.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder(Color.beansAmber.opacity(0.18), lineWidth: 0.7)
                                }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.94))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: legacyTabResolvedWidth)
        .background {
            RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                .fill(.clear)
                .background {
                    VisualEffectBlur(style: .systemUltraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.20), lineWidth: 0.7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.04), .black.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous))
                }
                .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .offset(x: CGFloat(legacyTabOffsetX), y: CGFloat(legacyTabOffsetY))
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - 系统 TabBar 清透风格（实例级配置）
// 系统 TabView 创建之后，`UITabBar.appearance()` 全局代理对已存在的实例不再生效，
// 所以每个 tab 页面内放一个 TabBarAppearanceConfigurator，通过 tabBarController
// 拿到当前 UITabBar 实例，直接设置固定清透外观（全透明、无阴影）。

struct TabBarAppearanceConfigurator: UIViewControllerRepresentable {
    var hidesSystemTabBarOnLegacy = true

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        // 纯外观配置视图：禁止拦截触摸，避免透明全屏视图吃掉页面按钮点击
        controller.view.isUserInteractionEnabled = false
        DispatchQueue.main.async { Self.apply(from: controller, hidesSystemTabBarOnLegacy: hidesSystemTabBarOnLegacy) }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async { Self.apply(from: uiViewController, hidesSystemTabBarOnLegacy: hidesSystemTabBarOnLegacy) }
    }

    /// 固定清透风格：全透明背景、无阴影；选中态用主题色，
    /// 材质与模糊完全交给系统对底层页面内容的渲染，不再支持手动调节透明度
    private static func apply(from controller: UIViewController, hidesSystemTabBarOnLegacy: Bool) {
        guard let tabBar = controller.tabBarController?.tabBar else { return }
        if #available(iOS 26, *) {
            tabBar.isHidden = false
        } else if hidesSystemTabBarOnLegacy {
            tabBar.isHidden = true
            tabBar.isTranslucent = true
            return
        } else {
            tabBar.isHidden = false
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        // 超薄材质模糊：与迷你播放器一致的清透玻璃透明度
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor.beansAmber
        tabBar.isTranslucent = true
    }
}
