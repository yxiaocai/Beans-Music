import SwiftUI
#if os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let beansQuickAction = Notification.Name("beans.quickAction")
    static let beansMacImportFile = Notification.Name("beans.mac.importFile")
}

enum QuickActionType: String {
    case playLiked = "com.beans.app.playLiked"
    case playRecent = "com.beans.app.playRecent"
}

final class QuickActionCenter {
    static let shared = QuickActionCenter()
    private(set) var pendingType: String?

    private init() {}

    #if os(iOS)
    func enqueue(_ item: UIApplicationShortcutItem) {
        pendingType = item.type
        NotificationCenter.default.post(name: .beansQuickAction, object: item.type)
    }
    #endif

    func enqueue(type: String) {
        pendingType = type
        NotificationCenter.default.post(name: .beansQuickAction, object: type)
    }

    @MainActor
    @discardableResult
    func performPending(player: PlayerManager, favorites: FavoritesStore) -> Bool {
        guard let type = pendingType else { return false }
        pendingType = nil
        return perform(type, player: player, favorites: favorites)
    }

    @MainActor
    @discardableResult
    func perform(_ type: String, player: PlayerManager, favorites: FavoritesStore) -> Bool {
        switch QuickActionType(rawValue: type) {
        case .playLiked:
            let songs = favorites.likedSongs
            guard !songs.isEmpty else {
                ToastCenter.shared.show("还没有喜欢的歌曲")
                return false
            }
            player.play(songs: songs, startAt: 0)
            ToastCenter.shared.show("正在播放喜欢的音乐")
            return true
        case .playRecent:
            let songs = player.history
            guard !songs.isEmpty else {
                ToastCenter.shared.show("还没有最近播放")
                return false
            }
            player.play(songs: songs, startAt: 0)
            ToastCenter.shared.show("正在播放最近播放")
            return true
        case nil:
            return false
        }
    }
}

#if os(iOS)
final class BeansAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            QuickActionCenter.shared.enqueue(item)
            return false
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            QuickActionCenter.shared.enqueue(item)
        }
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = BeansSceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        QuickActionCenter.shared.enqueue(shortcutItem)
        completionHandler(true)
    }
}

final class BeansSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActionCenter.shared.enqueue(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        QuickActionCenter.shared.enqueue(shortcutItem)
        completionHandler(true)
    }
}
#endif
