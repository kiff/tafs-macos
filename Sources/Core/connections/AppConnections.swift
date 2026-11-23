import Foundation

/// "Your {app} connections": a connected app's connections, as the iPad's `AppConnectionsView`
/// (kiff/tafs `ios/Tafs/Views/ConnectAppsView.swift:488-722`) and the model it reads
/// (`AppModel.swift:7025-7083`). This Mac reads them from planque with its own signed read, as
/// the iPad's `PlanqueClient.grants(signedBy:)`, and only reads: anything that changes a
/// connection is approved on another device (docs/connections.md).
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
        /// Whether planque sent the actions that work for it now: with its health, planque draws the row.
        let hasActions: Bool
        let signedIn: Bool?
        /// The tools it was asked for (`request.tools`), as the iPad's `Grant.Request.Tool`: each
        /// with its name in KIFF and the title Setup asked for it by. One that doesn't read is
        /// left out, never the grant.
        var tools: [Tool] = []

        /// A tool a grant was asked for, as the iPad's `PlanqueClient.Grant.Request.Tool`.
        struct Tool: Decodable, Equatable {
            let tool: String
            let name: String?
            /// What it does, in the owner's words, as Setup asked for it.
            let title: String?
            enum CodingKeys: String, CodingKey { case tool, name, title }
            init(tool: String, name: String? = nil, title: String? = nil) { self.tool = tool; self.name = name; self.title = title }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                tool = try c.decode(String.self, forKey: .tool)
                name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
                title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
            }
            /// Its name in KIFF and at the relay: the Card's action.
            var action: String { name ?? tool }
        }

        enum CodingKeys: String, CodingKey {
            case id, status, title, account, request, health, actions, entry
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
            hasActions = c.contains(.actions) && ((try? c.decodeNil(forKey: .actions)) ?? true) == false
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

    /// The word for ending a connection, as the iPad's `ConnectionFixWords.endWord`: "Cancel the
    /// request" for one nobody answered, Cancel for a sign-in that waits, else Remove access.
    static func endKey(_ g: Grant) -> String {
        g.pendingRequest ? "connect.cancel_request.button" : g.waitingSignIn ? "common.cancel" : "connect.disconnect_button"
    }
}

/// Where this Mac reads its connections: planque, with a read signed by this Mac's device key,
/// as the iPad's `grants(signedBy:)`. It signs a read only, asking no one, as Coach's read of
/// the same proof does; nothing here approves or changes a connection.
struct ConnectionsSource {
    /// What carries the read to planque.
    let transport: Transport
    let tenant: String
    var language = "en"
    /// This Mac's signed read of its grants (`PlanqueClient.grantsReadProof`), fresh each time:
    /// planque takes each once. Nil: this Mac can't sign one.
    let proof: () async -> String?

    init(transport: Transport, tenant: String, language: String = "en", proof: @escaping () async -> String?) {
        self.transport = transport
        self.tenant = tenant
        self.language = language
        self.proof = proof
    }

    /// The Mac's own: signed with the session's device key, with this device's id.
    init(account: AccountClient, planque: PlanqueClient, transport: Transport) {
        let tenant = account.session.tenant
        self.init(transport: transport, tenant: tenant, language: account.language, proof: { [account, planque] in
            guard let sign = account.signMessage else { return nil }
            planque.tenant = tenant
            return try? await planque.grantsReadProof(signedBy: sign)
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
