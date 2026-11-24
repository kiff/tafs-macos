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
    struct Body: Encodable, Equatable {
        let deviceToken: String
        var platform = MacPush.platform
        var environment = MacPush.environment
        let sound: Bool
        enum CodingKeys: String, CodingKey { case platform, environment, sound, deviceToken = "device_token" }
    }

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

    /// Alerts on with a token: registered, again when the token or the sound changed. Off, or signed out: the token
    /// tafs cloud holds is taken back. Nothing held and nothing wanted: nothing.
    static func step(wanted: Bool, token: String?, sound: Bool, held: Registered?) -> Step {
        if wanted, let token {
            return held == Registered(token: token, sound: sound) ? .none : .register(token: token, sound: sound)
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
    func registerPush(token: String, sound: Bool) async throws -> MacPush.Status {
        let status: MacPush.Status = try decoded(try await post("/v1/push", body: MacPush.Body(deviceToken: token, sound: sound)))
        return status
    }

    /// This Mac stops getting the account's alerts, as the iPad's `unregisterPush`.
    func unregisterPush(token: String) async throws {
        _ = try await delete("/v1/push/\(Self.escaped(token))")
    }
}
