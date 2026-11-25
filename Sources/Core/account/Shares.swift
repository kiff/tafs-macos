import Foundation

/// Who a taf is shared with, as KIFF answers it: ported from the iPad's `KIFFClient.Share`,
/// `shares(agent:)` and `ShareLine.sharedWith`. The Mac reads it; sharing is a signed act.
enum Shares {
    /// One grant of a taf: to a group, or to one person by their subject.
    struct Share: Codable, Equatable, Hashable {
        var group: String? = nil
        var subject: String? = nil
    }

    /// "Shared with Support and ana@acme.com", or not shared yet; "Sharing…" while unread.
    /// The person reading it is never named: a taf only they use is "Not shared", not
    /// "Shared with" themselves. `you` says whether a subject is the person reading.
    static func sharedWith(_ shares: [Share]?, groups: [People.Group], you: (String) -> Bool = { _ in false }, label: (String) -> String, words: Words) -> String {
        guard let shares else { return words("people.sharing") }
        // Shared with KIFF's default group alone: its own sentence, so the languages that inflect it read right.
        if let g = shares.first?.group, shares.count == 1, groups.first(where: { $0.id == g })?.everyone == true {
            return words("people.shared_with_everyone")
        }
        let names = shares.compactMap { s in
            s.group.flatMap { g in groups.first { $0.id == g }?.shownName(words) } ?? s.subject.flatMap { you($0) ? nil : label($0) }
        }
        return names.isEmpty ? words("people.not_shared") : words("people.shared_with_prefix") + words.list(names)
    }

    /// Who uses a taf, under its name on the Overview, as the iPad's `usedBy` (ShareViews.swift:378-394):
    /// "Support, ana@acme.com · 4 people", each group and person it's shared with, and how many
    /// people that is; "Not shared" with none. Nil until its shares are read: the line is only for
    /// whoever manages the taf, as on its page.
    static func usedBy(_ shares: [Share]?, groups: [People.Group], people: [People.Person], words: Words) -> String? {
        guard let shares else { return nil }
        if shares.isEmpty { return words("people.not_shared") }
        var subjects = Set<String>()
        var names: [String] = []
        for share in shares {
            if let id = share.group, let group = groups.first(where: { $0.id == id }) {
                names.append(group.shownName(words))
                group.members.forEach { subjects.insert($0.subject) }
            } else if let subject = share.subject {
                names.append(People.label(subject, people: people))
                subjects.insert(subject)
            }
        }
        // The count is held together by no-break spaces, so a narrow column moves "3 people" (or "1 persona") to the
        // next line whole, never splitting or cutting it (the iPad's `OverviewView.peopleLine`).
        return names.joined(separator: ", ") + " · " + words.count("people.count", subjects.count).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// The same, with the people read from KIFF: the reader is the person KIFF marks as them,
    /// or the one whose email (or subject) is the signed-in email; anyone else by their label.
    static func sharedWith(_ shares: [Share]?, groups: [People.Group], people: [People.Person], email: String?, words: Words) -> String {
        let email = email?.lowercased()
        func person(_ subject: String) -> People.Person? { people.first { $0.subject == subject } }
        return sharedWith(shares, groups: groups, you: { subject in
            let person = person(subject)
            return person?.you == true || (email != nil && (person?.email?.lowercased() == email || subject.lowercased() == email))
        }, label: { person($0)?.label ?? $0 }, words: words)
    }
}

extension Shares {
    /// What Share sends, as the iPad's `ShareTafSheet.save`: each newly chosen grant shared, then each no longer chosen
    /// stopped, in a fixed order (groups, then people, each by id), one act a change.
    static func changes(agent: String, had: Set<Share>, chosen: Set<Share>) -> [KeyAct] {
        func order(_ a: Share, _ b: Share) -> Bool {
            ((a.group == nil ? 1 : 0), a.group ?? a.subject ?? "") < ((b.group == nil ? 1 : 0), b.group ?? b.subject ?? "")
        }
        return chosen.subtracting(had).sorted(by: order).map { KeyAct.share(agent: agent, $0) }
            + had.subtracting(chosen).sorted(by: order).map { KeyAct.unshare(agent: agent, $0) }
    }

    /// "Maria (manager), Ana, Luis", a group's people with its managers first, as the iPad's `ShareTafSheet.people(of:)`;
    /// "No one yet" with none.
    static func people(of group: People.Group, people: [People.Person], words: Words) -> String {
        let names = People.sorted(group, people: people).map { m in
            let label = People.label(m.subject, people: people)
            return m.isManager ? words("people.name_manager", ["name": label]) : label
        }
        return names.isEmpty ? words("people.no_one_yet") : names.joined(separator: ", ")
    }

    /// What the change means, as the iPad's `ShareTafSheet.consequences`: each person's own chats, who uses it now, and
    /// who stops using it.
    static func consequences(taf: String, had: Set<Share>, chosen: Set<Share>, groups: [People.Group], people: [People.Person], words: Words) -> [String] {
        var lines: [String] = []
        if !chosen.isEmpty { lines.append(words("people.own_chats")) }
        for share in chosen.sorted(by: { ($0.group ?? $0.subject ?? "") < ($1.group ?? $1.subject ?? "") }) {
            if let id = share.group, let group = groups.first(where: { $0.id == id }) {
                let who = Self.people(of: group, people: people, words: words)
                lines.append(group.everyone ? words("people.everyone_uses", ["taf": taf, "people": who])
                                            : words("people.group_uses", ["group": group.shownName(words), "taf": taf, "people": who]))
            } else if let subject = share.subject {
                lines.append(words("people.person_uses", ["person": People.label(subject, people: people), "taf": taf]))
            }
        }
        for share in had.subtracting(chosen).sorted(by: { ($0.group ?? $0.subject ?? "") < ($1.group ?? $1.subject ?? "") }) {
            let name = share.group.flatMap { g in groups.first { $0.id == g }?.shownName(words) } ?? share.subject.map { People.label($0, people: people) } ?? ""
            lines.append(words("people.stops_using", ["who": name, "taf": taf]))
        }
        return lines
    }
}

extension AccountClient {
    /// The grants of a taf, by its KIFF agent (`GET /v1/agents/{agent}/grants`).
    func shares(agent: String) async throws -> [Shares.Share] {
        struct List: Decodable { let grants: [Shares.Share] }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let list: List = try read(try await send("GET", "/v1/agents/\(agent.addingPercentEncoding(withAllowedCharacters: allowed) ?? agent)/grants"))
        return list.grants
    }
}
