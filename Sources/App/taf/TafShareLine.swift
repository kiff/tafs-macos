import SwiftUI

/// Who uses the taf, as the iPad's `ShareLine`: one line under the taf's head, for whoever
/// manages it. Sharing it is signed with Face ID on the iPad (`ShareTafSheet`), which this Mac
/// can't do, so there's no Share here: the line only reads.
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
        HStack(spacing: 10) {
            Text(verbatim: Shares.sharedWith(shares, groups: groups, people: persons, email: email, words: words))
                .font(.system(size: 14)).foregroundColor(Theme.soft).lineLimit(1)
        }
        .padding(.top, 2)
        // Read again whenever the groups change; a read that fails leaves "Sharing…".
        .task(id: groups) { shares = try? await account.shares(agent: agent) }
        .task { if groups.isEmpty && persons.isEmpty { await people.load() } }
    }
}
