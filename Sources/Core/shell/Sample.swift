import Foundation

/// "Try it with sample data", as the iPad's `startSample` (AppModel.swift:3004-3018) and `loadSample`
/// (`:6763-6790`), and as Windows' `--sample`: the five sample tafs of the iPad's `TafTemplates`, each with its
/// Card, the calls their first two rounds made (the ones a Card holds waiting in Needs you, the rest done), Support
/// replies' chat, and the sample's devices. Every word is the iPad's own, from the shared strings (`sample.*`).
///
/// This Mac's screens read only tafs cloud and KIFF, so the sample is one transport (`SampleTransport`) that
/// answers those reads, in memory: no screen has a second path, nothing reaches the network, and nothing is kept
/// between launches. A write or an approval is answered "not in the sample", and nothing is done.
enum Sample {
    /// A Card's rule, as the iPad's `CardRule`: a count a day, held for the owner's answer, or never.
    struct Rule {
        let action: String
        let label: String
        var count: Int? = nil
        var ask = false
        var never = false
    }

    /// A call the demo plays, as the iPad's `ProposedAction`: its action, and its words' keys.
    struct Call {
        let action: String
        let summary: String
        let why: String
    }

    struct Taf {
        let key: String
        let tools: [String]
        let rules: [Rule]
        let script: [Call]
    }

    /// The iPad's `TafTemplates.all` in `loadSample`'s order, newest first as `start` inserts them: Support replies
    /// first.
    static let tafs: [Taf] = [
        Taf(key: "support", tools: ["sample.tool.email", "sample.tool.store"], rules: [
            Rule(action: "reply_ticket", label: "sample.support.rule.replies", count: 40),
            Rule(action: "promise", label: "sample.support.rule.promises", ask: true),
            Rule(action: "share_customer_data", label: "sample.support.rule.customer_data", never: true),
        ], script: [
            Call(action: "reply_ticket", summary: "sample.support.reply_7781", why: "sample.support.reply_7781_why"),
            Call(action: "promise", summary: "sample.support.promise_7802", why: "sample.support.promise_7802_why"),
        ]),
        Taf(key: "parcels", tools: ["sample.tool.store", "sample.tool.email"], rules: [
            Rule(action: "delay_message", label: "sample.parcels.rule.delay_messages", count: 100),
            Rule(action: "reship", label: "sample.parcels.rule.reships", ask: true),
            Rule(action: "change_address", label: "sample.parcels.rule.address_changes", never: true),
            Rule(action: "parcel_refund", label: "sample.parcels.rule.refunds", never: true),
        ], script: [
            Call(action: "delay_message", summary: "sample.parcels.tell_5120", why: "sample.parcels.tell_5120_why"),
            Call(action: "reship", summary: "sample.parcels.reship_5098", why: "sample.parcels.reship_5098_why"),
        ]),
        Taf(key: "access", tools: ["sample.tool.sign_in", "sample.tool.code"], rules: [
            Rule(action: "grant_role", label: "sample.access.rule.approved_roles", count: 40),
            Rule(action: "deactivate", label: "sample.access.rule.deactivations", count: 20),
            Rule(action: "elevate", label: "sample.access.rule.elevated", ask: true),
            Rule(action: "grant_admin", label: "sample.access.rule.admin_roles", never: true),
            Rule(action: "delete_user", label: "sample.access.rule.deleting_users", never: true),
        ], script: [
            Call(action: "grant_role", summary: "sample.access.sales_role", why: "sample.access.sales_role_why"),
            Call(action: "deactivate", summary: "sample.access.deactivate_tom", why: "sample.access.deactivate_tom_why"),
        ]),
        Taf(key: "deploys", tools: ["sample.tool.code", "sample.tool.hosting", "sample.tool.network"], rules: [
            Rule(action: "deploy", label: "sample.deploys.rule.deploys", count: 10),
            Rule(action: "rollback", label: "sample.deploys.rule.rollbacks", count: 20),
            Rule(action: "migration", label: "sample.deploys.rule.migrations", ask: true),
            Rule(action: "destroy_data", label: "sample.deploys.rule.destroy_data", never: true),
        ], script: [
            Call(action: "deploy", summary: "sample.deploys.deploy_api", why: "sample.deploys.deploy_api_why"),
            Call(action: "migration", summary: "sample.deploys.migration", why: "sample.deploys.migration_why"),
        ]),
        Taf(key: "leads", tools: ["sample.tool.email"], rules: [
            Rule(action: "reply_lead", label: "sample.leads.rule.replies", count: 50),
            Rule(action: "offer_discount", label: "sample.leads.rule.discounts", ask: true),
        ], script: [
            Call(action: "reply_lead", summary: "sample.leads.reply_kaya", why: "sample.leads.reply_kaya_why"),
            Call(action: "reply_lead", summary: "sample.leads.confirm_nord", why: "sample.leads.confirm_nord_why"),
        ]),
    ]

    /// The sample's account: no one's. Its session reaches no service, and signs nothing (no device key).
    static let tenant = "sample"
    static let session = Session(accessToken: "sample", expiresIn: 3600, tenant: tenant, subject: "sample", deviceID: nil)

    /// A taf's ids in the sample: tafs cloud's (`id`) and KIFF's agent (`kiff_agent`).
    static func tafID(_ taf: Taf) -> String { "sample-\(taf.key)" }
    static func agent(_ taf: Taf) -> String { "sample-agent-\(taf.key)" }

    /// The calls the first two rounds made, as `loadSample`'s two `playNextDemoActions()`: a call its Card holds for
    /// the owner (`ask`) waits in Needs you; the rest were done within the Card.
    static func held() -> [(Taf, Call)] {
        tafs.flatMap { taf in taf.script.prefix(2).filter { call in rule(taf, call.action)?.ask == true }.map { (taf, $0) } }
    }

