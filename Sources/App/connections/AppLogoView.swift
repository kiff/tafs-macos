import AppKit
import SwiftUI

/// The apps' logos for the views: `AppLogos` read from tafs cloud's own address, each decoded once
/// into an image and kept by its path. A logo that doesn't decode keeps nothing.
final class AppLogoImages: @unchecked Sendable {
    let logos: AppLogos
    private let lock = NSLock()
    private var images: [String: NSImage] = [:]

    init(_ logos: AppLogos) { self.logos = logos }

    /// The app's own: tafs cloud's address, over the network.
    static let app = AppLogoImages(AppLogos(transport: NetworkTransport(base: URL(string: CloudClient.base)!)))

    /// A logo already read, decoded, for the first frame.
    func cached(_ logo: String?) -> NSImage? {
        guard let path = AppLogos.path(logo) else { return nil }
        lock.lock()
        let image = images[path]
        lock.unlock()
        if let image { return image }
        return logos.cached(path).flatMap { keep($0, path) }
    }

    /// The logo, read once and decoded: nil when it isn't tafs cloud's, is refused, or doesn't decode.
    func load(_ logo: String?) async -> NSImage? {
        guard let path = AppLogos.path(logo) else { return nil }
        if let image = cached(path) { return image }
        guard let data = await logos.load(path) else { return nil }
        return keep(data, path)
    }

    private func keep(_ data: Data, _ path: String) -> NSImage? {
        guard let image = NSImage(data: data), image.isValid else { return nil }
        lock.lock()
        images[path] = image
        lock.unlock()
        return image
    }
}

private struct AppLogoImagesKey: EnvironmentKey {
    static let defaultValue = AppLogoImages.app
}

extension EnvironmentValues {
    /// Where the apps' logos are read: tafs cloud, else what a test gives.
    var appLogos: AppLogoImages {
        get { self[AppLogoImagesKey.self] }
        set { self[AppLogoImagesKey.self] = newValue }
    }
}

/// An app's logo from tafs cloud, `side` points square, as the iPad's `AsyncImage` beside an
/// app's name. While it loads, or when there's none: nothing, and with `holdsPlace` its square
/// stays empty (a Connect apps row, as the iPad's frame there); without, the name stands alone
/// (`AppMark`).
struct AppLogo: View {
    @Environment(\.appLogos) private var logos
    let logo: String?
    let side: CGFloat
    var holdsPlace = false
    @State private var loaded: NSImage?

    var body: some View {
        let shown = loaded ?? logos.cached(logo)
        Group {
            if let shown {
                Image(nsImage: shown).resizable().interpolation(.high).scaledToFit().frame(width: side, height: side)
            } else {
                // Nothing drawn; still a view, so the logo is asked for when it appears.
                Color.clear.frame(width: holdsPlace ? side : 0, height: holdsPlace ? side : 0)
            }
        }
        .accessibilityHidden(true)
        .task(id: logo) {
            let wanted = logo
            let source = logos
            let image = await source.load(wanted)
            loaded = image
        }
    }
}
