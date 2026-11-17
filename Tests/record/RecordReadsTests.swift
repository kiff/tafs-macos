import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")

/// One call in the Record, with its own `call` (KIFF's, as tafs cloud passes it).
private func call(_ id: String, at: String = "2026-11-14T17:30:00Z", kind: String = "done", amount: String? = "€150.00",
                  call: String = #"{"proposal_id":"p"}"#, detail: String = "Done, within its Card") -> String {
    let text = amount.map { #","amount_text":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","at":"\#(at)","kind":"\#(kind)","title":"Refund a payment","detail":"\#(detail)","time":"18:30","taf":{"id":"taf_1","name":"Refunds"},"call":\#(call)\#(text)}"#
}

private func entry(_ json: String) throws -> Record.Entry {
    try AccountClient.decoder.decode(Record.Entry.self, from: Data(json.utf8))
}

private func groups(_ entries: [String]) throws -> [Record.Group] {
    let body = #"{"entries":[],"groups":[{"id":"g","title":"","entries":[\#(entries.joined(separator: ","))]}]}"#
    return try AccountClient.decoder.decode(Record.Page.self, from: Data(body.utf8)).groups
}

private let signed = #""receipt":{"trace_id":"01KTRACE","status":"signed"}"#

let recordReadsTests: [Test] = [
    Test("a read is KIFF's call.read_only, as the iPad decodes it; absent or not a bool, the line reads as a call") {
        try expectEqual(try entry(call("a", call: #"{"proposal_id":"p","read_only":true}"#)).readOnly, true)
        try expectEqual(try entry(call("b", call: #"{"proposal_id":"p","read_only":false}"#)).readOnly, false)
        try expectEqual(try entry(call("c")).readOnly, false)
        let odd = try entry(call("d", call: #"{"proposal_id":"p","read_only":"yes"}"#))
        try expectEqual(odd.readOnly, false)
        try expectEqual(odd.title, "Refund a payment")
    },
    Test("the pinned Activity contract's entry reads as a Record line, with its taf: not a read, and tafs cloud's line") {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/taf-activity.json"))) as? [String: Any]
        guard var first = ((root?["answer"] as? [String: Any])?["entries"] as? [[String: Any]])?.first else { throw Failure(description: "no entry") }
        first["taf"] = ["id": "taf_1", "name": "Refunds"]
        let read = try AccountClient.decoder.decode(Record.Entry.self, from: JSONSerialization.data(withJSONObject: first))
        try expectEqual(read.readOnly, false)
        try expectEqual(read.receipt, nil)
        try expectEqual(read.line(try Words(language: "en", folder: strings)), read.detail)
    },
    Test("a day's reads fold apart under All, as the iPad's days; without folding every call is a line") {
        let all = try groups([
            call("a", at: "2026-11-15T09:00:00Z"),
            call("r1", at: "2026-11-15T08:00:00Z", call: #"{"proposal_id":"p","read_only":true}"#),
            call("r2", at: "2026-11-15T07:00:00Z", call: #"{"proposal_id":"p","read_only":true}"#),
            call("b", at: "2026-11-14T09:00:00Z"),
            call("r3", at: "2026-11-14T08:00:00Z", call: #"{"proposal_id":"p","read_only":true}"#),
        ])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let folded = Record.days(all, calendar: utc, foldingReads: true)
        try expectEqual(folded.map { $0.entries.map(\.id) }, [["a"], ["b"]])
        try expectEqual(folded.map { $0.reads.map(\.id) }, [["r1", "r2"], ["r3"]])
        let open = Record.days(all, calendar: utc)
        try expectEqual(open.map { $0.entries.map(\.id) }, [["a", "r1", "r2"], ["b", "r3"]])
        try expectEqual(open.map(\.reads), [[], []])
        // A day of reads alone is still a day, with no line but its fold.
        let reads = Record.days(try groups([call("r4", call: #"{"proposal_id":"p","read_only":true}"#)]), calendar: utc, foldingReads: true)
        try expectEqual(reads.map { $0.entries.count }, [0])
        try expectEqual(reads.map { $0.reads.map(\.id) }, [["r4"]])
        // The fold's words, in every language: "· 2 reads of data, within its Card · Show".
        let en = try Words(language: "en", folder: strings)
        try expectEqual("· " + en.count("record.reads", 2) + " · " + en("record.show"), "· 2 reads of data, within its Card · Show")
        try expectEqual(en.count("record.reads", 1), "1 read of data, within its Card")
        for language in try Words.shipped(folder: strings) {
            let say = try Words(language: language, folder: strings)
            for key in ["record.show", "record.hide"] { try expect(say(key) != key, "\(language) \(key)") }
            try expect(say.count("record.reads", 3) != "record.reads", "\(language) record.reads")
        }
    },
    Test("a day's spent is the iPad's: a sum for each currency of the money it moved, at the larger decimals") {
        func money(_ id: String, kind: String = "done", value: String, unit: String?, readOnly: Bool = false) -> String {
            let u = unit.map { #","unit":"\#($0)""# } ?? ""
            return call(id, kind: kind, call: #"{"proposal_id":"p","read_only":\#(readOnly),"amount":{"value":"\#(value)"\#(u)}}"#)
        }
        let entries = try [
            money("a", value: "150.00", unit: "EUR"),
            money("b", kind: "approved", value: "20.5", unit: "EUR"),
            money("c", value: "80", unit: "USD"),
            // A read with an amount counts, as on the iPad, which sums lines and reads.
            money("d", value: "0.25", unit: "EUR", readOnly: true),
            // Not money moved: held, refused; and a unit that isn't a currency, or none.
            money("e", kind: "held", value: "999", unit: "EUR"),
            money("f", kind: "refused", value: "999", unit: "EUR"),
            money("g", value: "3", unit: "messages"),
            money("h", value: "5", unit: nil),
            money("i", value: "1.5", unit: "eur"),
        ].map(entry)
        try expectEqual(Record.spent(entries), [Record.Amount(value: "170.75", unit: "EUR"), Record.Amount(value: "80", unit: "USD")])
        try expectEqual(Record.spent([]), [])
        try expectEqual(Record.spent(try [money("n", value: "-3.50", unit: "EUR"), money("m", value: "1", unit: "EUR")].map(entry)),
                        [Record.Amount(value: "-2.50", unit: "EUR")])
        // An amount Money moved doesn't keep (tafs cloud wrote no amount text) isn't summed.
        let untitled = try entry(call("x", amount: nil, call: #"{"proposal_id":"p","amount":{"value":"9","unit":"EUR"}}"#))
        try expectEqual(Record.spent([untitled]), [])
    },
    Test("a row's second line is the iPad's: who decided, then what became of it, in the shared words") {
        let en = try Words(language: "en", folder: strings)
        func line(_ kind: String, _ extra: String = "", detail: String = "tafs cloud's line") throws -> String {
            try entry(call("a", kind: kind, call: #"{"proposal_id":"p",\#(signed)\#(extra)}"#, detail: detail)).line(en)
        }
        try expectEqual(try line("done"), "within its Card · done")
        try expectEqual(try line("not_done"), "within its Card · not done")
        try expectEqual(try line("sending"), "within its Card · sent, no answer yet")
        try expectEqual(try line("unknown"), "within its Card · result unknown")
        try expectEqual(try line("refused"), "refused by its Card · nothing sent")
        try expectEqual(try line("revoked"), "Card revoked · nothing sent")
        try expectEqual(try line("approved"), "approved by you · done")
        try expectEqual(try line("done", #","outcome":"allowed","held":true"#), "approved by you · done")
        try expectEqual(try line("done", #","answer":{"decision":"approved_once","you":true}"#), "approved by you · done")
        try expectEqual(try line("refused", #","answer":{"decision":"refused","by":"admin"}"#), "refused by an admin · nothing sent")
        try expectEqual(try line("done", #","answer":{"decision":"approved_once","by":"finance_lead"}"#), "approved by someone with the role finance lead · done")
        try expectEqual(try line("done", #","answer":{"decision":"approved_once"}"#), "approved by someone else · done")
        // Held, KIFF may no longer hold it: tafs cloud's own line stands.
        try expectEqual(try line("held", detail: "Waiting for you"), "Waiting for you")
        // No receipt and no answer: tafs cloud's line, as the iPad's own.
        try expectEqual(try entry(call("b", detail: "Done, within its Card")).line(en), "Done, within its Card")
        // A receipt without its trace isn't one.
        try expectEqual(try entry(call("c", call: #"{"proposal_id":"p","receipt":{"trace_id":"","status":"pending"}}"#, detail: "d")).line(en), "d")
        // Every word of it is in each language.
        for language in try Words.shipped(folder: strings) {
            let say = try Words(language: language, folder: strings)
            for kind in ["done", "not_done", "sending", "unknown", "refused", "revoked", "approved", "started"] {
                let e = try entry(call("a", kind: kind, call: #"{"proposal_id":"p",\#(signed),"answer":{"decision":"refused","by":"viewer"}}"#))
                for part in [e.decidedLine(say), e.resultLine(say), e.answerer(say)] {
                    try expect(!part.contains("record.") && !part.contains("people.") && !part.contains("card.") && !part.isEmpty, "\(language) \(kind): \(part)")
                }
            }
        }
    },
    Test("Export receipts asks tafs cloud for the account's last days, and keeps its answer byte for byte", awaiting: {
        let body = #"{"from":"2026-11-11","to":"2026-11-17","time_zone":"Europe/Paris","receipts":[{"trace_id":"01K","causal_chain":[]}],"csv":"day,taf\n2026-11-12,Refunds\n","missing":2}"#
        let transport = CannedTransport([(200, body), (403, #"{"error":"forbidden","words":"Only someone who sees every taf can export."}"#)])
        let client = CloudClient(transport: transport, session: session, language: "fr")
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        // 23:30 UTC on the 16th is already the 17th in Paris: the last 7 days end on it.
        let range = Record.exportRange(7, today: ISO8601DateFormatter().date(from: "2026-11-16T23:30:00Z")!, calendar: paris)
        try expectEqual(range.from, "2026-11-11")
        try expectEqual(range.to, "2026-11-17")
        try expectEqual(Record.exportRange(1, today: ISO8601DateFormatter().date(from: "2026-11-16T23:30:00Z")!, calendar: paris).from, "2026-11-17")
        try expectEqual(Record.exportDays, [7, 30, 90])
        let export = try await client.exportReceipts(from: range.from, to: range.to)
        try expectEqual(transport.sent[0].method, "GET")
        try expectEqual(transport.sent[0].path, "/v1/record/receipts?from=2026-11-11&to=2026-11-17")
        try expectEqual(transport.sent[0].headers["Authorization"], "Bearer tok")
        try expectEqual(transport.sent[0].headers["Accept-Language"], "fr")
        try expectEqual(export.json, Data(body.utf8))
        try expectEqual(export.csv, "day,taf\n2026-11-12,Refunds\n")
        try expectEqual(export.missing, 2)
        try expectEqual(export.stem, "receipts-2026-11-11-to-2026-11-17")
        // Its two files, in the folder chosen; whatever else is there stays.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("record-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let files = try Record.write(export, to: folder)
        try expectEqual(files.map(\.lastPathComponent), ["receipts-2026-11-11-to-2026-11-17.json", "receipts-2026-11-11-to-2026-11-17.csv"])
        try expectEqual(try Data(contentsOf: files[0]), Data(body.utf8))
        try expectEqual(try String(contentsOf: files[1], encoding: .utf8), export.csv)
        try expectEqual(try String(contentsOf: folder.appendingPathComponent("notes.txt"), encoding: .utf8), "mine")
        try? FileManager.default.removeItem(at: folder)
        // An answer's own days never name the files: "../" or "/" in them writes nothing outside the folder.
        let hostile = #"{"from":"../../../Library/x","to":"2026/11/17","csv":"","missing":0}"#
        let named = try await CloudClient(transport: CannedTransport([(200, hostile)]), session: session).exportReceipts(from: range.from, to: range.to)
        try expectEqual(named.stem, "receipts-2026-11-11-to-2026-11-17")
        let odd = Record.ReceiptsExport(from: "../../x", to: "2026/11/17", json: Data(), csv: "", missing: 0)
        try expectEqual(odd.stem, "receipts--to-20261117")
        let box = FileManager.default.temporaryDirectory.appendingPathComponent("record-export-\(UUID().uuidString)")
        let written = try Record.write(odd, to: box)
        try expect(written.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == box.standardizedFileURL.path }, "inside the folder chosen")
        try? FileManager.default.removeItem(at: box)
        // tafs cloud decides who may: a refusal keeps its words.
        do { _ = try await client.exportReceipts(from: "2026-11-11", to: "2026-11-17"); throw Failure(description: "exported") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 403)
            try expectEqual(refusal.words, "Only someone who sees every taf can export.")
        }
        // An answer that isn't an object isn't an export.
        do { _ = try await CloudClient(transport: CannedTransport([(200, "[]")]), session: session).exportReceipts(from: "a", to: "b"); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .unreadable)
        }
    }),
    Test("Export receipts is for whoever oversees or manages every taf on tafs cloud, as the iPad's seesEveryTaf") {
        let home = #"{"tafs":[{"id":"taf_1","name":"Refunds","kiff_agent":"a1","state":"idle"},{"id":"taf_2","name":"Invoices","kiff_agent":"a2","state":"idle"},{"name":"Elsewhere","kiff_agent":"a3","state":"idle"}]}"#
        let tafs = try JSONDecoder().decode(Home.Page.self, from: Data(home.utf8)).tafs
        let oversee = Access(use: true, oversee: true), manage = Access(use: true, manage: true), use = Access(use: true)
        try expectEqual(Record.seesEveryTaf(tafs, access: ["a1": oversee, "a2": manage]), true)
        try expectEqual(Record.seesEveryTaf(tafs, access: ["a1": oversee, "a2": use]), false)
        try expectEqual(Record.seesEveryTaf(tafs, access: ["a1": oversee]), false)
        try expectEqual(Record.seesEveryTaf(tafs, access: nil), false)
        try expectEqual(Record.seesEveryTaf([], access: [:]), false)
    },
]
