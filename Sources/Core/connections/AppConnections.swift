import Foundation

/// "Your {app} connections": a connected app's connections, as the iPad's `AppConnectionsView`
/// (kiff/tafs `ios/Tafs/Views/ConnectAppsView.swift:488-722`) and the model it reads
/// (`AppModel.swift:7025-7083`). This Mac reads them from planque with its own signed read, as
/// the iPad's `PlanqueClient.grants(signedBy:)`. Ending one is signed here only on a Touch ID Mac
/// (`ConnectionEnding`); anything that grants access is approved on another device
/// (docs/connections.md).
enum AppConnections {
    /// One of the account's connections at planque, read as the iPad's `PlanqueClient.Grant`
    /// (`PlanqueClient.swift:115-330`), with only what this page draws. Read leniently: a field
    /// that doesn't read is none, and a grant with no id or status is left out.
    struct Grant: Decodable, Equatable, Identifiable {
        /// planque's own row for it (its rows): its health in plain words.
        struct Health: Decodable, Equatable {
            let ok: Bool
            let words: String
            enum CodingKeys: String, CodingKey { case ok, words }
            init(ok: Bool, words: String) { self.ok = ok; self.words = words }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ok = ((try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? nil) ?? false
                words = (((try? c.decodeIfPresent(String.self, forKey: .words)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        /// One of planque's actions that work for a connection now, as the iPad's
        /// `PlanqueClient.Grant.Action` (`PlanqueClient.swift:250-276`): its id, planque's words
        /// for it, how it's taken and what stops. Read leniently: what doesn't read is empty.
        struct Action: Decodable, Equatable, Identifiable {
            static let signInAgain = "sign_in_again", remove = "remove", removeUnfinished = "remove_unfinished"
            var id = ""
            var words = ""
            var how = ""
            var stops: String?
            enum CodingKeys: String, CodingKey { case id, words, how, stops }
            init(id: String = "", words: String = "", how: String = "", stops: String? = nil) {
                self.id = id; self.words = words; self.how = how; self.stops = stops
            }
            init(from decoder: Decoder) throws {
                guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
                func text(_ k: CodingKeys) -> String { (((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                id = text(.id); words = text(.words); how = text(.how)
                let s = text(.stops); stops = s.isEmpty ? nil : s
            }
            /// One this app knows how to take, with its words: anything else isn't drawn.
            var known: Bool {
                guard !words.isEmpty else { return false }
                switch id {
                case Self.signInAgain: return how == "approve" || how == "key"
                case Self.remove, Self.removeUnfinished: return how == "delete"
                default: return false
                }
            }
            /// It ends the connection: asked first, in planque's words.
            var removes: Bool { id == Self.remove || id == Self.removeUnfinished }
        }

        let id: String
        /// pending, approved, signed_in, listed, connected, failed, disconnected or needs_reconnect.
        let status: String
        /// planque's words for its status, drawn as sent.
        let statusWords: String?
        /// The connection's name for people ("Gmail · Demo Shop"), drawn as sent.
        let title: String?
        /// The account at the vendor: a name only for a connection that isn't a provider's.
        let account: String?
        /// The KIFF agent that asked for it: which taf it was made for.
        let agent: String
        /// A managed provider's connection.
        let throughProvider: Bool
        /// `api_key` for a vendor reached with a key.
        let kind: String?
        /// The vendor's name as planque gives it, else its server.
        let vendor: String
        /// The catalog entry it was connected from.
        let entry: String?
        /// The name of the taf it was made for, as planque keeps it.
        let agentName: String?
        /// The tafs that use it, by name, as planque sends them.
        let usedBy: [String]?
        let health: Health?
        /// The actions that work for it now, as planque sends them; nil when it sends none.
        let actions: [Action]?
        /// Whether planque sent the actions that work for it now: with its health, planque draws the row.
        var hasActions: Bool { actions != nil }
        /// The actions this app draws, in planque's order (the iPad's `actions.filter(\.known)`).
        var knownActions: [Action] { (actions ?? []).filter(\.known) }
        let signedIn: Bool?
        /// The tools it was asked for (`request.tools`), as the iPad's `Grant.Request.Tool`: each
        /// with its name in KIFF and the title Setup asked for it by. One that doesn't read is
        /// left out, never the grant.
        var tools: [Tool] = []
        /// The tools planque says the connection holds, by their actions, when it sends them.
        var heldTools: [String]?

        /// The Card actions it connects, as the iPad's `g.tools ?? request.tools.filter(\.tafs).map(\.action)`.
        var cardActions: Set<String> { Set(heldTools ?? tools.filter(\.tafs).map(\.action)) }

        /// A tool a grant was asked for, as the iPad's `PlanqueClient.Grant.Request.Tool`.
        struct Tool: Decodable, Equatable {
            let tool: String
            let name: String?
            /// What it does, in the owner's words, as Setup asked for it.
            let title: String?
            /// Setup's own read, not one of the taf's tools.
            var setupReads = false
            enum CodingKeys: String, CodingKey { case tool, name, title, setupReads = "setup_reads" }
            init(tool: String, name: String? = nil, title: String? = nil) { self.tool = tool; self.name = name; self.title = title }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                tool = try c.decode(String.self, forKey: .tool)
                name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
                title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
                setupReads = ((try? c.decodeIfPresent(Bool.self, forKey: .setupReads)) ?? nil) == true
            }
            /// One of the taf's own tools, as the iPad's `tafs`: not Setup's read.
            var tafs: Bool { !setupReads }
            /// Its name in KIFF and at the relay: the Card's action.
            var action: String { name ?? tool }
        }

        enum CodingKeys: String, CodingKey {
            case id, status, title, account, request, health, actions, entry, heldTools = "tools"
            case statusWords = "status_words", vendorName = "vendor", agentName = "agent_name", usedBy = "used_by", signedIn = "signed_in"
        }
        enum RequestKeys: String, CodingKey { case server, agent, connector, kind, tools }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) -> String? {
                guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            id = try c.decode(String.self, forKey: .id)
            status = try c.decode(String.self, forKey: .status)
            statusWords = text(.statusWords)
            title = text(.title)
            account = text(.account)
            entry = text(.entry)
            agentName = text(.agentName)
            usedBy = (try? c.decodeIfPresent([String].self, forKey: .usedBy)) ?? nil
            health = (try? c.decodeIfPresent(Health.self, forKey: .health)) ?? nil
            actions = (try? c.decodeIfPresent([Action].self, forKey: .actions)) ?? nil
            signedIn = (try? c.decodeIfPresent(Bool.self, forKey: .signedIn)) ?? nil
            let request = try? c.nestedContainer(keyedBy: RequestKeys.self, forKey: .request)
            let server = ((try? request?.decodeIfPresent(String.self, forKey: .server)) ?? nil) ?? ""
            agent = ((try? request?.decodeIfPresent(String.self, forKey: .agent)) ?? nil) ?? ""
            throughProvider = request?.contains(.connector) == true && ((try? request?.decodeNil(forKey: .connector)) ?? true) == false
            kind = (try? request?.decodeIfPresent(String.self, forKey: .kind)) ?? nil
            vendor = text(.vendorName) ?? server
            struct Lenient: Decodable {
                let tool: Tool?
                init(from decoder: Decoder) throws { tool = try? Tool(from: decoder) }
            }
            tools = (((try? request?.decodeIfPresent([Lenient].self, forKey: .tools)) ?? nil) ?? []).compactMap(\.tool)
            heldTools = (try? c.decodeIfPresent([String].self, forKey: .heldTools)) ?? nil
        }

        /// planque draws this connection's row: its health and its actions.
        var rowFromPlanque: Bool { !(health?.words.isEmpty ?? true) && hasActions }
        /// What its row is called: planque's title, else the account it names (never a
        /// provider's id), else nil and the row says the app.
        var name: String? {
            if let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
            if !throughProvider, let a = account?.trimmingCharacters(in: .whitespaces), !a.isEmpty { return a }
            return nil
        }
        var connected: Bool { status == "connected" }
        /// planque holds its sign-in and reads what the vendor offers, as the iPad's `listed`.
        var listed: Bool { status == "listed" }
        /// planque failed it, or it was ended: its card says so, as the iPad's `setupCardState`.
        var failed: Bool { status == "failed" || status == "disconnected" }
        var needsReconnect: Bool { status == "needs_reconnect" }
        var takesKey: Bool { kind == "api_key" }
        /// A provider's connection isn't signed in again in place.
        var signsInThroughProvider: Bool { throughProvider && connected && !takesKey }
        /// Approved, and waiting on a sign-in that hasn't come back.
        var waitingSignIn: Bool { status == "approved" && signedIn != true }
        /// A sign-in planque holds that no taf uses yet.
        var holdsSignIn: Bool { status == "listed" || (status == "pending" && signedIn == true) }
        /// A request nobody answered yet.
        var pendingRequest: Bool { status == "pending" && !holdsSignIn }
        /// Ended with Cancel, not Remove access.
        var cancellable: Bool { waitingSignIn || pendingRequest }
    }

    /// An app's connections for one taf, under its name.
    struct Group: Identifiable, Equatable {
        /// The KIFF agent that asked for them.
        let id: String
        let taf: String
        var grants: [Grant]
    }

    /// A tool's title from its approval, as the iPad's `AppModel.toolTitle` (AppModel.swift:5849-5852):
    /// the first grant tool whose action is this name, by the title Setup asked for it by. Nil
    /// when none has one: the tool is then said in words (`CallNames.toolWords`).
    static func toolTitle(_ name: String, in grants: [Grant]) -> String? {
        guard let title = grants.lazy.flatMap(\.tools).first(where: { $0.action == name })?.title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return title
    }

    /// The account's live connections to an app, as the iPad's `connections(of:in:)`
    /// (`AppModel.swift:7031-7033`): by its entry, or the grant tafs cloud named for it.
    static func connections(of app: Apps.App, in grants: [Grant]) -> [Grant] {
        grants.filter { ($0.entry == app.entry || (app.grant != nil && $0.id == app.grant)) && !["disconnected", "failed"].contains($0.status) }
    }

    /// Whether an app's row opens its connections, as the iPad's `opensConnections`
    /// (`AppModel.swift:7039-7041`): connected, or holding a connection on this account.
    static func opens(_ app: Apps.App, in grants: [Grant]) -> Bool {
        app.isConnected || !connections(of: app, in: grants).isEmpty
    }

    /// An app's connections grouped by the taf each was made for, as the iPad's
    /// `connectionGroups` (`AppModel.swift:7063-7083`): tafs with one needing attention first, then
    /// the rest by name; then those of tafs tafs cloud names as removed; then the others, whose taf
    /// this app can't name (never taken as removed without tafs cloud's word).
    static func groups(_ grants: [Grant], taf: (Grant) -> String?, removed: Set<String> = [])
        -> (tafs: [Group], removed: [Grant], others: [Grant]) {
        var groups: [Group] = []
        var gone: [Grant] = []
        var others: [Grant] = []
        for g in grants {
            guard let name = taf(g) else {
                if removed.contains(g.agent) { gone.append(g) } else { others.append(g) }
                continue
            }
            if let i = groups.firstIndex(where: { $0.id == g.agent }) {
                groups[i].grants.append(g)
            } else {
                groups.append(Group(id: g.agent, taf: name, grants: [g]))
            }
        }
        // The iPad's attention also counts a last failed call, which this Mac doesn't read yet.
        let needs = Set(groups.filter { $0.grants.contains { $0.waitingSignIn || $0.needsReconnect } }.map(\.id))
        groups.sort { a, b in
            let (x, y) = (needs.contains(a.id), needs.contains(b.id))
            if x != y { return x }
            let order = a.taf.localizedCaseInsensitiveCompare(b.taf)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
        return (groups, gone, others)
    }

    /// The taf a connection was made for, by name, from the tafs listed (`Home.Taf`, by KIFF
    /// agent), as the iPad's `tafOf`; nil when this app can't name it.
    /// The other tafs whose Card draws on a connection's tools, as the iPad's `alsoStops` and `tafsUsing`: a live,
    /// active Card's rule on one of the actions it connects. KIFF's tools are the account's, so a taf can draw on a
    /// connection another taf asked for; the one it was made for is left out. By name, in Home's order.
    static func alsoOn(_ grant: Grant, in tafs: [Home.Taf]) -> [String] {
        let actions = grant.cardActions
        guard !actions.isEmpty else { return [] }
        return tafs.filter { taf in
            taf.kiffAgent != grant.agent
                && taf.cards.contains { $0.active && $0.rules.contains { $0.action.map(actions.contains) == true } }
        }.map(\.name)
    }

    /// "Also on Refunds' Card", "Also on the Cards of Refunds and Leads", as the iPad's `alsoOnCards`; nil with none.
    static func alsoOnLine(_ names: [String], _ say: Words) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return say("connect.apps.also_on_one", ["owner": names[0]])
        default: return say("connect.apps.also_on_many", ["tafs": say.list(names)])
        }
    }

    /// A connection's last failed call, as the iPad's `lastFailure` (gap 13): the newest call through one of its tools
    /// that wasn't done, its own taf's first, in tafs cloud's words for it ("Last failed: Refund · Stripe didn't answer").
    /// Nil when none is in the Record read.
    static func lastFailure(_ grant: Grant, record: [Record.Entry], ownTaf: String?, _ say: Words) -> String? {
        let actions = grant.cardActions
        guard !actions.isEmpty else { return nil }
        let failed = record.filter { $0.kind == "not_done" && $0.action.map(actions.contains) == true }
        let own = failed.filter { $0.taf.id == ownTaf }
        guard let last = (own.isEmpty ? failed : own).max(by: { $0.at < $1.at }) else { return nil }
        return say("connect.last_failed", ["title": last.title, "detail": last.detail])
    }

    /// The tafs cloud id of the taf a connection was made for, as Home lists it.
    static func tafID(of grant: Grant, in tafs: [Home.Taf]) -> String? {
        tafs.first { $0.kiffAgent == grant.agent }?.tafID
    }

    static func taf(of grant: Grant, in tafs: [Home.Taf]) -> String? {
        tafs.first { $0.kiffAgent == grant.agent }?.name
    }

    /// What tafs cloud says of each removed taf's connection, by grant (`removedListed`).
    static func removedListed(_ removed: [Apps.RemovedTaf]) -> [String: Apps.RemovedTaf.Grant] {
        Dictionary(removed.flatMap { $0.grants ?? [] }.map { ($0.grant, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The removed tafs' connections Clear would end: only those tafs cloud lists with no taf using them.
    static func clearable(_ removed: [Grant], listed: [String: Apps.RemovedTaf.Grant]) -> [String] {
        removed.filter { listed[$0.id]?.usedBy.isEmpty == true }.map(\.id)
    }

    /// Under a removed taf's connection: the tafs whose Cards still use it, as the iPad's
    /// `ConnectionGroupWords.usedBy`; nil when none.
    static func keptLine(_ names: [String], _ say: Words) -> String? {
        var seen = Set<String>()
        let n = names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0).inserted }
        guard !n.isEmpty else { return nil }
        return n.count == 1 ? say("connect.used_by.one", ["name": n[0]]) : say("connect.used_by.many", ["names": say.list(n)])
    }

    /// Disconnect's question, as the iPad's `DisconnectWords.title` (`ConnectAppsView.swift:481-486`):
    /// it names the one taf it ends, else the vendor alone, then `alsoStops`, the other tafs whose
    /// Card draws on its tools.
    static func disconnectTitle(_ vendor: String, taf: String?, alsoStops: [String] = [], _ say: Words) -> String {
        let asked = taf.map { say("connect.disconnect.title_from", ["vendor": vendor, "taf": $0]) } ?? say("connect.disconnect.title", ["vendor": vendor])
        guard !alsoStops.isEmpty else { return asked }
        return asked + " " + say.count("connect.disconnect.also_stops", alsoStops.count, ["names": say.list(alsoStops)])
    }

    /// What removing access ends, as the iPad's `DisconnectWords.message` (`:490-501`): the taf's
    /// tools, the other Cards that stop, then what happens to the sign-in, or for a key (`key`),
    /// that it's deleted from tafs once no taf uses it.
    static func disconnectMessage(_ vendor: String, taf: String?, alsoStops: [String] = [], key: Bool = false, _ say: Words) -> String {
        let others: String
        switch alsoStops.count {
        case 0: others = ""
        case 1: others = " " + say("connect.disconnect.also_card", ["owner": alsoStops[0]])
        default: others = " " + say("connect.disconnect.also_cards", ["names": say.list(alsoStops)])
        }
        let start = taf.map { say("connect.disconnect.tools_stop", ["owner": $0, "vendor": vendor]) } ?? say("connect.disconnect.no_taf_uses", ["vendor": vendor])
        let rest = key ? " " + say("connect.disconnect.rest_key", ["vendor": vendor])
            : say("connect.other_connections_stay_connected_no", ["vendor": vendor, "vendor_2": vendor]) + say("connect.connecting_again_asks_you_approve")
        return start + others + rest
    }

    /// What's cancelled, asked first, as the iPad's `ConnectionFixWords.cancelTitle`: the request
    /// nobody answered, or the sign-in that never came back.
    static func cancelTitle(_ g: Grant, _ say: Words) -> String {
        say(g.pendingRequest ? "connect.cancel_request.title" : "connect.cancel_sign_in.title", ["vendor": g.vendor])
    }

    /// The cancel question's own button, as the iPad's `ConnectionFixWords.cancelWord`.
    static func cancelWordKey(_ g: Grant) -> String {
        g.pendingRequest ? "connect.cancel_request.button" : "connect.cancel_sign_in.button"
    }

    /// The word for ending a connection, as the iPad's `ConnectionFixWords.endWord`: "Cancel the
    /// request" for one nobody answered, Cancel for a sign-in that waits, else Remove access.
    static func endKey(_ g: Grant) -> String {
        g.pendingRequest ? "connect.cancel_request.button" : g.waitingSignIn ? "common.cancel" : "connect.disconnect_button"
    }
}

/// Where this Mac reads its connections: planque, with a read signed by this Mac's device key,
/// as the iPad's `grants(signedBy:)`. It signs a read, asking no one, as Coach's read of the same
/// proof does. On a Mac whose device key is in the Secure Enclave it can also end one connection
/// (`end`), only once the person passed Touch ID (`ConnectionEnding`); it never approves,
/// connects or signs in again.
struct ConnectionsSource {
    /// What carries the read to planque.
    let transport: Transport
    let tenant: String
    var language = "en"
    /// This Mac's signed read of its grants (`PlanqueClient.grantsReadProof`), fresh each time:
    /// planque takes each once. Nil: this Mac can't sign one.
    let proof: () async -> String?
    /// The session's device key is in the Secure Enclave: with Touch ID, this Mac ends a
    /// connection itself (`ConnectionEnding.route`). A software key never does.
    let enclaveKey: Bool
    /// Ends one connection at planque (`PlanqueClient.disconnect`), signed by the device key; nil
    /// ends none here. Called only after Touch ID (`ConnectionEnding.end`).
    let end: ((String) async throws -> Void)?

    init(transport: Transport, tenant: String, language: String = "en", proof: @escaping () async -> String?,
         enclaveKey: Bool = false, end: ((String) async throws -> Void)? = nil) {
        self.transport = transport
        self.tenant = tenant
        self.language = language
        self.proof = proof
        self.enclaveKey = enclaveKey
        self.end = end
    }

    /// The Mac's own: signed with the session's device key, with this device's id.
    init(account: AccountClient, planque: PlanqueClient, transport: Transport) {
        let tenant = account.session.tenant
        self.init(transport: transport, tenant: tenant, language: account.language, proof: { [account, planque] in
            guard let sign = account.signMessage else { return nil }
            planque.tenant = tenant
            return try? await planque.grantsReadProof(signedBy: sign)
        }, enclaveKey: account.keyStore == "enclave", end: { [account, planque, transport] id in
            guard let sign = account.signMessage else { throw PlanqueClient.PlanqueError.notSigning }
            planque.tenant = tenant
            try await planque.disconnect(grantID: id, signedBy: sign, over: transport)
        })
    }

    /// Why the connections weren't read.
    enum Unread: Error, Equatable {
        /// This Mac has no signed read to give: no device key in the session, or no device id.
        case notSigning
    }

    /// The path read: the account's grants, its tenant escaped as one segment.
    var path: String { "/v1/accounts/\(CloudClient.escaped(tenant))/grants" }

    /// The account's connections. A grant that doesn't read is left out; an answer with no list
    /// is unreadable, never "no connections".
    func grants() async throws -> [AppConnections.Grant] {
        guard let signature = await proof() else { throw Unread.notSigning }
        let request = HTTPRequest(method: "GET", path: path, headers: [
            "Accept": "application/json", "User-Agent": "tafs-macos", "Accept-Language": language,
            // This Mac's zone, for the times in planque's words; not part of what's signed.
            "X-Time-Zone": TimeZone.current.identifier,
            "Planque-Device-Signature": signature,
        ])
        let (status, body) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            let said = PlanqueClient.refusal(body)
            throw PlanqueClient.PlanqueError.server(status: status, message: said.error ?? "", words: said.words)
        }
        struct Lenient: Decodable {
            let grant: AppConnections.Grant?
            init(from decoder: Decoder) throws { grant = try? AppConnections.Grant(from: decoder) }
        }
        struct Answer: Decodable { let grants: [Lenient] }
        guard let answer = try? AccountClient.decoder.decode(Answer.self, from: body) else { throw KIFFError.unreadable }
        return answer.grants.compactMap(\.grant)
    }
}
