import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")

/// KIFF's usage as it sends it: a plan, its packs (the First month one first), and requests.
let kiffUsageAnswer = #"""
{"plan":"solo",
 "store":{"solo_product":"solo.monthly","packs":[
   {"id":"first","name":"First month","line":"First month · 2,000 credits","apple_product":"pack.first","once":true},
   {"id":"rayo","name":"Rayo","line":"Rayo · 5,000 credits","credits":5000,"apple_product":"pack.rayo"},
   {"id":"broken","line":"No name"}]},
 "requests":[
   {"id":"req_1","asked_by":"u2","kind":"pack","pack":"rayo","reason":"Refunds run out on the 24th.","status":"open","created_at":"2026-11-15T10:00:00Z","expires_at":"2026-11-30T23:59:59Z"},
   {"id":"req_2","asked_by":"u3","status":"declined","note":"Not this month.","created_at":"2026-11-14T10:00:00Z","expires_at":"2026-11-30T23:59:59Z"},
   {"id":"req_3"}]}
"""#

let packRequestAnswer = #"{"id":"req_9","asked_by":"u1","kind":"raise","reason":"","status":"open","created_at":"2026-11-15T10:00:00Z","expires_at":"2026-11-30T23:59:59Z"}"#

private func account(_ answers: [(Int, String)], signed: Bool = true) -> (AccountClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (AccountClient(transport: transport, session: session, sign: signed ? { _ in "t=2026-11-15T10:00:00.000Z,v1=SIG" } : nil), transport)
}

let usageRequestTests: [Test] = [
    Test("the old limit is written from the signed from_cents in the currency tafs cloud sends; none, or a bad code, is no line") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        func raise(_ currency: String) throws -> Usage.Balance.Raise? {
            let json = #"{"balance":{"state":"ok","words":"x","raise":{"words":"Raise the spend limit to €2,000","from_cents":150000"# + currency + "}}}"
            return try JSONDecoder().decode(Usage.Balance.self, from: Data(json.utf8)).raise
        }
        let eur = try raise(#","currency":"EUR""#)
        try expectEqual(eur?.currency, "EUR")
        try expectEqual(eur?.fromLine(words), words("usage.raise_limit.from", ["amount": TafCard.Amount(minor: 150000, unit: "EUR", scale: 2).written(language: "en")]))
        try expect(eur?.fromLine(words)?.contains("1,500") == true, "the figure is from_cents")
        // `from_cents` is in the currency's smallest unit: JPY has none, so 150000 is ¥150,000.
        try expectEqual(Usage.Balance.Raise.decimals("EUR"), 2)
        try expectEqual(Usage.Balance.Raise.decimals("JPY"), 0)
        try expectEqual(Usage.Balance.Raise.decimals("KWD"), 3)
        try expect(try raise(#","currency":"JPY""#)?.fromLine(words)?.contains("150,000") == true, "a currency with no decimals")
        // tafs cloud today sends none: no line, never a guessed currency.
        try expectEqual(try raise("")?.fromLine(words), nil)
        for bad in [#","currency":"eur""#, #","currency":"EURO""#, #","currency":null"#, #","currency":12"#] {
            let r = try raise(bad)
            try expectEqual(r?.currency, nil)
            try expectEqual(r?.fromCents, 150000)
        }
        // Drawn above Raise the limit, as the iPad's, and the confirm step is unchanged (sources).
        let view = try String(contentsOf: URL(fileURLWithPath: "Sources/App/usage/UsageView.swift"), encoding: .utf8)
        try expect(view.contains("if let from = raise.fromLine(words) {"), "the line is drawn")
        try expect(view.contains(#"Words.app("usage.raise_limit.prompt") + ": " + raise.words) }"#), "the prompt is as before")
    },
    Test("Raise the limit is KIFF's PUT from the limit seen, signed by the device key; the balance reads tafs cloud's offer", awaiting: {
        let (client, transport) = account([(200, "{}")])
        try await client.raiseLimit(from: 100000)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["PUT /v1/me/usage/limit"])
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self), #"{"from_cents":100000,"raise":true}"#)
        try expect(transport.sent[0].headers["KIFF-Device-Signature"] != nil, "signed")
        let offered = #"{"balance":{"state":"ok","words":"820 credits left","raise":{"words":"Raise the spend limit to €2,000","from_cents":100000}}}"#
        let balance = try JSONDecoder().decode(Usage.Balance.self, from: Data(offered.utf8))
        try expectEqual(balance.raise, Usage.Balance.Raise(words: "Raise the spend limit to €2,000", fromCents: 100000))
        // Without the limit now there's nothing to raise from: no offer.
        let noFrom = try JSONDecoder().decode(Usage.Balance.self, from: Data(#"{"balance":{"state":"ok","words":"x","raise":{"words":"Raise"}}}"#.utf8))
        try expect(noFrom.raise == nil, "no from_cents, no raise")
    }),
    Test("KIFF's usage reads as the iPad's: the plan, the packs that read, and the requests that read", awaiting: {
        let (client, transport) = account([(200, kiffUsageAnswer)])
        let usage = try await client.usage()
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["GET /v1/me/usage"])
        try expectEqual(usage.plan, "solo")
        // A pack without its name or product is left out, never the store.
        try expectEqual(usage.store?.packs.map(\.id), ["first", "rayo"])
        try expectEqual(usage.requests?.map(\.id), ["req_1", "req_2"])
        // A request from a KIFF that doesn't say its kind is for a pack.
        try expectEqual(usage.requests?[1].kind, "pack")
        try expectEqual(usage.requests?[1].reason, "")
        try expectEqual(usage.requests?[1].note, "Not this month.")
    }),
    Test("the packs listed put the First month pack first, and only while tafs cloud says it can be bought", awaiting: {
        let usage = try await account([(200, kiffUsageAnswer)]).0.usage()
        try expectEqual(usage.store?.offered(firstMonth: true).map(\.id), ["first", "rayo"])
        try expectEqual(usage.store?.offered(firstMonth: false).map(\.id), ["rayo"])
        let ready = try JSONDecoder().decode(Usage.Balance.self, from: Data(#"{"balance":{"state":"ok","words":"Fine","buy":{"packs":true,"first_month":{"ready":true}}}}"#.utf8))
        try expectEqual(ready.firstMonthReady, true)
        try expectEqual(try JSONDecoder().decode(Usage.Balance.self, from: Data(balanceAnswer.utf8)).firstMonthReady, false)
    }),
    Test("asking an admin sends a raise with no pack, or a pack, with the reason, as the iPad's askAdmin", awaiting: {
        let (client, transport) = account([(200, packRequestAnswer), (200, packRequestAnswer)])
        let asked = try await client.askAdmin(raise: true, pack: "rayo", reason: "Refunds")
        try expectEqual(asked.kind, "raise")
        _ = try await client.askAdmin(raise: false, pack: "rayo", reason: "")
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/me/pack-requests", "POST /v1/me/pack-requests"])
        try expectEqual(transport.sent.map { String(decoding: $0.body, as: UTF8.self) }, [#"{"kind":"raise","reason":"Refunds"}"#, #"{"pack":"rayo","reason":""}"#])
        // Neither is signed: asking grants nothing.
        try expectEqual(transport.sent.map { $0.headers["KIFF-Device-Signature"] }, [nil, nil])
    }),
    Test("withdrawing and declining go to the request's own path, escaped; only a decline is signed", awaiting: {
        let (client, transport) = account([(200, packRequestAnswer), (200, packRequestAnswer)])
        _ = try await client.withdrawRequest("req/1")
        _ = try await client.declineRequest("req 2", note: "Not now")
        try expectEqual(transport.sent.map(\.path), ["/v1/me/pack-requests/req%2F1/withdraw", "/v1/me/pack-requests/req%202/decline"])
        try expectEqual(transport.sent.map { String(decoding: $0.body, as: UTF8.self) }, ["{}", #"{"note":"Not now"}"#])
        try expectEqual(transport.sent.map { $0.headers["KIFF-Device-Signature"] }, [nil, "t=2026-11-15T10:00:00.000Z,v1=SIG"])
    }),
    Test("a decline without a device key isn't sent, and KIFF's refusal says its code", awaiting: {
        let (keyless, quiet) = account([(200, packRequestAnswer)], signed: false)
        do { _ = try await keyless.declineRequest("req_1", note: ""); throw Failure(description: "sent") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 0, code: "no_device_key"))
        }
        try expectEqual(quiet.sent.count, 0)
        let (client, _) = account([(409, #"{"error":"request_closed"}"#)])
        do { _ = try await client.askAdmin(raise: true, pack: nil, reason: ""); throw Failure(description: "taken") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 409, code: "request_closed"))
        }
    }),
]
