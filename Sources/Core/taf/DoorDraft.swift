import Foundation

/// A door Coach drafted for a taf, as tafs cloud keeps it (`GET /v1/tafs/{taf}/doors/drafts/{id}`), as the iPad's
/// `TafsCloud.DoorDraft`: what another application could hand the taf, read to be drawn. This Mac never approves it:
/// approving opens the door and shows its first key once, which stays the phone's (docs/approvals.md).
struct DoorDraft: Equatable {
    /// One field the application sends: its name, and for a choice, its values.
    struct Field: Decodable, Equatable {
        let name: String
        let type: String
        var values: [String]? = nil
    }

    let id: String
    /// The application's name, the fields it sends, what the taf does with them, what it gets back, and whether the
    /// taf may answer in its own words.
    let name: String
    let fields: [Field]
    let job: String
    let outcomes: [String]
    let text: Bool

    /// Read from tafs cloud's answer, as the iPad's `DoorDraft.read`: nil for one with no draft, one that isn't an API
    /// door's, or a draft with no name or job. A field that doesn't read is left out, never the draft.
    static func read(_ data: Data) throws -> DoorDraft? {
        struct Lenient<Item: Decodable>: Decodable {
            let value: Item?
            init(from decoder: Decoder) throws { value = try? Item(from: decoder) }
        }
        struct Raw: Decodable {
            let name: String?
            let fields: [Lenient<Field>]?
            let job: String?
            let outcomes: [String]?
            let text: Bool?
        }
        struct Body: Decodable {
            let kind: String?
            let draft: Raw?
        }
        struct Answer: Decodable {
            let id: String?
            let body: Body?
            enum CodingKeys: String, CodingKey { case id = "draft_id", body }
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let id = answer.id, answer.body?.kind == "api", let raw = answer.body?.draft else { return nil }
        let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let job = raw.job?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, !job.isEmpty else { return nil }
        return DoorDraft(id: id, name: name, fields: (raw.fields ?? []).compactMap(\.value), job: job,
                         outcomes: raw.outcomes ?? [], text: raw.text ?? false)
    }

    /// A field as the iPad's `APIDoorText.field`: its name, then its values, else its type.
    static func line(_ field: Field) -> String {
        if let values = field.values, !values.isEmpty { return field.name + " · " + values.joined(separator: " | ") }
        return field.name + " · " + field.type
    }

    /// tafs cloud refused the read because a door was already made from this draft (410 `draft_used`), as the
    /// iPad's `isUsed`: its words then say so, in the ok colour, since nothing went wrong.
    static func isUsed(_ error: Error) -> Bool {
        (error as? CloudRefusal)?.code == "draft_used"
    }
}

extension CloudClient {
    /// Reads a draft Coach made, as the iPad's `doorDraft(_:draft:)`; nil when tafs cloud's answer holds none this app
    /// can draw. Read only.
    func doorDraft(of taf: String, draft: String) async throws -> DoorDraft? {
        try DoorDraft.read(try await read("/v1/tafs/\(Self.escaped(taf))/doors/drafts/\(Self.escaped(draft))", saying: true))
    }
}
