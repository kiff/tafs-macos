import SwiftUI

@MainActor
final class OverviewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Home.Page)
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// tafs cloud's line for an account with no taf yet, for the sidebar.
    @Published private(set) var noTafsLine: String?
    /// The ready-made jobs tafs cloud lists while the account has no live taf.
    @Published private(set) var recipes: Recipes?
    /// Every ready-made job: Start a new taf's gallery and the strip under the tafs list. Nil
    /// before it's read, or from a tafs cloud without it, where Start a new taf opens Coach.
    @Published private(set) var gallery: Gallery?
    /// Each taf's Last result, by its id at tafs cloud, once read.
    @Published private(set) var lastResults: [String: String] = [:]
    /// The doors tafs cloud offers here, as Home last said; a read that fails keeps them.
    @Published private(set) var doorsOffered: [String] = []
    /// The label the tafs list is filtered to; nil is All. The list opens on All every time.
    @Published private(set) var listLabel: String?
    /// The list's order, settled when its tafs change (`ListOrder`), as the iPad's `listOrder`.
    @Published private(set) var listOrder = ListOrder()
    /// Who each taf is shared with, by its KIFF agent, once read: the line under its name.
    @Published private(set) var shares: [String: [Shares.Share]] = [:]
    private let cloud: CloudClient
    /// Where the list last read is kept for the next launch's first frame; nil keeps none.
    private let remembered: UserDefaults?
    /// Set at sign-out before its first wait: a read still on its way then keeps nothing.
    private var ended = false

    /// With `remembered`, the list last read for this account shows at once, as the iPad's
    /// `showRememberedList`, and is read again with the first read.
    init(cloud: CloudClient, remembered: UserDefaults? = nil) {
        self.cloud = cloud
        self.remembered = remembered
        if let remembered, let page = RememberedHome.shown(tenant: cloud.session.tenant, in: remembered) {
            state = .loaded(page)
            listOrder.show(page.tafs)
        }
    }

    /// The tafs as listed, in the sidebar and on the Overview, as the iPad's `listedTafs`: waiting
    /// on the person first, then the one at work most recently.
    var listedTafs: [Home.Taf] { listOrder.listed(tafs) }

    var tafs: [Home.Taf] {
        if case .loaded(let page) = state { return page.tafs }
        return []
    }

    /// The list was read and has no taf. Not so while it loads, or when it couldn't be read:
    /// then nobody is told to pick a job for a first taf they may already have.
    var hasNoTafs: Bool {
        if case .loaded(let page) = state { return page.tafs.isEmpty }
        return false
    }

    /// The session is ending: nothing read from now on is kept for the next launch.
    func endSession() { ended = true }

    /// The account's labels as Home last sent them; none with no labelled taf.
    var labels: [HomeLabel] {
        if case .loaded(let page) = state { return page.labels }
        return []
    }

    /// The first chip's word: Home's, else the app's own "All".
    func labelsAll(_ words: Words) -> String {
        if case .loaded(let page) = state, let all = page.labelsAll { return all }
        return words("home.labels_all")
    }

    /// Filters the list to a label, or back to All with nil, as the iPad's `filterList`.
    func filterList(_ label: String?) { listLabel = label }

    /// The tafs the list shows under its chip, in Home's order (`HomeLabels.filtered`).
    func filtered(_ tafs: [Home.Taf]) -> [Home.Taf] { HomeLabels.filtered(tafs, by: listLabel, in: labels) }

    func load() async {
        // Whether this read worked: a list kept on screen after a failed read doesn't count.
        var readNow = false
        do {
            let read = try await cloud.homeRead()
            state = .loaded(read.page)
            listOrder.show(read.page.tafs)
            doorsOffered = read.page.doorsOffered ?? []
            readNow = true
            // Kept for the next launch's first frame, as the iPad's `rememberList` after `show`;
            // never once the session ends or this read was given up.
            if let remembered, !ended, !Task.isCancelled {
                RememberedHome.remember(read.body, tenant: cloud.session.tenant, in: remembered)
            }
            LaunchClock.mark("first list read")
        } catch {
            // A list on screen stays when a read fails, as the iPad's (AppModel.swift:1909-1916);
            // only an empty screen says why.
            if case .loaded = state {} else { state = .unread(why: NeedsYouModel.why(error)) }
        }
        // As the iPad's `refresh` and `loadRecipes` (AppModel.swift:1852-1857, 7210-7215): read
        // with each list read that has no taf, and a read that fails keeps what was read.
        if hasNoTafs, let read = try? await cloud.recipes() { recipes = read }
        noTafsLine = recipes?.home?.shown == true ? recipes?.homeWords : nil
        // The gallery, with each list read that worked, as the iPad's `refresh`: reached only
        // after `try await home` (AppModel.swift:1823-1824, 1867), so a failed read asks nothing
        // and keeps the gallery read before, even with a list kept on screen.
        guard readNow else { return }
        await loadGallery()
    }

    /// Reads the gallery of ready-made jobs, as the iPad's `loadGallery` (AppModel.swift:7217-7228):
    /// a read that fails keeps what was read; a tafs cloud without the route (404) leaves none.
    func loadGallery() async {
        do {
            gallery = try await cloud.recipesGallery()
        } catch KIFFError.refused(404, _) {
            gallery = nil
        } catch {}
    }

    /// The recipes a job's sheet draws from, as the iPad's `sheetRecipes(for:)`
    /// (HomeSplitView.swift:434-438): Home's list when the job is on it, else the gallery's, with
    /// `/v1/recipes`' sheet words where the gallery sends none.
    func sheetRecipes(for recipe: Recipes.Recipe) -> Recipes {
        if let recipes, recipes.recipes.contains(where: { $0.id == recipe.id }) { return recipes }
        return gallery?.asRecipes(labels: recipes?.labels) ?? recipes ?? Recipes(categories: [], recipes: [], labels: nil)
    }

    /// Reads the Last result of each taf not read yet, in the list's order: its runs, then its
    /// newest run's report, as the iPad's `loadReport` (AppModel.swift:3189-3203). Only while the
    /// Overview is shown, and once a taf. Until then the list's `last_run` says it; runs that
    /// can't be read say so.
    func loadLastResults(words: Words) async {
        let clock = AppDates.formatter(words, time: .short)
        for taf in listedTafs {
            guard let id = taf.tafID, lastResults[id] == nil else { continue }
            let lastRun = taf.lastRun
            let runs: [Runs.Run]
            do {
                runs = try await cloud.runs(of: id)
            } catch {
                lastResults[id] = Runs.notRead(NeedsYouModel.why(error), words: words)
                continue
            }
            let latest = Runs.latest(runs)
            var report: Runs.Report?
            if let session = latest?.session { report = try? await cloud.report(of: id, session: session) }
            lastResults[id] = Runs.line(latest: latest, newest: runs.first, report: report, lastRun: lastRun, words: words, time: { clock.string(from: $0) })
        }
    }

    /// A taf's Last result as the row shows it: read, else by the list's `last_run`, else
    /// "Nothing yet"; "–" only for an agent tafs doesn't run.
    func lastResult(_ taf: Home.Taf, words: Words, time: (Date) -> String) -> String {
        guard let id = taf.tafID else { return "–" }
        return lastResults[id] ?? Runs.line(lastRun: taf.lastRun, words: words, time: time)
    }

    /// Reads who uses each taf this person manages, in the list's order, as the iPad's Overview
    /// does on showing (ShareViews.swift:274-280). One that can't be read shows no line.
    func loadShares(agents: [String], read: (String) async throws -> [Shares.Share]) async {
        for agent in agents {
            if let grants = try? await read(agent) { shares[agent] = grants }
        }
    }
}

