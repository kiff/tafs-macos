import ImageIO
import SwiftUI

/// The page as a paired Chrome showed it just before a taf's step acted, as the iPad's `ChromeShotView`: "Before this step",
/// the picture, when it was taken (in the account's time zone) and that it's kept for 30 days; or that none is kept, or that
/// it couldn't be loaded. The bytes are checked first (`ChromeShots.read`) and never written to disk.
struct ChromeShotSheet: View {
    @Environment(\.words) private var words
    let step: String
    /// planque's read for one step, set by the window; nil reads nothing, and the sheet says it couldn't be loaded.
    let read: ((String) async -> ChromeShots.Read)?
    var timeZone: String?
    let close: () -> Void

    enum Phase: Equatable {
        case loading
        case shown(ChromeShots.Shot, CGImage)
        case none
        case failed

        static func == (a: Phase, b: Phase) -> Bool {
            switch (a, b) {
            case (.loading, .loading), (.none, .none), (.failed, .failed): return true
            case (.shown(let x, _), .shown(let y, _)): return x == y
            default: return false
            }
        }
    }

    @State private var phase: Phase = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(words("chrome.shot_title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch phase {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    case .shown(let shot, let picture):
                        Image(decorative: picture, scale: 1)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.dim.opacity(0.3)))
                            .accessibilityLabel(Text(words("chrome.shot_title")))
                            .accessibilityIdentifier("chrome.shot.image")
                        Text(verbatim: AccountTime(timeZone).zonedShown(shot.takenAt, date: .abbreviated, time: .standard, words: words))
                            .font(.system(size: 13)).foregroundColor(Theme.dim)
                        Text(words("chrome.shot_kept")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    case .none:
                        Text(words("chrome.shot_none")).font(.system(size: 15)).foregroundColor(Theme.dim)
                    case .failed:
                        Text(words("chrome.shot_failed")).font(.system(size: 15)).foregroundColor(Theme.no)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .background(Theme.background)
        .task { await load() }
    }

    private func load() async {
        guard let read else {
            phase = .failed
            return
        }
        switch await read(step) {
        case .shown(let shot):
            // A picture that won't decode is said as one that couldn't be loaded, never a blank.
            phase = Self.decoded(shot.image).map { .shown(shot, $0) } ?? .failed
        case .none:
            phase = .none
        case .failed:
            phase = .failed
        }
    }

    /// The WebP decoded on this Mac, at most `ChromeShots.decodedSide` on its longest side, whatever size the file declares:
    /// ImageIO's thumbnail of the whole picture, never the full canvas. Nil when it won't decode.
    static func decoded(_ bytes: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ChromeShots.decodedSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
