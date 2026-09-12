#if os(macOS)
import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import WebKit

typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIFont = NSFont

extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

extension Color {
    init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

extension NSColor {
    convenience init(white: CGFloat, alpha: CGFloat) {
        self.init(calibratedWhite: white, alpha: alpha)
    }

    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var systemGray2: NSColor { .systemGray }
}

extension CIImage {
    convenience init?(image: NSImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    var scale: CGFloat { 1 }
}

final class UIGraphicsImageRendererFormat {
    var scale: CGFloat = 1
    static func `default`() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

struct UIGraphicsImageRendererContext {}

final class UIGraphicsImageRenderer {
    private let size: CGSize
    private let format: UIGraphicsImageRendererFormat

    init(size: CGSize, format: UIGraphicsImageRendererFormat = .default()) {
        self.size = size
        self.format = format
    }

    func image(_ actions: (UIGraphicsImageRendererContext) -> Void) -> NSImage {
        let scale = max(format.scale, 1)
        let pixelsW = max(1, Int((size.width * scale).rounded()))
        let pixelsH = max(1, Int((size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        actions(UIGraphicsImageRendererContext())
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

enum BeansHaptics {
    static func prepare() {}
    static func tap() {}
    static func medium() {}
    static func success() {}
    static func select() {}
}

enum MacOpenPanel {
    static func pickFiles(contentTypes: [UTType], multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}

struct TabBarAppearanceConfigurator: View {
    var hidesSystemTabBarOnLegacy = true
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}

struct ShareSheet: View {
    let items: [Any]
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                let urls = items.compactMap { $0 as? URL }
                guard let view = NSApp.keyWindow?.contentView else { return }
                let picker = NSSharingServicePicker(items: urls.isEmpty ? items : urls)
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
    }
}

struct WallpaperPhotoPicker: View {
    let onPicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .onAppear {
                let urls = MacOpenPanel.pickFiles(contentTypes: [.image], multiple: true)
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        onPicked(data)
                    }
                }
                dismiss()
            }
    }
}

struct FontDocumentPicker: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .onAppear {
                if let url = MacOpenPanel.pickFiles(contentTypes: [.item], multiple: false).first {
                    onPick(url)
                }
                dismiss()
            }
    }
}

struct BackupDocumentPicker: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .onAppear {
                if let url = MacOpenPanel.pickFiles(contentTypes: [.json, .plainText, .item], multiple: false).first {
                    onPick(url)
                }
                dismiss()
            }
    }
}

struct BeansWebView: NSViewRepresentable {
    let urlString: String
    let onLoaded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoaded: onLoaded) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: () -> Void
        init(onLoaded: @escaping () -> Void) { self.onLoaded = onLoaded }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.onLoaded() }
        }
    }
}

struct QQWebView: View {
    let onLoaded: () -> Void
    var body: some View {
        BeansWebView(urlString: "https://y.qq.com/", onLoaded: onLoaded)
    }
}

struct NetEaseWebView: View {
    let onLoaded: () -> Void
    var body: some View {
        BeansWebView(urlString: "https://music.163.com/#/login", onLoaded: onLoaded)
    }
}

enum NavigationBarItem {
    enum TitleDisplayMode {
        case inline
        case large
        case automatic
    }
}

enum UIKeyboardType {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}

struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .cancellationAction }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .cancellationAction }
}

struct EditButton: View {
    var body: some View { EmptyView() }
}

extension View {
    func navigationBarHidden(_ hidden: Bool) -> some View { self }

    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }

    func keyboardType(_ type: UIKeyboardType) -> some View { self }

    func textInputAutocapitalization(_ cap: TextInputAutocapitalization) -> some View { self }

    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}

enum UIPasteboard {
    static let general = UIPasteboardProxy()
}

final class UIPasteboardProxy {
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            let board = NSPasteboard.general
            board.clearContents()
            if let newValue {
                board.setString(newValue, forType: .string)
            }
        }
    }
}

struct UIDevice {
    static let current = UIDevice()
    var model: String { "Mac" }
    var systemName: String { "macOS" }
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    var identifierForVendor: UUID? {
        if let raw = UserDefaults.standard.string(forKey: "beans.mac.vendorID"), let uuid = UUID(uuidString: raw) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: "beans.mac.vendorID")
        return uuid
    }
}

#endif
