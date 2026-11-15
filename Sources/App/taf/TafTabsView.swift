import SwiftUI

/// A taf's Activity and Setup, read from tafs cloud when their tab opens. Both only read.
@MainActor
final class TafPagesModel: ObservableObject {
    enum State<Page: Equatable>: Equatable {
        case loading
        case loaded(Page)
        case unread(why: String)
    }

    @Published private(set) var activity: State<TafActivity> = .loading
    @Published private(set) var setup: State<TafSetup> = .loading
    /// The Activity filter shown, as tafs cloud names it.
    @Published private(set) var filter = "all"

    private let cloud: CloudClient
    let taf: String
    private var asked = 0

    init(cloud: CloudClient, taf: String) {
        self.cloud = cloud
        self.taf = taf
    }

    /// Reads the Activity, for a filter tafs cloud offered. A slower answer to an older filter is dropped.
    func loadActivity(filter: String? = nil) async {
        if let filter { self.filter = filter }
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.activity(of: taf, filter: self.filter)
            guard mine == asked else { return }
            activity = .loaded(page)
        } catch {
            guard mine == asked else { return }
            activity = .unread(why: NeedsYouModel.why(error))
        }
    }

    func loadSetup() async {
        do { setup = .loaded(try await cloud.setup(of: taf)) } catch { setup = .unread(why: NeedsYouModel.why(error)) }
    }
}

/// A taf's Activity, as the iPad's: its Card's line, tafs cloud's filters as pills, then its
/// calls by day, each drawn as sent.
struct TafActivityTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let taf: Home.Taf
    /// Opens the Card tab, from the Card's line.
    let openCard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let card = taf.cards.first { cardLine(card) }
                switch model.activity {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.loadActivity() } }
                case .loaded(let page):
                    ForEach(page.exceptions) { CardUnitPanel(exception: $0) }
                    if !page.filters.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(page.filters) { choice in
                                Chip(title: choice.title, chosen: model.filter == choice.id) { Task { await model.loadActivity(filter: choice.id) } }
                            }
                        }
                    }
                    ForEach(page.groups) { group in
                        if !group.title.isEmpty {
                            Text(verbatim: group.title.uppercased()).font(Theme.mono(11)).tracking(1.5).foregroundColor(Theme.soft).padding(.top, 6)
                        }
                        ForEach(group.entries) { row($0) }
                    }
                    if let end = page.endWords {
                        Text(verbatim: end).font(.system(size: 13)).foregroundColor(Theme.dim).frame(maxWidth: .infinity).padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, Look.inset)
        }
        .task { await model.loadActivity() }
    }

    /// The taf's first Card in one line: what is left, and the Card's title. It opens the Card.
    private func cardLine(_ card: TafCard) -> some View {
        Button(action: openCard) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.tafColor(taf.color)).frame(width: 48, height: 32)
                    .overlay(Image(systemName: "creditcard").font(.system(size: 14, weight: .semibold)).foregroundColor(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let left = card.line(words) { Text(verbatim: left).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink) }
                    Text(verbatim: card.title).font(.system(size: 13)).foregroundColor(Theme.soft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One call: its kind's dot, tafs cloud's title and detail, and its time.
    private func row(_ entry: TafActivity.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(color(entry.kind)).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let detail = entry.detail { Text(verbatim: detail).font(.system(size: 14)).foregroundColor(Theme.soft) }
            }
            Spacer()
            if let time = entry.time { Text(verbatim: time).font(Theme.mono(12)).foregroundColor(Theme.soft) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    /// Done is green, held amber, refused red; a kind this app doesn't know has no colour of its own.
    private func color(_ kind: String) -> Color {
        switch kind {
        case "done": return Theme.ok
        case "held": return Theme.amber
        case "refused": return Theme.no
        default: return Theme.soft
        }
    }
}

/// A taf's Setup, as tafs cloud sends it: what waits on its Card first, then each part with
/// its line. It only reads here: changing a part is done with Coach, with its approval.
struct TafSetupTab: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.setup {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_from_kiff")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.loadSetup() } }
                case .loaded(let setup):
                    ForEach(setup.exceptions) { CardUnitPanel(exception: $0) }
                    if let workflow = setup.workflow { part(workflow) }
                    if let error = setup.connectionsError {
                        Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.soft).padding(.horizontal, 4)
                    }
                    if let versions = setup.versions { part(versions) }
                    if let memory = setup.memory { part(memory) }
                }
            }
            .padding(.bottom, Look.inset)
        }
        .task { await model.loadSetup() }
    }

    private func part(_ part: TafSetup.Part) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: part.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let summary = part.summary { Text(verbatim: summary).font(.system(size: 14)).foregroundColor(Theme.soft) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}

/// A call refused for want of a limit in its unit: tafs cloud's title, words and history,
/// edged in amber. What to do about it is Coach's, with its approval: no button here.
struct CardUnitPanel: View {
    let exception: CardUnitException

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: exception.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if let words = exception.words { Text(verbatim: words).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if let history = exception.history { Text(verbatim: history).font(.system(size: 12)).foregroundColor(Theme.soft) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.7)))
    }
}
