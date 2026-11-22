import SwiftUI

/// The Record's pages for its screen: one search, continued page by page.
@MainActor
final class RecordModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var groups: [Record.Group] = []
    /// tafs cloud's words: the search box's, "nothing matched", and the end's.
    @Published private(set) var hint = ""
    @Published private(set) var noneWords: String?
    @Published private(set) var endWords: String?
    @Published private(set) var canContinue = false
    @Published var search = ""
    /// Which calls are shown, of those read.
    @Published var filter: Record.Filter = .all
    /// One taf's calls only, by its id at tafs cloud; nil for every taf's.
    @Published var taf: String?

    var shown: [Record.Group] { Record.only(taf: taf, in: filter.keeping(groups)) }
    /// The days whose reads are shown, not folded, as the iPad's `openReads`.
    @Published var openReads: Set<Date> = []
    /// What this person may do with each taf, by KIFF agent, as KIFF answers it: Export receipts
    /// is for whoever sees every taf's Record. Nil until read.
    @Published private(set) var access: [String: Access]?
    /// Export receipts, its range and where it stands.
    let exports: ReceiptsExportModel
    /// The calls KIFF holds for an answer, by proposal id (`HeldCall.heldProposals`): a held line
    /// KIFF no longer holds says "no longer waiting". Nil until read, or when it couldn't be: every
    /// held line still waits, as the iPad's before its list is read.
    @Published private(set) var heldProposals: Set<String>?

    /// A search across the Record, kept apart from the list as the iPad's `RecordSearch`: its
    /// words, its pages as tafs cloud sent them, and where it stands.
    struct Found: Equatable {
        let q: String
        var pages: [Record.Page] = []
        var loading = false
        var error: String?
        var nextCursor: String? { pages.last?.nextCursor }
    }

    /// The search shown in the list's place; nil shows the list.
    @Published private(set) var found: Found?
    /// The words of the search shown; empty for the list.
    var searched: String { found?.q ?? "" }
    /// One case, open from a search: what it's about, and its calls once read.
    @Published private(set) var caseAbout: String?
    @Published private(set) var openCase: Record.Case?
    @Published private(set) var caseError: String?

    /// One line's KIFF receipt, open in its sheet: the line, the receipt as KIFF wrote it, and this
    /// Mac's check of it, as the iPad's `ReceiptView`.
    @Published private(set) var receiptEntry: Record.Entry?
    @Published private(set) var receiptRaw: Data?
    @Published private(set) var receiptCheck: ReceiptCheck?
    @Published private(set) var receiptError: String?
    /// The signer a receipt must be KIFF's by: KIFF's own, set otherwise only by a test.
    var receiptSigner = ReceiptCheck.kiffSigner

    private let cloud: CloudClient
    /// KIFF itself, for a line's receipt (`GET /v1/receipts/{trace_id}`); nil reads none.
    private let account: AccountClient?
    private var cursor: String?
    private var asked = 0
    /// The search waiting for the person to stop typing.
    private var typing: Task<Void, Never>?
    /// How long the Record waits after the last key before it searches what's typed, as the
    /// iPad's `recordTypingPause`.
    var typingPause: UInt64 = 400_000_000

    init(cloud: CloudClient, account: AccountClient? = nil) {
        self.cloud = cloud
        self.account = account
        exports = ReceiptsExportModel(cloud: cloud)
    }

    /// Reads what this person may do with each taf from KIFF, as the iPad's `access`. Unread, Export
    /// receipts isn't shown.
    func loadAccess() async {
        guard let account, let read = try? await account.myAccess() else { return }
        access = read
    }

    /// Reads the calls KIFF holds (`GET /v1/me/card-exceptions?status=held`, the iPad's `heldCalls`),
    /// for the held lines' "no longer waiting". Unread, every held line still waits.
    func loadHeld() async {
        guard let account else { return }
        do {
            heldProposals = HeldCall.heldProposals(try await account.heldCalls())
        } catch {
            heldProposals = nil
        }
    }

    /// Whether a held line still waits for the person (`Record.isWaiting`).
    func isWaiting(_ entry: Record.Entry) -> Bool { Record.isWaiting(entry, held: heldProposals) }

    /// Names what the lines read acted on, as the iPad's `nameRecordLines` (AppModel.swift:6726-6740):
    /// each taf with a line KIFF hashed and not yet named has its calls read from tafs cloud
    /// (`GET /v1/tafs/{id}/calls`), and a line is named only by the value whose hash is KIFF's. Best
    /// effort: a taf whose calls can't be read keeps its lines unnamed. A newer read of the list drops it.
    private func name(_ mine: Int) async {
        let ids = Record.tafsToName(groups)
        guard !ids.isEmpty else { return }
        var refs: [String: String] = [:]
        for id in ids {
            guard let calls = try? await cloud.calls(id) else { continue }
            for call in calls { refs[call.invocation] = call.value }
        }
        guard mine == asked, !refs.isEmpty else { return }
        groups = Record.naming(groups, refs: refs, sha256: PasskeyCrypto.sha256)
    }

    /// Shows a day's reads, or folds them again.
    func toggleReads(_ day: Date) {
        if openReads.contains(day) { openReads.remove(day) } else { openReads.insert(day) }
    }

    /// Reads the Record's list again from the first page. A slower answer is dropped.
    func load() async {
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.record()
            guard mine == asked else { return }
            groups = page.shown
            show(page)
            await name(mine)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// The next page of the same search, added under what is shown.
    func more() async {
        guard let cursor else { return }
        let mine = asked
        do {
            let page = try await cloud.record(cursor: cursor)
            guard mine == asked else { return }
            for group in page.shown {
                if let at = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[at] = Record.Group(id: group.id, title: group.title, entries: groups[at].entries + group.entries)
                } else {
                    groups.append(group)
                }
            }
            show(page)
            await name(mine)
        } catch KIFFError.refused(status: 409, code: _) {
            // A call was made since: the cursor is over, so the search starts again.
            await load()
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// The box as the person types, as the iPad's `recordQueryTyped`: what's typed is searched
    /// once they pause, so a word typed letter by letter is one search, not one a letter. Words
    /// already searched, or being searched, aren't searched again. An emptied box shows the
    /// list again at once, with nothing read.
    func typed() {
        typing?.cancel()
        typing = nil
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { found = nil; return }
        let pause = typingPause
        typing = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: pause) } catch { return }
            guard let self, !Task.isCancelled, self.found?.q != q else { return }
            self.typing = nil
            await self.find(q)
        }
    }

    /// Return: what's typed, at once, with no wait left to search it again.
    func submitted() async {
        typing?.cancel()
        typing = nil
        await find(search)
    }

    /// Searches the Record across the person's tafs, as the iPad's `searchRecord`: the words
    /// are the search's as soon as it starts. `more` reads its next page; a cursor tafs cloud
    /// refuses (409, a call made since) searches again from the top.
    func find(_ words: String, more: Bool = false) async {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { found = nil; return }
        let current = found?.q == q ? found : nil
        if more, current == nil || current?.loading == true || current?.nextCursor == nil { return }
        var started = more ? (current ?? Found(q: q)) : Found(q: q)
        started.loading = true
        started.error = nil
        found = started
        do {
            let page = try await cloud.record(q, cursor: more ? current?.nextCursor : nil, saying: true)
            guard var now = found, now.q == q else { return }
            // Each page as tafs cloud sent it, after the ones before: a day split across two
            // pages is two groups, as on the iPad.
            now.pages = (more ? now.pages : []) + [page]
            now.loading = false
            found = now
            if !page.hint.trimmingCharacters(in: .whitespaces).isEmpty { hint = page.hint }
        } catch let refusal as CloudRefusal where more && refusal.status == 409 {
            await find(q)
        } catch {
            guard var now = found, now.q == q else { return }
            now.loading = false
            now.error = NeedsYouModel.why(error)
            found = now
        }
    }

    /// Opens one case from a search: every call about the same thing, oldest first, and the
    /// step that didn't go through, as the iPad's `openRecordCase`.
    func open(case about: String) async {
        guard !about.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        caseAbout = about
        openCase = nil
        caseError = nil
        do {
            let read = try await cloud.recordCase(about)
            if caseAbout == about { openCase = read }
        } catch {
            if caseAbout == about { caseError = NeedsYouModel.why(error) }
        }
    }

    /// Opens a line's receipt sheet and reads KIFF's receipt, as the iPad's `ReceiptView`. A line
    /// with no receipt opens nothing.
    func openReceipt(_ entry: Record.Entry) async {
        guard entry.receipt != nil else { return }
        receiptEntry = entry
        await loadReceipt()
    }

    /// Reads the open line's receipt from KIFF, as it wrote it, and checks it on this Mac. A sheet
    /// closed or moved to another line meanwhile takes nothing.
    func loadReceipt() async {
        guard let entry = receiptEntry, let trace = entry.receipt?.traceID, let account else { return }
        receiptRaw = nil
        receiptCheck = nil
        receiptError = nil
        do {
            let raw = try await account.send("GET", "/v1/receipts/\(CloudClient.escaped(trace))")
            let signer = receiptSigner
            // The signer's recovery is plain arithmetic: off the main thread.
            let check = await Task.detached { ReceiptCheck.check(raw, signer: signer, sha256: PasskeyCrypto.sha256, recover: ReceiptRecovery.recover) }.value
            guard receiptEntry?.id == entry.id else { return }
            receiptRaw = raw
            receiptCheck = check
        } catch {
            if receiptEntry?.id == entry.id { receiptError = UsageModel.plainWhy(error) }
        }
    }

    func closeReceipt() {
        receiptEntry = nil
        receiptRaw = nil
        receiptCheck = nil
        receiptError = nil
    }

    func closeCase() {
        caseAbout = nil
        openCase = nil
        caseError = nil
    }

    private func show(_ page: Record.Page) {
        if !page.hint.isEmpty { hint = page.hint }
        noneWords = page.isEmpty && groups.isEmpty ? page.noneWords : nil
        endWords = page.nextCursor == nil ? page.endWords : nil
        cursor = page.nextCursor
        canContinue = cursor != nil
        state = .loaded
    }
}

