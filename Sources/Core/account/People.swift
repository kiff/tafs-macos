import Foundation

/// People and groups, as KIFF keeps them (`GET /v1/groups`, `GET /v1/tenant/members`): the
/// account's groups, each with its people and the tafs it uses. Ported from the iPad's
/// `KIFFClient.Group`, `GroupMember`, `Person` and `PeopleGroupsView`'s rules. The Mac reads
/// them, and changes them as the iPad's `changePeople`: Touch ID first, then each request signed
/// by this Mac's device key, which KIFF takes for these routes (`PeopleChange`).
enum People {
    struct Group: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        /// KIFF's default group: everyone on the account is in it.
        let everyone: Bool
        let members: [Member]
        /// The KIFF agents the group is shared.
        let agents: [String]

        // As the iPad's `KIFFClient.Group`: its members and agents must be there, as KIFF sends
        // them, and one that doesn't read fails the read, which then says why.
        enum Keys: String, CodingKey { case id, name, everyone, members, agents }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            everyone = try c.decodeIfPresent(Bool.self, forKey: .everyone) ?? false
            members = try c.decode([Member].self, forKey: .members)
            agents = try c.decode([String].self, forKey: .agents)
        }

        /// The name as the person reads it: KIFF's default group in the app's language, since
        /// KIFF keeps it as "Everyone"; any other group as it was named.
        func shownName(_ words: Words) -> String { everyone ? words("people.everyone_group") : name }
    }

    struct Member: Decodable, Equatable {
        let subject: String
        /// manager or member.
        let role: String
        var isManager: Bool { role == "manager" }
    }

    struct Person: Decodable, Identifiable, Equatable {
        let subject: String
        let role: String
        let status: String
        let email: String?
        let you: Bool
        var id: String { subject }

        // As the iPad's `KIFFClient.Person`: subject, role and status must be there.
        enum Keys: String, CodingKey { case subject, role, status, email, you }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            subject = try c.decode(String.self, forKey: .subject)
            role = try c.decode(String.self, forKey: .role)
            status = try c.decode(String.self, forKey: .status)
            email = try c.decodeIfPresent(String.self, forKey: .email)
            you = try c.decodeIfPresent(Bool.self, forKey: .you) ?? false
        }

        /// What the app shows: their email, else KIFF's id for them.
        var label: String { email.flatMap { $0.isEmpty ? nil : $0 } ?? subject }
        /// Someone on the account now, not invited or removed.
        var active: Bool { status == "active" }
    }

    /// The lists as the iPad's `refreshPeople` keeps them: only the people on the account now,
    /// by label; the default group first, then the others by name, case aside.
    static func shown(groups: [Group], people: [Person]) -> ([Group], [Person]) {
        let groups = groups.sorted { ($0.everyone ? 0 : 1, $0.name.lowercased()) < ($1.everyone ? 0 : 1, $1.name.lowercased()) }
        let people = people.filter(\.active).sorted { $0.label.lowercased() < $1.label.lowercased() }
        return (groups, people)
    }

    /// A member's label: the person's, else KIFF's id for them.
    static func label(_ subject: String, people: [Person]) -> String {
        people.first { $0.subject == subject }?.label ?? subject
    }

    /// A group's people, its managers first, then by label, as the iPad's `managersFirst`.
    static func sorted(_ group: Group, people: [Person]) -> [Member] {
        group.members.sorted { a, b in
            if a.isManager != b.isManager { return a.isManager }
            return label(a.subject, people: people).lowercased() < label(b.subject, people: people).lowercased()
        }
    }

    /// "Uses Refunds and Invoices", or that it uses none yet; the tafs by name, sorted.
    static func uses(_ group: Group, name: (String) -> String?, words: Words) -> String {
        let names = group.agents.compactMap(name).sorted()
        if names.isEmpty { return words(group.everyone ? "people.everyone_uses_none" : "people.uses_none") }
        return words("people.uses", ["tafs": words.list(names)])
    }

    /// The line over the groups: the account's name and how many people, as the iPad's
    /// `AccountLines.people`; the count alone when the account is named after its owner's email.
    static func accountLine(account: String?, signedInAs: String?, email: String?, count: Int, words: Words) -> String {
        let people = words.count("people.count", count)
        guard let account, !account.isEmpty, !(signedInAs == nil && email?.isEmpty == false) else { return people }
        return "\(account) · " + people
    }
}

extension AccountClient {
    /// The account's groups, each with its people and the agents it is shared.
    func groups() async throws -> [People.Group] {
        struct Answer: Decodable { let groups: [People.Group] }
        let answer: Answer = try read(try await send("GET", "/v1/groups"))
        return answer.groups
    }

    /// The account's people.
    func people() async throws -> [People.Person] {
        struct Answer: Decodable { let members: [People.Person] }
        let answer: Answer = try read(try await send("GET", "/v1/tenant/members"))
        return answer.members
    }
}

/// A change to the account's groups, as the iPad's `KIFFClient` writes it (KIFFClient.swift:1636-1656): KIFF takes each
/// signed by the device key (signed routes, not approvals), after the person's own confirmation on this Mac.
enum PeopleChange: Equatable {
    case create(name: String)
    case rename(group: String, name: String)
    case delete(group: String)
    /// Adds someone, or changes their role: `manager` or `member`.
    case setMember(group: String, subject: String, role: String)
    case removeMember(group: String, subject: String)

    var method: String {
        switch self {
        case .create: return "POST"
        case .rename: return "PATCH"
        case .delete, .removeMember: return "DELETE"
        case .setMember: return "PUT"
        }
    }

    var path: String {
        switch self {
        case .create: return "/v1/groups"
        case .rename(let group, _), .delete(let group): return "/v1/groups/\(CloudClient.escaped(group))"
        case .setMember(let group, let subject, _), .removeMember(let group, let subject):
            return "/v1/groups/\(CloudClient.escaped(group))/members/\(CloudClient.escaped(subject))"
        }
    }

    /// The iPad's bodies: the name, the role, or an empty object.
    var body: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json(_ fields: [String: String]) -> Data { (try? encoder.encode(fields)) ?? Data("{}".utf8) }
        switch self {
        case .create(let name), .rename(_, let name): return json(["name": name])
        case .setMember(_, _, let role): return json(["role": role])
        case .delete, .removeMember: return Data("{}".utf8)
        }
    }

    /// What the person confirms, the iPad's `tafs.people.v1|{tenant}|{what}` (AppModel `changePeople`), where `what` is the
    /// change in their words, the same line Touch ID asks with.
    static func confirmation(tenant: String, what: String) -> Data {
        Data("tafs.people.v1|\(tenant)|\(what)".utf8)
    }
}

extension AccountClient {
    /// One group change, signed by the device key. A refusal is KIFF's (`KIFFError`).
    func change(_ change: PeopleChange) async throws {
        _ = try await send(change.method, change.path, body: change.body, signed: true)
    }
}
