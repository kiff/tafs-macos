import Foundation

/// planque, for the one thing this Mac asks of it: its proof that this device reads its own
/// account's grants, as the iPad's `PlanqueClient.grantsReadProof` (`PlanqueClient.swift:68-73`,
/// `:577-586`). tafs cloud forwards it with a taf's Setup read (`Planque-Device-Signature`), so
/// Setup can list the taf's connected apps. It grants nothing.
final class PlanqueClient {
    enum PlanqueError: Error, Equatable { case notSigning, noDevice }

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

    init(baseURL: String = PlanqueClient.baseURL) { self.baseURL = baseURL }

    /// What the device signs for a request to planque (planque's `device.Message`): seven lines,
    /// the base with no trailing slash, and the body's SHA-256 in hex.
    static func message(base: String, tenant: String, method: String, uri: String, bodyHash: String, signedAt: String) -> String {
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        return ["planque.request.v1", b, tenant, method, uri, bodyHash, signedAt].joined(separator: "\n")
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
