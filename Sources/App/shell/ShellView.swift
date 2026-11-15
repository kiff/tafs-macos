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
    /// The person's tafs, listed under the screens; and tafs cloud's line for when there are none.
    var tafs: [Home.Taf] = []
    var noTafsLine: String?
    /// The calls held for the person, listed under NEEDS YOU above the tafs.
    var held: [HeldRow] = []
    /// Who is signed in, under Account: their email, as KIFF says it.
    var accountLine: String?
    /// The screens that are built, each drawn in its place. A screen that isn't shows its name.
    var screen: (Screen) -> AnyView? = { _ in nil }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(Theme.raised)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    /// The sidebar, to the iPad's: the mark, the screens, the person's tafs, then Start a new
    /// taf, Coach and Account at the foot.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The app's own mark at the top: it opens the Overview, as on the iPad.
            Button { selection = .overview } label: {
                HStack(spacing: 10) {
                    Mascot(size: 30)
                    Text(words("app.name")).font(Theme.display(22)).foregroundColor(Theme.ink)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words(Screen.overview.titleKey))
            .padding(.top, 34).padding(.bottom, 22)

            ForEach(Screen.list) { item($0) }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !held.isEmpty {
                        // Amber as text, as the palette has it for small words on the sidebar.
                        eyebrow(words("needs_you.title"), color: Theme.amberText)
                        ForEach(held) { heldRow($0) }
                        Spacer().frame(height: 10)
                    }
                    eyebrow(words("home.your_tafs"), color: Theme.soft)
                    if tafs.isEmpty, let line = noTafsLine {
                        Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(tafs) { taf in tafRow(taf) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
            }

            foot
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    /// The iPad's eyebrow: mono 12, tracking 0.7.
    private func eyebrow(_ text: String, color: Color) -> some View {
        Eyebrow(text: text, color: color).accessibilityAddTraits(.isHeader)
    }

    /// A held call, as the iPad lists it: an amber dot, the taf and what it asks, then why and
    /// the time to answer by. It opens Needs you.
    private func heldRow(_ row: HeldRow) -> some View {
        Button { selection = .needsYou } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8).padding(.top, 5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                    if let line = row.line(words, time: { Self.clock.string(from: $0) }) {
                        Text(verbatim: line).font(.system(size: 12)).foregroundColor(Theme.soft).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// The time to answer by, as this Mac shows a time.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func item(_ screen: Screen) -> some View {
        let selected = selection == screen
        return Button { selection = screen } label: {
            HStack(spacing: 12) {
                Image(systemName: screen.symbol)
                    .font(.system(size: 17)).foregroundColor(Theme.ink)
                    .frame(width: 24, alignment: .leading)
                Text(words(screen.titleKey)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer(minLength: 0)
                if screen == .needsYou, needsYou > 0 {
                    // The count as the iPad shows it: a plain number at the row's end.
                    Text(words.number(needsYou)).font(.system(size: 15)).foregroundColor(Theme.soft)
                        .accessibilityLabel(words.count("needs_you.count", needsYou))
                }
            }
            .frame(height: 46)
            // The chosen row's grey ground, as the iPad's sidebar list draws it.
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.chosen : Color.clear))
            .padding(.horizontal, -12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A taf in the sidebar, as the iPad's `tafRow`: its 34 avatar, its name (15 semibold), and
    /// tafs cloud's line for where its work stands (13). The line is soft, not the iPad's dim:
    /// dim is under 4.5:1 on the raised ground.
    private func tafRow(_ taf: Home.Taf) -> some View {
        HStack(spacing: 12) {
            TafAvatar(name: taf.name, color: taf.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: taf.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                if let now = taf.now { Text(verbatim: now).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(1) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 8) {
            footButton(words("home.start_new_taf"), symbol: "plus", fill: AnyShapeStyle(Theme.brand)) { selection = .coach }
            footButton(words(Screen.coach.titleKey), symbol: "sparkle", fill: AnyShapeStyle(Theme.ink), text: Theme.onFill, selected: selection == .coach) { selection = .coach }
            Button { selection = .account } label: {
                HStack(spacing: 10) {
                    // As the iPad's: soft, and filled amber while Account is chosen.
                    Image(systemName: selection == .account ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 20)).foregroundColor(selection == .account ? Theme.amberText : Theme.soft)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(words(Screen.account.titleKey)).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                        if let accountLine { Text(verbatim: accountLine).font(.system(size: 12)).foregroundColor(Theme.soft).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == .account ? .isSelected : [])
        }
        .padding(.horizontal, -12)
    }

    private func footButton(_ title: String, symbol: String, fill: AnyShapeStyle, text: Color = .white, selected: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(text)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(fill))
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
