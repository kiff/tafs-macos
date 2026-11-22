import Foundation

/// The account's "Show suggestions" setting, as tafs cloud keeps it (`/v1/me/suggestions`), as
/// the iPad's `TafsCloud.Suggestions`: whether a new Coach conversation offers them, and tafs
/// cloud's words for what the switch does now.
struct Suggestions: Decodable, Equatable {
    var show = true
    var words = ""

    private enum CodingKeys: String, CodingKey { case show, words }
    init(show: Bool = true, words: String = "") { self.show = show; self.words = words }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        show = try c.decodeIfPresent(Bool.self, forKey: .show) ?? true
        words = try c.decodeIfPresent(String.self, forKey: .words) ?? ""
    }
}

/// A time zone in Account's picker, as tafs cloud names it (`/v1/time-zones`), as the iPad's
/// `TafsCloud.TimeZoneChoice`: its IANA id and its title for people.
struct TimeZoneChoice: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
}

/// A passkey of the account's, as KIFF lists it (`/v1/me/passkeys`), as the iPad's
/// `KIFFClient.Passkey` (KIFFClient.swift:503-524): the person's own, with its id, or a
/// computer's own (`device_id`, no id), which goes with its computer and is never removed on
/// its own.
struct Passkey: Decodable, Equatable {
    var passkeyID: String? = nil
    var name: String? = nil
    var synced: Bool? = nil
    var createdAt: Date? = nil
    var deviceID: String? = nil

    /// Only a passkey of its own can be removed: a computer's goes with the computer.
    var removable: Bool { passkeyID != nil && deviceID == nil }

    enum CodingKeys: String, CodingKey {
        case passkeyID = "id", name, synced, createdAt = "created_at", deviceID = "device_id"
    }
}

extension CloudClient {
    /// The account's "Show suggestions", as the iPad's `suggestions()`.
    func suggestions() async throws -> Suggestions {
        struct Answer: Decodable { let suggestions: Suggestions }
        let answer: Answer = try await get("/v1/me/suggestions")
        return answer.suggestions
    }

    /// Turns the account's suggestions off for good, or on again, as the iPad's
    /// `setSuggestions(_:)`: for the people who manage its tafs (403 otherwise).
    func setSuggestions(_ show: Bool) async throws -> Suggestions {
        struct Body: Encodable { let show: Bool }
        struct Answer: Decodable { let suggestions: Suggestions }
        let answer: Answer = try decoded(try await send("PUT", "/v1/me/suggestions", body: Body(show: show)))
        return answer.suggestions
    }

    /// The zones the picker lists for a search, as the iPad's `timeZones(_:)`; all of them for
    /// an empty one.
    func timeZones(_ search: String) async throws -> [TimeZoneChoice] {
        struct Answer: Decodable { let zones: [TimeZoneChoice] }
        let answer: Answer = try await get("/v1/time-zones?q=\(Self.query(search))")
        return answer.zones
    }

    /// Has tafs cloud take the account's zone from KIFF again, for the tafs' schedules, as the
    /// iPad's `syncTimeZone()`.
    func syncTimeZone() async throws {
        _ = try await send("POST", "/v1/account/time-zone", body: Optional<[String: String]>.none)
    }

    /// The AI-data consent as tafs cloud keeps it for this person, for Account's AI use row, as
    /// the iPad's `aiConsent()`.
    func aiConsent() async throws -> TafsCloud.AIConsent {
        struct Answer: Decodable { let consent: TafsCloud.AIConsent }
        let answer: Answer = try await get("/v1/me/ai-consent")
        return answer.consent
    }

    /// Withdraws it, from Account, as the iPad's `withdrawAI()`: from then on, nothing this
    /// person writes reaches the model. tafs cloud answers the consent as it now is.
    func withdrawAI() async throws -> TafsCloud.AIConsent {
        struct Answer: Decodable { let consent: TafsCloud.AIConsent }
        let answer: Answer = try decoded(try await send("DELETE", "/v1/me/ai-consent", body: Optional<[String: String]>.none))
        return answer.consent
    }
}

