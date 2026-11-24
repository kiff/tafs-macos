import Foundation

/// planque, which keeps a taf's vendor sign-ins so they never reach this Mac, tafs cloud, the
/// agent or KIFF, as the iPad's `PlanqueClient`. This Mac asks three things of it: its proof
/// that this device reads its own account's grants (`grantsReadProof`), which tafs cloud
/// forwards with a taf's Setup read; this device's enrolment (`enrol`); and, on a Mac whose
/// device key is in the Secure Enclave, after a Touch ID-only check, the end of one connection
/// (`disconnect`), which takes access away and grants none. Each request is signed by the device
/// key with this device's id (`Planque-Device-Signature`). It never approves or confirms a
/// grant, sends a key or connects one (`routes`; docs/approvals.md).
final class PlanqueClient {
    enum PlanqueError: Error, Equatable {
        case notSigning
        /// This device's id in KIFF couldn't be read: planque takes no signature without it, so
        /// nothing is sent.
        case noDevice
        /// Asked with no connector key, planque holds none that still stands (`409 needs_key`):
        /// the one answer on which this Mac mints a key, as the iPad's `PlanqueError.needsKey`.
        case needsKey
        /// planque refused: its status, its `error` for the log, and its own `words` for the
        /// person when it sends some, as the iPad's `PlanqueError.server`.
        case server(status: Int, message: String, words: String?)
    }

    /// The only routes under the account `send` signs at planque: its enrolment. Never a
    /// grant's `approve` or `confirm`, the iPad's two routes under a grant: this Mac
    /// approves nothing at planque, so `send` refuses any other path before anything is signed or
    /// sent. Adding one is a change to this list, which `PlanqueRoutesTests` pins. Ending a
    /// connection (`disconnect`) is its own method, `DELETE` only, which `PlanqueRoutesTests` pins too.
    static let routes: Set<String> = ["enrolment"]

    /// planque's address, as the iPad's `baseURL`.
    static let baseURL = "https://planque.kiff.dev"
    /// The SHA-256 of an empty body, in hex: a read's body.
    static let emptyBodyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    let baseURL: String
    /// The account, by KIFF's tenant; nil signs nothing.
    var tenant: String?
    /// This device's id in KIFF's Devices list (`dev_…`), once read.
    var deviceID: String?
    /// Reads `deviceID` when it isn't known: KIFF's `this_device`, only for a session with a key.
    var deviceLoader: (() async -> String?)?
    /// What carries a request to planque; nil sends nothing.
    var transport: Transport?
    /// Signs one of planque's messages with the device key, in standard base64: set while a step
    /// the person confirmed runs, as the iPad's `signer`. Nil sends nothing.
    var signer: ((String) throws -> String)?
    /// The SHA-256 of a body, in hex, for what is signed (the app's `Signing.sha256Hex`).
    var bodyHash: ((Data) -> String)?
    /// planque's `code` on the last refusal, or nil when it sent none, as the iPad's
    /// `lastRefusalCode`: a 409 an older planque sent with no code at enrolment is another
    /// device's; today's planque names each of its own (`signature_replayed`, …).
    private(set) var lastRefusalCode: String?

    init(baseURL: String = PlanqueClient.baseURL) { self.baseURL = baseURL }

    /// What the device signs for a request to planque (planque's `device.Message`): seven lines,
    /// the base with no trailing slash, and the body's SHA-256 in hex.
    static func message(base: String, tenant: String, method: String, uri: String, bodyHash: String, signedAt: String) -> String {
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        return ["planque.request.v1", b, tenant, method, uri, bodyHash, signedAt].joined(separator: "\n")
    }

    // MARK: Enrolment

    /// planque's record of this device's enrolment, as the iPad's `Enrolment`.
    struct Enrolment: Decodable, Equatable {
        let tenant: String
        /// The device key's fingerprint, as planque shows it in its record.
        let device: String
        /// The connector key planque holds still stands, so it kept it and took no new one.
        var kept: Bool?
    }

    /// Hands planque the KIFF connector key it keeps to register tools, as the iPad's
    /// `enrol(deviceKey:connectorKey:)` (`PlanqueClient.swift:107-111`). The device's key goes
    /// too, for a planque that enrols one device by its key. With no `connectorKey`, it only asks
    /// whether the enrolled key still stands: planque answers `kept`, or refuses (`needs_key`)
    /// and keeps nothing.
    func enrol(deviceKey: Data, connectorKey: String?) async throws -> Enrolment {
        var body = ["device_key": deviceKey.base64EncodedString()]
        if let connectorKey { body["connector_key"] = connectorKey }
        return try await send("POST", "enrolment", body: body)
    }

