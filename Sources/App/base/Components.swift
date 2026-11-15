import SwiftUI

/// The pieces every screen shares, to the iPad app's look.
enum Look {
    /// A screen's own inset from the sidebar and the window's edges.
    static let inset: CGFloat = 32
    /// The radius of a grouped panel.
    static let panelRadius: CGFloat = 18
}

/// A screen's large title, with its one line under it when it has one, as the iPad's: rounded
/// bold at 30 (the Overview), 34 for Record and Needs you; a plain bold large title for the
/// iPad's navigation titles (Account, Connect apps, Devices). The line is `dim`.
struct ScreenTitle: View {
    let title: String
    var lead: String?
    var size: CGFloat = 30
    var rounded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: size, weight: .bold, design: rounded ? .rounded : .default)).foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let lead { Text(lead).font(.system(size: 14)).foregroundColor(Theme.dim) }
        }
    }
}

/// A choice among a few, as the iPad's pill: 13 regular, dark and filled when chosen, white
/// and outlined with its words in `soft` when not.
struct Chip: View {
    let title: String
    let chosen: Bool
    /// A taf's colour, as a dot before its name.
    var dot: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true) }
                Text(title).font(.system(size: 13))
            }
                .foregroundColor(chosen ? Theme.onFill : Theme.soft)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(chosen ? Theme.ink : Theme.panel))
                .overlay(Capsule().stroke(chosen ? Color.clear : Theme.line))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A small heading in capitals over a column or a group, as the iPad's `Eyebrow`: 12
/// monospaced, tracking 0.7, in `dim`.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.dim

    var body: some View {
        Text(text.uppercased()).tracking(0.7).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
    }
}

/// A taf's avatar, as the iPad's `TafAvatar`: its colour, a continuous square with corners at
/// 0.3 of its size, and its initial in white, rounded bold at half its size.
struct TafAvatar: View {
    let name: String
    let color: Int
    var size: CGFloat = 40

    var body: some View {
        Text(verbatim: String(name.prefix(1)).uppercased())
            .font(Theme.display(size * 0.5))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.tafColor(color)))
            .accessibilityHidden(true)

/// The iPad's outlined button: 15 medium in ink, at least 48 high, on a continuous rounded
/// stroke at 40%, faded while disabled.
struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        Look(configuration: configuration, color: color)
    }

    private struct Look: View {
        let configuration: Configuration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundColor(color)
                .background(Theme.ink.opacity(configuration.isPressed ? 0.08 : 0))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
