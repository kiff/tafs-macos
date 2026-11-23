import Foundation

/// KIFF's side of Plan & usage (`GET /v1/me/usage`), as the iPad's `KIFFClient.Usage`
/// (KIFFClient.swift:629-719): the plan, who bills it, the packs KIFF sells, and members'
/// requests to the account's admins.
struct KIFFUsage: Decodable, Equatable {
    /// Who bills the plan, as the iPad's `KIFFClient.Usage.Billing`: `apple`, `google`, `stripe`
    /// (KIFF) or `contract` (an agreement). Read as the iPad reads it: a billing with no source,
    /// or with a date that doesn't read, is none.
    struct Billing: Decodable, Equatable {
        var source: String
        /// The account moved from Solo in the App Store to Company, which KIFF bills now, and
        /// Solo still renews with Apple on this date unless it's cancelled there.
        var appleSoloUntil: Date? = nil
        enum CodingKeys: String, CodingKey { case source, appleSoloUntil = "apple_solo_until" }
    }

    /// Apple's page for the Apple account's subscriptions, which the App Store opens on a Mac:
    /// where Solo bought in the App Store is managed or cancelled, as the iPad's
    /// `manageSubscriptions`. The app never points anywhere else to buy.
    static let appleSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// What KIFF sells: the packs of credits. On the Mac nothing is bought; a pack is only what
    /// a member asks an admin for.
    struct Store: Decodable, Equatable {
        struct Pack: Decodable, Equatable, Identifiable {
            let id: String
            let name: String
            /// KIFF's line for it, shown as it is.
            let line: String
            /// The pack's credits, from a KIFF that says.
            var credits: Int? = nil
            let appleProduct: String
            /// The First month pack: bought once per account. KIFF drops it once bought.
            var once = false
            enum CodingKeys: String, CodingKey { case id, name, line, credits, appleProduct = "apple_product", once }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                name = try c.decode(String.self, forKey: .name)
                line = try c.decode(String.self, forKey: .line)
                credits = (try? c.decodeIfPresent(Int.self, forKey: .credits)) ?? nil
                appleProduct = try c.decode(String.self, forKey: .appleProduct)
                once = ((try? c.decodeIfPresent(Bool.self, forKey: .once)) ?? nil) ?? false
            }
        }
        let soloProduct: String
        var packs: [Pack] = []
        enum CodingKeys: String, CodingKey { case soloProduct = "solo_product", packs }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            soloProduct = try c.decode(String.self, forKey: .soloProduct)
            packs = ((try? c.decodeIfPresent([Lenient<Pack>].self, forKey: .packs)) ?? nil)?.compactMap(\.value) ?? []
        }

        /// The packs the app lists, as the iPad's `offered(firstMonth:)`: the First month pack
        /// first, and only while tafs cloud says it can be bought (`firstMonth`); then the packs
        /// that can be bought again. Never the First month pack alone or greyed.
        func offered(firstMonth: Bool) -> [Pack] {
            var listed: [Pack] = []
            if firstMonth, let first = packs.first(where: \.once) { listed.append(first) }
            listed.append(contentsOf: packs.filter { !$0.once })
            return listed
        }
    }

    /// KIFF's plan: "solo", "team" (Company), "company" (an agreement), "internal", or none.
    var plan: String? = nil
    var billing: Billing? = nil
    var store: Store? = nil
    /// Members' requests for a raise or a pack: every open one for someone who manages
    /// billing, this person's own otherwise.
    var requests: [PackRequest]? = nil

    enum CodingKeys: String, CodingKey { case plan, billing, store, requests }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = (try? c.decodeIfPresent(String.self, forKey: .plan)) ?? nil
        billing = (try? c.decodeIfPresent(Billing.self, forKey: .billing)) ?? nil
        store = (try? c.decodeIfPresent(Store.self, forKey: .store)) ?? nil
        requests = ((try? c.decodeIfPresent([Lenient<PackRequest>].self, forKey: .requests)) ?? nil)?.compactMap(\.value)
    }

    /// The words key of the one line on who bills the plan, as the iPad's `billingLine`; nil
    /// when no plan is billed, or by a source this app doesn't know.
    var billingLine: String? {
        switch billing?.source {
        case "apple": return "billing.by_apple"
        case "google": return "billing.by_google_play"
        case "stripe": return "billing.by_kiff"
        case "contract": return "billing.by_agreement"
        default: return nil
        }
    }

    /// Apple bills the plan, so it's managed in the Apple account's subscriptions (Manage).
    var managedByApple: Bool { billing?.source == "apple" }

    /// After a move from Solo to Company, which KIFF bills now, the date Solo still renews with
    /// Apple unless it's cancelled there, as the iPad's `soloStillRenews`; nil otherwise.
    var soloStillRenews: Date? {
        guard billing?.source == "stripe" else { return nil }
        return billing?.appleSoloUntil
    }

    /// One item of a list that reads, or nil, as the iPad's `LenientItem`: one that doesn't
    /// read is left out, never the list.
    private struct Lenient<Item: Decodable>: Decodable {
        let value: Item?
        init(from decoder: Decoder) throws { value = try? Item(from: decoder) }
    }
}

/// A member's request to the account's admins, as the iPad's `KIFFClient.PackRequest`
/// (KIFFClient.swift:723-755): a raise of the spend limit (`kind: "raise"`) or a pack of
/// credits (`kind: "pack"`, naming the pack).
struct PackRequest: Decodable, Equatable, Identifiable {
    let id: String
    let askedBy: String
    /// "raise" or "pack"; a request from a KIFF that doesn't say is for a pack.
    var kind: String = "pack"
    var pack: String? = nil
    var reason: String = ""
    /// open, approved, declined, withdrawn or expired.
    let status: String
    let createdAt: Date
    let expiresAt: Date
    var note: String? = nil
    enum CodingKeys: String, CodingKey { case id, askedBy = "asked_by", kind, pack, reason, status, createdAt = "created_at", expiresAt = "expires_at", note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        askedBy = try c.decode(String.self, forKey: .askedBy)
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? "pack"
        pack = (try? c.decodeIfPresent(String.self, forKey: .pack)) ?? nil
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

extension AccountClient {
    /// KIFF's side of Plan & usage, as the iPad's `usage()`.
    func usage() async throws -> KIFFUsage { try read(try await send("GET", "/v1/me/usage")) }

    /// Asks the account's admins, with a reason, as the iPad's `askAdmin(raise:pack:reason:)`: for
    /// a raise (`{"kind": "raise", "reason"}`, no pack), or for a pack (`{"pack", "reason"}`,
    /// where no `kind` means a pack).
    func askAdmin(raise: Bool, pack: String?, reason: String) async throws -> PackRequest {
        var body = ["reason": reason]
        if raise { body["kind"] = "raise" } else if let pack { body["pack"] = pack }
        return try read(try await send("POST", "/v1/me/pack-requests", body: try Self.json(body)))
    }

    /// Takes back this person's request, as the iPad's `withdrawRequest`.
    func withdrawRequest(_ id: String) async throws -> PackRequest {
        try read(try await send("POST", "/v1/me/pack-requests/\(CloudClient.escaped(id))/withdraw", body: try Self.json([String: String]())))
    }

    /// Declines a member's request, with a note, as the iPad's `declineRequest`: a signed call,
    /// signed by this Mac's device key over the exact bytes sent.
    func declineRequest(_ id: String, note: String) async throws -> PackRequest {
        try read(try await send("POST", "/v1/me/pack-requests/\(CloudClient.escaped(id))/decline", body: try Self.json(["note": note]), signed: true))
    }

    private static func json(_ fields: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(fields)
    }
}
