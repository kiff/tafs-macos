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

    private let cloud: CloudClient
    private var cursor: String?
    private var asked = 0

    init(cloud: CloudClient) { self.cloud = cloud }

    /// Searches again from the first page. A slower answer to an older search is dropped.
    func load() async {
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.record(search)
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
            let page = try await cloud.record(search, cursor: cursor)
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
                        .onSubmit { Task { await model.load() } }
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                // "All tafs", then a chip for each taf with its colour, as on the iPad.
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
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    /// One call, as the iPad's `RecordRow`: its status dot; then its taf's dot and "Taf · what it
    /// did · amount", with its time at the right; then what it was about and how it went.
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
                Text(verbatim: [entry.about, entry.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundColor(Theme.soft)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    /// Green for done, amber for a call that waits, red for one refused; plain otherwise.
    private func color(_ kind: String) -> Color {
        switch kind {
        case "done": return Theme.ok
        case "held": return Theme.amber
        case "refused", "failed": return Theme.no
        default: return Theme.dim
        }
    }
}
