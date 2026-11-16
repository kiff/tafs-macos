import SwiftUI

/// The sign-in window's illustrations, drawn from shapes and SF Symbols only, as the iPad's
/// `SignInArt`: no letter, number or word is ever in one (every word on the screen is a shared
/// line). Each is decoration, hidden from VoiceOver.
enum SignInArt {
    /// KIFF's side: a Card, its mark and a lock, with two orbiting dots.
    static func kiff(size: CGFloat = 150) -> some View { KIFFArt(size: size).accessibilityHidden(true) }
    /// The phone's side: a phone holding a code of squares, with the scan's corners.
    static func phone(size: CGFloat = 150) -> some View { PhoneArt(size: size).accessibilityHidden(true) }
    /// Connected: a Mac and a phone, joined, with a check.
    static func connected(size: CGFloat = 180) -> some View { ConnectedArt(size: size).accessibilityHidden(true) }
}

/// A soft disc behind each piece, in the brand's colours.
private struct ArtBackdrop: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Theme.brand).opacity(0.12)
            Circle().stroke(Theme.line, lineWidth: 1).padding(size * 0.08)
        }
        .frame(width: size, height: size)
    }
}

private struct KIFFArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ArtBackdrop(size: size)
            RoundedRectangle(cornerRadius: size * 0.08).fill(Theme.panel)
                .frame(width: size * 0.62, height: size * 0.42)
                .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(Theme.line))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            Capsule().fill(Theme.line).frame(width: size * 0.26, height: size * 0.035).offset(x: size * 0.07, y: -size * 0.06)
            Capsule().fill(Theme.line).frame(width: size * 0.18, height: size * 0.035).offset(x: size * 0.03, y: size * 0.01)
            RoundedRectangle(cornerRadius: size * 0.05).fill(Theme.brand)
                .frame(width: size * 0.15, height: size * 0.15).offset(x: -size * 0.17, y: -size * 0.03)
            Circle().fill(Theme.brand).frame(width: size * 0.22, height: size * 0.22)
                .overlay(Image(systemName: "lock.fill").font(.system(size: size * 0.1, weight: .bold)).foregroundColor(.white))
                .offset(x: size * 0.24, y: size * 0.17)
            Circle().fill(Theme.amber).frame(width: size * 0.06, height: size * 0.06).offset(x: -size * 0.33, y: -size * 0.3)
            Circle().fill(Theme.sky).frame(width: size * 0.045, height: size * 0.045).offset(x: size * 0.36, y: -size * 0.24)
        }
        .frame(width: size, height: size)
    }
}

private struct PhoneArt: View {
    let size: CGFloat
    /// Which squares of the little code are filled: a pattern, never a real code.
    private static let filled: [Bool] = [true, false, true, false, true, true, true, false, true]

    var body: some View {
        ZStack {
            ArtBackdrop(size: size)
            RoundedRectangle(cornerRadius: size * 0.09).fill(Theme.panel)
                .frame(width: size * 0.4, height: size * 0.68)
                .overlay(RoundedRectangle(cornerRadius: size * 0.09).stroke(Theme.ink.opacity(0.7), lineWidth: size * 0.022))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            Capsule().fill(Theme.ink.opacity(0.7)).frame(width: size * 0.1, height: size * 0.022).offset(y: -size * 0.29)
            squares.offset(y: -size * 0.02)
            ScanCorners(size: size * 0.32).offset(y: -size * 0.02)
            Circle().fill(Theme.brand).frame(width: size * 0.16, height: size * 0.16)
                .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.07, weight: .heavy)).foregroundColor(.white))
                .offset(x: size * 0.22, y: size * 0.24)
        }
        .frame(width: size, height: size)
    }

    private var squares: some View {
        VStack(spacing: size * 0.02) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: size * 0.02) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: size * 0.012)
                            .fill(Self.filled[row * 3 + column] ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.line))
                            .frame(width: size * 0.06, height: size * 0.06)
                    }
                }
            }
        }
    }
}

/// The four corners of a camera's frame around the code.
private struct ScanCorners: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { corner in
                Corner().stroke(Theme.amber, style: StrokeStyle(lineWidth: max(2, size * 0.05), lineCap: .round))
                    .frame(width: size * 0.25, height: size * 0.25)
                    .rotationEffect(.degrees(Double(corner) * 90))
                    .offset(x: (corner == 0 || corner == 3 ? -1 : 1) * size * 0.4, y: (corner < 2 ? -1 : 1) * size * 0.4)
            }
        }
        .frame(width: size, height: size)
    }

    /// A top-left corner: down the left side and along the top.
    private struct Corner: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}

private struct ConnectedArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ArtBackdrop(size: size)
            Image(systemName: "laptopcomputer").font(.system(size: size * 0.26, weight: .regular)).foregroundColor(Theme.ink.opacity(0.75))
                .offset(x: -size * 0.2, y: size * 0.02)
            Image(systemName: "iphone").font(.system(size: size * 0.2, weight: .regular)).foregroundColor(Theme.ink.opacity(0.75))
                .offset(x: size * 0.24, y: size * 0.02)
            Capsule().fill(Theme.brand).frame(width: size * 0.2, height: size * 0.025).offset(x: size * 0.03, y: size * 0.02)
            Circle().fill(Theme.brand).frame(width: size * 0.2, height: size * 0.2)
                .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.09, weight: .heavy)).foregroundColor(.white))
                .offset(x: size * 0.03, y: -size * 0.24)
            Circle().fill(Theme.amber).frame(width: size * 0.05, height: size * 0.05).offset(x: -size * 0.34, y: -size * 0.28)
            Circle().fill(Theme.sky).frame(width: size * 0.04, height: size * 0.04).offset(x: size * 0.36, y: -size * 0.3)
            Circle().fill(Theme.ok).frame(width: size * 0.035, height: size * 0.035).offset(x: size * 0.3, y: size * 0.34)
        }
        .frame(width: size, height: size)
    }
}
