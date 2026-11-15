import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let balanceAnswer = #"{"balance":{"state":"warning","why":null,"meter_pct":82,"words":"180 credits left","detail":"Of 1,000 this month.","warning":"At this pace they run out on the 24th.","raise":null,"buy":{"solo":false,"packs":true},"credits_panel":true},"plan_line":"Solo · renews 1 December","plan_tone":"ok","home_line":null}"#
let creditsAnswer = #"{"period":{"start":"2026-11-01","end":"2026-11-30","current":true},"credits":820,"runs":412,"words":"820 credits this period","tafs":[{"taf":"taf-1","credits":600,"runs":300,"words":"Refunds · 600 credits","pace":"At this pace, about 640 this month"},{"taf":null,"credits":220,"runs":112,"words":"Removed tafs · 220 credits"},{"taf":"taf-3","words":"  "},7],"coach":null,"not_counted":{"runs":4,"words":"4 runs not counted","lines":[{"why":"coach","runs":3,"words":"Coach, included · 3 runs"},{"why":"failed","runs":1,"words":"Failed on our side · 1 run"},{"why":"x"},{"why":"y","words":7},"z",{"why":"trial","words":"Trials · 2 runs"}]},"note":"Credits renew on the 1st."}"#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

let usageTests: [Test] = [
    Test("the balance is tafs cloud's words and meter, as sent", awaiting: {
        let (client, transport) = cloud([(200, balanceAnswer)])
        let balance = try await client.balance()
        try expectEqual(transport.sent[0].path, "/v1/usage/balance")
        try expectEqual(balance.words, "180 credits left")
        try expectEqual(balance.meter, 82)
        try expectEqual(balance.state, "warning")
        try expectEqual(balance.waiting, false)
        try expectEqual(balance.warning, "At this pace they run out on the 24th.")
        try expectEqual(balance.planLine, "Solo · renews 1 December")
    }),
    Test("the meter stays within 0 to 100 as on the phones, no number is no bar, and a balance without its words is unreadable", awaiting: {
        for (pct, want) in [("140", 100), ("-3", 0), ("0", 0), ("100", 100)] {
            let body = #"{"balance":{"state":"ok","meter_pct":\#(pct),"words":"Fine"}}"#
            let balance = try await cloud([(200, body)]).0.balance()
            try expectEqual(balance.meter, want)
        }
        for pct in ["null", "\"half\""] {
            let body = #"{"balance":{"state":"ok","meter_pct":\#(pct),"words":"Fine"}}"#
            let balance = try await cloud([(200, body)]).0.balance()
            try expectEqual(balance.meter, nil)
        }
        for body in ["{}", #"{"balance":{"state":"ok"}}"#, "<html>"] {
            do { _ = try await cloud([(200, body)]).0.balance(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        do { _ = try await cloud([(503, #"{"error":"kiff_unreadable","words":"KIFF can't be read just now."}"#)]).0.balance(); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 503, code: "kiff_unreadable"))
        }
    }),
    Test("the period's credits list each taf's line, and a row that doesn't read is left out", awaiting: {
        let (client, transport) = cloud([(200, creditsAnswer), (200, creditsAnswer)])
        let credits = try await client.credits()
        try expectEqual(transport.sent[0].path, "/v1/usage/credits")
        try expectEqual(credits.words, "820 credits this period")
        try expectEqual(credits.rows.map(\.words), ["Refunds · 600 credits", "Removed tafs · 220 credits"])
        try expectEqual(credits.rows[0].pace, "At this pace, about 640 this month")
        try expectEqual(credits.rows[1].taf, nil)
        try expectEqual(credits.coach, nil)
        try expectEqual(credits.notCounted, "4 runs not counted")
        try expectEqual(credits.notCountedLines, ["Coach, included · 3 runs", "Failed on our side · 1 run", "Trials · 2 runs"])
        try expectEqual(credits.note, "Credits renew on the 1st.")
        _ = try await client.credits(previous: true)
        try expectEqual(transport.sent[1].path, "/v1/usage/credits?period=previous")
    }),
]
