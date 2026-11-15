import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

func recordEntry(_ id: String, about: String? = "Order 1042", amount: String? = "€150.00") -> String {
    let optional = [about.map { #""about":"\#($0)""# }, amount.map { #""amount_text":"\#($0)""# }].compactMap { $0 }.map { "," + $0 }.joined()
    return #"{"id":"\#(id)","at":"2026-11-14T17:30:00Z","kind":"done","title":"Refund a payment","detail":"Within its Card","time":"18:30","call":{"proposal_id":"p"},"taf":{"id":"taf_1","name":"Refunds"}\#(optional)}"#
}

let recordPage = #"{"q":"","hint":"Search by order, invoice, amount or action","entries":[\#(recordEntry("e1")),\#(recordEntry("e2", about: nil, amount: nil))],"groups":[{"id":"today","title":"Today","entries":[\#(recordEntry("e1")),\#(recordEntry("e2", about: nil, amount: nil))]}],"next_cursor":"c2","end_words":"That's everything."}"#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session, language: "pt"), transport)
}

let recordTests: [Test] = [
    Test("the Record is read as tafs cloud sends it, with its own words", awaiting: {
        let (client, transport) = cloud([(200, recordPage)])
        let page = try await client.record()
        try expectEqual(transport.sent[0].path, "/v1/record?q=")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(transport.sent[0].headers["Accept-Language"], "pt")
        try expectEqual(page.hint, "Search by order, invoice, amount or action")
        try expectEqual(page.shown.map(\.title), ["Today"])
        try expectEqual(page.entries[0].title, "Refund a payment")
        try expectEqual(page.entries[0].amountText, "€150.00")
        try expectEqual(page.entries[0].about, "Order 1042")
        try expectEqual(page.entries[0].taf, Record.Entry.Taf(id: "taf_1", name: "Refunds"))
        try expectEqual(page.entries[1].amountText, nil)
        try expectEqual(page.entries[1].about, nil)
        try expectEqual(page.nextCursor, "c2")
        try expectEqual(page.endWords, "That's everything.")
    }),
    Test("what is typed goes in the query escaped, cut at tafs cloud's limit, and a cursor continues it", awaiting: {
        let (client, transport) = cloud([(200, recordPage), (200, recordPage)])
        _ = try await client.record("Order #1042 & more/..", cursor: "a+b=")
        try expectEqual(transport.sent[0].path, "/v1/record?q=Order%20%231042%20%26%20more%2F%2E%2E&cursor=a%2Bb%3D")
        _ = try await client.record(String(repeating: "x", count: 150))
        try expectEqual(transport.sent[1].path, "/v1/record?q=" + String(repeating: "x", count: 100))
    }),
    Test("a page with no groups shows its entries as one, and nothing matched is tafs cloud's line", awaiting: {
        let (client, _) = cloud([(200, #"{"entries":[\#(recordEntry("e1"))]}"#), (200, #"{"entries":[],"none_words":"Nothing matched."}"#)])
        let ungrouped = try await client.record()
        try expectEqual(ungrouped.shown.map(\.id), ["all"])
        let none = try await client.record("zzz")
        try expect(none.isEmpty, "empty")
        try expectEqual(none.noneWords, "Nothing matched.")
    }),
    Test("a page that isn't the Record is unreadable, never empty, and a refusal keeps its code", awaiting: {
        for body in ["{}", "<html>", #"{"entries":[{"id":"e1"}]}"#] {
            do { _ = try await cloud([(200, body)]).0.record(); throw Failure(description: "\(body) was read") } catch let error as KIFFError { try expectEqual(error, .unreadable) }
        }
        do { _ = try await cloud([(409, #"{"error":"search_again"}"#)]).0.record(cursor: "old"); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 409, code: "search_again"))
        }
    }),
    Test("the filters keep the iPad's kinds, and a group left with nothing is left out") {
        func entry(_ id: String, _ kind: String, amount: Bool) -> String {
            recordEntry(id, about: nil, amount: amount ? "€10.00" : nil).replacingOccurrences(of: #""kind":"done""#, with: #""kind":"\#(kind)""#)
        }
        let entries = [entry("a", "done", amount: true), entry("b", "done", amount: false), entry("c", "approved", amount: true),
                       entry("d", "refused", amount: true), entry("e", "not_done", amount: false), entry("f", "revoked", amount: false),
                       entry("g", "held", amount: true), entry("h", "sending", amount: false), entry("i", "unknown", amount: false), entry("j", "new_kind", amount: true)]
        let body = #"{"entries":[],"groups":[{"id":"today","title":"Today","entries":[\#(entries.joined(separator: ","))]},{"id":"old","title":"Earlier","entries":[\#(entry("k", "done", amount: false))]}]}"#
        let page = try AccountClient.decoder.decode(Record.Page.self, from: Data(body.utf8))
        func ids(_ filter: Record.Filter) -> [String] { filter.keeping(page.groups).flatMap { $0.entries.map(\.id) } }
        try expectEqual(ids(.all).count, 11)
        try expectEqual(ids(.moneyMoved), ["a", "c"])
        try expectEqual(ids(.stopped), ["d", "e", "f"])
        try expectEqual(ids(.waiting), ["g", "h", "i"])
        try expectEqual(Record.Filter.moneyMoved.keeping(page.groups).map(\.id), ["today"])
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        for filter in Record.Filter.allCases { try expect(words(filter.titleKey) != filter.titleKey, filter.titleKey) }
    },
    Test("a case is every call about one thing, with the step that failed in tafs cloud's words", awaiting: {
        let body = #"{"about":"Order 1042","steps":[\#(recordEntry("e1")),\#(recordEntry("e2"))],"failed":{"id":"e2","words":"The refund didn't go through."}}"#
        let (client, transport) = cloud([(200, body)])
        let found = try await client.recordCase("Order #1042")
        try expectEqual(transport.sent[0].path, "/v1/record/cases/Order%20%231042")
        try expectEqual(found.steps.map(\.id), ["e1", "e2"])
        try expectEqual(found.failed, Record.Case.Failed(id: "e2", words: "The refund didn't go through."))
    }),
    Test("one taf's chip keeps only that taf's calls, and a day left with none is left out") {
        func entry(_ id: String, taf: String) -> String {
            #"{"id":"\#(id)","at":"2026-11-15T00:17:00Z","kind":"done","title":"t","detail":"d","time":"00:17","taf":{"id":"\#(taf)","name":"N"}}"#
        }
        let json = #"{"hint":"h","entries":[],"groups":[{"id":"d1","title":"Today","entries":[\#(entry("a", taf: "t1")),\#(entry("b", taf: "t2"))]},{"id":"d2","title":"Yesterday","entries":[\#(entry("c", taf: "t2"))]}]}"#
        let page = try AccountClient.decoder.decode(Record.Page.self, from: Data(json.utf8))
        try expectEqual(Record.only(taf: "t1", in: page.groups).map { $0.entries.map(\.id) }, [["a"]])
        try expectEqual(Record.only(taf: nil, in: page.groups).count, 2)
    },
]
