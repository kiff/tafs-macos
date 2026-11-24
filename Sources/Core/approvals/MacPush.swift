import Foundation

/// Alerts with tafs closed, as the iPad's `registerPush`/`unregisterPush`: this Mac gives tafs cloud its push token
/// (`POST /v1/push`) while Alerts on this Mac is on, and takes it back (`DELETE /v1/push/{token}`) when it's turned off
/// or the person signs out. Apple's push service then reaches it with the app closed.
///
/// It's built only with `PUSH=1` (docs/release.md, "alerts with tafs closed"): the signed app needs a Developer ID
/// profile with push for `bot.tafs.macos` and `aps-environment` first, and tafs cloud sends a Mac's token to that topic,
/// `platform: macos`. Without the flag nothing here is called, and the app alerts only while it's open (`Notifier`).
enum MacPush {
    /// tafs cloud's name for a Mac: its token is APNs's, like an iPhone's, for the Mac app's own topic.
    static let platform = "macos"
    /// A Developer ID app's push environment: Apple's production service. There's no sandbox outside development builds.
    static let environment = "production"

    /// The token as tafs cloud takes it: APNs's bytes, in lowercase hex.
    static func token(_ bytes: Data) -> String { Encoding.hex(bytes) }

    /// The registration, as the iPhone's body with this Mac's platform: `sound` false is Sound for alerts turned off.
    /// With `alertTarget`, KIFF's alert target's secret, which tafs cloud checks KIFF's deliveries with; with `kinds`,
    /// which kinds of alert this Mac gets, as the person chose them (`DeviceAlerts.kinds`).
    struct Body: Encodable, Equatable {
        let deviceToken: String
        var platform = MacPush.platform
        var environment = MacPush.environment
        let sound: Bool
        var alertTarget: AlertTarget?
        var kinds: [String: Bool]?
        enum CodingKeys: String, CodingKey {
            case platform, environment, sound, kinds, deviceToken = "device_token", alertTarget = "alert_target"
        }
    }

    /// Where KIFF sends the account's held calls, as the iPad's `KIFFClient.AlertTarget`: its id and the secret KIFF
    /// signs each delivery with, handed to tafs cloud with the token and never kept on this Mac.
    struct AlertTarget: Codable, Equatable {
        let id: String
        let signingSecret: String
        enum CodingKeys: String, CodingKey { case id, signingSecret = "signing_secret" }
    }

    /// What alerts this Mac, as tafs cloud keeps it for its token (`GET /v1/push`), as the iPad's `PhoneAlerts`: on or
    /// not, each kind with its words and choice, and the tafs whose answers alert the account's devices.
    struct DeviceAlerts: Decodable, Equatable {
        struct Choice: Decodable, Equatable, Identifiable { let id: String; let title: String; let words: String; let enabled: Bool }
        struct Taf: Decodable, Equatable, Identifiable { let id: String; let name: String }
        struct Answering: Decodable, Equatable { let title: String; let tafs: [Taf] }
        let enabled: Bool
        let sound: Bool
        let kinds: [Choice]
        let answering: Answering?

        /// The kinds as they're sent back, with one changed.
        func kinds(setting id: String, to enabled: Bool) -> [String: Bool] {
            var all = Dictionary(kinds.map { ($0.id, $0.enabled) }, uniquingKeysWith: { first, _ in first })
            all[id] = enabled
            return all
        }
    }

    /// Where an alert the person clicked opens, as the iPad's `PushDelegate` reads tafs cloud's payload: a hold opens
    /// Needs you, a brief's alert or an urgent one (`brief_kind`) the brief in its place, a step a taf handed over
    /// (`handoff`) that step, and anything else where `open` says.
    enum Destination: Equatable {
        case needsYou
        case step(String)
        case other(String)
    }

    static func destination(_ info: [AnyHashable: Any]) -> Destination? {
        let open = info["open"] as? String
        if info["hold_id"] is String, open == "needs-you" { return .needsYou }
        if open == nil, isBrief(info) { return .needsYou }
        if let handoff = info["handoff"] as? String, !handoff.isEmpty { return .step(handoff) }
        if open == "needs-you" { return .needsYou }
        return open.map(Destination.other)
    }

