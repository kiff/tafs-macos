import Foundation

/// People and groups, as KIFF keeps them (`GET /v1/groups`, `GET /v1/tenant/members`): the
/// account's groups, each with its people and the tafs it uses. Ported from the iPad's
/// `KIFFClient.Group`, `GroupMember`, `Person` and `PeopleGroupsView`'s rules. The Mac reads
/// them; each change is the person's act behind their device's key, so it waits for #16.
enum People {
    struct Group: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        /// KIFF's default group: everyone on the account is in it.
        let everyone: Bool
        let members: [Member]
        /// The KIFF agents the group is shared.
        let agents: [String]

        enum Keys: String, CodingKey { case id, name, everyone, members, agents }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            everyone = ((try? c.decodeIfPresent(Bool.self, forKey: .everyone)) ?? nil) ?? false
            members = ((try? c.decodeIfPresent([Lenient<Member>].self, forKey: .members)) ?? nil)?.compactMap(\.value) ?? []
            agents = ((try? c.decodeIfPresent([String].self, forKey: .agents)) ?? nil) ?? []
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

        enum Keys: String, CodingKey { case subject, role, status, email, you }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            subject = try c.decode(String.self, forKey: .subject)
            role = ((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil) ?? ""
            status = ((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? ""
            email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? nil
            you = ((try? c.decodeIfPresent(Bool.self, forKey: .you)) ?? nil) ?? false
        }

        /// What the app shows: their email, else KIFF's id for them.
        var label: String { email.flatMap { $0.isEmpty ? nil : $0 } ?? subject }
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

/// Reads one item of a list, or nothing: an item that doesn't read is left out, never the list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension AccountClient {
    /// The account's groups, each with its people and the agents it is shared.
    func groups() async throws -> [People.Group] {
        struct Answer: Decodable { let groups: [Lenient<People.Group>] }
        let answer: Answer = try read(try await send("GET", "/v1/groups"))
        return answer.groups.compactMap(\.value)
    }

    /// The account's people.
    func people() async throws -> [People.Person] {
        struct Answer: Decodable { let members: [Lenient<People.Person>] }
        let answer: Answer = try read(try await send("GET", "/v1/tenant/members"))
        return answer.members.compactMap(\.value)
    }
}