    static func done() -> [(Taf, Call)] {
        tafs.flatMap { taf in taf.script.prefix(2).filter { call in rule(taf, call.action)?.ask != true }.map { (taf, $0) } }
    }

    static func rule(_ taf: Taf, _ action: String) -> Rule? { taf.rules.first { $0.action == action } }

    // MARK: The answers

    static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// A taf's Card in tafs cloud's shape (`card.cards[]`): each rule's label, a count a day, held, or refused.
    static func card(_ taf: Taf, words: Words, now: Date) -> [String: Any] {
        let expires = time(Calendar(identifier: .gregorian).date(byAdding: .month, value: 3, to: now) ?? now)
        let rules: [[String: Any]] = taf.rules.map { rule in
            var made: [String: Any] = ["action": rule.action, "label": words(rule.label), "outside": rule.never ? "refuse" : "hold"]
            if let count = rule.count {
                made["count_per_window"] = count
                made["window"] = "calendar_day"
                made["window_words"] = ["each": words("card.window.a_day"), "now": words("card.window.today")]
            } else if rule.ask || rule.never {
                made["count_per_window"] = 0
            }
            return made
        }
        let one: [String: Any] = ["id": "card-\(taf.key)", "title": words("sample.\(taf.key).name"), "environment": "", "live": true,
                                  "active": true, "expires": expires, "rules": rules]
        return ["ids": ["card-\(taf.key)"], "active": true, "expires": expires, "tools": taf.tools.map { words($0) }, "rules": rules, "cards": [one]]
    }

    /// Home (`GET /v1/home`): the five tafs at work, the headline, and what waits.
    static func home(words: Words, now: Date) -> Data {
        let waiting = held()
        let list: [[String: Any]] = tafs.enumerated().map { index, taf in
            let name = words("sample.\(taf.key).name")
            return ["id": tafID(taf), "kiff_agent": agent(taf), "name": name, "job": words("sample.\(taf.key).job"),
                    "job_summary": words("sample.\(taf.key).job"), "status": "active", "state": "working", "color": index,
                    "waiting": waiting.filter { $0.0.key == taf.key }.count, "card": card(taf, words: words, now: now)]
        }
        return json(["tafs": list, "headline": ["words": words.count("home.working", tafs.count)],
                     "setting_up": [], "others": [], "removing": [],
                     "needs_you": ["count": waiting.count, "words": waiting.isEmpty ? words("needs_you.nothing") : words.count("needs_you.count", waiting.count)]])
    }

    /// KIFF's held calls (`GET /v1/me/card-exceptions?status=held`): each held call the sample's Cards hold, for its
    /// owner's answer, expiring in an hour.
    static func heldCalls(words: Words, now: Date) -> Data {
        let calls: [[String: Any]] = held().enumerated().map { index, pair in
            let (taf, call) = pair
            return ["id": "sample-held-\(taf.key)", "subject": agent(taf), "action": call.action, "title": words(call.summary),
                    "reason_text": words(rule(taf, call.action).map { $0.label } ?? call.summary), "taf_about": words(call.summary),
                    "taf_reason": words(call.why), "created_at": time(now.addingTimeInterval(Double(-600 * (index + 1)))),
                    "expires_at": time(now.addingTimeInterval(3600)), "accounting_version": 1, "next_steps": nextSteps(taf, words: words)]
        }
        return json(["exceptions": calls])
    }

    static func nextSteps(_ taf: Taf, words: Words) -> [String] {
        let key = "sample.\(taf.key).next_step"
        let line = words(key)
        return line == key ? [] : [line]
    }

    /// Who is signed in (`GET /v1/me`): the sample's account, which approves nothing.
    static func me(words: Words) -> Data {
        json(["tenant_slug": tenant, "tenant_display_name": words("settings.mode_sample"), "approval_mode": "view",
              "capabilities": ["holds.answer", "cards.manage", "billing.manage"]])
    }

    /// The answer the sample gives a request: its reads from the sample, every other read empty, and a write or an
    /// approval refused, with nothing done.
    static func answer(method: String, path: String, words: Words, now: Date) -> (Int, Data) {
        let bare = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard method == "GET" else {
            return (403, json(["error": "sample", "words": notInSample(words)]))
        }
        switch bare {
        case "/v1/home": return (200, home(words: words, now: now))
        case "/v1/me": return (200, me(words: words))
        case "/v1/me/card-exceptions": return (200, heldCalls(words: words, now: now))
        case "/v1/me/did-this-happen": return (200, json(["calls": []]))
        case "/v1/me/devices": return (200, json(["devices": []]))
        case "/v1/me/passkeys": return (200, json(["passkeys": []]))
        case "/v1/groups": return (200, json(["groups": []]))
        case "/v1/tenant/members": return (200, json(["members": []]))
        default: return (404, json(["error": "not_found", "words": notInSample(words)]))
        }
    }

    /// The line for what the sample can't do, in the person's language: that it takes KIFF. A shared line of its own
    /// is asked of tafs's strings; until it's there, this is the app's own.
    static func notInSample(_ words: Words) -> String { words("sign_in.with_kiff") }
}

/// tafs cloud and KIFF, stood in by the sample, in memory: what `Sample.answer` says, and never the network.
final class SampleTransport: Transport, @unchecked Sendable {
    let words: Words
    let now: () -> Date

    init(words: Words, now: @escaping () -> Date = Date.init) {
        self.words = words
        self.now = now
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let (status, body) = Sample.answer(method: request.method, path: request.path, words: words, now: now())
        return (status, body)
    }
}
