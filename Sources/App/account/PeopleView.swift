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
    /// Why the last change didn't go through, or that it's made on the phone, as the iPad's `peopleError`.
    @Published private(set) var problem: String?
    /// A change is on its way.
    @Published private(set) var changing = false
    /// Where a change is made: here with Touch ID, on a Mac whose device key is in the Secure Enclave and that has this
    /// sign-in's ending key; else on the phone, as Disconnect (the owner's rule for ending access: Touch ID, else the phone).
    @Published private(set) var route: ConnectionEnding.Route = .phone
    private let account: AccountClient
    private let touchID: TouchIDOnly

    init(account: AccountClient, touchID: TouchIDOnly? = nil) {
        self.account = account
        self.touchID = touchID ?? .system(session: account.session)
        refreshRoute()
    }

    /// Works out `route` again: on load, and at each change.
    func refreshRoute() {
        let now = ConnectionEnding.route(enclaveKey: account.keyStore == "enclave", biometrics: touchID.available())
        if now != route { route = now }
    }

    /// A change to the groups, as the iPad's `changePeople`: Touch ID with `what` (the change in the person's words) by
    /// the ending key, over the iPad's `tafs.people.v1` confirmation, then KIFF's request signed by the device key, then
    /// the lists read again. A closed or failed Touch ID sends nothing and says nothing; a Mac that can't confirm says to
    /// approve on the phone. True when it went through.
    @discardableResult
    func change(_ change: PeopleChange, what: String) async -> Bool {
        guard !changing else { return false }
        problem = nil
        refreshRoute()
        guard route == .touchID else {
            problem = Words.app(ConnectionEnding.phoneLine)
            return false
        }
        changing = true
        do {
            try await touchID.confirm(what, PeopleChange.confirmation(tenant: account.session.tenant, what: what))
        } catch is ConnectionEnding.KeyGone {
            changing = false
            refreshRoute()
            problem = Words.app(ConnectionEnding.phoneLine)
            return false
        } catch {
            changing = false
            return false
        }
        do {
            try await account.change(change)
        } catch {
            await load()
            changing = false
            problem = Words.app("common.didnt_go_through", ["what": what, "why": NeedsYouModel.why(error)])
            return false
        }
        await load()
        changing = false
        return true
    }

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

