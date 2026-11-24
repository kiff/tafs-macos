import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let token = String(repeating: "ab", count: 32)

let approvalsMacPushTests: [Test] = [
    Test("a Mac's push token goes to tafs cloud as the iPhone's does, with its own platform, in production", awaiting: {
        let transport = CannedTransport([(200, #"{"answers":true,"alerts":false}"#), (200, #"{"removed":true}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let status = try await cloud.registerPush(token: MacPush.token(Data(repeating: 0xAB, count: 32)), sound: false)
        try expectEqual(status, MacPush.Status(answers: true, alerts: false))
        try await cloud.unregisterPush(token: token)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/push", "DELETE /v1/push/\(token)"])
        let body = try JSONSerialization.jsonObject(with: transport.sent[0].body) as? [String: Any]
        try expectEqual(body?["device_token"] as? String, token)
        try expectEqual(body?["platform"] as? String, "macos")
        try expectEqual(body?["environment"] as? String, "production")
        try expectEqual(body?["sound"] as? Bool, false)
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
    }),
    Test("the token is sent while alerts are on, again only when it or the sound changes, and taken back when they're off") {
        let held = MacPush.Registered(token: token, sound: true)
        try expectEqual(MacPush.step(wanted: true, token: token, sound: true, held: nil), .register(token: token, sound: true))
        try expectEqual(MacPush.step(wanted: true, token: token, sound: true, held: held), MacPush.Step.none)
        try expectEqual(MacPush.step(wanted: true, token: token, sound: false, held: held), .register(token: token, sound: false))
        try expectEqual(MacPush.step(wanted: true, token: "cd" + token.dropFirst(2), sound: true, held: held), .register(token: "cd" + token.dropFirst(2), sound: true))
        // Off, or signed out: tafs cloud's is taken back; with none held, nothing is sent.
        try expectEqual(MacPush.step(wanted: false, token: nil, sound: true, held: held), .unregister(token: token))
        try expectEqual(MacPush.step(wanted: false, token: nil, sound: true, held: nil), MacPush.Step.none)
        // At launch, or when tafs cloud says it doesn't alert this Mac: registered again, even with the same token kept.
        try expectEqual(MacPush.step(wanted: true, token: token, sound: true, held: held, again: true), .register(token: token, sound: true))
        try expectEqual(MacPush.step(wanted: false, token: nil, sound: true, held: held, again: true), .unregister(token: token))
        // On, but Apple's service gave no token: what's held is taken back, never left to alert a Mac that can't hear.
        try expectEqual(MacPush.step(wanted: true, token: nil, sound: true, held: held), .unregister(token: token))
    },
    Test("turning alerts on hands tafs cloud KIFF's alert target and the kinds chosen; what alerts this Mac is read for its token", awaiting: {
        let transport = CannedTransport([(200, "{}"), (200, #"{"enabled":true,"sound":true,"kinds":[{"id":"holds","title":"Held calls","words":"With sound","enabled":true},{"id":"briefs","title":"Your brief","words":"Quiet","enabled":false}],"answering":{"title":"A taf answered someone","tafs":[{"id":"taf_1","name":"Support"}]}}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let target = MacPush.AlertTarget(id: "at_1", signingSecret: "s3cret")
        _ = try? await cloud.registerPush(token: token, sound: true, target: target, kinds: ["briefs": false])
        let body = try JSONSerialization.jsonObject(with: transport.sent[0].body) as? [String: Any]
        try expectEqual((body?["alert_target"] as? [String: String]) ?? [:], ["id": "at_1", "signing_secret": "s3cret"])
        try expectEqual((body?["kinds"] as? [String: Bool]) ?? [:], ["briefs": false])
        let alerts = try await cloud.deviceAlerts(token: token)
        try expectEqual(transport.sent[1].method + " " + transport.sent[1].path, "GET /v1/push")
        try expectEqual(transport.sent[1].headers["Tafs-Device-Token"], token)
        try expectEqual(alerts.kinds.map(\.id), ["holds", "briefs"])
        try expectEqual(alerts.answering?.tafs.map(\.name), ["Support"])
        try expectEqual(alerts.kinds(setting: "briefs", to: true), ["holds": true, "briefs": true])
        // Without a target or kinds, neither is sent.
        let plain = try JSONEncoder().encode(MacPush.Body(deviceToken: token, sound: true))
        try expect(!String(decoding: plain, as: UTF8.self).contains("alert_target") && !String(decoding: plain, as: UTF8.self).contains("kinds"), "nothing extra")
    }),
    Test("KIFF's alert target points at tafs cloud's alerts, signed by the device key", awaiting: {
        let transport = CannedTransport([(200, #"{"id":"at_1","signing_secret":"s3cret"}"#)])
        let account = AccountClient(transport: transport, session: session, sign: { _ in "t=1,v1=SIG" })
        let target = try await account.registerAlertTarget()
        try expectEqual(target, MacPush.AlertTarget(id: "at_1", signingSecret: "s3cret"))
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/me/alert-targets")
        try expectEqual(transport.sent[0].headers["KIFF-Device-Signature"], "t=1,v1=SIG")
        let body = try JSONSerialization.jsonObject(with: transport.sent[0].body) as? [String: String]
        try expectEqual(body?["url"], "https://cloud.tafs.kiff.dev/v1/kiff/alerts")
    }),
    Test("a clicked push opens where tafs cloud says, as the iPad's: a hold, a brief's alert and a handed step in Needs you") {
        try expectEqual(MacPush.destination(["hold_id": "h1", "open": "needs-you"]), .needsYou)
        try expectEqual(MacPush.destination(["brief_kind": "urgent"]), .needsYou)
        try expectEqual(MacPush.destination(["brief_kind": "brief"]), .needsYou)
        // `brief_kind` doesn't override an `open` tafs cloud sent.
        try expectEqual(MacPush.destination(["brief_kind": "brief", "open": "taf:1"]), .other("taf:1"))
        try expectEqual(MacPush.destination(["handoff": "step_1"]), .step("step_1"))
        try expectEqual(MacPush.destination(["brief_kind": "weekly"]), nil)
        try expect(MacPush.isBrief(["brief_kind": "urgent"]) && !MacPush.isBrief(["kind": "brief"]), "only brief_kind")
    },
    Test("what tafs cloud holds is kept per account") {
        let defaults = UserDefaults(suiteName: "MacPushTests-\(UUID().uuidString)")!
        MacPush.Registered.save(MacPush.Registered(token: token, sound: false), to: defaults, account: "t-a")
        try expectEqual(MacPush.Registered.load(from: defaults, account: "t-a"), MacPush.Registered(token: token, sound: false))
        try expectEqual(MacPush.Registered.load(from: defaults, account: "t-b"), nil)
        MacPush.Registered.save(nil, to: defaults, account: "t-a")
        try expectEqual(MacPush.Registered.load(from: defaults, account: "t-a"), nil)
    },
    Test("push is built only with PUSH=1, and the signed build carries aps-environment only with its profile (sources)") {
        let build = try String(contentsOf: URL(fileURLWithPath: "scripts/build.sh"), encoding: .utf8)
        try expect(build.contains(#"[ "${PUSH:-0}" = "1" ] && FLAGS="-D PUSH""#), "the flag")
        let dmg = try String(contentsOf: URL(fileURLWithPath: "scripts/dmg.sh"), encoding: .utf8)
        try expect(dmg.contains(#"cp "$PROFILE" "$APP/Contents/embedded.provisionprofile""#), "the profile, with PUSH=1")
        try expect(dmg.contains(#"aps-environment is signed in without PUSH=1 and its profile"#), "never without it")
        let plain = try String(contentsOf: URL(fileURLWithPath: "App/tafs.entitlements"), encoding: .utf8)
        try expect(!plain.contains("aps-environment"), "the usual entitlements have no push")
        let push = try String(contentsOf: URL(fileURLWithPath: "App/tafs-push.entitlements"), encoding: .utf8)
        try expect(push.contains("com.apple.developer.aps-environment") && push.contains("R54YWFRK4B.bot.tafs.macos"), "push's own")
        // AppKit is asked for a token only in a PUSH build.
        let app = try String(contentsOf: URL(fileURLWithPath: "Sources/App/approvals/PushToken.swift"), encoding: .utf8)
        try expect(app.contains("#if PUSH\n            if waiting.count == 1 { NSApplication.shared.registerForRemoteNotifications() }"), "registered only with PUSH")
    },
]
