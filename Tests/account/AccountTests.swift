import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")

private func client(_ answers: [(Int, String)], sign: ((HTTPRequest) throws -> String)? = nil) -> (AccountClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (AccountClient(transport: transport, session: session, language: "fr", sign: sign), transport)
}

let accountClientTests: [Test] = [
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
        let offered = try Words.offered(folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(Set(declared), Set(offered))
        try expectEqual(AppInfo.version(info), "0.1 (4)")
        // The Dock and Finder show the app's own icon: Info.plist names it, and its 1024-point source is there.
        try expectEqual(info["CFBundleIconFile"] as? String ?? "", "tafs")
        let icon = try Data(contentsOf: URL(fileURLWithPath: "App/AppIcon.png"))
        try expectEqual(Array(icon.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let side = { (at: Int) in icon[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        try expectEqual([side(16), side(20)], [1024, 1024])
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
        // A list that isn't one fails the read, as the iPad's synthesized `Account`.
        try expectEqual(try? me(#"{"capabilities":"cards.manage"}"#), nil)
        let (account, transport) = client([(200, #"{"agents":{"rae":{"use":true,"manage":true},"ben":{"use":true},"odd":7}}"#)])
        let read = try? await account.myAccess()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me/access")
        // One agent that doesn't read fails the read, as the iPad's: then nothing is shown.
        try expectEqual(read, nil)
        // Each flag is required, as the iPad's synthesized `Access`: one missing or not a Bool, or
        // groups that aren't a list, fails the whole read.
        for agents in [#"{"ben":{"use":true}}"#, #"{"ben":{"use":true,"oversee":false,"manage":"yes"}}"#,
                       #"{"ben":{"use":true,"oversee":false,"manage":false,"groups":"g1"}}"#] {
            let (strict, _) = client([(200, #"{"agents":"# + agents + "}")])
            let read = try? await strict.myAccess()
            try expectEqual(read, nil)
        }
        let (fine, _) = client([(200, #"{"agents":{"rae":{"use":true,"oversee":true,"manage":true,"groups":["g1"]},"ben":{"use":true,"oversee":false,"manage":false}}}"#)])
        let access = try await fine.myAccess()
        try expectEqual(access["rae"]?.groups, ["g1"])
        try expectEqual(Access.manages(access["rae"]), true)
        try expectEqual(Access.manages(access["ben"]), false)
        try expectEqual(Access.manages(access["gone"]), false)
    }),
    Test("Export my chats reads tafs cloud's export and splits it into its two files, as the iPad's", awaiting: {
        let export = #"{"exported_at":"2026-11-15T10:00:00Z","readable":"Refunds\nYou: hello","chats":[{"taf":"Refunds"}],"url":"a/b"}"#
        let transport = CannedTransport([(200, export), (200, "[1]"), (503, #"{"error":"down"}"#)])
        let cloud = CloudClient(transport: transport, session: session, language: "fr")
        let files = try await cloud.exportChats()
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/me/chats/export")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(files.text, "Refunds\nYou: hello")
        // Pretty, sorted, slashes as they are, and no readable text in it.
        try expectEqual(String(decoding: files.json, as: UTF8.self), "{\n  \"chats\" : [\n    {\n      \"taf\" : \"Refunds\"\n    }\n  ],\n  \"exported_at\" : \"2026-11-15T10:00:00Z\",\n  \"url\" : \"a/b\"\n}")
        let notAnObject = try? await cloud.exportChats()
        try expect(notAnObject == nil, "an answer that isn't an object isn't an export")
        let refused = try? await cloud.exportChats()
        try expect(refused == nil, "a refusal isn't an export")
    }),
    Test("the two files are tafs-chats.json and tafs-chats.txt, replacing the last export's, and removed at sign-out") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: folder.appendingPathComponent("old.txt"))
        let files = try ChatsExport.write((json: Data("{}".utf8), text: "hello"), in: folder)
        try expectEqual(files.map(\.lastPathComponent), ["tafs-chats.json", "tafs-chats.txt"])
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["tafs-chats.json", "tafs-chats.txt"])
        try expectEqual(try String(contentsOf: files[1]), "hello")
        ChatsExport.removeFiles(in: folder)
        try expectEqual(FileManager.default.fileExists(atPath: folder.path), false)
    },
    Test("a taf's grants are KIFF's, read by its agent as written in the path, each one strictly", awaiting: {
        let grants = #"{"grants":[{"group":"g1"},{"subject":"u2"},{}]}"#
        let (account, transport) = client([(200, grants), (200, #"{"grants":[{"group":7}]}"#), (200, "{}")])
        let read = try await account.shares(agent: "refunds-bot_1.a")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/agents/refunds-bot_1.a/grants")
        try expectEqual(read, [Shares.Share(group: "g1"), Shares.Share(subject: "u2"), Shares.Share()])
        let mistyped = try? await account.shares(agent: "a/b")
        try expect(mistyped == nil, "a group that isn't words doesn't read")
        try expectEqual(transport.sent[1].path, "/v1/agents/a%2Fb/grants")
        let none = try? await account.shares(agent: "a")
        try expect(none == nil, "an answer without grants doesn't read")
    }),
    Test("who a taf is shared with, as the iPad's ShareLine: everyone alone, groups and people by name, never the reader") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let groups = try JSONDecoder().decode([People.Group].self, from: Data(#"[{"id":"g0","name":"Everyone","everyone":true,"members":[],"agents":[]},{"id":"g1","name":"Support","members":[],"agents":[]}]"#.utf8))
        let people = try JSONDecoder().decode([People.Person].self, from: Data(#"[{"subject":"u1","role":"admin","status":"active","email":"Zoe@Example.com"},{"subject":"u2","role":"member","status":"active","email":"ana@acme.com"},{"subject":"u3","role":"member","status":"active","email":"","you":true}]"#.utf8))
        let line = { (shares: [Shares.Share]?) in Shares.sharedWith(shares, groups: groups, people: people, email: "zoe@example.com", words: words) }
        try expectEqual(line(nil), "Sharing…")
        try expectEqual(line([Shares.Share(group: "g0")]), "Shared with everyone")
        try expectEqual(line([Shares.Share(group: "g1"), Shares.Share(subject: "u2"), Shares.Share(subject: "u9")]), "Shared with " + words.list(["Support", "ana@acme.com", "u9"]))
        // The reader, by KIFF's mark, by their email, or by a subject that is their email.
        try expectEqual(line([Shares.Share(subject: "u1"), Shares.Share(subject: "u3"), Shares.Share(subject: "ZOE@example.com")]), "Not shared")
        try expectEqual(line([]), "Not shared")
        // Everyone among others is named as a group, not as its own sentence.
        try expectEqual(line([Shares.Share(group: "g0"), Shares.Share(group: "g1")]), "Shared with " + words.list(["Everyone", "Support"]))
    },
]
