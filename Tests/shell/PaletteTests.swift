import Foundation

let shellPaletteTests: [Test] = [
    Test("contrast is 1 for a colour on itself and 21 for black on white") {
        try expectEqual(Palette.contrast(0x123456, 0x123456), 1)
        try expect(abs(Palette.contrast(0x000000, 0xFFFFFF) - 21) < 0.001, "21")
    },
    Test("ink and soft text are 4.5:1 on every ground, and dim on the background and the panel") {
        // Dim is 4.2:1 on the sidebar's ground in light: the sidebar's second lines use soft.
        let pairs: [(String, Shade, [Shade])] = [
            ("ink", Palette.ink, [Palette.background, Palette.panel, Palette.raised]),
            ("soft", Palette.soft, [Palette.background, Palette.panel, Palette.raised]),
            ("dim", Palette.dim, [Palette.background, Palette.panel]),
        ]
        for (name, text, grounds) in pairs {
            for ground in grounds {
                let light = Palette.contrast(text.light, ground.light)
                let dark = Palette.contrast(text.dark, ground.dark)
                try expect(light >= 4.5, "\(name) on \(String(ground.light, radix: 16)): \(light)")
                try expect(dark >= 4.5, "\(name) on \(String(ground.dark, radix: 16)): \(dark)")
            }
        }
    },
    Test("amber as text is 4.5:1 on the background") {
        try expect(Palette.contrast(Palette.amberText.light, Palette.background.light) >= 4.5, "light")
        try expect(Palette.contrast(Palette.amberText.dark, Palette.background.dark) >= 4.5, "dark")
    },
    Test("white text is 4.5:1 on every taf colour and every stop of the brand") {
        for hex in Palette.tafColors + Palette.brand {
            try expect(Palette.contrast(0xFFFFFF, hex) >= 4.5, String(hex, radix: 16))
        }
    },
    Test("a taf's colour wraps around, for a negative index too") {
        try expectEqual(Palette.tafColor(Palette.tafColors.count), Palette.tafColors[0])
        try expectEqual(Palette.tafColor(-1), Palette.tafColors[Palette.tafColors.count - 1])
    },
]
