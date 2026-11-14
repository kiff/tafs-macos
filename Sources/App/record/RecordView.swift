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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("record.title")).font(Theme.display(28)).foregroundColor(Theme.ink)
                TextField(model.hint, text: $model.search)
                    .textFieldStyle(.roundedBorder).font(.system(size: 14)).frame(maxWidth: 420)
                    .onSubmit { Task { await model.load() } }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.dim)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded:
                    if let none = model.noneWords { Text(none).font(.system(size: 14)).foregroundColor(Theme.dim) }
                    ForEach(model.groups) { group in
                        if !group.title.isEmpty {
                            Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim).padding(.top, 6)
                        }
                        VStack(spacing: 0) {
                            ForEach(group.entries) { entry in
                                row(entry)
                                if entry.id != group.entries.last?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                    }
                    if model.canContinue {
                        ProgressView().controlSize(.small).task { await model.more() }
                    } else if let end = model.endWords {
                        Text(end).font(.system(size: 13)).foregroundColor(Theme.dim)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func row(_ entry: Record.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color(entry.kind)).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(entry.detail).font(.system(size: 13)).foregroundColor(Theme.soft)
                Text(verbatim: [entry.taf.name, entry.about].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundColor(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let amount = entry.amountText { Text(amount).font(Theme.mono(14, weight: .semibold)).foregroundColor(Theme.ink) }
                Text(entry.time).font(.system(size: 12)).foregroundColor(Theme.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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