    /// A brief's alert, or an urgent one (`brief_kind: brief|urgent`): with tafs open, the brief is read again.
    static func isBrief(_ info: [AnyHashable: Any]) -> Bool {
        guard let kind = info["brief_kind"] as? String else { return false }
        return kind == "brief" || kind == "urgent"
    }

    /// Where KIFF posts the account's held calls for tafs cloud to push (`POST /v1/me/alert-targets`).
    static var alertsURL: String { CloudClient.base + "/v1/kiff/alerts" }

    /// The kinds the person chose on this Mac, kept per account and sent with each registration.
    static func kindsKey(_ account: String) -> String { "tafs.push.kinds|\(account)" }

    /// What tafs cloud says after a registration, as the iPad's `PushStatus`.
    struct Status: Decodable, Equatable {
        let answers: Bool
        let alerts: Bool
    }

    /// What's sent next, from what this Mac wants and what tafs cloud holds.
    enum Step: Equatable {
        case none
        /// Give tafs cloud this token, with Sound for alerts.
        case register(token: String, sound: Bool)
        /// Take back the token it holds.
        case unregister(token: String)
    }

    /// Alerts on with a token: registered, again when the token or the sound changed, and always `again` (at launch,
    /// or when tafs cloud says it doesn't alert this Mac): tafs cloud may have dropped the row, and registering is
    /// idempotent there. Off, or signed out: the token tafs cloud holds is taken back. Nothing held and nothing wanted:
    /// nothing.
    static func step(wanted: Bool, token: String?, sound: Bool, held: Registered?, again: Bool = false) -> Step {
        if wanted, let token {
            return !again && held == Registered(token: token, sound: sound) ? .none : .register(token: token, sound: sound)
        }
        if let held { return .unregister(token: held.token) }
        return .none
    }

    /// The token tafs cloud holds for this Mac, with the sound it was given: kept per account, so it's taken back at
    /// sign-out and sent again only when it changes.
    struct Registered: Codable, Equatable {
        let token: String
        let sound: Bool

        static func key(_ account: String) -> String { "tafs.push.registered|\(account)" }

        static func load(from defaults: UserDefaults, account: String) -> Registered? {
            defaults.data(forKey: key(account)).flatMap { try? JSONDecoder().decode(Registered.self, from: $0) }
        }

        static func save(_ registered: Registered?, to defaults: UserDefaults, account: String) {
            if let registered, let data = try? JSONEncoder().encode(registered) {
                defaults.set(data, forKey: key(account))
            } else {
                defaults.removeObject(forKey: key(account))
            }
        }
    }
}

extension CloudClient {
    /// This Mac gets the account's alerts at `token`, as the iPad's `registerPush`.
    func registerPush(token: String, sound: Bool, target: MacPush.AlertTarget? = nil, kinds: [String: Bool]? = nil) async throws -> MacPush.Status {
        let body = MacPush.Body(deviceToken: token, sound: sound, alertTarget: target, kinds: kinds)
        let status: MacPush.Status = try decoded(try await post("/v1/push", body: body))
        return status
    }

    /// What alerts this Mac, as tafs cloud keeps it for `token`, as the iPad's `phoneAlerts`.
    func deviceAlerts(token: String) async throws -> MacPush.DeviceAlerts {
        try await get("/v1/push", headers: ["Tafs-Device-Token": token])
    }

    /// This Mac stops getting the account's alerts, as the iPad's `unregisterPush`.
    func unregisterPush(token: String) async throws {
        _ = try await delete("/v1/push/\(Self.escaped(token))")
    }
}

extension AccountClient {
    /// Points the account's held-call alerts at tafs cloud, replacing the target there before, as the iPad's
    /// `registerAlertTarget`: a setup call signed by the device key, with no prompt. It grants nothing.
    func registerAlertTarget() async throws -> MacPush.AlertTarget {
        let body = try JSONEncoder().encode(["url": MacPush.alertsURL])
        return try read(try await send("POST", "/v1/me/alert-targets", body: body, signed: true))
    }
}
