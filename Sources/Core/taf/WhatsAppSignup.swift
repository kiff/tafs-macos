import Foundation

/// Adding a WhatsApp door (tafs docs/doors.md, the iPad's `DoorsModel.add` for WhatsApp): tafs cloud's page runs Meta's
/// embedded signup, then hands back to the app on `tafs://doors/whatsapp`, and the app makes the door with Meta's code, as
/// the session. On this Mac the page opens in the system's private sign-in sheet, which catches `tafs:` itself (nothing is
/// registered with macOS for it), so no other page or app can hand a return in. As the other desktops do besides, each
/// signup sends its own one-use `state`, which the page echoes, and only the return carrying it, for that taf, within
/// 15 minutes, is taken.
struct WhatsAppSignup: Equatable {
    /// How long a signup waits for its return.
    static let wait: TimeInterval = 15 * 60
    /// The scheme the page comes back on, which the sign-in sheet catches.
    static let scheme = "tafs"

    let taf: String
    let state: String
    let opened: Date

    /// What a return carries once it's this signup's: Meta's code and the number's ids (which may be empty, as the page
    /// sends them when Meta gave none).
    struct Back: Equatable {
        let code: String
        let phoneNumberID: String
        let wabaID: String
    }

    init(taf: String, state: String = WhatsAppSignup.newState(), opened: Date = Date()) {
        self.taf = taf
        self.state = state
        self.opened = opened
    }

    /// A one-use state: 32 random bytes from the system's secure generator, base64url (43 characters of `[A-Za-z0-9_-]`).
    static func newState() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// tafs cloud's signup page for this taf, with this signup's state: `<cloud>/doors/whatsapp/connect?taf=…&state=…`.
    func page(cloud: String = CloudClient.base) -> URL? {
        guard var parts = URLComponents(string: cloud) else { return nil }
        parts.path = "/doors/whatsapp/connect"
        parts.queryItems = [URLQueryItem(name: "taf", value: taf), URLQueryItem(name: "state", value: state)]
        // `+` is legal in a query but read as a space by some servers: spelled out, as every other reserved character.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }

    /// The page's return, if it's this signup's: `tafs://doors/whatsapp`, each field given once, this taf and this state
    /// (compared in fixed time), with a code, within 15 minutes of opening. Anything else is nil and isn't read further.
    func answer(_ url: URL, now: Date = Date()) -> Back? {
        guard now >= opened, now.timeIntervalSince(opened) <= Self.wait,
              url.scheme == Self.scheme, url.host == "doors", url.path == "/whatsapp",
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var fields: [String: String] = [:]
        for item in items {
            // A field given twice is no return: which one the page meant can't be told.
            guard fields[item.name] == nil else { return nil }
            fields[item.name] = item.value ?? ""
        }
        guard fields["taf"] == taf, let given = fields["state"], Self.same(given, state),
              let code = fields["code"], !code.isEmpty else { return nil }
        return Back(code: code, phoneNumberID: fields["phone_number_id"] ?? "", wabaID: fields["waba_id"] ?? "")
    }

    /// The door's extra fields for tafs cloud (`POST /v1/tafs/{id}/doors`, beside its `app`), as the iPad and the other
    /// desktops send them.
    static func doorFields(_ back: Back) -> [String: String] {
        ["code": back.code, "phone_number_id": back.phoneNumberID, "waba_id": back.wabaID]
    }

    /// Two states compared in time that doesn't depend on where they differ.
    private static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
