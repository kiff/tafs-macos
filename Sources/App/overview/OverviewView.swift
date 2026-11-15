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
    private let cloud: CloudClient

    init(cloud: CloudClient) { self.cloud = cloud }

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

    func load() async {
        do { state = .loaded(try await cloud.home()) } catch { state = .unread(why: NeedsYouModel.why(error)) }
        // The line is only an invitation: if it can't be read, the sidebar just doesn't show one.
        noTafsLine = (try? await cloud.homeWords())?.line
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(title: words("home.overview.title"), lead: words("home.overview.subtitle"))
                    .padding(.top, 56)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_tafs")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let page):
                    let count = page.needsYouCount ?? 0
                    if count > 0 || !held.isEmpty { needsYou(count: count, words: page.needsYouWords) }
                    table(page.tafs)
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
    }

    /// NEEDS YOU, as the iPad's: one row per held call, then a row for the rest tafs cloud
    /// counts (Coach's chats, steps), in its words. Each opens Needs you.
    private func needsYou(count: Int, words line: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(words("needs_you.title").uppercased()).font(Theme.mono(12)).tracking(0.7).foregroundColor(Theme.amberText)
            ForEach(held) { row in
                needsRow(row.taf.map { "\($0) · \(row.asks)" } ?? row.asks) {
                    if let by = row.answerBy {
                        Text(words("needs_you.answer_by", ["time": Self.clock.string(from: by)])).font(.system(size: 12)).foregroundColor(Theme.soft)
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

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// The iPad's four columns, headed in plain 11 bold.
    private func table(_ tafs: [Home.Taf]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ForEach(["home.overview.column_taf", "home.overview.column_now", "home.overview.column_card", "home.overview.column_last_result"], id: \.self) { key in
                    Text(words(key)).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if tafs.isEmpty {
                Text(words("home.no_tafs")).font(.system(size: 14)).foregroundColor(Theme.dim)
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

    /// One taf: its name; tafs cloud's line for now; its Card's line; and its last result,
    /// "–" until it is read.
    private func row(_ taf: Home.Taf) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tafColor(taf.color)).frame(width: 30, height: 30)
                    .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white))
                    .accessibilityHidden(true)
                Text(verbatim: taf.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(verbatim: taf.now ?? "–").foregroundColor(Theme.ink)
                Text(verbatim: taf.cards.first?.line(words) ?? "–").foregroundColor(Theme.ink)
                Text(verbatim: "–").foregroundColor(Theme.soft).lineLimit(2)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
