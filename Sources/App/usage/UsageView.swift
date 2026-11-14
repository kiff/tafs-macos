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
            VStack(alignment: .leading, spacing: 16) {
                Text(words("usage.title")).font(Theme.display(28)).foregroundColor(Theme.ink)
                panel(words("usage.balance")) { balance }
                panel(words("usage.credits")) { credits }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.dim)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    @ViewBuilder private var balance: some View {
        switch model.balance {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.balance_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let balance):
            Text(balance.words).font(.system(size: 20, weight: .bold)).foregroundColor(balance.waiting ? Theme.no : Theme.ink)
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
            if let plan = balance.planLine { Text(plan).font(.system(size: 13)).foregroundColor(Theme.dim) }
        }
    }

    @ViewBuilder private var credits: some View {
        HStack(spacing: 8) {
            period(words("usage.this_period"), previous: false)
            period(words("usage.last_period"), previous: true)
        }
        switch model.credits {
        case .loading:
            reading
        case .unread(let why):
            Text(words("usage.credits_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
        case .loaded(let credits):
            Text(credits.words).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
            ForEach(credits.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.words).font(.system(size: 14)).foregroundColor(Theme.ink)
                    if let pace = row.pace { Text(pace).font(.system(size: 12)).foregroundColor(Theme.dim) }
                }
            }
            if let coach = credits.coach { Text(coach).font(.system(size: 14)).foregroundColor(Theme.coach) }
            if let not = credits.notCounted { Text(not).font(.system(size: 13)).foregroundColor(Theme.dim) }
            if let note = credits.note { Text(note).font(.system(size: 13)).foregroundColor(Theme.dim) }
        }
    }

    private var reading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(words("usage.reading")).font(.system(size: 14)).foregroundColor(Theme.dim)
        }
    }

    private func period(_ title: String, previous: Bool) -> some View {
        let selected = model.previous == previous
        return Button(title) { Task { await model.show(previous: previous) } }
            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
            .foregroundColor(selected ? Theme.onFill : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(selected ? Theme.ink : Theme.raised))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
