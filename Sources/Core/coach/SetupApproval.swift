import Foundation

/// An approval card's Approve, as the iPad's `AppModel.approve(_:shown:shownDraft:)` (kiff/tafs#413), for the one step
/// this Mac can sign: **the Card's** (`cards`), KIFF's draft confirm, which KIFF takes from this Mac's security key
/// (kiff/cloud `confirmDraft`, the policy's passkey path). The connection's step (`connect`) is planque's routine
/// route, which takes the phone's approval key only, so it stays the phone's.
///
/// tafs cloud decides each step. The Mac asks (`approval`, with its planque read proof), and tafs cloud answers:
/// - `answered`: done, with its note;
/// - `read_again`: what the card showed is out of date;
/// - `sign`: one ask.
///
/// The Mac signs an ask only when it's the Card's, for the draft and version the card drew, and its message is exactly
/// the one this Mac builds itself (`cardsMessage`). Then it confirms the draft on the key and reports what came of it
/// (`approvalReport`, signed by the device key). Any other ask is refused and nothing is signed.
enum SetupApproval {
    struct Decision: Decodable, Equatable {
        struct Ask: Decodable, Equatable {
            /// KIFF's draft to confirm, at exactly this version.
            struct KIFF: Decodable, Equatable { let draft: String; let version: String }
            let id: String
            /// `connect` or `cards`.
            let step: String
            /// The exact message the step stands for, which this Mac rebuilds and compares.
            let message: String
            /// What the prompt says.
            let reason: String
            var kiff: KIFF?
        }
        let outcome: String
        var note: String?
        var ask: Ask?
        var session: String?
    }

    /// Approve clicked: what the card showed, so tafs cloud compares it with what KIFF holds now.
    struct AskBody: Encodable, Equatable {
        let grant: String
        var draft: String?
        var shownDraft: String?
        var session: String?
        enum CodingKeys: String, CodingKey { case grant, draft, shownDraft = "shown_draft", session }
    }

    /// What came of the call: never an answer, only what happened.
    struct ReportBody: Encodable, Equatable {
        let result: String
        var why: String?
        var session: String?
    }

    /// The Card step's message, as the iPad's `expectedApprovalMessage` builds it for `cards`.
    static func cardsMessage(tenant: String, draft: String, version: String) -> String {
        "tafs.cards.v1|\(tenant)|\(draft)|\(version)"
    }

    /// Whether this Mac signs `ask`: the Card's step only, for the draft the card names at the version it drew, with
    /// exactly the message this Mac builds. Anything else, the connection's step above all, is never signed here.
    static func signsHere(_ ask: Decision.Ask, draft: String?, shownDraft: String?, tenant: String) -> Bool {
        guard ask.step == "cards", let k = ask.kiff, let draft, let shownDraft,
              k.draft == draft, k.version == shownDraft else { return false }
        return ask.message == cardsMessage(tenant: tenant, draft: draft, version: shownDraft)
    }

    /// Whether a card offers Approve here: an approval whose connection is already made, whose Card comes next and is
    /// drawn from KIFF's draft at a version. Its connection's own approval stays the phone's.
    static func offered(connected: Bool, cardNext: Bool, draft: String?, shownDraft: String?) -> Bool {
        connected && cardNext && draft != nil && shownDraft != nil
    }
}

extension CloudClient {
    /// Approve clicked on an approval card (`POST /v1/tafs/{taf}/components/{component}/approval`), with this Mac's
    /// planque read proof so tafs cloud reads planque's grant as this device.
    func approval(taf: String, component: String, body: SetupApproval.AskBody, proof: String?) async throws -> SetupApproval.Decision {
        let path = "/v1/tafs/\(Self.escaped(taf))/components/\(Self.escaped(component))/approval"
        let answer = try await post(path, body: body, headers: proof.map { ["Planque-Device-Signature": $0] } ?? [:])
        let decision: SetupApproval.Decision = try decoded(answer)
        return decision
    }

    /// What came of the ask (`POST …/approval/{ask}`), signed as a KIFF request by the device key (`sign`, over the
    /// exact bytes sent), with a fresh planque read proof. tafs cloud answers Coach, and says what it answered.
    func approvalReport(taf: String, component: String, ask: String, body: SetupApproval.ReportBody, proof: String?,
                        sign: (HTTPRequest) throws -> String) async throws -> SetupApproval.Decision {
        let path = "/v1/tafs/\(Self.escaped(taf))/components/\(Self.escaped(component))/approval/\(Self.escaped(ask))"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var request = HTTPRequest(method: "POST", path: path, headers: [
            "Authorization": "Bearer \(session.accessToken)", "Accept": "application/json", "Accept-Language": language,
            "User-Agent": "tafs-macos", "Content-Type": "application/json",
        ], body: try encoder.encode(body))
        request.headers["KIFF-Device-Signature"] = try sign(request)
        if let proof { request.headers["Planque-Device-Signature"] = proof }
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw CloudRefusal(status: status, body: answer) }
        let decision: SetupApproval.Decision = try decoded(answer)
        return decision
    }
}
