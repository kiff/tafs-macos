import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let meParis = #"{"tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com","time_zone":"Europe/Paris","capabilities":["cards.manage"]}"#

private func clients(_ kiff: [(Int, String)], _ cloud: [(Int, String)], signed: Bool = true) -> (AccountClient, CannedTransport, CloudClient, CannedTransport) {
    let kiffTransport = CannedTransport(kiff)
    let cloudTransport = CannedTransport(cloud)
    let account = AccountClient(transport: kiffTransport, session: session, sign: signed ? { _ in "t=2026-11-17T10:00:00.000Z,v1=SIG" } : nil)
    return (account, kiffTransport, CloudClient(transport: cloudTransport, session: session), cloudTransport)
}

private func english() throws -> Words { try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings")) }

/// One case's body from tafs cloud's own AI-consent contract, as sent.
private func consentCase(_ name: String) throws -> String {
    struct File: Decodable { let cases: [Case] }
    struct Case: Decodable { let name: String }
    let data = try Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/ai-consent.json"))
    let names = try JSONDecoder().decode(File.self, from: data).cases.map(\.name)
    guard let index = names.firstIndex(of: name),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = root["cases"] as? [[String: Any]], let body = cases[index]["body"]
    else { throw Failure(description: "no case \(name)") }
    return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
}

let accountControlsTests: [Test] = [
    Test("the time zone is confirmed, then saved to KIFF signed, who is signed in read again, and tafs cloud takes it", awaiting: {
        let words = try english()
        let (account, kiff, cloud, cloudSent) = clients([(200, #"{"time_zone":"Europe/Paris"}"#), (200, meParis)], [(200, #"{"time_zone":"Europe/Paris","updated":2}"#)])
        var asked: [String] = []
        let saved = await AccountZone.save("Europe/Paris", account: account, cloud: cloud, words: words, confirm: { asked.append($0) })
        try expectEqual(asked, ["Set your account's time zone to Europe/Paris"])
        try expectEqual(kiff.sent.map { $0.method + " " + $0.path }, ["PUT /v1/me/time-zone", "GET /v1/me"])
        // JSONEncoder's bytes, as the iPad's `JSONEncoder().encode(body)` sends them: the slash escaped.
        try expectEqual(String(decoding: kiff.sent[0].body, as: UTF8.self), #"{"time_zone":"Europe\/Paris"}"#)
        try expectEqual(kiff.sent[0].headers["KIFF-Device-Signature"], "t=2026-11-17T10:00:00.000Z,v1=SIG")
        try expectEqual(kiff.sent[1].headers["KIFF-Device-Signature"], nil)
        try expectEqual(cloudSent.sent.map { $0.method + " " + $0.path }, ["POST /v1/account/time-zone"])
        try expectEqual(saved.me?.timeZone, "Europe/Paris")
        try expectEqual(saved.why, nil)
        try expectEqual(AccountZone.current(saved.me), "Europe/Paris")
        try expectEqual(AccountZone.current(nil), "UTC")
        try expectEqual(AccountZone.offersDevice(saved.me, device: "Europe/Paris"), false)
        try expectEqual(AccountZone.offersDevice(saved.me, device: "America/New_York"), true)
    }),
    Test("on a security-key Mac the time zone is approved by the key alone: named in its sheet, the same bytes, no device signature, no prompt", awaiting: {
        let words = try english()
        let (account, kiff, cloud, cloudSent) = clients([(200, meParis)], [(200, #"{"time_zone":"Europe/Paris","updated":2}"#)], signed: false)
        var asked: [String] = [], acts: [KeyAct] = [], titles: [String] = []
        let saved = await AccountZone.save("Europe/Paris", account: account, cloud: cloud, words: words, confirm: { asked.append($0) },
                                           approveWithKey: { act, title in acts.append(act); titles.append(title); return Data() })
        try expectEqual(asked, [])
        try expectEqual(acts, [.timeZone("Europe/Paris")])
        try expectEqual(titles, ["Set your account's time zone to Europe/Paris"])
        try expectEqual(KeyAct.timeZone("Europe/Paris").method + " " + KeyAct.timeZone("Europe/Paris").path, "PUT /v1/me/time-zone")
        // The same bytes as the device key's call.
        try expectEqual(String(decoding: KeyAct.timeZone("Europe/Paris").body, as: UTF8.self), #"{"time_zone":"Europe\/Paris"}"#)
        try expectEqual(kiff.sent.map { $0.method + " " + $0.path }, ["GET /v1/me"])
        try expectEqual(cloudSent.sent.map { $0.method + " " + $0.path }, ["POST /v1/account/time-zone"])
        try expectEqual(saved.why, nil)
        // The key's sheet closed: nothing more is sent, and nothing is said.
        let (account2, kiff2, cloud2, _) = clients([], [], signed: false)
        let closed = await AccountZone.save("Europe/Paris", account: account2, cloud: cloud2, words: words, confirm: { _ in },
                                            approveWithKey: { _, _ in throw CancellationError() })
        try expectEqual(closed, AccountZone.Saved(me: nil, why: nil))
        try expectEqual(kiff2.sent.count, 0)
        // "Approve on your phone instead": nothing sent, and the line says where to approve, never the error's type.
        let onPhone = await AccountZone.save("Europe/Paris", account: account2, cloud: cloud2, words: words, confirm: { _ in },
                                             approveWithKey: { _, _ in throw ApproveOnPhone() })
        try expectEqual(onPhone.why, words("settings.time_zone.not_changed", ["why": words("approval.device_can_not_approve_approve")]))
        try expectEqual(kiff2.sent.count, 0)
    }),
    Test("Revoke is the iPad's plain session call: POST /v1/me/mandates/{id}/revoke with {}, no signature and no key", awaiting: {
        let (account, kiff, _, _) = clients([(200, "{}")], [])
        try await account.revoke(cardID: "card/1")
        try expectEqual(kiff.sent.map { $0.method + " " + $0.path }, ["POST /v1/me/mandates/card%2F1/revoke"])
        try expectEqual(String(decoding: kiff.sent[0].body, as: UTF8.self), "{}")
        try expectEqual(kiff.sent[0].headers["KIFF-Device-Signature"], nil)
        try expectEqual(kiff.sent[0].headers["KIFF-Passkey-Assertion"], nil)
    }),
    Test("a time zone not confirmed, or without a device key, sends nothing and says why", awaiting: {
        let words = try english()
        let (account, kiff, cloud, cloudSent) = clients([], [])
        let closed = await AccountZone.save("Europe/Paris", account: account, cloud: cloud, words: words, confirm: { _ in throw OwnerPrompt.Closed() })
        try expectEqual(closed, AccountZone.Saved(me: nil, why: "Cancelled. Nothing changed."))
        struct Failed: Error {}
        let failed = await AccountZone.save("Europe/Paris", account: account, cloud: cloud, words: words, confirm: { _ in throw Failed() })
        try expectEqual(failed.why, "Not sent: it wasn't confirmed.")
        let (unsigned, unsignedSent, _, _) = clients([], [], signed: false)
        var asked = 0
        let noKey = await AccountZone.save("Europe/Paris", account: unsigned, cloud: cloud, words: words, confirm: { _ in asked += 1 })
        try expectEqual(noKey.why, words("sign_in.again_to_sign"))
        try expectEqual(asked, 0)
        try expectEqual(kiff.sent.count + unsignedSent.sent.count + cloudSent.sent.count, 0)
    }),
    Test("a time zone KIFF refuses isn't changed; one whose schedules tafs cloud couldn't take says so", awaiting: {
        let words = try english()
        let (account, kiff, cloud, cloudSent) = clients([(403, #"{"error":"role_forbidden"}"#)], [])
        let refused = await AccountZone.save("Europe/Paris", account: account, cloud: cloud, words: words, confirm: { _ in })
        try expectEqual(refused.me, nil)
        try expectEqual(refused.why, words("settings.time_zone.not_changed", ["why": words("error.not_allowed")]))
        try expectEqual(kiff.sent.count, 1)
        try expectEqual(cloudSent.sent.count, 0)
        let (taken, _, unsynced, _) = clients([(200, #"{"time_zone":"Europe/Paris"}"#), (200, meParis)], [(503, "")])
        let half = await AccountZone.save("Europe/Paris", account: taken, cloud: unsynced, words: words, confirm: { _ in })
        try expectEqual(half.me?.timeZone, "Europe/Paris")
        try expectEqual(half.why, words("settings.account_zone_changed_schedules_could", ["why": words("error.cloud_answered", ["status": "503"])]))
    }),
    Test("the picker's zones are tafs cloud's for the search, the query escaped", awaiting: {
        let (_, _, cloud, sent) = clients([], [(200, #"{"zones":[{"id":"Europe/Paris","title":"Paris (UTC+1)"},{"id":"Europe/Lisbon","title":"Lisbon (UTC+0)"}]}"#)])
        let zones = try await cloud.timeZones("Europe Pa")
        try expectEqual(sent.sent[0].path, "/v1/time-zones?q=Europe%20Pa")
        try expectEqual(zones, [TimeZoneChoice(id: "Europe/Paris", title: "Paris (UTC+1)"), TimeZoneChoice(id: "Europe/Lisbon", title: "Lisbon (UTC+0)")])
    }),
    Test("the passkeys are read unsigned, a computer's own going with its computer", awaiting: {
        let body = #"{"passkeys":[{"id":"pk_1","name":"iPhone","synced":true,"created_at":"2026-11-10T09:00:00Z"},{"name":"YubiKey 5C","device_id":"dev_1"},{"device_id":"dev_2"}]}"#
        let (account, kiff, _, _) = clients([(200, body), (200, "{}")], [])
        let passkeys = try await account.passkeys()
        try expectEqual(kiff.sent[0].method + " " + kiff.sent[0].path, "GET /v1/me/passkeys")
        try expectEqual(kiff.sent[0].headers["KIFF-Device-Signature"], nil)
        try expectEqual(passkeys.map(\.name), ["iPhone", "YubiKey 5C", nil])
        try expectEqual(passkeys.map(\.removable), [true, false, false])
        try expectEqual(passkeys[0].createdAt, Date(timeIntervalSince1970: 1_794_301_200))
        let none = try await account.passkeys()
        try expectEqual(none, [])
    }),
    Test("removing a passkey is the iPad's request, the security key's act: DELETE its own path, empty body, the iPad's prompt") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let act = KeyAct.removePasskey(id: "pk/1")
        try expectEqual(act.method + " " + act.path, "DELETE /v1/me/passkeys/pk%2F1")
        try expectEqual(act.body, Data())
        try expectEqual(act.title(words, device: "iPhone"), "Remove the passkey iPhone from your account")
    },
    Test("a passkey is the same by its id, else a computer's by its device; the last one is the only one left, as the iPad's") {
        let read = { (json: String) in try AccountClient.decoder.decode(Passkey.self, from: Data(json.utf8)) }
        let phone = try read(#"{"id":"pk_1","name":"iPhone"}"#), key = try read(#"{"id":"pk_2","name":"YubiKey"}"#)
        let mac = try read(#"{"name":"Mac","device_id":"dev_1"}"#)
        try expect(phone.isSamePasskey(as: try read(#"{"id":"pk_1","name":"renamed"}"#)), "the same id")
        try expect(!phone.isSamePasskey(as: key), "another id")
        try expect(mac.isSamePasskey(as: try read(#"{"device_id":"dev_1"}"#)), "a computer's by its device")
        try expect(!mac.isSamePasskey(as: phone), "a computer's isn't an id's")
        try expect(Passkey.removesLast(phone, among: [phone]), "the only one")
        try expect(!Passkey.removesLast(phone, among: [phone, key]), "another left")
        try expect(!Passkey.removesLast(phone, among: [phone, mac]), "a computer's counts too, as the iPad's")
        // A computer's own passkey that also has an id is still the computer's: never removable here (as Linux pins it).
        let both = try read(#"{"id":"pk_9","name":"Mac","device_id":"dev_1"}"#)
        try expect(!both.removable, "an id with a device_id is a computer's")
    },
    Test("who removes passkeys is KIFF's member_role, an owner or an admin; a KIFF that doesn't say offers no Remove") {
        let me = { (json: String) in try AccountClient.decoder.decode(Me.self, from: Data(json.utf8)) }
        try expectEqual(try me(#"{"member_role":"owner"}"#).managesPasskeys, true)
        try expectEqual(try me(#"{"member_role":"admin"}"#).managesPasskeys, true)
        try expectEqual(try me(#"{"member_role":"editor"}"#).managesPasskeys, false)
        try expectEqual(try me(#"{"member_role":" "}"#).role, nil)
        try expectEqual(try me("{}").managesPasskeys, false)
    },
    Test("the AI-data consent is read, given for the version read, and withdrawn, as tafs cloud's contract answers", awaiting: {
        let (_, _, cloud, sent) = clients([], [(200, try consentCase("not given yet")), (200, try consentCase("given")), (200, try consentCase("withdrawn"))])
        let read = try await cloud.aiConsent()
        try expectEqual(read.given, false)
        try expectEqual(read.drawable, true)
        try expectEqual(read.words.given, "AI use: allowed")
        let given = try await cloud.giveAIConsent(version: read.version)
        try expectEqual(given?.given, true)
        let withdrawn = try await cloud.withdrawAI()
        try expectEqual(withdrawn.given, false)
        try expectEqual(sent.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/ai-consent", "POST /v1/me/ai-consent", "DELETE /v1/me/ai-consent"])
        try expectEqual(String(decoding: sent.sent[1].body, as: UTF8.self), #"{"version":"1"}"#)
        try expectEqual(sent.sent[2].body, Data())
    }),
    Test("a yes to older words is refused with the newer ones, to be read again", awaiting: {
        let (_, _, cloud, _) = clients([], [(409, try consentCase("a yes from an older screen"))])
        do {
            _ = try await cloud.giveAIConsent(version: "0")
            throw Failure(description: "a 409 was taken")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 409)
            try expectEqual(refusal.consent?.drawable, true)
        }
    }),
    Test("Show suggestions is read, and changed with a PUT of its one field", awaiting: {
        let (_, _, cloud, sent) = clients([], [(200, #"{"suggestions":{"show":true,"words":"Coach offers jobs to start from."}}"#), (200, #"{"suggestions":{"show":false}}"#)])
        let read = try await cloud.suggestions()
        try expectEqual(read, Suggestions(show: true, words: "Coach offers jobs to start from."))
        let off = try await cloud.setSuggestions(false)
        try expectEqual(off, Suggestions(show: false, words: ""))
        try expectEqual(sent.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/suggestions", "PUT /v1/me/suggestions"])
        try expectEqual(String(decoding: sent.sent[1].body, as: UTF8.self), #"{"show":false}"#)
    }),
    Test("the KIFF account page's id is the slug only when the name isn't it, and Delete account follows account.delete") {
        func me(_ json: String) throws -> Me { try AccountClient.decoder.decode(Me.self, from: Data(json.utf8)) }
        try expectEqual(try me(meParis).accountID, "acme")
        try expectEqual(try me(#"{"tenant_slug":"acme"}"#).accountID, nil)
        try expectEqual(try me(meParis).mayDeleteAccount, false)
        try expectEqual(try me(#"{"tenant_slug":"acme","capabilities":["account.delete"]}"#).mayDeleteAccount, true)
        try expectEqual(try me(#"{"tenant_slug":"acme"}"#).mayDeleteAccount, true)
    },
]