struct RecordView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: RecordModel
    /// The person's tafs: a chip each, and each call's taf colour.
    var tafs: [Home.Taf] = []
    /// The account's time zone, as KIFF says it: the days are the account's, as the iPad's.
    var timeZone: String? = nil
    /// The moment "Today" and "Yesterday" are told from: this Mac's clock, or a fixed one for the
    /// Store's screenshots.
    var now: Date? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle(title: words("record.title"), lead: words("record.lead"), size: 34).padding(.top, 56)
                // The search box, across the screen, with tafs cloud's own hint in it.
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundColor(Theme.soft)
                    TextField(model.hint, text: $model.search).textFieldStyle(.plain).font(.system(size: 15))
                        .onSubmit { Task { await model.submitted() } }
                        .onChange(of: model.search) { _ in model.typed() }
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                // Export receipts, for whoever sees every taf's Record, as the iPad's.
                if Record.seesEveryTaf(tafs, access: model.access) {
                    ExportReceiptsRow(model: model.exports, timeZone: timeZone)
                }
                // While a search is shown it stands in for the list, as on the iPad: its calls as
                // tafs cloud found them, never narrowed by the list's chips.
                if let found = model.found {
                    results(found)
                } else {
                    list
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
        .task { await model.loadAccess() }
        .task { await model.loadHeld() }
        .sheet(isPresented: Binding(get: { model.caseAbout != nil }, set: { if !$0 { model.closeCase() } })) { caseSheet }
        // A line's receipt from the list or a search; a case's step opens its own over the case's sheet.
        .background(EmptyView().sheet(isPresented: receiptShown(inCase: false)) { receiptSheet })
    }

    /// Whether the receipt sheet is up, from the case's sheet or from the screen: one place at a time.
    private func receiptShown(inCase: Bool) -> Binding<Bool> {
        Binding(get: { model.receiptEntry != nil && (model.caseAbout != nil) == inCase }, set: { if !$0 { model.closeReceipt() } })
    }

    @ViewBuilder private var receiptSheet: some View {
        if let entry = model.receiptEntry { ReceiptSheet(model: model, entry: entry, tafs: tafs, timeZone: timeZone) }
    }

    /// Every call by day, as before a search: the chips, then the calls they keep.
    @ViewBuilder private var list: some View {
        chips
        switch model.state {
        case .loading:
            ProgressView().controlSize(.small)
        case .unread(let why):
            Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
            Button(words("common.try_again")) { Task { await model.load(); await model.loadHeld() } }
        case .loaded:
            if model.shown.isEmpty {
                Text(model.noneWords ?? words("common.nothing_yet")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
            // By day in the account's calendar, newest first, each titled as the iPad's
            // `dayTitle`: "TODAY · NOV 15", in 11 medium monospaced capitals. Under All, a day's
            // reads fold into one line, as the iPad's.
            let time = AccountTime(timeZone)
            ForEach(Record.days(model.shown, calendar: time.calendar, foldingReads: model.filter == .all)) { day in
                dayView(day, time: time)
            }
            if model.canContinue {
                ProgressView().controlSize(.small).task { await model.more() }
            } else if let end = model.endWords, !model.shown.isEmpty {
                Text(end).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
        }
    }

    /// A day's heading: its title, then what it spent, all in capitals (`Record.dayHeading`).
    private func dayHeading(_ day: Record.Day, time: AccountTime) -> String {
        Record.dayHeading(title: time.dayTitle(day.start, words: words, now: now ?? Date()),
                          spent: Record.spentWords(day.entries + day.reads, words: words), language: words.language)
    }

    /// One day: its title, its calls, then its reads folded into one line, "· 3 reads of data,
    /// within its Card · Show", which shows them (Hide folds them again), as the iPad's list.
    @ViewBuilder private func dayView(_ day: Record.Day, time: AccountTime) -> some View {
        // The day's title, then what it spent ("€640 spent"), as the iPad's (RecordView.swift:48).
        Text(verbatim: dayHeading(day, time: time)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Theme.dim).padding(.top, 6)
        let open = model.openReads.contains(day.start)
        VStack(spacing: 8) {
            ForEach(day.entries + (open ? day.reads : [])) { entry in
                panel(entry)
            }
        }
        if !day.reads.isEmpty {
            Button { model.toggleReads(day.start) } label: {
                Text(verbatim: "· " + words.count("record.reads", day.reads.count) + " · " + (open ? words("record.hide") : words("record.show")))
                    .font(.system(size: 13)).foregroundColor(Theme.ok).padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    /// A call in its panel.
    private func panel(_ entry: Record.Entry) -> some View {
        row(entry)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// What a search found, as the iPad's `RecordResults`: each page's groups as tafs cloud sent
    /// them, each call with what it's about as the link to its case; nothing found in tafs
    /// cloud's words; why it couldn't be read; its next page on More.
    @ViewBuilder private func results(_ found: RecordModel.Found) -> some View {
        ForEach(Array(found.pages.enumerated()), id: \.offset) { _, page in
            pageGroups(page)
        }
        if !found.pages.isEmpty, found.pages.allSatisfy(\.isEmpty), let none = found.pages.last?.noneWords {
            Text(verbatim: none).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
        if let why = found.error { Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no) }
        if found.loading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if found.nextCursor != nil {
            Button(words("common.more")) { Task { await model.find(found.q, more: true) } }
                .buttonStyle(OutlineButtonStyle())
        } else if let end = found.pages.last?.endWords {
            Text(verbatim: end).font(.system(size: 13)).foregroundColor(Theme.dim)
        }
    }

    /// A page's groups, each call as the iPad's `RecordHitRow`: a listed taf's as its Activity draws
    /// it, with what it's about opening its case.
    @ViewBuilder private func pageGroups(_ page: Record.Page) -> some View {
        ForEach(page.shown) { group in
            if !group.title.isEmpty {
                Text(verbatim: group.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim).padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.entries) { entry in RecordStepRow(model: model, entry: entry, listed: listed(entry)) }
            }
        }
    }

    /// The call's taf is one of the person's listed tafs, as the iPad's `tafID(cloudID:)`.
    private func listed(_ entry: Record.Entry) -> Bool { tafs.contains { $0.tafID == entry.taf.id } }

    /// "All tafs", then a chip for each taf with its colour, then the filters, as on the iPad.
    @ViewBuilder private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: words("record.all_tafs"), chosen: model.taf == nil) { model.taf = nil }
                ForEach(tafs.filter { $0.tafID != nil }) { taf in
                    Chip(title: taf.name, chosen: model.taf == taf.tafID, dot: Theme.tafColor(taf.color)) { model.taf = taf.tafID }
                }
            }
        }
        HStack(spacing: 8) {
            ForEach(Record.Filter.allCases) { filter in
                Chip(title: words(filter.titleKey), chosen: model.filter == filter) { model.filter = filter }
            }
        }
    }

    /// One call, as the iPad's `RecordRow`: its status dot; then its taf's dot and "Taf · what it
    /// did · amount", with its time at the right; then who decided and what became of it at the
    /// tool, "within its Card · done", as the iPad's `detail`.
    private func row(_ entry: Record.Entry) -> some View {
        let taf = tafs.first { $0.tafID == entry.taf.id }
        let head = [entry.taf.name, entry.title, entry.amountText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(color(entry.kind)).frame(width: 9, height: 9).padding(.top, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(taf.map { Theme.tafColor($0.color) } ?? Theme.soft).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(verbatim: head).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    Spacer()
                    Text(verbatim: entry.time).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim)
                }
                // What it acted on, then who decided and what became of it, or "no longer waiting".
                Text(verbatim: entry.line(words, waiting: model.isWaiting(entry))).font(.system(size: 13)).foregroundColor(Theme.soft)
                // KIFF's receipt, opened in its sheet and checked there, as the iPad's row opens it.
                if entry.receipt != nil {
                    Button { Task { await model.openReceipt(entry) } } label: {
                        Label(words("receipt.kiff_receipt"), systemImage: "doc.text").font(.system(size: 12)).foregroundColor(Theme.ok)
                    }
                    .buttonStyle(.plain)
                    .help(words("record.shows_receipt"))
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }

    /// The iPad's kind colours (`RecordEntry.Kind.color`), as a taf's Activity has them.
    private func color(_ kind: String) -> Color {
        switch TafActivity.Entry.tone(of: kind) {
        case .ok: return Theme.ok
        case .amber: return Theme.amber
        case .no: return Theme.no
        }
    }

    /// One case, open from a search: every call about the same thing, oldest first, each as its
    /// taf's Activity draws it with its own next step (`RecordStepRow`), the step that didn't go
    /// through named first in red, as the iPad's `RecordCaseSheet`. A step's receipt opens over it.
    /// The Record never sends anything again itself.
    private var caseSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: model.caseAbout ?? "").font(Theme.display(24)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done")) { model.closeCase() }.keyboardShortcut(.cancelAction)
            }
            if let failed = model.openCase?.failed?.words, !failed.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: failed).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.no)
            }
            if let why = model.caseError { Text(verbatim: why).font(.system(size: 14)).foregroundColor(Theme.no) }
            // Read, or read with no steps: the spinner stays until there's a step or an error, as the iPad's.
            if (model.openCase?.steps ?? []).isEmpty, model.caseError == nil { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.openCase?.steps ?? []) { entry in
                        RecordStepRow(model: model, entry: entry, listed: listed(entry), opensCase: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .background(EmptyView().sheet(isPresented: receiptShown(inCase: true)) { receiptSheet })
    }
}
