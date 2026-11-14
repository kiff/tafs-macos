import SwiftUI

/// The window's two panes, to the iPad app's layout: the sidebar on the raised ground, and
/// the screen it opens beside it on the background.
struct ShellView: View {
    static let sidebarWidth: CGFloat = 300
    static let minimumSize = CGSize(width: 900, height: 600)

    @Environment(\.words) private var words
    @Binding var selection: Screen
    /// How many requests wait for the person: the number beside Needs you.
    var needsYou = 0
    /// The screens that are built, each drawn in its place. A screen that isn't shows its name.
    var screen: (Screen) -> AnyView? = { _ in nil }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(Theme.raised)
            Rectangle().fill(Theme.line).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The app's own mark at the top: it opens the Overview, as on the iPad.
            Button { selection = .overview } label: {
                HStack(spacing: 10) {
                    Mascot(size: 34)
                    Text(words("app.name")).font(Theme.display(22)).foregroundColor(Theme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words(Screen.overview.titleKey))
            .padding(.bottom, 8)

            ForEach(Screen.list) { item($0) }
            Spacer(minLength: 12)
            ForEach(Screen.foot) { item($0) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
    }

    private func item(_ screen: Screen) -> some View {
        let selected = selection == screen
        return Button { selection = screen } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(screen == .coach ? Theme.coach : Theme.soft)
                    .frame(width: 24)
                Text(words(screen.titleKey)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer(minLength: 0)
                if screen == .needsYou, needsYou > 0 {
                    Text(words.number(needsYou))
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.amberFill))
                        .accessibilityLabel(words.count("needs_you.count", needsYou))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.panel : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each screen arrives in its own pull request. Until then its place shows its name.
    @ViewBuilder private var detail: some View {
        if let built = screen(selection) { built } else { placeholder }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Mascot(size: 72)
            Text(words(selection.titleKey)).font(Theme.display(28)).foregroundColor(Theme.ink)
        }
    }
}
