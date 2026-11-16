import Foundation

/// One colour for the light appearance and one for dark, each `0xRRGGBB` with its opacity.
struct Shade: Equatable {
    let light: UInt32
    let dark: UInt32
    var lightOpacity: Double = 1
    var darkOpacity: Double = 1

    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.light = light; self.dark = dark
        self.lightOpacity = lightOpacity; self.darkOpacity = darkOpacity
    }

    /// The same colour in both appearances.
    init(_ hex: UInt32) { self.init(light: hex, dark: hex) }
}

/// The tafs palette, the values of the iPad app's theme: a warm cream ground, deep ink, and
/// the mascot's orange, pink and blue as the brand. Amber is "needs you", green is done,
/// red is refused. Kept apart from the views so its contrast is tested on any machine.
enum Palette {
    static let background = Shade(light: 0xFBF7EE, dark: 0x141311)
    static let panel = Shade(light: 0xFFFFFF, dark: 0x1F1E1B)
    /// The sidebar's ground.
    static let raised = Shade(light: 0xF3ECDF, dark: 0x2A2824)
    static let ink = Shade(light: 0x1B1726, dark: 0xF2EFE9)
    static let soft = Shade(light: 0x4F4A5E, dark: 0xA8A49C)
    /// Secondary text: 4.5:1 on the background and on panels, in both appearances.
    static let dim = Shade(light: 0x736D7F, dark: 0x96918A)
    static let line = Shade(light: 0x1B1726, dark: 0xF2EFE9, lightOpacity: 0.10, darkOpacity: 0.12)
    /// The ground of the sidebar's chosen row: the iPad's grey, as ink over the sidebar.
    static let chosen = Shade(light: 0x1B1726, dark: 0xF2EFE9, lightOpacity: 0.08, darkOpacity: 0.10)
    static let amber = Shade(0xFF8A1F)
    /// Amber as text: 4.5:1 on the background, which the amber itself is not.
    static let amberText = Shade(light: 0xB35500, dark: 0xF0A45A)
    /// Text on an ink, Coach, green or red fill.
    static let onFill = Shade(light: 0xFFFFFF, dark: 0x141311)
    static let ok = Shade(light: 0x198056, dark: 0x4CC38A)
    static let no = Shade(light: 0xDB1F25, dark: 0xFF8A73)
    static let coach = Shade(light: 0x2A64F5, dark: 0x7FA2FF)
    static let coachWash = Shade(light: 0xEEF3FF, dark: 0x1A2033)
    static let coachPanel = Shade(light: 0xE3EBFF, dark: 0x232B42)
    /// The drawings' pink and blue (`Illustration`), the iPad theme's `pink` and `blue`.
    static let pink = Shade(0xFF4F7B)
    static let blue = Shade(light: 0x2A64F5, dark: 0x7FA2FF)
    /// The brand's sweep, each stop dark enough for white text.
    static let brand: [UInt32] = [0xB35C00, 0xE8003A, 0x2A64F5]
    /// A taf's colour, by its index: bright, and dark enough for white text.
    static let tafColors: [UInt32] = [0xC25100, 0xE51255, 0x7B4DFF, 0x2A64F5, 0x0B7DA4, 0x128462]

    static func tafColor(_ index: Int) -> UInt32 {
        tafColors[((index % tafColors.count) + tafColors.count) % tafColors.count]
    }

    /// The contrast ratio of two opaque colours (WCAG 2), from 1 to 21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ v: UInt32) -> Double {
                let c = Double(v & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
