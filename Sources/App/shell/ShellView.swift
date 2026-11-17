import SwiftUI

/// The window's two panes, to the iPad app's layout: the sidebar on the raised ground, and
/// the screen it opens beside it on the background.
struct ShellView: View {
    static let sidebarWidth: CGFloat = 300
    static let minimumSize = WindowSize.minimum

    @Environment(\.words) private var words
    @Binding var selection: Screen
    /// How many requests wait for the person: the number beside Needs you.
    var needsYou = 0
    /// Needs you's name in the sidebar: tafs cloud's "Your brief" once there is one.
    var needsYouTitle: String?
    /// The person's tafs, listed under the screens; and tafs cloud's line for when there are none.
    var tafs: [Home.Taf] = []
    var noTafsLine: String?
    /// The calls held for the person, listed under NEEDS YOU above the tafs.
    var held: [HeldRow] = []
    /// The open taf's page, drawn in place of the screen.
    var tafPage: AnyView?
    /// The taf whose page is open, by its agent; and what opens one.
    var openTaf: String?
    var open: (Home.Taf) -> Void = { _ in }
    /// Who is signed in, under Account: their email, as KIFF says it.
    var accountLine: String?
    /// Every ready-made job, for "Explore jobs" and the strip under the tafs list; and what
    /// opens the gallery, and one job's sheet.
    var gallery: Gallery?
    var openGallery: (GalleryMode) -> Void = { _ in }
    var openRecipe: (Recipes.Recipe) -> Void = { _ in }
    /// Start a new taf, as the iPad's + New: the gallery where tafs cloud sends it, else Coach.
    var newTaf: (() -> Void)?
    /// The screens that are built, each drawn in its place. A screen that isn't shows its name.
    var screen: (Screen) -> AnyView? = { _ in nil }
    /// Start a new taf: a new conversation in Coach, Coach open or not.
    var startNewTaf: () -> Void = {}
    /// The sidebar's Coach: opens Coach, as the iPad's `openCoach`.
    var openCoach: () -> Void = {}

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
                    ForEach(tafs) { taf in
                        // The open taf sits on the chosen row's grey, as on the iPad.
                        Button { open(taf) } label: {
                            tafRow(taf).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 16).fill(openTaf == taf.id ? Theme.chosen : Color.clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, -10)
                        .accessibilityAddTraits(openTaf == taf.id ? .isSelected : [])
                    }
                    jobs
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
            }

            foot
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    /// The jobs, as the iPad's sidebar has them (HomeSplitView.swift:338-374): "Explore jobs" to
    /// browse with nothing created, with or without tafs, once tafs cloud sends the row's words;
    /// then, with tafs, a few jobs the account doesn't run yet, where tafs cloud shows them, in its
    /// order, each on its category's colour, and the row that opens them all.
    @ViewBuilder private var jobs: some View {
        if let words = gallery?.explore {
            Spacer().frame(height: 10)
            Button { openGallery(.browse) } label: {
                Label(words, systemImage: "square.grid.2x2").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if !tafs.isEmpty, let gallery, !gallery.stripRecipes.isEmpty {
            Spacer().frame(height: 10)
            eyebrow(gallery.strip.title, color: Theme.soft)
            ForEach(gallery.stripRecipes) { recipe in
                Button { openRecipe(recipe) } label: {
                    HStack(spacing: 10) {
                        (gallery.category(of: recipe)?.color.map { Color($0) } ?? Theme.line)
                            .frame(width: 4, height: 28).clipShape(Capsule()).accessibilityHidden(true)
                        Text(verbatim: recipe.lead).font(.system(size: 14)).foregroundColor(Theme.ink).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // The strip shows a few: this row opens them all, in tafs cloud's words for them.
            if let words = gallery.seeAll {
                Button { openGallery(.browse) } label: {
                    Text(verbatim: words).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
                    if let line = row.line(words, time: { clock.string(from: $0) }) {
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

    /// The time to answer by, as the app shows a time, in its language.
    private var clock: DateFormatter { AppDates.formatter(words, time: .short) }

    private func item(_ screen: Screen) -> some View {
        // A taf's page open in place of the screen: no screen row is the chosen one.
        let selected = selection == screen && openTaf == nil
        return Button { selection = screen } label: {
            HStack(spacing: 12) {
                Image(systemName: screen.symbol)
                    .font(.system(size: 17)).foregroundColor(Theme.ink)
                    .frame(width: 24, alignment: .leading)
                Text(verbatim: screen == .needsYou ? needsYouTitle ?? words(screen.titleKey) : words(screen.titleKey)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
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
                // As the iPad's `tafRow`: what went wrong last, red when failing and amber
                // otherwise; a setup stopped partway in amber; else "now".
                if let trouble = taf.healthNow {
                    Text(verbatim: trouble).font(.system(size: 13)).foregroundColor(taf.health?.level == "failing" ? Theme.no : Theme.amberText).lineLimit(1)
                } else if let finish = taf.finishWords {
                    Text(verbatim: finish).font(.system(size: 13)).foregroundColor(Theme.amberText).lineLimit(1)
                } else {
                    Text(verbatim: taf.now(words, time: { clock.string(from: $0) })).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A new taf, as the iPad's + New (`HomeSplitView.startNewTaf`, HomeSplitView.swift:434-438):
            // the gallery where tafs cloud sends it, else a new conversation in Coach.
            footButton(words("home.start_new_taf"), symbol: "plus", fill: AnyShapeStyle(Theme.brand)) { if let newTaf { newTaf() } else { startNewTaf() } }
            // Coach opens, as the iPad's `openCoach`; it closes from its own Back.
            footButton(words(Screen.coach.titleKey), symbol: "sparkle", fill: AnyShapeStyle(Theme.ink), text: Theme.onFill, selected: selection == .coach && openTaf == nil) { openCoach() }
            Button { selection = .account } label: {
                HStack(spacing: 10) {
                    // As the iPad's: soft, and filled amber while Account is chosen.
                    // While a taf's page is open, Account isn't the one chosen.
                    let chosen = selection == .account && openTaf == nil
                    Image(systemName: chosen ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 20)).foregroundColor(chosen ? Theme.amberText : Theme.soft)
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
            .accessibilityAddTraits(selection == .account && openTaf == nil ? .isSelected : [])
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
        if let page = tafPage { page } else if let built = screen(selection) { built } else { placeholder }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Mascot(size: 72)
            Text(words(selection.titleKey)).font(Theme.display(28)).foregroundColor(Theme.ink)
        }
    }
}
