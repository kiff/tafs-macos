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
        /// The summary is shown as it is, not a key: the iPad's `DROP TABLE sessions_old`.
        var literal = false

        func title(_ words: Words) -> String { literal ? summary : words(summary) }
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
            Call(action: "reply_ticket", summary: "sample.support.reply_7790", why: "sample.support.reply_7790_why"),
            Call(action: "share_customer_data", summary: "sample.support.share_history", why: "sample.support.share_history_why"),
        ]),
        Taf(key: "parcels", tools: ["sample.tool.store", "sample.tool.email"], rules: [
            Rule(action: "delay_message", label: "sample.parcels.rule.delay_messages", count: 100),
            Rule(action: "reship", label: "sample.parcels.rule.reships", ask: true),
            Rule(action: "change_address", label: "sample.parcels.rule.address_changes", never: true),
            Rule(action: "parcel_refund", label: "sample.parcels.rule.refunds", never: true),
        ], script: [
            Call(action: "delay_message", summary: "sample.parcels.tell_5120", why: "sample.parcels.tell_5120_why"),
            Call(action: "reship", summary: "sample.parcels.reship_5098", why: "sample.parcels.reship_5098_why"),
            Call(action: "delay_message", summary: "sample.parcels.tell_5134", why: "sample.parcels.tell_5134_why"),
            Call(action: "change_address", summary: "sample.parcels.change_address", why: "sample.parcels.change_address_why"),
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
            Call(action: "elevate", summary: "sample.access.database_lee", why: "sample.access.database_lee_why"),
            Call(action: "grant_admin", summary: "sample.access.admin_lee", why: "sample.access.admin_lee_why"),
        ]),
        Taf(key: "deploys", tools: ["sample.tool.code", "sample.tool.hosting", "sample.tool.network"], rules: [
            Rule(action: "deploy", label: "sample.deploys.rule.deploys", count: 10),
            Rule(action: "rollback", label: "sample.deploys.rule.rollbacks", count: 20),
            Rule(action: "migration", label: "sample.deploys.rule.migrations", ask: true),
            Rule(action: "destroy_data", label: "sample.deploys.rule.destroy_data", never: true),
        ], script: [
            Call(action: "deploy", summary: "sample.deploys.deploy_api", why: "sample.deploys.deploy_api_why"),
            Call(action: "migration", summary: "sample.deploys.migration", why: "sample.deploys.migration_why"),
            Call(action: "destroy_data", summary: "DROP TABLE sessions_old", why: "sample.deploys.drop_table_why", literal: true),
        ]),
        Taf(key: "leads", tools: ["sample.tool.email"], rules: [
            Rule(action: "reply_lead", label: "sample.leads.rule.replies", count: 50),
            Rule(action: "offer_discount", label: "sample.leads.rule.discounts", ask: true),
        ], script: [
            Call(action: "reply_lead", summary: "sample.leads.reply_kaya", why: "sample.leads.reply_kaya_why"),
            Call(action: "reply_lead", summary: "sample.leads.confirm_nord", why: "sample.leads.confirm_nord_why"),
            Call(action: "offer_discount", summary: "sample.leads.discount_lumen", why: "sample.leads.discount_lumen_why"),
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
    static func held(rounds: Int = firstRounds) -> [(Taf, Call)] {
        made(rounds).filter { taf, call in rule(taf, call.action)?.ask == true }
    }

    static func done(rounds: Int = firstRounds) -> [(Taf, Call)] {
        made(rounds).filter { taf, call in rule(taf, call.action)?.ask != true && rule(taf, call.action)?.never != true }
    }

    /// The calls a Card refused outright (`never`), as the iPad's: refused, never sent, and in the Record.
    static func refused(rounds: Int = firstRounds) -> [(Taf, Call)] {
        made(rounds).filter { taf, call in rule(taf, call.action)?.never == true }
    }

    /// Every call the demo has made after `rounds` rounds, round by round, as the iPad's `playNextDemoActions()`: each
    /// working taf plays its script's next call.
    static func made(_ rounds: Int) -> [(Taf, Call)] {
        (0..<max(0, rounds)).flatMap { round in tafs.compactMap { taf in round < taf.script.count ? (taf, taf.script[round]) : nil } }
    }

    /// The rounds `loadSample` plays at once; "Play the next sample actions" plays one more, up to the longest script.
    static let firstRounds = 2
    static var lastRound: Int { tafs.map(\.script.count).max() ?? firstRounds }

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
    static func home(words: Words, now: Date, rounds: Int = firstRounds, paused: Set<String> = []) -> Data {
        let waiting = held(rounds: rounds)
        let list: [[String: Any]] = tafs.enumerated().map { index, taf in
            let name = words("sample.\(taf.key).name")
            let mine = waiting.filter { $0.0.key == taf.key }.count
            // Its state as tafs cloud's `stateOf` (`runtime/src/cloud/home.ts`): waiting while a call of its waits on the
            // owner, else paused when paused, else working. The screens read the state, not `status`.
            let state = mine > 0 ? "waiting" : paused.contains(taf.key) ? "paused" : "working"
            return ["id": tafID(taf), "kiff_agent": agent(taf), "name": name, "job": words("sample.\(taf.key).job"),
                    "job_summary": words("sample.\(taf.key).job"), "status": paused.contains(taf.key) ? "paused" : "active",
                    "state": state, "color": index, "waiting": mine, "card": card(taf, words: words, now: now)]
        }
        return json(["tafs": list, "headline": ["words": words.count("home.working", tafs.count)],
                     "setting_up": [], "others": [], "removing": [],
                     "needs_you": ["count": waiting.count, "words": waiting.isEmpty ? words("needs_you.nothing") : words.count("needs_you.count", waiting.count)]])
    }

    /// KIFF's held calls (`GET /v1/me/card-exceptions?status=held`): each held call the sample's Cards hold, for its
    /// owner's answer, expiring in an hour.
    static func heldCalls(words: Words, now: Date, rounds: Int = firstRounds) -> Data {
        let calls: [[String: Any]] = held(rounds: rounds).enumerated().map { index, pair in
            let (taf, call) = pair
            return ["id": "sample-held-\(taf.key)-\(call.action)", "subject": agent(taf), "action": call.action, "title": call.title(words),
                    "reason_text": words(rule(taf, call.action).map { $0.label } ?? call.summary), "taf_about": call.title(words),
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

    /// Devices (`GET /v1/me/devices`), as the iPad's `SampleScreens.devices`: this Mac, an iPhone used three hours ago,
    /// and a Mac yesterday, each named as tafs names a device.
    static func devices(words: Words, now: Date) -> Data {
        let name = { (device: String) in words("settings.devices.this_device_name", ["device": device]) }
        return json(["devices": [
            ["id": "dev_this", "display_name": name(words("device.mac")), "platform": "macos", "last_used_at": time(now), "this_device": true],
            ["id": "dev_phone", "display_name": name("iPhone"), "platform": "ios", "last_used_at": time(now.addingTimeInterval(-3 * 3600))],
            ["id": "dev_mac", "display_name": name(words("device.mac")), "platform": "macos", "last_used_at": time(now.addingTimeInterval(-26 * 3600))],
        ]])
    }

    /// Who is signed in (`GET /v1/me`): the sample's account, which approves nothing.
    static func me(words: Words) -> Data {
        json(["tenant_slug": tenant, "tenant_display_name": words("settings.mode_sample"), "approval_mode": "view",
              "capabilities": ["holds.answer", "cards.manage", "billing.manage"]])
    }

    /// Plan & usage's balance (`GET /v1/usage/balance`), as the iPad's `sampleBalance`: Solo, about half the
    /// period's credits left.
    static func balance(words: Words) -> Data {
        json(["balance": ["state": "ok", "meter_pct": 48, "words": words("sample.credits.balance_words"),
                          "detail": words("sample.credits.balance_detail"), "credits_panel": true],
              "plan_line": words("sample.credits.plan_line"), "plan_tone": "ok"])
    }

    /// The period's credits (`GET /v1/usage/credits`, `?period=previous` for the one before), as the iPad's
    /// `sampleCredits`.
    static func credits(words: Words, previous: Bool) -> Data {
        if previous {
            return json(["credits": 2310, "runs": 126, "words": words("sample.credits.last_period"),
                         "tafs": [["taf": "sample-support", "credits": 1480, "runs": 74, "words": words("sample.credits.refunds_last")],
                                  ["taf": "sample-parcels", "credits": 830, "runs": 52, "words": words("sample.credits.invoices_last")]],
                         "note": words("sample.credits.note")])
        }
        return json(["credits": 1240, "runs": 69, "words": words("sample.credits.this_period"),
                     "tafs": [["taf": "sample-support", "credits": 820, "runs": 41, "words": words("sample.credits.refunds_this")],
                              ["taf": "sample-parcels", "credits": 420, "runs": 28, "words": words("sample.credits.invoices_this")]],
                     "not_counted": ["runs": 9, "words": words("sample.credits.not_counted"),
                                     "lines": [["why": "coach", "runs": 6, "words": words("sample.credits.not_counted_coach")],
                                               ["why": "trial", "runs": 2, "words": words("sample.credits.not_counted_trials")],
                                               ["why": "failed", "runs": 1, "words": words("sample.credits.not_counted_failed")]]],
                     "note": words("sample.credits.note")])
    }

    /// The Record (`GET /v1/record`): what the first two rounds did, newest first. Each call done within its Card,
    /// and each one held, waiting for the owner.
    static func record(words: Words, now: Date, rounds: Int = firstRounds) -> Data {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: words.language)
        clock.timeStyle = .short
        clock.dateStyle = .none
        // Newest first: the last round's calls at the top.
        let made: [(Taf, Call)] = Self.made(rounds).reversed()
        let entries: [[String: Any]] = made.enumerated().map { index, item in
            let (taf, call) = item
            let rule = Self.rule(taf, call.action)
            let kind = rule?.never == true ? "refused" : rule?.ask == true ? "held" : "done"
            let detail = kind == "refused" ? "record.decided.refused_by_card" : kind == "held" ? "record.waiting_for_you" : "record.done_within_card"
            let at = now.addingTimeInterval(Double(-300 * (index + 1)))
            return ["id": "sample-record-\(taf.key)-\(call.action)", "at": time(at), "kind": kind,
                    "title": call.title(words), "detail": words(detail),
                    "time": clock.string(from: at), "call": ["proposal_id": "sample-\(taf.key)-\(call.action)"],
                    "taf": ["id": tafID(taf), "name": words("sample.\(taf.key).name")]]
        }
        return json(["entries": entries])
    }

    /// The sample taf a tafs cloud path names (`/v1/tafs/sample-{key}/…`), and what follows its id.
    static func taf(in path: String) -> (Taf, String)? {
        guard path.hasPrefix("/v1/tafs/") else { return nil }
        let rest = path.dropFirst("/v1/tafs/".count)
        let id = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard let taf = tafs.first(where: { tafID($0) == id }) else { return nil }
        return (taf, String(rest.dropFirst(id.count)))
    }

    /// A taf's own reads: its chat (its hello, and for Support replies the iPad's sample question), its Setup (its job
    /// as its workflow), its Activity (what it did), and everything else it has: none yet.
    static func tafAnswer(_ taf: Taf, _ rest: String, words: Words, now: Date, rounds: Int = firstRounds, said: [Said] = []) -> (Int, Data)? {
        let name = words("sample.\(taf.key).name")
        switch rest {
        case "/conversation":
            func message(_ id: String, _ from: String, _ at: Date, _ text: String) -> [String: Any] {
                ["type": "message", "message": ["id": id, "from": from, "at": time(at), "text": text]]
            }
            var items: [[String: Any]] = [message("sample-hello-\(taf.key)", "taf", now.addingTimeInterval(-3600),
                                                  words("sample.hello", ["name": name, "now": words("sample.\(taf.key).job")]))]
            // Support replies' sample question, and its answer from its own record, as the iPad's `loadSample`.
            if taf.key == "support" {
                let question = words("sample.chat.question")
                items.append(message("sample-question", "owner", now.addingTimeInterval(-1800), question))
                items.append(message("sample-question-reply", "taf", now.addingTimeInterval(-1799), reply(to: question, taf: taf, words: words, rounds: rounds).0))
            }
            // What the person said here, each with the taf's reply.
            for (index, one) in said.enumerated() {
                items.append(message("sample-said-\(index)", "owner", one.at, one.text))
                items.append(message("sample-said-\(index)-reply", "taf", one.at.addingTimeInterval(1), one.reply))
            }
            return (200, json(["working": false, "items": items]))
        case "/setup":
            return (200, json(["connections": [], "workflow": ["title": words("sample.\(taf.key).name"), "summary": words("sample.\(taf.key).job"), "steps": []]]))
        case "/activity":
            let page = try? JSONSerialization.jsonObject(with: record(words: words, now: now, rounds: rounds)) as? [String: Any]
            let mine = ((page?["entries"] as? [[String: Any]]) ?? []).filter { (($0["taf"] as? [String: Any])?["id"] as? String) == tafID(taf) }
            return (200, json(["entries": mine]))
        case "/runs": return (200, json(["runs": []]))
        case "/memory": return (200, json(["notes": []]))
        case "/work": return (200, json(["summary": ["status": "idle"], "requests": [], "skipped": []]))
        default: return nil
        }
    }

    /// The answer the sample gives a request: its reads from the sample, every other read empty, and a write or an
    /// approval refused, with nothing done.
    static func answer(method: String, path: String, words: Words, now: Date, rounds: Int = firstRounds, talk: Talk = Talk()) -> (Int, Data) {
        let bare = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard method == "GET" else {
            return (403, json(["error": "sample", "words": notInSample(words)]))
        }
        if let (taf, rest) = taf(in: bare),
           let answer = tafAnswer(taf, rest, words: words, now: now, rounds: rounds, said: talk.said[taf.key] ?? []) { return answer }
        switch bare {
        case "/v1/home": return (200, home(words: words, now: now, rounds: rounds, paused: talk.paused))
        case "/v1/me": return (200, me(words: words))
        case "/v1/me/card-exceptions": return (200, heldCalls(words: words, now: now, rounds: rounds))
        case "/v1/me/did-this-happen": return (200, json(["calls": []]))
        case "/v1/me/devices": return (200, devices(words: words, now: now))
        case "/v1/me/passkeys": return (200, json(["passkeys": []]))
        case "/v1/groups": return (200, json(["groups": []]))
        case "/v1/usage/balance": return (200, balance(words: words))
        case "/v1/usage/credits": return (200, credits(words: words, previous: path.contains("period=previous")))
        case "/v1/record": return (200, record(words: words, now: now, rounds: rounds))
        case "/v1/tenant/members": return (200, json(["members": []]))
        default: return (404, json(["error": "not_found", "words": notInSample(words)]))
        }
    }

    /// What the person said in a sample taf's chat, and the taf's reply.
    struct Said: Equatable {
        let text: String
        let reply: String
        let at: Date
    }

    /// What changes in the sample as the person talks to it: each taf's chat, and the tafs they paused.
    struct Talk: Equatable {
        var said: [String: [Said]] = [:]
        var paused: Set<String> = []
    }

    /// What a message asks of the taf, besides its reply.
    enum Turn: Equatable { case pause, resume, none }

    /// A sample taf's reply, as the iPad's `sampleReply`: from its own record, what it did lately and what waits for
    /// the owner, with the sample's note; or a pause, a return to work, or that only the owner gives it more room.
    static func reply(to text: String, taf: Taf, words: Words, rounds: Int = firstRounds) -> (String, Turn) {
        let lower = text.lowercased()
        if ["stop", "pause", "hold off"].contains(where: { lower.contains($0) }) {
            return (words("sample.reply.paused"), .pause)
        }
        if ["go", "carry on", "resume", "continue"].contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            return (words("sample.reply.back_to_work"), .resume)
        }
        if ["more", "raise", "limit", "bigger", "increase"].contains(where: { lower.contains($0) }) {
            return (words("sample.reply.more_room"), .none)
        }
        // Its own calls, newest first, as the Record has them: the last three.
        let done = made(rounds).reversed().filter { $0.0.key == taf.key }.prefix(3).map { "• " + $0.1.title(words) }
        let waiting = held(rounds: rounds).filter { $0.0.key == taf.key }.count
        var lines = [done.isEmpty ? words("sample.reply.nothing_done") : words("sample.reply.lately", ["done": done.joined(separator: "\n")])]
        if waiting > 0 { lines.append(words.count("sample.reply.waiting", waiting)) }
        lines.append(words("sample.reply.note"))
        return (lines.joined(separator: "\n\n"), .none)
    }

    /// The line for what the sample can't do, in the person's language, the shared one every app says: "This isn't in
    /// the sample. Sign in with KIFF to do it."
    static func notInSample(_ words: Words) -> String { words("sample.not_in_sample") }
}

/// tafs cloud and KIFF, stood in by the sample, in memory: what `Sample.answer` says, and never the network.
final class SampleTransport: Transport, @unchecked Sendable {
    /// The words the sample opened in.
    let words: Words
    let now: () -> Date
    /// Another language's words, asked for by a request's `Accept-Language`; nil answers every one in `words`.
    private let load: ((String) -> Words?)?
    private let lock = NSLock()
    private var played = Sample.firstRounds
    private var loaded: [String: Words] = [:]
    private var talked = Sample.Talk()
    /// Where the sample is kept between launches; nil keeps it this launch only.
    private let store: SampleStore?

    init(words: Words, now: @escaping () -> Date = Date.init, load: ((String) -> Words?)? = nil, store: SampleStore? = nil) {
        self.words = words
        self.now = now
        self.load = load
        self.store = store
        // Where the person left off, as the iPad's `restore`: the rounds played, its chats and what they paused.
        if let saved = store?.load() {
            played = min(max(saved.rounds, Sample.firstRounds), Sample.lastRound)
            talked.said = saved.said.mapValues { $0.map { Sample.Said(text: $0.text, reply: $0.reply, at: $0.at) } }
            talked.paused = Set(saved.paused).intersection(Sample.tafs.map(\.key))
        }
    }

    /// Keeps what changed, as the iPad's `save` after each change. Called with the lock held.
    private func keep() {
        store?.save(SampleStore.Saved(rounds: played, said: talked.said.mapValues { $0.map { .init(text: $0.text, reply: $0.reply, at: $0.at) } },
                                      paused: talked.paused.sorted()))
    }

    /// Clear the sample: what was kept goes too.
    func forget() {
        lock.lock(); defer { lock.unlock() }
        store?.clear()
    }

    /// The words a request is answered in: its `Accept-Language`, as tafs cloud and KIFF answer in it, so a language
    /// chosen in Account while in the sample reads in that language with the rounds played kept. One that can't be
    /// loaded is answered in the sample's own.
    func words(for request: HTTPRequest) -> Words {
        guard let language = request.headers["Accept-Language"], language != words.language, let load else { return words }
        lock.lock(); defer { lock.unlock() }
        if let known = loaded[language] { return known }
        let other = load(language) ?? words
        loaded[language] = other
        return other
    }

    /// The rounds played so far.
    var rounds: Int {
        lock.lock(); defer { lock.unlock() }
        return played
    }

    /// "Play the next sample actions", as the iPad's `playNextDemoActions()`: each taf plays its script's next call,
    /// up to the last. False when every script is played.
    @discardableResult
    func playNext() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard played < Sample.lastRound else { return false }
        played += 1
        keep()
        return true
    }

    /// What the person has said to the sample's tafs so far, and the tafs they paused.
    var talk: Sample.Talk {
        lock.lock(); defer { lock.unlock() }
        return talked
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let said = words(for: request)
        // A message to a sample taf: its reply, kept in memory with what was said, as the iPad's `sampleReply`. Nothing
        // else is written.
        if request.method == "POST", let (taf, rest) = Sample.taf(in: request.path), rest == "/messages" {
            struct Message: Decodable { let text: String }
            guard let text = (try? JSONDecoder().decode(Message.self, from: request.body))?.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return Sample.answer(method: request.method, path: request.path, words: said, now: now())
            }
            let at = now()
            let (reply, turn) = Sample.reply(to: text, taf: taf, words: said, rounds: rounds)
            let count: Int = {
                lock.lock(); defer { lock.unlock() }
                talked.said[taf.key, default: []].append(Sample.Said(text: text, reply: reply, at: at))
                switch turn {
                case .pause: talked.paused.insert(taf.key)
                case .resume: talked.paused.remove(taf.key)
                case .none: break
                }
                keep()
                return talked.said[taf.key]?.count ?? 0
            }()
            return (200, Sample.json(["session": "sample", "new_session": false, "message": ["id": "sample-said-\(count - 1)"]]))
        }
        return Sample.answer(method: request.method, path: request.path, words: said, now: now(), rounds: rounds, talk: talk)
    }
}
