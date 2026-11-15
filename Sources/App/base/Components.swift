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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13))
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
