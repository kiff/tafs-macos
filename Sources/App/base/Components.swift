import SwiftUI

/// The pieces every screen shares, to the iPad app's look.
enum Look {
    /// A screen's own inset from the sidebar and the window's edges.
    static let inset: CGFloat = 32
    /// The radius of a grouped panel.
    static let panelRadius: CGFloat = 18
}

/// A screen's large title, with its one line under it when it has one.
struct ScreenTitle: View {
    let title: String
    var lead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let lead { Text(lead).font(.system(size: 14)).foregroundColor(Theme.soft) }
        }
    }
}

/// A choice among a few, as a pill: dark and filled when chosen, white and outlined when not.
struct Chip: View {
    let title: String
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: chosen ? .semibold : .regular))
                .foregroundColor(chosen ? Theme.onFill : Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(chosen ? Theme.ink : Theme.panel))
                .overlay(Capsule().stroke(chosen ? Color.clear : Theme.line))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A small heading in capitals over a column or a group.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.soft

    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundColor(color)
    }
}
