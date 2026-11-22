import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")

/// The iPad's fixture (RecordFieldsTests.swift:42-43): a payment and its hash as KIFF signs it.
private let paymentA = "pi_3USeCjHcvoaKP2f008Vgp"
private func hashOf(_ value: String) -> String { "sha256:" + ReceiptCheck.hexEncode(testSHA256(Data(value.utf8))) }

/// One Record line with KIFF's `call` as tafs cloud passes it.
private func line(_ id: String, kind: String = "done", taf: String = "taf_1", call: String, detail: String = "tafs cloud's line",
                  next: String? = nil) throws -> Record.Entry {
    let after = next.map { #","next":\#($0)"# } ?? ""
    let json = #"{"id":"\#(id)","at":"2026-11-14T17:30:00Z","kind":"\#(kind)","title":"Refund a payment","detail":"\#(detail)","time":"18:30","taf":{"id":"\#(taf)","name":"Refunds"},"call":\#(call)\#(after)}"#
    return try AccountClient.decoder.decode(Record.Entry.self, from: Data(json.utf8))
}

private func hashed(_ entity: String = "tc-a", arg: String? = "payment", hash: String? = nil, extra: String = "") -> String {
    let argPart = arg.map { #","on_arg":"\#($0)""# } ?? ""
    return #"{"proposal_id":"p1","entity_id":"\#(entity)","on_hash":"\#(hash ?? hashOf(paymentA))"\#(argPart)\#(extra)}"#
}

private func named(_ entry: Record.Entry, refs: [String: String]) -> Record.Entry {
    Record.naming([Record.Group(id: "g", title: "", entries: [entry])], refs: refs, sha256: testSHA256)[0].entries[0]
}

private let signed = #","receipt":{"trace_id":"01KTRACE","status":"signed"}"#

let recordNamingTests: [Test] = [
    Test("a value is KIFF's only as its exact SHA-256, in lowercase hex after sha256:") {
        let hash = hashOf(paymentA)
        try expect(hash.hasPrefix("sha256:") && hash == hash.lowercased(), hash)
        try expect(Record.isOn(paymentA, hash: hash, sha256: testSHA256), "the value itself")
        try expect(!Record.isOn(paymentA.lowercased(), hash: hash, sha256: testSHA256), "another case")
        try expect(!Record.isOn(paymentA + " ", hash: hash, sha256: testSHA256), "a trailing space")
        try expect(!Record.isOn(paymentA, hash: String(hash.dropFirst("sha256:".count)), sha256: testSHA256), "no prefix")
        try expect(!Record.isOn(paymentA, hash: "sha256:" + hash.dropFirst("sha256:".count).uppercased(), sha256: testSHA256), "uppercase hex")
        // sha256("foo"), as Linux's fixture.
        try expect(Record.isOn("foo", hash: "sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae", sha256: testSHA256), "foo")
    },
    Test("a line names only the value KIFF hashed, by its key, as the iPad's naming") {
        let en = try Words(language: "en", folder: strings)
        let entry = try line("a", call: hashed())
        try expectEqual(entry.entityID, "tc-a")
        try expectEqual(entry.onArg, "payment")
        try expectEqual(entry.onValue, nil)
        try expectEqual(entry.onText(en), nil)
        let a = named(entry, refs: ["tc-a": paymentA, "tc-b": "pi_other"])
        try expectEqual(a.onValue, paymentA)
        try expectEqual(a.onText(en), "payment …08Vgp")
        // Another value under its key, its value under another key, or no key: nothing.
        try expectEqual(named(entry, refs: ["tc-a": "pi_NOT_KIFFS"]).onValue, nil)
        try expectEqual(named(entry, refs: ["tc-b": paymentA]).onValue, nil)
        try expectEqual(named(try line("b", call: #"{"proposal_id":"p1","entity_id":"tc-a","on_arg":"payment"}"#), refs: ["tc-a": paymentA]).onValue, nil)
        try expectEqual(named(try line("c", call: #"{"proposal_id":"p1","on_hash":"\#(hashOf(paymentA))"}"#), refs: ["tc-a": paymentA]).onValue, nil)
        // The noun: its argument with spaces, else "it"; a short value whole.
        try expectEqual(named(try line("d", call: hashed(arg: "payment_intent")), refs: ["tc-a": paymentA]).onText(en), "payment intent …08Vgp")
        try expectEqual(named(try line("e", call: hashed(arg: nil)), refs: ["tc-a": paymentA]).onText(en), "it …08Vgp")
        try expectEqual(named(try line("f", call: hashed(hash: hashOf("pi_123"))), refs: ["tc-a": "pi_123"]).onText(en), "payment pi_123")
        try expectEqual(named(try line("g", call: hashed(hash: hashOf("pi_1234"))), refs: ["tc-a": "pi_1234"]).onText(en), "payment …_1234")
        // Its second line starts with it.
        try expectEqual(a.line(en), "payment …08Vgp · tafs cloud's line")
        // The receipt's On fact: the argument and the whole value.
        try expectEqual(a.receiptOn, "payment \(paymentA)")
        try expectEqual(entry.receiptOn, nil)
    },
    Test("only tafs with a hashed line not yet named are read, each once") {
        let groups = [Record.Group(id: "g", title: "", entries: [
            try line("a", taf: "t1", call: hashed()), try line("b", taf: "t1", call: hashed()),
            try line("c", taf: "t2", call: #"{"proposal_id":"p"}"#), try line("d", taf: "t3", call: hashed()),
        ])]
        try expectEqual(Record.tafsToName(groups), ["t1", "t3"])
        let done = Record.naming(groups, refs: ["tc-a": paymentA], sha256: testSHA256)
        try expectEqual(Record.tafsToName(done), [])
    },
    Test("a taf's calls are read as the iPad's, whole or not at all", awaiting: {
        let transport = CannedTransport([(200, #"{"calls":[{"invocation":"tc-a","value":"pi_1","at":"2026-11-14T17:30:00Z"}]}"#),
                                         (200, #"{"calls":[{"invocation":"tc-a"}]}"#), (200, "{}")])
        let client = CloudClient(transport: transport, session: session, language: "en")
        let refs = try await client.calls("taf a/b")
        try expectEqual(refs, [Record.CallRef(invocation: "tc-a", value: "pi_1")])
        try expectEqual(transport.sent[0].method, "GET")
        try expectEqual(transport.sent[0].path, "/v1/tafs/taf%20a%2Fb/calls")
        try expectEqual(transport.sent[0].body, Data())
        var unread = 0
        for _ in 0..<2 {
            do { _ = try await client.calls("t") } catch { unread += 1 }
        }
        try expectEqual(unread, 2)
    }),
    Test("KIFF's key and reason are drawn without direction or control characters") {
        try expectEqual(Record.visible("a\u{202E}b\u{2066}c\u{200F}d"), "abcd")
        try expectEqual(Record.visible("a\nb\tc\u{7}d"), "a b c d")
        let entry = try line("a", call: #"{"proposal_id":"p","entity_id":"tc-‮a","reason":"over\nthe limit"}"#)
        try expectEqual(entry.entityID, "tc-a")
        try expectEqual(entry.reason, "over the limit")
    },
]

private func held(_ id: String, proposal: String? = nil, kind: String? = nil) -> String {
    let p = proposal.map { #","proposal_id":"\#($0)""# } ?? ""
    let k = kind.map { #","kind":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","subject":"agt_refunds","action":"stripe_create_refund","created_at":"2026-11-14T17:30:00Z"\#(p)\#(k)}"#
}

private func heldCalls(_ items: [String]) throws -> [HeldCall] {
    try AccountClient.decoder.decode([HeldCall].self, from: Data("[\(items.joined(separator: ","))]".utf8))
}

let recordWaitingTests: [Test] = [
    Test("a held call decodes its proposal and kind, and one without them still reads") {
        let calls = try heldCalls([held("ex1", proposal: "p1", kind: "approval"), held("ex2")])
        try expectEqual(calls[0].proposalID, "p1")
        try expectEqual(calls[0].kind, "approval")
        try expectEqual(calls[1].proposalID, nil)
        try expectEqual(calls[1].kind, nil)
        // A Card unit request isn't a held call; one without a proposal is matched by its own id.
        let proposals = HeldCall.heldProposals(try heldCalls([held("ex1", proposal: "p1"), held("ex2"), held("ex3", proposal: "p3", kind: "card_unit")]))
        try expectEqual(proposals, ["p1", "ex2"])
    },
    Test("a held line says no longer waiting only once KIFF's held list is read without it, as the iPad's") {
        let en = try Words(language: "en", folder: strings)
        let entry = named(try line("a", kind: "held", call: hashed(extra: signed)), refs: ["tc-a": paymentA])
        // Unread (or failed): still waiting, as the iPad before its list is read.
        try expect(Record.isWaiting(entry, held: nil), "unread")
        try expectEqual(entry.line(en, waiting: Record.isWaiting(entry, held: nil)), "payment …08Vgp · waiting for you · nothing sent yet")
        // Read, and KIFF still holds it.
        try expect(Record.isWaiting(entry, held: ["p1"]), "still held")
        // Read, and KIFF no longer holds it.
        try expect(!Record.isWaiting(entry, held: ["p9"]), "no longer held")
        try expectEqual(entry.line(en, waiting: false), "payment …08Vgp · no longer waiting · nothing sent")
        // Matched by the hold's id when it has no proposal; a Card unit request never holds it.
        try expect(Record.isWaiting(entry, held: HeldCall.heldProposals(try heldCalls([held("p1")]))), "by the hold's id")
        try expect(!Record.isWaiting(entry, held: HeldCall.heldProposals(try heldCalls([held("x", proposal: "p1", kind: "card_unit")]))), "card unit")
        // A line without a proposal id still waits.
        let bare = try line("b", kind: "held", call: #"{"held":true}"#, detail: "Waiting for you")
        try expect(Record.isWaiting(bare, held: []), "no proposal")
        // A held line with neither receipt nor answer, still waiting: tafs cloud's words.
        try expectEqual(bare.line(en), "Waiting for you")
        // Any other kind ignores waiting.
        let done = try line("c", call: #"{"proposal_id":"p"\#(signed)}"#)
        try expectEqual(done.line(en, waiting: false), "within its Card · done")
    },
]

/// A chain as KIFF writes it, with a decision step that signed what it acted on (sha256("foo")) and its
/// amount, then the hold's answer: Linux's fixture (receipt_view.rs RAW). The steps are read, not checked.
private let onHashReceipt = #"{"trace_id":"01KTRACE","causal_chain":[{"sequence":1,"kind":"decision","occurred_at":"2026-10-21T00:41:03.12Z","message":"held","data_hash":"aa","data":{"on_hash":"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae","amount":{"value":"150.00","unit":"EUR"}}},{"sequence":2,"kind":"hold_settled","occurred_at":"2026-10-21T00:41:04.12Z","data_hash":"bb","data":{"answer":"approved_once"}}]}"#

/// The same chain signed by a test key the way KIFF signs (keccak256 of the chain's SHA-256 in hex,
/// secp256k1 with recovery), so the payment check is seen on a receipt this check verifies.
let onHashSignedReceipt = #"{"schema_version":"0.1","trace_id":"01KTRACE","issued_at":"2026-10-21T00:41:03.12Z","causal_chain":[{"sequence":1,"kind":"decision","actor_id":"agt_refunds","occurred_at":"2026-10-21T00:41:03.12Z","message":"held: over €100","data_hash":"aa","data":{"amount":{"unit":"EUR","value":"150.00"},"on_hash":"sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"}},{"sequence":2,"kind":"hold_settled","occurred_at":"2026-10-21T00:41:04.12Z","data_hash":"bb","data":{"answer":"approved_once"}}],"attestation":{"algorithm":"secp256k1+keccak256","signature":"bd09000aeeae543b5bedaf8482d1fc9d53cc81ddba8a1614c94ddea17b02ff2d4918ea4a18d06fb00bc42d2de2eaaf7b4bcb52bb52f0fd581129edbaf52328a500","wallet_address":"0x6d2db245f3722b83932d506613808d3f72fbe2c9"}}"#
let onHashTestSigner = "0x6d2db245f3722b83932d506613808d3f72fbe2c9"

let receiptOnHashTests: [Test] = [
    Test("a verified receipt over another payment is a mismatch, never checked; over this one it matches") {
        let check = ReceiptCheck.check(Data(onHashSignedReceipt.utf8), signer: onHashTestSigner, sha256: testSHA256, recover: Secp256k1.recover)
        try expectEqual(check, .verified(signer: onHashTestSigner))
        let steps = ReceiptSteps(Data(onHashSignedReceipt.utf8))
        let eur = Record.Amount(value: "150.00", unit: "EUR")
        try expectEqual(steps.mismatchKey(onValue: "foo", amount: eur, answer: "approved_once", sha256: testSHA256), nil)
        try expectEqual(steps.mismatchKey(onValue: "bar", amount: eur, answer: "approved_once", sha256: testSHA256), "receipt.check.payment_mismatch")
        try expect(!ReceiptCheck.showsWhatHappened(check, mismatch: true), "no What happened over another payment")
        // A line not named compares nothing: the signature's check stands, and nothing is said of the payment.
        try expectEqual(steps.mismatchKey(onValue: nil, amount: eur, answer: "approved_once", sha256: testSHA256), nil)
        // A byte changed in what was signed fails the signature, whatever the payment.
        let changed = onHashSignedReceipt.replacingOccurrences(of: "2c26b46b", with: "2c26b46c")
        try expectEqual(ReceiptCheck.check(Data(changed.utf8), signer: onHashTestSigner, sha256: testSHA256, recover: Secp256k1.recover), .failed(.signatureMismatch))
    },
    Test("what the line acted on is held to what KIFF signed, as the iPad's onMismatch") {
        let steps = ReceiptSteps(Data(onHashReceipt.utf8))
        try expectEqual(steps.steps.map(\.onHash), ["sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae", nil])
        try expect(!steps.onMismatch(nil, sha256: testSHA256), "no value: nothing compared")
        try expect(!steps.onMismatch("foo", sha256: testSHA256), "the value KIFF signed")
        try expect(steps.onMismatch("bar", sha256: testSHA256), "another value")
        // A chain that signed none compares nothing.
        try expect(!ReceiptSteps(Data(signedReceipt.utf8)).onMismatch("bar", sha256: testSHA256), "no on_hash")
    },
    Test("the first mismatch is named in the iPad's order: payment, amount, answer") {
        let steps = ReceiptSteps(Data(onHashReceipt.utf8))
        let eur = Record.Amount(value: "150", unit: "eur")
        func key(_ on: String?, _ amount: Record.Amount?, _ answer: String?) -> String? {
            steps.mismatchKey(onValue: on, amount: amount, answer: answer, sha256: testSHA256)
        }
        try expectEqual(key("foo", eur, "approved_once"), nil)
        try expectEqual(key(nil, nil, nil), nil)
        try expectEqual(key("bar", Record.Amount(value: "15", unit: "EUR"), "refused"), "receipt.check.payment_mismatch")
        try expectEqual(key("foo", Record.Amount(value: "15", unit: "EUR"), "refused"), "receipt.check.amount_mismatch")
        try expectEqual(key("foo", eur, "refused"), "receipt.check.answer_mismatch")
        // A verified receipt that doesn't match draws no "What happened".
        try expect(!ReceiptCheck.showsWhatHappened(.verified(signer: "0x1"), mismatch: key("bar", eur, nil) != nil), "hidden")
        try expect(!ReceiptCheck.showsWhatHappened(.notSignedYet, mismatch: false), "unsigned")
        let en = try Words(language: "en", folder: strings)
        try expectEqual(en("receipt.check.payment_mismatch"), "The payment on this line doesn't match KIFF's receipt.")
    },
]

let recordNextStepTests: [Test] = [
    Test("a call's next step is tafs cloud's, and one without words isn't one") {
        let next = try line("a", kind: "not_done", call: #"{"proposal_id":"p"}"#,
                            next: #"{"kind":"reconnect","words":"Connect Stripe again","tool":"stripe_create_refund"}"#).next
        try expectEqual(next, Record.NextStep(kind: "reconnect", words: "Connect Stripe again", tool: "stripe_create_refund"))
        try expectEqual(try line("b", call: "{}").next, nil)
        try expectEqual(try line("c", call: "{}", next: #"{"kind":"try_later","words":"  "}"#).next, nil)
        try expectEqual(try line("d", call: "{}", next: #"{"kind":"try_later"}"#).next, nil)
        try expectEqual(try line("e", call: "{}", next: #""soon""#).next, nil)
    },
    Test("a case's steps keep their next step, and its failed step decodes its own") {
        let step = #"{"id":"e2","at":"2026-11-14T17:30:00Z","kind":"not_done","title":"Refund","detail":"Not sent","time":"18:30","taf":{"id":"t1","name":"Refunds"},"call":{"proposal_id":"p"},"next":{"kind":"ask_coach","words":"Ask Coach","message":"Why?"}}"#
        let body = #"{"about":"Order 1042","steps":[\#(step)],"failed":{"id":"e2","words":"The refund didn't go through.","next":{"kind":"try_later","words":"Try later"}}}"#
        let found = try AccountClient.decoder.decode(Record.Case.self, from: Data(body.utf8))
        try expectEqual(found.steps[0].next, Record.NextStep(kind: "ask_coach", words: "Ask Coach", message: "Why?"))
        try expectEqual(found.failed?.next, Record.NextStep(kind: "try_later", words: "Try later"))
    },
]

let receiptFactsTests: [Test] = [
    Test("the receipt's facts are the iPad's: its state, outcome and who decided") {
        let en = try Words(language: "en", folder: strings)
        let done = try line("a", call: #"{"proposal_id":"p","amount":{"value":"150.00","unit":"EUR"}}"#)
        try expectEqual(done.receiptLabel(en), "Done within the Card")
        try expectEqual(done.receiptOutcome(en), "Done.")
        try expectEqual(done.receiptDecidedBy(en), "KIFF, against the Card")
        let moved = try AccountClient.decoder.decode(Record.Entry.self, from: Data(#"{"id":"m","at":"2026-11-14T17:30:00Z","kind":"done","title":"t","detail":"d","time":"t","amount_text":"€150.00","taf":{"id":"t1","name":"R"},"call":{"amount":{"value":"150.00","unit":"EUR"}}}"#.utf8))
        try expectEqual(moved.receiptOutcome(en), "Done. €150.00 moved.")
        let refused = try line("b", kind: "refused", call: #"{"proposal_id":"p","answer":{"decision":"refused","by":"admin","signed":true,"device":"Rae's iPhone"}}"#)
        try expectEqual(refused.receiptLabel(en), en("receipt.refused_by", ["who": refused.answerer(en)]))
        try expectEqual(refused.receiptOutcome(en), en("receipt.outcome.refused_by", ["who": refused.answerer(en)]))
        try expect(refused.receiptDecidedBy(en).hasSuffix(", signed on Rae's iPhone"), refused.receiptDecidedBy(en))
        let mine = try line("c", kind: "done", call: #"{"proposal_id":"p","answer":{"decision":"approved_once","you":true,"signed":true}}"#)
        try expectEqual(mine.receiptDecidedBy(en), "You, signed on your device")
        try expectEqual(mine.receiptLabel(en), en("receipt.approved_once_by", ["who": en("record.answerer.you")]))
        try expectEqual(try line("d", kind: "refused", call: "{}").receiptOutcome(en), "Not sent. Its Card refused it.")
        try expectEqual(try line("e", kind: "held", call: "{}").receiptOutcome(en), "Waiting for your answer.")
        try expectEqual(try line("e", kind: "held", call: "{}").receiptLabel(en), "Held for you")
        try expectEqual(try line("f", kind: "not_done", call: "{}", detail: "Not sent").receiptOutcome(en), "Not sent")
        try expectEqual(try line("g", kind: "approved", call: "{}").receiptDecidedBy(en), "You, approving once")
        try expectEqual(try line("h", kind: "revoked", call: "{}").receiptDecidedBy(en), "You, revoking the Card")
        try expectEqual(try line("h", kind: "revoked", call: "{}").receiptLabel(en), "Card revoked")
        try expectEqual(try line("i", kind: "started", call: "{}").receiptDecidedBy(en), "You, issuing the Card")
        try expectEqual(try line("j", kind: "new_kind", call: "{}").receiptLabel(en), "Outcome unknown")
        // Every word of it is in each language.
        for language in try Words.shipped(folder: strings) {
            let say = try Words(language: language, folder: strings)
            for e in [done, moved, refused, mine] {
                for text in [e.receiptLabel(say), e.receiptOutcome(say), e.receiptDecidedBy(say)] {
                    try expect(!text.contains("receipt.") && !text.contains("record."), "\(language): \(text)")
                }
            }
        }
    },
]
