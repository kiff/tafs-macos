import SwiftUI

/// People & groups, read from KIFF, as the iPad's `PeopleGroupsView` lists them. Read again
/// every 20 seconds while open, so someone who joins shows without leaving the screen.
@MainActor
final class PeopleModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([People.Group], [People.Person])
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// Why the last read failed, shown over what was read before, until a read works.
    @Published private(set) var notRead: String?
    private let account: AccountClient

    init(account: AccountClient) { self.account = account }

    /// Both lists, together: a page with groups and no people, or the other way round, isn't one.
    func load() async {
        do {
            // One after the other: the same lists as the iPad's two reads at once.
            let groups = try await account.groups()
            let people = try await account.people()
            let (shownGroups, shownPeople) = People.shown(groups: groups, people: people)
            state = .loaded(shownGroups, shownPeople)
            notRead = nil
        } catch {
            // What was shown stays when a later read fails, with why over it, as the iPad's
            // `peopleError`; a first read that fails says why alone.
            if case .loaded = state {
                notRead = NeedsYouModel.why(error)
            } else {
                state = .unread(why: NeedsYouModel.why(error))
            }
        }
    }

    /// "No groups" only for lists that read, with no read failed since, as the iPad's
    /// `loaded && groups.isEmpty && peopleError == nil` (PeopleViews.swift:42).
    var showsNoGroups: Bool {
        guard case .loaded(let groups, _) = state else { return false }
        return groups.isEmpty && notRead == nil
    }

    static let readEvery: TimeInterval = 20
}

/// The account's groups, each with its people (managers first) and the tafs it uses. Making a
/// group, renaming it and changing its people are each the person's act behind their key, so
/// they come with approvals on this Mac (#16): this screen shows them all, and changes none.
struct PeopleView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: PeopleModel
    /// The account's name and who is signed in, for the line above the groups.
    let me: Me?
    /// A taf's name by its KIFF agent, for "Uses …".
    let tafName: (String) -> String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("people.title")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("people.not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let groups, let people):
                    if let why = model.notRead {
                        Text(words("people.not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    }
                    Text(People.accountLine(account: me?.account, signedInAs: me?.signedInAs, email: me?.email, count: people.count, words: words))
                        .font(.system(size: 14)).foregroundColor(Theme.soft)
                    if model.showsNoGroups {
                        Text(words("people.no_groups")).font(.system(size: 14)).foregroundColor(Theme.dim)
                    }
                    ForEach(groups) { group($0, people: people) }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task {
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(nanoseconds: UInt64(PeopleModel.readEvery * 1_000_000_000))
            }
        }
    }

    /// A group's name and the tafs it uses, over its people.
    private func group(_ group: People.Group, people: [People.Person]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.shownName(words)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(People.uses(group, name: tafName, words: words)).font(.system(size: 12)).foregroundColor(Theme.dim)
            }
            .padding(.leading, 4).padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            let members = People.sorted(group, people: people)
            if !members.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        row(member, label: People.label(member.subject, people: people))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
        }
    }

    /// A person in a group: their badge, their email (else KIFF's id for them), and their role
    /// in it, a manager's in amber, as the iPad's `memberRow`.
    private func row(_ member: People.Member, label: String) -> some View {
        HStack(spacing: 12) {
            // The iPad's `PersonBadge`: their initial on a raised circle, 32 across.
            Text(verbatim: String(label.prefix(1)).uppercased()).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(width: 32, height: 32).background(Circle().fill(Theme.raised))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.system(size: 15)).foregroundColor(Theme.ink).lineLimit(1)
                Text(words(member.isManager ? "people.manager" : "people.member")).font(.system(size: 12))
                    .foregroundColor(member.isManager ? Theme.amberText : Theme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