    /// One signed request to the account's routes at planque, as the iPad's `raw`
    /// (`PlanqueClient.swift:637-694`): the device key signs the method, the path as sent, the
    /// body's hash and the time, with this device's id; never a key alone. A refusal keeps
    /// planque's `code`; `409 needs_key` is `needsKey`.
    private func send<Answer: Decodable>(_ method: String, _ path: String, body: [String: String]) async throws -> Answer {
        // Only the routes this Mac may sign (`routes`): never a grant's approve or confirm.
        guard Self.routes.contains(path) else { throw PlanqueError.notSigning }
        guard let tenant else { throw PlanqueError.notSigning }
        guard let signer, let bodyHash, let transport else { throw PlanqueError.notSigning }
        let account = "/v1/accounts/\(CloudClient.escaped(tenant))"
        let uri = path.isEmpty ? account : "\(account)/\(path)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(body)
        // planque asks KIFF whether this device signed: never a key alone.
        if deviceID == nil, let load = deviceLoader { deviceID = await load() }
        guard let device = deviceID else { throw PlanqueError.noDevice }
        let at = SigningTime.next()
        let message = Self.message(base: baseURL, tenant: tenant, method: method, uri: uri, bodyHash: bodyHash(bytes), signedAt: at)
        let request = HTTPRequest(method: method, path: uri, headers: [
            "Accept": "application/json", "Content-Type": "application/json", "User-Agent": "tafs-macos",
            // This Mac's zone, for the times in planque's words; not part of what's signed.
            "X-Time-Zone": TimeZone.current.identifier,
            "Planque-Device-Signature": "t=\(at),v1=\(try signer(message)),d=\(device)",
        ], body: bytes)
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            lastRefusalCode = Self.refusalCode(answer)
            if status == 409, lastRefusalCode == "needs_key" { throw PlanqueError.needsKey }
            let said = Self.refusal(answer)
            throw PlanqueError.server(status: status, message: said.error ?? "", words: said.words)
        }
        guard let read = try? AccountClient.decoder.decode(Answer.self, from: answer) else { throw KIFFError.unreadable }
        return read
    }

    /// planque's `error` and its `words` for the person on a refusal, when it sends them as text
    /// that isn't blank, as the iPad's `refusal` (`PlanqueClient.swift:612-619`).
    static func refusal(_ data: Data) -> (error: String?, words: String?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        func line(_ key: String) -> String? {
            guard let s = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        return (line("error"), line("words"))
    }

    /// planque's machine-readable `code` on a refusal, when it sends one as text, as the iPad's
    /// `refusalCode` (`PlanqueClient.swift:622-624`).
    static func refusalCode(_ data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["code"] as? String
    }

    // MARK: Ending a connection

    /// Ends one connection at planque, as the iPad's `disconnect(grantID:)`
    /// (`PlanqueClient.swift:598-600`): `DELETE` of the grant, with no body, signed v1 by the device
    /// key with this device's id. It takes access away and grants none: planque removes its tools
    /// from KIFF and signs out at the vendor. The only grant route this Mac signs, and only once
    /// the person passed Touch ID (`ConnectionEnding`, docs/approvals.md). Its signer comes with
    /// the call, so the client's own `signer` stays armed only around the enrolment. A grant
    /// planque already ended answers 200 too.
    func disconnect(grantID: String, signedBy sign: (String) throws -> String, over transport: Transport) async throws {
        guard let tenant, !grantID.isEmpty else { throw PlanqueError.notSigning }
        if deviceID == nil, let load = deviceLoader { deviceID = await load() }
        guard let device = deviceID else { throw PlanqueError.noDevice }
        let uri = Self.disconnectPath(tenant: tenant, grantID: grantID)
        let at = SigningTime.next()
        // No body, as the iPad's: the empty body's hash is what's signed, and no Content-Type.
        let message = Self.message(base: baseURL, tenant: tenant, method: "DELETE", uri: uri, bodyHash: Self.emptyBodyHash, signedAt: at)
        let request = HTTPRequest(method: "DELETE", path: uri, headers: [
            "Accept": "application/json", "User-Agent": "tafs-macos",
            // This Mac's zone, for the times in planque's words; not part of what's signed.
            "X-Time-Zone": TimeZone.current.identifier,
            "Planque-Device-Signature": "t=\(at),v1=\(try sign(message)),d=\(device)",
        ])
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            lastRefusalCode = Self.refusalCode(answer)
            let said = Self.refusal(answer)
            throw PlanqueError.server(status: status, message: said.error ?? "", words: said.words)
        }
    }

    /// The one grant's path this Mac signs, as the iPad's and Windows' `DisconnectPath`: the
    /// account and the grant, each escaped as one segment.
    static func disconnectPath(tenant: String, grantID: String) -> String {
        "/v1/accounts/\(CloudClient.escaped(tenant))/grants/\(CloudClient.escaped(grantID))"
    }

    /// planque's safe routes this Mac signs, as Linux's `planque::Safe` (tafs-linux#89): Account › Chrome's list, and
    /// unpairing one Chrome, which takes authority away (planque ends its connections, "Your Chrome" 3). Each is a GET or
    /// a DELETE with an empty body, signed per call by the device key (`planque.request.v1`), never through the armed
    /// `signer`, and never with a session token. Nothing here approves, confirms or pairs: pairing a Chrome stays the
    /// phone's, as it binds the phone's approval key.
    enum Safe: Equatable {
        case chromes
        case unpairChrome(String)
        /// The pictures kept for one operation's Chrome steps, without their bytes (`ChromeShots`): a read.
        case chromeShots(operation: String)
        /// One step's picture: a read.
        case chromeShot(step: String)
        /// Stops an app-event subscription (a Slack door's channel), as the iPad's `unsubscribe`: planque turns its
        /// delivery off, then removes it upstream. It takes authority away, so the device key signs it (planque's safe
        /// routes, docs/api.md).
        case deleteTrigger(grant: String, trigger: String)

        var method: String {
            switch self {
            case .chromes, .chromeShots, .chromeShot: return "GET"
            case .unpairChrome: return "DELETE"
            case .deleteTrigger: return "DELETE"
            }
        }

        /// Under the account's routes. The operation is escaped into the query, which is part of what's signed.
        var path: String {
            switch self {
            case .chromes: return "chromes"
            case .unpairChrome(let id): return "chromes/\(CloudClient.escaped(id))"
            case .chromeShots(let operation): return "chromes/screenshots?op=\(ChromeShots.queryEscaped(operation))"
            case .chromeShot(let step): return "chromes/screenshots/\(CloudClient.escaped(step))"
            case .deleteTrigger(let grant, let trigger): return "grants/\(CloudClient.escaped(grant))/triggers/\(CloudClient.escaped(trigger))"
            }
        }
    }

    /// One safe route, signed by `sign` (the device key) for this one request. planque's answer, else its refusal.
    func safe(_ route: Safe, signedBy sign: (String) throws -> String) async throws -> Data {
        guard let tenant, let transport else { throw PlanqueError.notSigning }
        if deviceID == nil, let load = deviceLoader { deviceID = await load() }
        guard let device = deviceID else { throw PlanqueError.noDevice }
        let uri = "/v1/accounts/\(CloudClient.escaped(tenant))/\(route.path)"
        let at = SigningTime.next()
        let message = Self.message(base: baseURL, tenant: tenant, method: route.method, uri: uri, bodyHash: Self.emptyBodyHash, signedAt: at)
        let request = HTTPRequest(method: route.method, path: uri, headers: [
            "Accept": "application/json", "User-Agent": "tafs-macos", "X-Time-Zone": TimeZone.current.identifier,
            "Planque-Device-Signature": "t=\(at),v1=\(try sign(message)),d=\(device)",
        ])
        let (status, answer) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            let said = Self.refusal(answer)
            throw PlanqueError.server(status: status, message: said.error ?? "", words: said.words)
        }
        return answer
    }

    /// A Chrome paired to the account, as planque lists it: its name, and the browser and system its extension reported.
    struct Chrome: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        var browser: String?
        var os: String?
        /// The browser connections that run in this Chrome, as planque lists them ("Your Chrome" 3 and 4): live ones only, decided
        /// there, never by the app. nil from a planque that doesn't list them, or a list that doesn't read: never a broken Chrome.
        var connections: [Connection]?
        enum CodingKeys: String, CodingKey { case id = "chrome_id", name, browser, os, connections }

        /// One connection run in a Chrome, as the iPad's `PlanqueClient.Chrome.Connection`: its grant, its taf's name and its sites.
        struct Connection: Decodable, Equatable {
            let grant: String
            var name = ""
            var sites: [String] = []
            enum CodingKeys: String, CodingKey { case grant, name, sites }
            init(grant: String, name: String = "", sites: [String] = []) { self.grant = grant; self.name = name; self.sites = sites }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                grant = try c.decode(String.self, forKey: .grant)
                name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
                sites = ((try? c.decodeIfPresent([String].self, forKey: .sites)) ?? nil) ?? []
            }
        }

        init(id: String, name: String, browser: String? = nil, os: String? = nil, connections: [Connection]? = nil) {
            self.id = id; self.name = name; self.browser = browser; self.os = os; self.connections = connections
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            browser = (try? c.decodeIfPresent(String.self, forKey: .browser)) ?? nil
            os = (try? c.decodeIfPresent(String.self, forKey: .os)) ?? nil
            connections = (try? c.decodeIfPresent([Connection].self, forKey: .connections)) ?? nil
        }

        /// The sites of its connections, as the owner reads them ("wikipedia.org, shop.example"), each once, in planque's order, as
        /// the iPad's `ChromeConnections.sites`: what the row says it's used for, and what unpairing ends. Empty when none.
        var sites: String {
            var seen: [String] = []
            for site in (connections ?? []).flatMap(\.sites) where !seen.contains(site) { seen.append(site) }
            return seen.joined(separator: ", ")
        }
    }

    /// The Chromes paired to the account; nil while planque doesn't offer them (404), or this person may only view (403),
    /// and Account shows no Chrome row, as the iPad's `chromes` nil.
    func chromes(signedBy sign: (String) throws -> String) async throws -> [Chrome]? {
        do {
            struct List: Decodable { let chromes: [Lenient] }
            struct Lenient: Decodable { let chrome: Chrome?; init(from decoder: Decoder) throws { chrome = try? Chrome(from: decoder) } }
            let data = try await safe(.chromes, signedBy: sign)
            guard let list = try? JSONDecoder().decode(List.self, from: data) else { throw KIFFError.unreadable }
            return list.chromes.compactMap(\.chrome)
        } catch PlanqueError.server(let status, _, _) where status == 404 || status == 403 {
            return nil
        }
    }

    /// The device signs its own read; the cloud only forwards this proof.
    func grantsReadProof(signedBy sign: (String) throws -> String) async throws -> String {
        guard let tenant else { throw PlanqueError.notSigning }
        if deviceID == nil, let load = deviceLoader { deviceID = await load() }
        guard let device = deviceID else { throw PlanqueError.noDevice }
        let path = "/v1/accounts/\(CloudClient.escaped(tenant))/grants"
        let at = SigningTime.next()
        let bytes = Self.message(base: baseURL, tenant: tenant, method: "GET", uri: path, bodyHash: Self.emptyBodyHash, signedAt: at)
        return "t=\(at),v1=\(try sign(bytes)),d=\(device)"
    }
}

