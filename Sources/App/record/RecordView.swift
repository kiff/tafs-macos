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

    /// A search across the Record, kept apart from the list as the iPad's `RecordSearch`: its
    /// words, its pages as tafs cloud sent them, and where it stands.
    struct Found: Equatable {
        let q: String
        var groups: [Record.Group] = []
        var loading = true
        var error: String?
        var nextCursor: String?
        var endWords: String?
        var noneWords: String?
    }

    /// The search shown in the list's place; nil shows the list.
    @Published private(set) var found: Found?
    /// The words of the search shown; empty for the list.
    var searched: String { found?.q ?? "" }
    /// One case, open from a search: what it's about, and its calls once read.
    @Published private(set) var caseAbout: String?
    @Published private(set) var openCase: Record.Case?
    @Published private(set) var caseError: String?

    private let cloud: CloudClient
    private var cursor: String?
    private var asked = 0
    /// The search waiting for the person to stop typing.
    private var typing: Task<Void, Never>?
    /// How long the Record waits after the last key before it searches what's typed, as the
    /// iPad's `recordTypingPause`.
    var typingPause: UInt64 = 400_000_000

    init(cloud: CloudClient) { self.cloud = cloud }

    /// Reads the Record's list again from the first page. A slower answer is dropped.
    func load() async {
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.record()
            guard mine == asked else { return }
            groups = page.shown
            show(page)
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
            if more {
                for group in page.shown {
                    if let at = now.groups.firstIndex(where: { $0.id == group.id }) {
                        now.groups[at] = Record.Group(id: group.id, title: group.title, entries: now.groups[at].entries + group.entries)
                    } else {
                        now.groups.append(group)
                    }
                }
            } else {
                now.groups = page.shown
            }
            now.loading = false
            now.nextCursor = page.nextCursor
            now.endWords = page.nextCursor == nil ? page.endWords : nil
            now.noneWords = now.groups.isEmpty ? page.noneWords : nil
            found = now
            if !page.hint.isEmpty { hint = page.hint }
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
        .sheet(isPresented: Binding(get: { model.caseAbout != nil }, set: { if !$0 { model.closeCase() } })) { caseSheet }
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
            Button(words("common.try_again")) { Task { await model.load() } }
        case .loaded:
            if model.shown.isEmpty {
                Text(model.noneWords ?? words("common.nothing_yet")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
            ForEach(model.shown) { group in
                // The day, as the iPad's: 11 medium monospaced, in capitals.
                if !group.title.isEmpty {
                    Text(verbatim: group.title.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Theme.dim).padding(.top, 6)
                }
                VStack(spacing: 8) {
                    ForEach(group.entries) { entry in
                        row(entry)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            if model.canContinue {
                ProgressView().controlSize(.small).task { await model.more() }
            } else if let end = model.endWords, !model.shown.isEmpty {
                Text(end).font(.system(size: 13)).foregroundColor(Theme.soft)
            }
        }
    }

    /// What a search found, as the iPad's `RecordResults`: tafs cloud's groups as sent, each call
    /// with what it's about as the link to its case; nothing found in tafs cloud's words; why it
    /// couldn't be read; its next page as the end shows.
    @ViewBuilder private func results(_ found: RecordModel.Found) -> some View {
        ForEach(found.groups) { group in
            if !group.title.isEmpty {
                Text(verbatim: group.title.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Theme.dim).padding(.top, 6)
            }
            VStack(spacing: 8) {
                ForEach(group.entries) { entry in
                    row(entry)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        if let none = found.noneWords, !found.loading { Text(verbatim: none).font(.system(size: 14)).foregroundColor(Theme.soft) }
        if let why = found.error { Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no) }
        if found.loading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if found.nextCursor != nil {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).task { await model.find(found.q, more: true) }
        } else if let end = found.endWords, !found.groups.isEmpty {
            Text(verbatim: end).font(.system(size: 13)).foregroundColor(Theme.soft)
        }
    }

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
    /// did · amount", with its time at the right; then what it was about and how it went.
    private func row(_ entry: Record.Entry, opensCase: Bool = true) -> some View {
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
                Text(verbatim: [entry.about, entry.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundColor(Theme.soft)
                // In a search, what it's about opens the case, as the iPad's `RecordHitRow`.
                if opensCase, model.found != nil, let about = entry.about, !about.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { Task { await model.open(case: about) } } label: {
                        Text(verbatim: "\(about) ›").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

    /// One case, open from a search: every call about the same thing, oldest first, the step
    /// that didn't go through named first in red, as the iPad's `RecordCaseSheet`. The Record
    /// never sends anything again itself.
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
            if model.openCase == nil, model.caseError == nil { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.openCase?.steps ?? []) { entry in
                        row(entry, opensCase: false)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Theme.background)
    }
}
