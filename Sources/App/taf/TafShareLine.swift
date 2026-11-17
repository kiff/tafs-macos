import SwiftUI

/// Who uses the taf, as the iPad's `ShareLine` (ShareViews.swift:6-45): Share, then one line
/// under the taf's head, for whoever manages it. Sharing it is signed with Face ID on the iPad
/// (`ShareTafSheet`), which this Mac can't do: Share is drawn as the iPad's, and a click says
/// where it's done (`approval.device_can_not_approve_approve`), sending nothing.
struct ShareLine: View {
    @Environment(\.words) private var words
    /// The taf's KIFF agent: what its grants are read by.
    let agent: String
    let account: AccountClient
    /// The account's groups and people, read from KIFF, to name each grant.
    @ObservedObject var people: PeopleModel
    /// The signed-in person's email: they're never named in the line.
    let email: String?
    @State private var shares: [Shares.Share]?
    /// Share was clicked: the line for an approval made on another device shows.
    @State private var said = false

    /// `shares` is what was read already, if anything (a screenshot's); the line reads them again.
    init(agent: String, account: AccountClient, people: PeopleModel, email: String?, shares: [Shares.Share]? = nil) {
        self.agent = agent
        self.account = account
        self.people = people
        self.email = email
        _shares = State(initialValue: shares)
    }

    private var groups: [People.Group] {
        if case .loaded(let groups, _) = people.state { return groups }
        return []
    }

    private var persons: [People.Person] {
        if case .loaded(_, let persons) = people.state { return persons }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                share
                Text(verbatim: Shares.sharedWith(shares, groups: groups, people: persons, email: email, words: words))
                    .font(.system(size: 14)).foregroundColor(Theme.soft).lineLimit(1)
            }
            if said {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        // Read again whenever the groups change; a read that fails leaves "Sharing…".
        .task(id: groups) { shares = try? await account.shares(agent: agent) }
        .task { if groups.isEmpty && persons.isEmpty { await people.load() } }
    }

    /// The iPad's Share: the share mark and its word in a capsule, large enough to find.
    private var share: some View {
        Button { said = true } label: {
            Label(words("people.share.action"), systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.panel)
                .overlay(Capsule().stroke(Theme.line))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("share-taf")
    }
}
