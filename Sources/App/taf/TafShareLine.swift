import SwiftUI

/// Who uses the taf, as the iPad's `ShareLine` (ShareViews.swift:6-45): Share, then one line
/// under the taf's head, for whoever manages it. Share opens `ShareTafSheet` on a Mac that
/// approves with its security key, where KIFF takes sharing as an approval; on any other Mac a
/// click says where it's done (`approval.device_can_not_approve_approve`), sending nothing.
struct ShareLine: View {
    @Environment(\.words) private var words
    /// The taf's KIFF agent: what its grants are read by.
    let agent: String
    let account: AccountClient
    /// The account's groups and people, read from KIFF, to name each grant.
    @ObservedObject var people: PeopleModel
    /// The signed-in person's email: they're never named in the line.
    let email: String?
    /// The taf's name, in the sheet's words.
    let taf: String
    /// This Mac's security key, when it approves with one: each change of who uses the taf is its act.
    let approveWithKey: ((KeyAct, String) async throws -> Data)?
    @State private var shares: [Shares.Share]?
    @State private var sharing = false
    /// Share was clicked: the line for an approval made on another device shows.
    @State private var said = false

    /// `shares` is what was read already, if anything (a screenshot's); the line reads them again.
    init(agent: String, account: AccountClient, people: PeopleModel, email: String?, taf: String = "",
         approveWithKey: ((KeyAct, String) async throws -> Data)? = nil, shares: [Shares.Share]? = nil) {
        self.agent = agent
        self.account = account
        self.people = people
        self.email = email
        self.taf = taf
        self.approveWithKey = approveWithKey
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
        .sheet(isPresented: $sharing, onDismiss: { Task { shares = try? await account.shares(agent: agent) } }) {
            if let approveWithKey {
                ShareTafSheet(agent: agent, taf: taf, account: account, people: people, approveWithKey: approveWithKey) { sharing = false }
                    .environment(\.words, words)
            }
        }
    }

    /// The iPad's Share: the share mark and its word in a capsule, large enough to find.
    private var share: some View {
        Button { if approveWithKey != nil { sharing = true } else { said = true } } label: {
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

/// Share a taf, in the iPad's two steps (`ShareTafSheet`, ShareViews.swift:76-198): who uses it, then what that means, then
/// Share. Each change is one act on this Mac's security key (`KeyAct.share`, `.unshare`), where the iPad's one Face ID
/// covers them all: this Mac never signs two requests under one. The first that isn't approved stops the rest, and says
/// why; KIFF keeps what was already done, which the list read again shows.
struct ShareTafSheet: View {
    @Environment(\.words) private var words
    let agent: String
    let taf: String
    let account: AccountClient
    @ObservedObject var people: PeopleModel
    let approveWithKey: (KeyAct, String) async throws -> Data
    let close: () -> Void
    @State private var step = 1
    @State private var had: Set<Shares.Share> = []
    @State private var chosen: Set<Shares.Share> = []
    @State private var loaded = false
    @State private var saving = false
    @State private var problem: String?

    private var groups: [People.Group] {
        if case .loaded(let groups, _) = people.state { return groups }
        return []
    }

    private var persons: [People.Person] {
        if case .loaded(_, let persons) = people.state { return persons }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(words(step == 1 ? "people.share.step1" : "people.share.step2")).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim)
            if step == 1 { whoUses } else { whatItMeans }
            if let problem {
                Text(verbatim: problem).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .background(Theme.background)
        .task {
            if groups.isEmpty && persons.isEmpty { await people.load() }
            if let now = try? await account.shares(agent: agent) { had = Set(now); chosen = had }
            loaded = true
        }
    }

    // Step 1 of 2: who uses it.
    private var whoUses: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(words("people.share.who_uses", ["taf": taf])).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.ink)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !groups.isEmpty {
                        Text(words("people.groups")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
                        ForEach(groups) { group in
                            pick(Shares.Share(group: group.id), title: group.shownName(words),
                                 detail: Shares.people(of: group, people: persons, words: words))
                        }
                    }
                    Text(words("people.one_person")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft).padding(.top, 6)
                    ForEach(persons) { person in
                        pick(Shares.Share(subject: person.subject), title: person.label, detail: nil)
                    }
                    Text(words("people.share.choose_someone")).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
            }
            .frame(maxHeight: 360)
        }
    }

    // Step 2 of 2: what sharing means for them.
    private var whatItMeans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(words(chosen.isEmpty ? "people.share.not_shared" : "people.share.who_gets", ["taf": taf]))
                .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.ink)
            ForEach(Shares.consequences(taf: taf, had: had, chosen: chosen, groups: groups, people: persons, words: words), id: \.self) { line in
                Label(line, systemImage: "checkmark.circle").font(.system(size: 14)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if step == 1 {
                Button(words("common.cancel")) { close() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(words("common.next")) { step = 2 }.keyboardShortcut(.defaultAction).disabled(!loaded || chosen == had)
            } else {
                Button(words("common.back")) { step = 1 }.disabled(saving)
                Spacer()
                Button(words("people.share.action")) { save() }.keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
    }

    private func pick(_ share: Shares.Share, title: String, detail: String?) -> some View {
        let on = chosen.contains(share)
        return Button {
            if on { chosen.remove(share) } else { chosen.insert(share) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    if let detail { Text(verbatim: detail).font(.system(size: 12)).foregroundColor(Theme.dim).lineLimit(1) }
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundColor(on ? Theme.amber : Theme.dim)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Stopped part-way: what KIFF has now is read again, so the sheet shows how far it got (what's shared, and what
    /// Share would still change) and Share sends only what's left, never a change already made.
    private func stopped() async {
        if let now = try? await account.shares(agent: agent) { had = Set(now) }
        saving = false
    }

    /// Each change on the key, in `Shares.changes`' order. A key closed, or "Approve on your phone instead", stops the rest
    /// with nothing more sent; KIFF's refusal says why.
    private func save() {
        guard !saving else { return }
        saving = true
        problem = nil
        let changes = Shares.changes(agent: agent, had: had, chosen: chosen)
        let title = words("people.share.title", ["taf": taf])
        Task {
            for act in changes {
                do {
                    _ = try await approveWithKey(act, title)
                } catch is CancellationError {
                    await stopped()
                    return
                } catch is ApproveOnPhone {
                    problem = words("approval.device_can_not_approve_approve")
                    await stopped()
                    return
                } catch {
                    problem = words("common.didnt_go_through", ["what": title, "why": NeedsYouModel.why(error)])
                    await stopped()
                    return
                }
            }
            saving = false
            close()
        }
    }
}
