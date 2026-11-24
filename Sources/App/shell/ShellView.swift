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
    /// Whether a taf was shared with this person to use, not theirs to manage
    /// (`Access.sharedWithMe`): it's listed under Shared with you.
    var sharedWithMe: (Home.Taf) -> Bool = { _ in false }
    /// The tafs being set up, among the person's tafs as the iPad's sidebar lists them (HomeSplitView.swift:343-357):
    /// by name, with tafs cloud's Finish setting up line, and Discard for the person who started it (`discard`).
    var settingUp: [SettingUp] = []
    var discard: ((SettingUp) async -> String?)?
    /// The calls held for the person, listed under NEEDS YOU above the tafs.
    var held: [HeldRow] = []
    /// The open taf's page, drawn in place of the screen.
    var tafPage: AnyView?
    /// The taf whose page is open, by its agent; and what opens one.
    var openTaf: String?
    var open: (Home.Taf) -> Void = { _ in }
    /// Who is signed in, under Account: their email, as KIFF says it.
    var accountLine: String?
    /// What the last list read couldn't do (`Unreachable`), and whether the app still tries again: a quiet line at the
    /// foot, with KIFF's status page. Nil when all is well.
    var unreachable: String?
    var retrying = false
    /// The balance, for the plan's line at the foot: tafs cloud's `home_line`, only when the plan needs the person.
    var balance: Usage.Balance?
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
    /// Coach is open over the screen (`CoachPanelHost`): its button is the chosen one.
    var coachOpen = false
    /// The account's halt, for the sidebar's Halt all where the iPad shows it (`AccountHalt.shown`);
    /// nil, no row. `halted` reads the list again after a halt.
    var haltAll: HaltModel?
    var halted: () async -> Void = {}

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
            // Every taf at once, in a section of its own under Connect apps, as the iPad's sidebar.
            if let haltAll { HaltAllItem(model: haltAll, halted: halted).padding(.top, 8) }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !held.isEmpty {
                        // Amber as text, as the palette has it for small words on the sidebar.
                        eyebrow(words("needs_you.title"), color: Theme.amberText)
                        ForEach(held) { heldRow($0) }
                        Spacer().frame(height: 10)
                    }
                    // Theirs, then the ones shared with them, as the iPad's sidebar (HomeSplitView.swift:338-368):
                    // someone with only shared tafs sees just those.
                    // A taf being set up is among their own, by name, as the iPad's (HomeSplitView.swift:343-357).
                    if !ownTafs.isEmpty || !settingUp.isEmpty || sharedTafs.isEmpty {
                        eyebrow(words("home.your_tafs"), color: Theme.soft)
                        if tafs.isEmpty, let line = noTafsLine {
                            Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(ownTafs) { tafButton($0) }
                        ForEach(settingUp) { SettingUpRow(taf: $0, discard: discard, inSidebar: true) }
                    }
                    if !sharedTafs.isEmpty {
                        if !ownTafs.isEmpty || !settingUp.isEmpty { Spacer().frame(height: 10) }
                        eyebrow(words("home.shared_you"), color: Theme.soft)
                        ForEach(sharedTafs) { tafButton($0) }
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
    /// the time to answer by. It opens its taf's page, where its chat shows the call in place, as the iPad's
    /// `HomeSelection.held` opens `TafDetailView`; a call whose taf isn't listed opens Needs you.
    private func heldRow(_ row: HeldRow) -> some View {
        Button {
            if let taf = tafs.first(where: { $0.kiffAgent == row.agent }), taf.tafID != nil { open(taf) } else { selection = .needsYou }
        } label: {
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

    /// The person's own tafs, in the list's order.
    private var ownTafs: [Home.Taf] { tafs.filter { !sharedWithMe($0) } }
    /// The tafs shared with this person, in the list's order.
    private var sharedTafs: [Home.Taf] { tafs.filter(sharedWithMe) }

    /// A taf's row: the open taf sits on the chosen row's grey, as on the iPad.
    private func tafButton(_ taf: Home.Taf) -> some View {
        Button { open(taf) } label: {
            tafRow(taf).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(openTaf == taf.id ? Theme.chosen : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .accessibilityAddTraits(openTaf == taf.id ? .isSelected : [])
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
            // As the iPad's footer (HomeSplitView.swift:551-555): KIFF out of reach, then the plan, each only when it says something.
            if let unreachable { unreachableLine(unreachable) }
            if let line = balance?.homeLine { planLine(line, tone: balance?.planTone ?? "ok") }
            // Coach opens over the screen, as the iPad's `openCoach`; it closes from its own Back.
            footButton(words(Screen.coach.titleKey), symbol: "sparkle", fill: AnyShapeStyle(Theme.ink), text: Theme.onFill, selected: coachOpen) { openCoach() }
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

    /// KIFF can't be reached just now, as the iPad's `UnreachableLine`: an amber dot, the words ("· trying again" while
    /// the app still tries), and KIFF's status page.
    private func unreachableLine(_ said: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.amber).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(verbatim: Unreachable.line(said, retrying: retrying, words)).font(.system(size: 12)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Link(words("home.status"), destination: Unreachable.statusPage).font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.amberText)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("unreachable")
    }

    /// The plan, only when it needs the person, as the iPad's `PlanLine`: tafs cloud's line in its tone's colour, and
    /// Plan & usage beside it, which it opens.
    private func planLine(_ line: String, tone: String) -> some View {
        let color: Color = tone == "waiting" ? Theme.no : Theme.amberText
        return Button { selection = .usage } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(verbatim: line).font(.system(size: 13)).foregroundColor(color).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text(words(Screen.usage.titleKey)).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amberText)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(words("home.opens_plan", ["title": words(Screen.usage.titleKey)]))
        .accessibilityIdentifier("plan-line")
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
        if let page = tafPage { page } else if let built = screen(selection) { built.environment(\EnvironmentValues.openTaf, open) } else { placeholder }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Mascot(size: 72)
            Text(words(selection.titleKey)).font(Theme.display(28)).foregroundColor(Theme.ink)
        }
    }
}