extension AccountClient {
    /// The account's passkeys, as the iPad's `passkeys()`: read unsigned, as Devices is.
    func passkeys() async throws -> [Passkey] {
        struct Answer: Decodable { let passkeys: [Passkey]? }
        let answer: Answer = try read(try await send("GET", "/v1/me/passkeys"))
        return answer.passkeys ?? []
    }

    /// Sets the account's time zone (an IANA name), as the iPad's `setTimeZone(_:)`: a signed
    /// setup call, signed by this Mac's device key over the exact bytes sent, which only the
    /// account's owner or an admin may make. KIFF answers the zone it keeps.
    func setTimeZone(_ zone: String) async throws -> String {
        struct Saved: Decodable { let timeZone: String; enum CodingKeys: String, CodingKey { case timeZone = "time_zone" } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let saved: Saved = try read(try await send("PUT", "/v1/me/time-zone", body: try encoder.encode(["time_zone": zone]), signed: true))
        return saved.timeZone
    }
}

/// Saving the account's time zone, as the iPad's `setAccountTimeZone(_:)` (AppModel.swift:356-388):
/// the owner confirms (Touch ID or the Mac's password), KIFF takes the zone signed by the device
/// key, who is signed in is read again, then tafs cloud takes the zone for the schedules.
enum AccountZone {
    /// How a save ended: who is signed in once KIFF took the zone (nil when it didn't), and why
    /// it didn't go all the way, in the app's words (nil when it did).
    struct Saved: Equatable {
        var me: Me?
        var why: String?
    }

    /// Saves `zone`. `confirm` asks for the owner's presence and throws when it isn't given
    /// (`OwnerPrompt.Closed` for a prompt closed). Nothing is sent before it; a session without
    /// a device key sends nothing and says to sign in again.
    /// `approveWithKey`: on a Mac that approves with its security key (kiff/cloud#96), the key approves the one
    /// request (`KeyAct.timeZone`), named in its sheet, in place of the confirmation and the device key's signature;
    /// a closed sheet sends nothing and says nothing.
    static func save(_ zone: String, account: AccountClient, cloud: CloudClient, words: Words,
                     confirm: (String) async throws -> Void,
                     approveWithKey: ((KeyAct, String) async throws -> Data)? = nil) async -> Saved {
        if let approveWithKey {
            let act = KeyAct.timeZone(zone)
            do { _ = try await approveWithKey(act, act.title(words)) } catch is CancellationError {
                return Saved(me: nil, why: nil)
            } catch {
                return Saved(me: nil, why: words("settings.time_zone.not_changed", ["why": CoachStart.why(error, words: words)]))
            }
        } else {
            guard account.sign != nil else { return Saved(me: nil, why: words("sign_in.again_to_sign")) }
            do { try await confirm(words("settings.time_zone.prompt", ["zone": zone])) } catch {
                return Saved(me: nil, why: OwnerPrompt.stopped(error, words: words))
            }
            do { _ = try await account.setTimeZone(zone) } catch {
                return Saved(me: nil, why: words("settings.time_zone.not_changed", ["why": CoachStart.why(error, words: words)]))
            }
        }
        // KIFF took it: what's read from here on is in the new zone.
        let me = try? await account.me()
        do { try await cloud.syncTimeZone() } catch {
            return Saved(me: me, why: words("settings.account_zone_changed_schedules_could", ["why": CoachStart.why(error, words: words)]))
        }
        return Saved(me: me, why: nil)
    }

    /// The zone a picker's row is ticked by: KIFF's, else UTC, as the iPad's
    /// `kiffAccount?.timeZone ?? "UTC"`.
    static func current(_ me: Me?) -> String { me?.timeZone ?? "UTC" }

    /// Whether "Use this Mac's" is offered on the KIFF account page: only when the Mac's zone
    /// isn't the account's, as the iPad's `zone != TimeZone.current.identifier`.
    static func offersDevice(_ me: Me?, device: String) -> Bool { current(me) != device }
}

extension CloudClient {
    /// The person allows AI use, for the version of the words they read, as the iPad's
    /// `allowAI(version:)`: tafs cloud answers the consent as it now is. A yes to older words is
    /// refused (409) with the newer ones (`CloudRefusal.consent`).
    func giveAIConsent(version: String) async throws -> TafsCloud.AIConsent? {
        TafsCloud.consent(in: try await post("/v1/me/ai-consent", ["version": version]))
    }
}
