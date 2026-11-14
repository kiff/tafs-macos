import AppKit
import SwiftUI

/// The palette as SwiftUI colours that follow the Mac's appearance.
enum Theme {
    static let background = Color(Palette.background)
    static let panel = Color(Palette.panel)
    static let raised = Color(Palette.raised)
    static let ink = Color(Palette.ink)
    static let soft = Color(Palette.soft)
    static let dim = Color(Palette.dim)
    static let line = Color(Palette.line)
    static let amber = Color(Palette.amber)
    static let amberText = Color(Palette.amberText)
    /// A count's fill, dark enough for white numbers.
    static let amberFill = Color(Shade(Palette.brand[0]))
    static let onFill = Color(Palette.onFill)
    static let ok = Color(Palette.ok)
    static let no = Color(Palette.no)
    static let coach = Color(Palette.coach)
    static let coachWash = Color(Palette.coachWash)
    static let coachPanel = Color(Palette.coachPanel)

    static let brand = LinearGradient(colors: Palette.brand.map { Color(Shade($0)) },
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

    static func tafColor(_ index: Int) -> Color { Color(Shade(Palette.tafColor(index))) }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension NSColor {
    /// A colour that is `shade.light` in the light appearance and `shade.dark` in dark.
    convenience init(_ shade: Shade) {
        func color(_ hex: UInt32, _ alpha: Double) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
        }
        self.init(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? color(shade.dark, shade.darkOpacity) : color(shade.light, shade.lightOpacity)
        }
    }
}

extension Color {
    init(_ shade: Shade) { self.init(nsColor: NSColor(shade)) }
}
