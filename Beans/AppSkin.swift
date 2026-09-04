import SwiftUI

/// 浏览壳皮肤：Beans 液态玻璃（默认）/ Apple Music 资料库风格
enum AppSkin: String, CaseIterable, Identifiable {
    case beans
    case appleMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beans: return "Beans"
        case .appleMusic: return "资料库"
        }
    }

    var subtitle: String {
        switch self {
        case .beans: return "液态玻璃，沿用当前界面"
        case .appleMusic: return "大标题与专辑网格"
        }
    }

    var icon: String {
        switch self {
        case .beans: return "circle.lefthalf.filled"
        case .appleMusic: return "music.note.house"
        }
    }

    /// Apple Music 风格强调色（非官方商标色的近似粉红）
    static let applePink = Color(red: 0.980, green: 0.176, blue: 0.282)
    static let applePinkUI = UIColor(red: 0.980, green: 0.176, blue: 0.282, alpha: 1)
}

final class AppSkinStore: ObservableObject {
    static let shared = AppSkinStore()
    static let defaultsKey = "beans.appSkin"

    @Published var skin: AppSkin {
        didSet {
            UserDefaults.standard.set(skin.rawValue, forKey: Self.defaultsKey)
            ThemeStore.shared.objectWillChange.send()
        }
    }

    var isAppleMusic: Bool { skin == .appleMusic }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        skin = AppSkin(rawValue: raw) ?? .beans
    }
}
