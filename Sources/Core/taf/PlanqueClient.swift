import Foundation

/// planque, which keeps a taf's vendor sign-ins so they never reach this Mac, tafs cloud, the
/// agent or KIFF, as the iPad's `PlanqueClient`. This Mac asks two things of it: its proof
/// that this device reads its own account's grants (`grantsReadProof`), which tafs cloud
/// forwards with a taf's Setup read; and this device's enrolment (`enrol`), each request
/// signed by the device key with this device's id (`Planque-Device-Signature`).
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
