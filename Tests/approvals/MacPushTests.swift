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
        // On, but Apple's service gave no token: what's held is taken back, never left to alert a Mac that can't hear.
        try expectEqual(MacPush.step(wanted: true, token: nil, sound: true, held: held), .unregister(token: token))
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
