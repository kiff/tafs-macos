import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")

private func client(_ answers: [(Int, String)], sign: ((HTTPRequest) throws -> String)? = nil) -> (AccountClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (AccountClient(transport: transport, session: session, language: "fr", sign: sign), transport)
}

let accountTests: [Test] = [
    Test("every request carries the session and the app's language, and no signature unless asked", awaiting: {
        let (account, transport) = client([(200, #"{"devices":[]}"#)])
        let none = try await account.devices()
        try expectEqual(none, [])
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "GET /v1/me/devices")
        try expectEqual(sent.headers["Authorization"], "Bearer tok")
        try expectEqual(sent.headers["Accept-Language"], "fr")
        try expectEqual(sent.headers["KIFF-Device-Signature"], nil)
        try expectEqual(sent.headers["Content-Type"], nil)
    }),
    Test("the devices are read as KIFF lists them", awaiting: {
        let body = #"""
        {"devices":[
          {"id":"dev_1","name":"tafs on this Mac","display_name":"Mac","platform":"macos","key_fingerprint":"3f2a 91c0 7b1e 0d44","attested":false,"created_at":"2026-11-14T18:00:00Z","last_used_at":"2026-11-14T18:30:00.250Z","this_device":true},
          {"id":"dev_2","name":"A phone","last_seen_at":"2026-11-13T09:00:00Z"},
          {"id":"dev_3"}
        ]}
        """#
        let (account, _) = client([(200, body)])
        let devices = try await account.devices()
        try expectEqual(devices.map(\.id), ["dev_1", "dev_2", "dev_3"])
        try expectEqual(devices[0].name, "Mac")
        try expectEqual(devices[0].thisDevice, true)
        try expectEqual(devices[0].lastUsed, Date(timeIntervalSince1970: 1_794_681_000.25))
        try expectEqual(devices[1].name, "A phone")
        try expectEqual(devices[1].lastUsed, Date(timeIntervalSince1970: 1_794_560_400))
        try expectEqual(devices[2], Device(id: "dev_3", name: nil))
    }),
    Test("a key fingerprint isn't read: a device whose fingerprint isn't text still lists", awaiting: {
        let body = #"{"devices":[{"id":"dev_1","display_name":"Mac","key_fingerprint":{"sha256":"3f2a"},"this_device":true}]}"#
        let (account, _) = client([(200, body)])
        let devices = try await account.devices()
        try expectEqual(devices, [Device(id: "dev_1", name: "Mac", thisDevice: true)])
    }),
    Test("an answer that isn't the devices list is unreadable, never an empty list", awaiting: {
        for body in ["{}", "<html>", #"{"devices":[{"name":"no id"}]}"#] {
            let (account, _) = client([(200, body)])
            do { _ = try await account.devices(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
    }),
    Test("removing a device names it in the path, escaped", awaiting: {
        let (account, transport) = client([(204, "")])
        try await account.removeDevice("dev/../x y")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "DELETE /v1/me/devices/dev%2F..%2Fx%20y")
    }),
    Test("a session KIFF no longer knows ends, and another refusal doesn't", awaiting: {
        let (account, _) = client([(401, #"{"error":"invalid_token"}"#), (403, #"{"error":"phone_session_forbidden"}"#)])
        do { _ = try await account.devices(); throw Failure(description: "401 was read") } catch let error as KIFFError { try expect(error.endsSession, "401 ends it") }
        do { _ = try await account.devices(); throw Failure(description: "403 was read") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 403, code: "phone_session_forbidden"))
            try expect(!error.endsSession, "403 doesn't")
        }
    }),
    Test("a signed request carries the signature of the request as sent, and isn't sent without a key", awaiting: {
        var signedRequest: HTTPRequest?
        let (account, transport) = client([(200, "{}")], sign: { signedRequest = $0; return "t=T,v1=SIG" })
        _ = try await account.send("POST", "/v1/me/window/win_a/close", body: Data(#"{"a":1}"#.utf8), signed: true)
        try expectEqual(transport.sent[0].headers["KIFF-Device-Signature"], "t=T,v1=SIG")
        try expectEqual(signedRequest?.body, transport.sent[0].body)
        try expectEqual(signedRequest?.path, "/v1/me/window/win_a/close")
        let (keyless, untouched) = client([(200, "{}")])
        do { _ = try await keyless.send("POST", "/x", signed: true); throw Failure(description: "sent unsigned") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 0, code: "no_device_key"))
        }
        try expectEqual(untouched.sent.count, 0)
    }),
    Test("who is signed in and how the session approves are KIFF's words, and view-only is only what KIFF calls view", awaiting: {
        let (account, transport) = client([(200, #"{"tenant_id":"t1","tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com","approval_mode":"view"}"#),
                                           (200, #"{"tenant_slug":"acme","approval_mode":"passkey"}"#), (200, #"{"tenant_slug":"acme","email":" "}"#), (200, "<html>")])
        let view = try await account.me()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me")
        try expectEqual(view.email, "you@example.com")
        try expectEqual(view.account, "Acme")
        try expectEqual(view.viewOnly, true)
        let passkey = try await account.me()
        try expectEqual(passkey.viewOnly, false)
        try expectEqual(passkey.account, "acme")
        // A KIFF that doesn't say: the app claims neither.
        let silent = try await account.me()
        try expectEqual(silent.approvalMode, nil)
        try expectEqual(silent.viewOnly, false)
        try expectEqual(silent.email, nil)
        do { _ = try await account.me(); throw Failure(description: "HTML was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
    }),
    Test("Signed in as is the email, unless it is the account's own name", awaiting: {
        let (account, _) = client([(200, #"{"tenant_slug":"acme","tenant_display_name":"Acme","email":"you@example.com"}"#),
                                   (200, #"{"tenant_slug":"you@example.com","email":"You@Example.com "}"#),
                                   (200, #"{"tenant_slug":"acme"}"#)])
        let named = try await account.me(), sameAsName = try await account.me(), none = try await account.me()
        try expectEqual(named.signedInAs, "you@example.com")
        try expectEqual(sameAsName.signedInAs, nil)
        try expectEqual(none.signedInAs, nil)
    }),
    Test("signing out ends the session at KIFF", awaiting: {
        let (account, transport) = client([(200, "{}")])
        try await account.signOut()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/auth/device/logout")
    }),
    Test("About's version is the version and its build; a language is named in its own words") {
        try expectEqual(AppInfo.version(["CFBundleShortVersionString": "0.1", "CFBundleVersion": "1"]), "0.1 (1)")
        try expectEqual(AppInfo.version(["CFBundleShortVersionString": "0.1"]), "0.1")
        try expectEqual(AppInfo.version([:]), "–")
        try expectEqual(AppInfo.languageName("fr"), "Français")
        try expectEqual(AppInfo.languageName("pt"), "Português")
        try expectEqual(AppInfo.languageName("en"), "English")
    },
    Test("the app declares every shipped language, so macOS offers each one as the app's own language") {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "App/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] ?? [:]
        let declared = info["CFBundleLocalizations"] as? [String] ?? []
        let shipped = try Words.shipped(folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(Set(declared), Set(shipped))
        try expectEqual(AppInfo.version(info), "0.1 (1)")
    },
    Test("people and groups are read as KIFF lists them and kept as the iPad keeps them; only read", awaiting: {
        let groups = #"{"groups":[{"id":"g2","name":"finance","members":[{"subject":"u2","role":"member"}],"agents":[]},{"id":"g1","name":"Everyone","everyone":true,"members":[{"subject":"u1","role":"member"},{"subject":"u2","role":"manager"}],"agents":["refunds","gone"]},{"id":"g3","name":"Accounts","members":[],"agents":[]}]}"#
        let people = #"{"members":[{"subject":"u1","role":"admin","status":"active","email":"zoe@example.com","you":true},{"subject":"u2","role":"member","status":"active","email":""},{"subject":"u3","role":"member","status":"invited","email":"amy@example.com"}]}"#
        let (account, transport) = client([(200, groups), (200, people)])
        let read = try await account.groups()
        let persons = try await account.people()
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/groups", "GET /v1/tenant/members"])
        // Only those on the account now, by label; the default group first, then by name, case aside.
        let (shownGroups, shownPeople) = People.shown(groups: read, people: persons)
        try expectEqual(shownGroups.map(\.id), ["g1", "g3", "g2"])
        try expectEqual(shownPeople.map(\.label), ["u2", "zoe@example.com"])
        try expectEqual(persons[0].you, true)
        // Managers first, then by label.
        try expectEqual(People.sorted(shownGroups[0], people: shownPeople).map(\.subject), ["u2", "u1"])
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(shownGroups[0].shownName(words), "Everyone")
        try expectEqual(shownGroups[2].shownName(words), "finance")
        let names = ["refunds": "Refunds"]
        try expectEqual(People.uses(shownGroups[0], name: { names[$0] }, words: words), "Uses Refunds")
        try expectEqual(People.uses(shownGroups[1], name: { names[$0] }, words: words), "Uses no taf yet")
        try expectEqual(People.accountLine(account: "Acme", signedInAs: "zoe@example.com", email: "zoe@example.com", count: shownPeople.count, words: words), "Acme · 2 people")
        try expectEqual(People.accountLine(account: "zoe@example.com", signedInAs: nil, email: "zoe@example.com", count: 1, words: words), "1 person")
    }),
    Test("a group or person that doesn't read fails the read, as the iPad's, never a list with someone missing", awaiting: {
        for (path, body) in [("groups", #"{"groups":[{"id":"g1","name":"A","members":[]}]}"#), ("people", #"{"members":[{"subject":"u1","status":"active"}]}"#)] {
            let (account, _) = client([(200, body)])
            do {
                if path == "groups" { _ = try await account.groups() } else { _ = try await account.people() }
                throw Failure(description: "\(path) was read")
            } catch let error as KIFFError {
                try expectEqual(error, .unreadable)
            }
        }
    }),
    Test("who manages the Cards and each taf, as KIFF says: no capabilities leaves it to KIFF, no access shows nothing", awaiting: {
        func me(_ json: String) throws -> Me { try AccountClient.decoder.decode(Me.self, from: Data(json.utf8)) }
        try expectEqual(try me(#"{"capabilities":["cards.manage","members.manage"]}"#).managesCards, true)
        try expectEqual(try me(#"{"capabilities":["tafs.use"]}"#).managesCards, false)
        try expectEqual(try me("{}").managesCards, true)
        let (account, transport) = client([(200, #"{"agents":{"rae":{"use":true,"manage":true},"ben":{"use":true},"odd":7}}"#)])
        let read = try? await account.myAccess()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me/access")
        // One agent that doesn't read fails the read, as the iPad's: then nothing is shown.
        try expectEqual(read, nil)
        let (fine, _) = client([(200, #"{"agents":{"rae":{"use":true,"manage":true},"ben":{"use":true}}}"#)])
        let access = try await fine.myAccess()
        try expectEqual(Access.manages(access["rae"]), true)
        try expectEqual(Access.manages(access["ben"]), false)
        try expectEqual(Access.manages(access["gone"]), false)
    }),
]
