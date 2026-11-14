import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    enum Read<Value: Equatable>: Equatable {
        case loading
        case loaded(Value)
        case unread(why: String)
    }

    @Published private(set) var balance: Read<Usage.Balance> = .loading
    @Published private(set) var credits: Read<Usage.Credits> = .loading
    /// Whether the last period is shown, not this one.
    @Published private(set) var previous = false

    private let cloud: CloudClient
    private var asked = 0

    init(cloud: CloudClient) { self.cloud = cloud }

    /// Each half is read on its own: one that can't be read doesn't take the other away.
    func load() async {
        do { balance = .loaded(try await cloud.balance()) } catch { balance = .unread(why: NeedsYouModel.why(error)) }
        await loadCredits()
    }

    func show(previous: Bool) async {
        guard previous != self.previous else { return }
        self.previous = previous
        credits = .loading
        await loadCredits()
    }

    private func loadCredits() async {
        asked += 1
        let mine = asked
        do {
            let read = try await cloud.credits(previous: previous)
            if mine == asked { credits = .loaded(read) }
        } catch {
            if mine == asked { credits = .unread(why: NeedsYouModel.why(error)) }
        }
    }
}

/// Plan & usage: the balance and the period's credits, in tafs cloud's words. Nothing is
/// bought or changed from this screen.
struct UsageView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: UsageModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The screen's name sits small and centred at the top, as on the iPad.
                Text(words("usage.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                panel { balance }
                panel {
                    Eyebrow(text: words("usage.credits"))
                    periods
                    creditsTotal
                }
                creditsRows
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    @ViewBuilder private var balance: some View {
        switch model.balance {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.balance_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let balance):
            Text(balance.words).font(.system(size: 16, weight: .semibold)).foregroundColor(balance.waiting ? Theme.no : Theme.ink)
            if let meter = balance.meter {
                GeometryReader { space in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.raised)
                        Capsule().fill(balance.state == "ok" ? Theme.ok : Theme.amber)
                            .frame(width: space.size.width * CGFloat(meter) / 100)
                    }
                }
                .frame(height: 8)
                .accessibilityLabel(words("usage.label"))
                .accessibilityValue(words.number(meter) + " %")
            }
            if let detail = balance.detail { Text(detail).font(.system(size: 14)).foregroundColor(Theme.soft) }
            if let warning = balance.warning { Text(warning).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText) }
            if let plan = balance.planLine { Text(plan).font(.system(size: 13)).foregroundColor(Theme.soft) }
        }
    }

    /// Last period and This period, as the iPad's two-part switch.
    private var periods: some View {
        HStack(spacing: 0) {
            period(words("usage.last_period"), previous: true)
            period(words("usage.this_period"), previous: false)
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
    }

    private func period(_ title: String, previous: Bool) -> some View {
        let selected = model.previous == previous
        return Button { Task { await model.show(previous: previous) } } label: {
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.panel : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var creditsTotal: some View {
        switch model.credits {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.credits_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let credits):
            Text(credits.words).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
        }
    }

    /// Each taf's line as its own panel, then what wasn't counted, then tafs cloud's note.
    @ViewBuilder private var creditsRows: some View {
        if case .loaded(let credits) = model.credits {
            ForEach(credits.rows) { row in
                panel {
                    Text(row.words).font(.system(size: 14)).foregroundColor(Theme.ink)
                    if let pace = row.pace { Text(pace).font(.system(size: 12)).foregroundColor(Theme.soft) }
                }
            }
            if credits.coach != nil || credits.notCounted != nil {
                panel {
                    if let not = credits.notCounted { Text(not).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink) }
                    ForEach(credits.notCountedLines, id: \.self) { line in Text(line).font(.system(size: 14)).foregroundColor(Theme.soft) }
                    if let coach = credits.coach { Text(coach).font(.system(size: 14)).foregroundColor(Theme.soft) }
                }
            }
            if let note = credits.note { Text(note).font(.system(size: 13)).foregroundColor(Theme.soft).padding(.leading, 4) }
        }
    }

    private var reading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(words("usage.reading")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }
}
