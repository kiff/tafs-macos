import Foundation

/// One act approved by this Mac's security key alone (docs/approvals.md, "Approving with the security key";
/// kiff/cloud#96, the PM's decision (i)): the request the app writes in full, its `kiff.request.v1` message signed by
/// a fresh assertion of the key (UP, and UV from its PIN), and sent with `KIFF-Passkey-Assertion` only. One request
/// per assertion: never a window, never two requests under one (`RequestsTogether` is never used here), never the
/// device key's signature, which grants nothing on a software-key Mac.
extension PasskeySession {
    /// Signs and sends `method path` with exactly `body`, approved by the key through `pin`. A refusal is KIFF's own
    /// (`KIFFError`), so the act's line says it; the key's failures are `SecurityKeyFailure` and `PasskeyRefusal`.
    func approved(method: String, path: String, body: Data = Data(), pin: SecurityKeyPIN?) async throws -> Data {
        let assertion = try await approver.approve(tenant: session.tenant, method: method, path: path, body: body, pin: pin)
        var headers = ["Authorization": "Bearer \(session.accessToken)", "Accept": "application/json",
                       "Accept-Language": language, "User-Agent": "tafs-macos", Passkeys.headerName: assertion]
        if !body.isEmpty { headers["Content-Type"] = "application/json" }
        let (status, answer) = try await transport.send(HTTPRequest(method: method, path: path, headers: headers, body: body))
        guard (200..<300).contains(status) else { throw KIFFError(status: status, body: answer) }
        return answer
    }
}

/// The acts this Mac approves with its security key, each with the request the iPad's `KIFFClient` writes for it.
enum KeyAct: Equatable {
    /// Signing another device out (the iPad's `prepareRemoveDevice`): `DELETE /v1/me/devices/{id}`, empty body.
    case signOutDevice(id: String)

    var method: String {
        switch self {
        case .signOutDevice: return "DELETE"
        }
    }

    var path: String {
        switch self {
        case .signOutDevice(let id): return "/v1/me/devices/\(CloudClient.escaped(id))"
        }
    }

    var body: Data {
        switch self {
        case .signOutDevice: return Data()
        }
    }

    /// The act's name in the security key's sheet ("Sign out {device}"), so the person sees what the key approves.
    func title(_ words: Words, device: String = "") -> String {
        switch self {
        case .signOutDevice: return words("settings.devices.sign_out_prompt", ["device": device])
        }
    }
}