extension AccountClient {
    /// The key planque keeps to register a taf's tools in KIFF, as the iPad's `mintConnectorKey`
    /// (`KIFFClient.swift:1406-1411`): it connects tools and does nothing else. Minted with a
    /// signed setup call (`KIFF-Device-Signature`, the device key); its plaintext is answered this
    /// once and goes straight to planque, never to storage.
    func mintConnectorKey() async throws -> String {
        struct Minted: Decodable { let plaintext: String }
        struct Body: Encodable { let label: String; let roles: [String] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(Body(label: "planque", roles: ["connector"]))
        let minted: Minted = try read(try await send("POST", "/v1/keys", body: body, signed: true))
        return minted.plaintext
    }

    /// This device's id in KIFF's Devices list, as the iPad's `thisDeviceID`: the one KIFF marks
    /// `this_device`, and only a `dev_` one.
    func thisDeviceID() async throws -> String? {
        struct Device: Decodable {
            let id: String
            let thisDevice: Bool?
            enum CodingKeys: String, CodingKey { case id, thisDevice = "this_device" }
        }
        struct Answer: Decodable { let devices: [Device] }
        let answer: Answer = try read(try await send("GET", "/v1/me/devices"))
        return answer.devices.first { $0.thisDevice == true && $0.id.hasPrefix("dev_") }?.id
    }
}