/// Overview: today, across the person's tafs, one line each, to the iPad's layout: a large
/// title, what needs the person, the columns' headings, and plain rows with no panel.
struct OverviewView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: OverviewModel
    /// The calls held for the person, one row each under NEEDS YOU.
    var held: [HeldRow] = []
    /// Opens Needs you, where each is answered.
    var openNeedsYou: () -> Void = {}
    /// Opens a taf's page from its line.
    var openTaf: ((Home.Taf) -> Void)?
    /// Needs you's count and line, as the iPad's `needsYouCount` and `needsYouWords`; nil, Home's.
    var needsCount: Int?
    var needsWords: String?
    /// Who uses each taf, under its name, for whoever manages it (`manages`): its grants read by
    /// its KIFF agent (`readShares`), named from the account's people and groups.
    var people: PeopleModel?
    var manages: (Home.Taf) -> Bool = { _ in false }
    var readShares: ((String) async throws -> [Shares.Share])?
    /// Whether this person may use Coach, as the iPad's `mayUseCoach`: without it, no Own words
    /// row and no button that hands a recipe to Coach.
    var mayUseCoach = false
    /// "Say it in your own words": Coach, as the iPad's `startNewTaf`.
    var ownWords: () -> Void = {}
    /// Hands a recipe to Coach, as the iPad's `handRecipeToCoach`.
    var hand: (Recipes.Recipe) -> Void = { _ in }
    /// Whether the new onboarding is on (`Onboarding.on`): then Home with no taf is the first Home.
    var onboarding = Onboarding.on
    /// How tafs works, opened from the first Home.
    @State private var showingHowItWorks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(title: words("home.overview.title"), lead: words("home.overview.subtitle"))
                    .padding(.top, 56)
                // Board 10, the Overview's header (docs/window.md › Illustrations), the iPad's at its
                // width: always on a Mac, but where no taf yet draws its own below.
                if board == .overview { Illustration.overview.frame(maxWidth: .infinity) }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_tafs")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let page):
                    // Everything Needs you counts, not only the held calls, as the iPad's Overview.
                    let count = needsCount ?? page.needsYouCount ?? 0
                    if count > 0 || !held.isEmpty { needsYou(count: count, words: needsWords ?? page.needsYouWords) }
                    // The labels' chips, filtering the table below, as the iPad's Overview
                    // (ShareViews.swift, #1173); none without a labelled taf.
                    if !page.labels.isEmpty {
                        LabelChips(labels: page.labels, selected: model.listLabel, all: model.labelsAll(words)) { model.filterList($0) }
                    }
                    // In the iPad's order (`listedTafs`). Halt all is the sidebar's, as on the iPad.
                    if page.tafs.isEmpty { noTaf } else { table(model.filtered(model.listedTafs)) }
                    if openTaf != nil, !page.tafs.isEmpty {
                        Text(words("home.overview.each_line_opens")).font(.system(size: 12)).foregroundColor(Theme.dim)
                    }
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.loadLastResults(words: words) }
        // Read again once KIFF says which tafs this person manages, as the iPad's Overview reads
        // the shares of each taf it manages when shown.
        .task(id: managed) { await loadShares() }
    }

    /// The KIFF agents of the tafs this person manages, in the list's order.
    private var managed: [String] { model.listedTafs.filter(manages).map(\.kiffAgent) }

    @MainActor private func loadShares() async {
        guard let read = readShares, !managed.isEmpty else { return }
        let agents = managed
        if let people { await people.load() }
        await model.loadShares(agents: agents, read: read)
    }

    /// The screen's one drawing (`ArtBoard.overview`): no taf yet once the list is read empty and
    /// no job is listed, else the Overview's own.
    private var board: ArtBoard {
        var tafs: Int?
        if case .loaded(let page) = model.state { tafs = page.tafs.count }
        return ArtBoard.overview(tafs: tafs, listsRecipes: model.recipes?.homeListsRecipes == true)
    }

    /// With no taf, as the iPad's Home (HomeView.swift:104-125): tafs cloud's recipes under its
    /// line where it lists them; else its empty line, or the app's own when it sent none, and
    /// "Say it in your own words" still leading to Coach.
    @ViewBuilder private var noTaf: some View {
        if let recipes = model.recipes, recipes.homeListsRecipes {
            HomeRecipesView(recipes: recipes, ownWords: mayUseCoach ? ownWords : nil, canHand: mayUseCoach, hand: hand, sampleLabel: model.gallery?.sampleLabel)
        } else {
            // Board 2, no tafs yet (docs/window.md › Illustrations), above the empty line.
            if board == .noTafs { Illustration.noTafs.frame(maxWidth: .infinity) }
            if Onboarding.showsFirstHome(on: onboarding, mayUseCoach: mayUseCoach) {
                firstHome
            } else {
                emptyLine
            }
        }
    }

    /// The first Home, as the iPad's (HomeView.swift:137-152, docs/pairing.md): tafs cloud's line, else the app's
    /// "No tafs yet" and what Coach does; Ask Coach; and How tafs works, the cards again.
    @ViewBuilder private var firstHome: some View {
        let lines = Onboarding.firstHomeLines(cloud: model.recipes?.homeWords, words: words)
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: lines.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let lead = lines.lead {
                Text(verbatim: lead).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        HStack(spacing: 12) {
            Button(words("coach.ask"), action: ownWords).buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 260)
            Button(words("onboarding.how_it_works")) { showingHowItWorks = true }.buttonStyle(OutlineButtonStyle()).frame(maxWidth: 260)
        }
        .sheet(isPresented: $showingHowItWorks) {
            HowTafsWorksView { showingHowItWorks = false }.inLanguage(words).frame(minWidth: 620, minHeight: 640)
        }
    }

    /// Home with no taf and no job listed, before the new onboarding: tafs cloud's empty line, or the app's own.
    @ViewBuilder private var emptyLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let line = model.recipes?.homeWords {
                // tafs cloud's empty line, whoever reads it: no words of the app's.
                Text(verbatim: line).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            } else {
                // Not read yet, or a tafs cloud from before the line: the app's own.
                Text(words("home.no_tafs")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                // Setting one up is Coach's: someone who may not use it reads where shared tafs show.
                Text(mayUseCoach ? words("home.empty.coach") : words("home.empty.shared")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        // No job listed: "Say it in your own words" still leads to Coach.
        if mayUseCoach, let own = model.recipes?.homeOwnWords {
            OwnWordsRow(title: own.title, line: own.line, action: ownWords)
        }
    }

    /// NEEDS YOU, as the iPad's: one row per held call, then a row for the rest tafs cloud
    /// counts (Coach's chats, steps), in its words. Each opens Needs you.
    private func needsYou(count: Int, words line: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: words("needs_you.title"), color: Theme.amberText)
            ForEach(held) { row in
                needsRow(row.taf.map { "\($0) · \(row.asks)" } ?? row.asks) {
                    if let by = row.answerBy {
                        Text(words("needs_you.answer_by", ["time": clock.string(from: by)])).font(.system(size: 12)).foregroundColor(Theme.soft)
                    }
                }
            }
            if count > held.count, let line {
                needsRow(line) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                }
            }
        }
    }

    private func needsRow<End: View>(_ title: String, @ViewBuilder end: () -> End) -> some View {
        Button(action: openNeedsYou) {
            HStack(spacing: 10) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(verbatim: title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                Spacer()
                end()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A time as the app shows it, in its language.
    private var clock: DateFormatter { AppDates.formatter(words, time: .short) }

    /// The iPad's four columns, headed in plain 11 bold.
    private func table(_ tafs: [Home.Taf]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ForEach(["home.overview.column_taf", "home.overview.column_now", "home.overview.column_card", "home.overview.column_last_result"], id: \.self) { key in
                    Text(words(key)).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(tafs) { taf in
                Rectangle().fill(Theme.line).frame(height: 1)
                if let openTaf {
                    Button { openTaf(taf) } label: { row(taf).contentShape(Rectangle()) }.buttonStyle(.plain)
                } else {
                    row(taf)
                }
            }
        }
    }

    /// One taf: its name, and who uses it; tafs cloud's line for now; its Card's line; and its
    /// last result, by the list's `last_run` until it is read. Every cell is centred on the row's
    /// height, which the avatar sets, so the lines sit level with the taf's name.
    private func row(_ taf: Home.Taf) -> some View {
        HStack(alignment: .center, spacing: 16) {
            nameCell(taf).frame(maxWidth: .infinity, alignment: .leading)
            Group {
                // "Now" by its state, as the iPad's; the sidebar shows what went wrong instead.
                Text(verbatim: taf.now(words, time: { clock.string(from: $0) })).foregroundColor(Theme.ink)
                Text(verbatim: taf.cards.first?.line(words) ?? "–").foregroundColor(Theme.ink)
                Text(verbatim: model.lastResult(taf, words: words, time: { clock.string(from: $0) })).foregroundColor(Theme.soft).lineLimit(2)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The taf's avatar, its name, who uses it ("Support · 3 people", as the iPad's `usedBy`, for
    /// whoever manages it), and its labels.
    private func nameCell(_ taf: Home.Taf) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tafColor(taf.color)).frame(width: 30, height: 30)
                .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: taf.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                if let people, manages(taf) { UsedByLine(people: people, shares: model.shares[taf.kiffAgent]) }
                TafLabelChips(labels: HomeLabels.of(taf, in: model.labels))
            }
        }
    }
}

/// "Support · 3 people" under a taf's name on the Overview, as the iPad's `usedBy`: none until its
/// shares are read.
private struct UsedByLine: View {
    @Environment(\.words) private var words
    @ObservedObject var people: PeopleModel
    let shares: [Shares.Share]?

    var body: some View {
        if let line = Shares.usedBy(shares, groups: groups, people: persons, words: words) {
            Text(verbatim: line).font(.system(size: 12)).foregroundColor(Theme.dim).lineLimit(1)
        }
    }

    private var groups: [People.Group] {
        if case .loaded(let groups, _) = people.state { return groups }
        return []
    }

    private var persons: [People.Person] {
        if case .loaded(_, let persons) = people.state { return persons }
        return []
    }
}