/// The account's groups, each with its people (managers first) and the tafs it uses. New group, Rename, Delete, Add
/// someone, Make the manager or a member and Remove, as the iPad's `PeopleGroupsView`: each confirmed with Touch ID on a
/// Mac that can (`PeopleModel.change`), else said to be made on the phone. KIFF decides who may make each.
struct PeopleView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: PeopleModel
    /// The account's name and who is signed in, for the line above the groups.
    let me: Me?
    /// A taf's name by its KIFF agent, for "Uses …".
    let tafName: (String) -> String?
    /// The group being named: a new one (`nil` id), or one renamed.
    @State private var naming: Naming?
    /// The group asked about before it's deleted.
    @State private var deleting: People.Group?

    struct Naming: Identifiable {
        let group: People.Group?
        var id: String { group?.id ?? "new" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(words("people.title")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                    Spacer()
                    Button(words("people.new_group")) { naming = Naming(group: nil) }.disabled(model.changing)
                }
                if let problem = model.problem {
                    Text(verbatim: problem).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
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
        .sheet(item: $naming) { naming in
            GroupNameSheet(group: naming.group) { name in
                self.naming = nil
                guard let name else { return }
                Task {
                    if let group = naming.group {
                        await model.change(.rename(group: group.id, name: name),
                                           what: words("people.rename_group", ["group": group.shownName(words), "name": name]))
                    } else {
                        await model.change(.create(name: name), what: words("people.create_group", ["name": name]))
                    }
                }
            }
            .environment(\.words, words)
        }
        .alert(deleting.map { words("people.delete_group_title", ["group": $0.shownName(words)]) } ?? "",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(deleting.map { words("people.delete_group_button", ["group": $0.shownName(words)]) } ?? "", role: .destructive) {
                guard let group = deleting else { return }
                deleting = nil
                Task { await model.change(.delete(group: group.id), what: words("people.delete_group", ["group": group.shownName(words)])) }
            }
            Button(words("common.cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(words("people.delete_group_body"))
        }
        .task {
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(nanoseconds: UInt64(PeopleModel.readEvery * 1_000_000_000))
            }
        }
    }

    /// A group's name and the tafs it uses, over its people; its actions beside its name.
    private func group(_ group: People.Group, people: [People.Person]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.shownName(words)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(People.uses(group, name: tafName, words: words)).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                actions(group, people: people)
            }
            .padding(.leading, 4).padding(.top, 8)
            let members = People.sorted(group, people: people)
            if !members.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        row(member, label: People.label(member.subject, people: people), in: group)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
        }
    }

    /// A person in a group: their badge, their email (else KIFF's id for them), and their role
    /// in it, a manager's in amber, as the iPad's `memberRow`.
    private func row(_ member: People.Member, label: String, in group: People.Group) -> some View {
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
            memberActions(member, label: label, in: group)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    /// A group's own: add someone not in it yet, and, but for KIFF's default group, Rename and Delete.
    private func actions(_ group: People.Group, people: [People.Person]) -> some View {
        let name = group.shownName(words)
        let outside = people.filter { p in !group.members.contains { $0.subject == p.subject } }
        return Menu {
            Menu(words("people.add_someone_to", ["name": name])) {
                ForEach(outside) { person in
                    Button(person.label) {
                        Task { await model.change(.setMember(group: group.id, subject: person.subject, role: "member"),
                                                  what: words("people.add_to_group", ["who": person.label, "group": name])) }
                    }
                }
            }
            .disabled(outside.isEmpty)
            if !group.everyone {
                Button(words("people.rename")) { naming = Naming(group: group) }
                Button(words("people.delete"), role: .destructive) { deleting = group }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 17)).foregroundColor(Theme.soft)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.changing)
        .accessibilityLabel(words("people.group_actions", ["group": name]))
    }

    /// A person in a group: make them its manager or a member, or remove them from it.
    private func memberActions(_ member: People.Member, label: String, in group: People.Group) -> some View {
        let name = group.shownName(words)
        return Menu {
            if member.isManager {
                Button(words("people.make_member")) {
                    Task { await model.change(.setMember(group: group.id, subject: member.subject, role: "member"),
                                              what: words("people.make_role_member", ["who": label, "group": name])) }
                }
            } else {
                Button(words("people.make_manager")) {
                    Task { await model.change(.setMember(group: group.id, subject: member.subject, role: "manager"),
                                              what: words("people.make_role_manager", ["who": label, "group": name])) }
                }
            }
            Button(words("people.remove_from", ["group": name]), role: .destructive) {
                Task { await model.change(.removeMember(group: group.id, subject: member.subject),
                                          what: words("people.remove_from_group", ["who": label, "group": name])) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(Theme.soft)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.changing)
    }
}

/// Naming a group, new or renamed, as the iPad's sheet: its name, with Create or Rename once it has one.
private struct GroupNameSheet: View {
    @Environment(\.words) private var words
    let group: People.Group?
    /// The name, or nil for Cancel.
    let done: (String?) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.map { words("people.rename_group_title", ["group": $0.shownName(words)]) } ?? words("people.new_group"))
                .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.ink)
            TextField(words("people.group_name_hint"), text: $name).textFieldStyle(.roundedBorder)
            Text(words(group == nil ? "people.new_group_hint" : "people.rename_hint")).font(.system(size: 12)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(words("common.cancel")) { done(nil) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(words(group == nil ? "people.create" : "people.rename")) { done(trimmed) }
                    .keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.background)
        .onAppear { name = group?.name ?? "" }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
