import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")

private let held = #"""
{"exceptions":[
  {"id":"exc_1","subject":"agent_refunds","action":"stripe.refund","entity_id":"e1","status":"held",
   "title":"Refund a payment","reason_text":"€640 is over its €500 limit.","taf_about":"Dispute #4825","taf_reason":42,
   "breaches":[],"next_steps":["return first"],"can_approve_once":false,
   "created_at":"2026-11-14T18:00:00Z","expires_at":"2026-11-14T19:00:00.500Z","accounting_version":3},
  {"id":"exc_2","subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z","title":"  "}
]}
"""#

private func client(_ answers: [(Int, String)], signMessage: ((String) throws -> String)? = { _ in "SIG" }) -> (AccountClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (AccountClient(transport: transport, session: session, signMessage: signMessage), transport)
}

private func calls() async throws -> [HeldCall] {
    try await client([(200, held)]).0.heldCalls()
}

private func refusal(_ body: @autoclosure () async throws -> Void, is code: String) async throws {
    do { try await body(); throw Failure(description: "it was sent") } catch let error as KIFFError {
        try expectEqual(error, .refused(status: 0, code: code))
    }
}

let approvalsTests: [Test] = [
    Test("a held call's amount is the first parameter KIFF names a unit for, and none without one") {
        func call(_ fields: String) throws -> HeldCall {
            try AccountClient.decoder.decode(HeldCall.self, from: Data(#"{"id":"e","subject":"a","action":"refund","created_at":"2026-11-14T18:00:00Z"\#(fields)}"#.utf8))
        }
        let named = try call(#","parameters":{"Amount":64000,"count":3},"parameter_units":{"amount":{"unit":"EUR","scale":2}}"#)
        try expectEqual(named.amount, TafCard.Amount(minor: 64000, unit: "EUR", scale: 2))
        try expectEqual(named.amount?.written(language: "en"), "€640")
        // A number KIFF names no unit for is never shown as money.
        try expectEqual(try call(#","parameters":{"count":3}"#).amount, nil)
        try expectEqual(try call("").amount, nil)
        try expectEqual(try call(#","parameters":"x","parameter_units":7"#).amount, nil)
    },
    Test("a held call is read with KIFF's words as sent, and words that aren't text are left out", awaiting: {
        let (account, transport) = client([(200, held)])
        let all = try await account.heldCalls()
        try expectEqual(transport.sent[0].path, "/v1/me/card-exceptions?status=held")
        try expectEqual(all.map(\.id), ["exc_1", "exc_2"])
        try expectEqual(all[0].title, "Refund a payment")
        try expectEqual(all[0].reasonText, "€640 is over its €500 limit.")
        try expectEqual(all[0].tafAbout, "Dispute #4825")
        try expectEqual(all[0].tafReason, nil)
        try expectEqual(all[0].nextSteps, ["return first"])
        try expectEqual(all[0].canApproveOnce, false)
        try expectEqual(all[0].accountingVersion, 3)
        try expectEqual(all[1].title, nil)
        try expectEqual(all[1].canApproveOnce, true)
        try expectEqual(all[1].accountingVersion, nil)
    }),
    Test("a hold without its id or its time is unreadable, never dropped silently", awaiting: {
        for body in [#"{"exceptions":[{"subject":"a","action":"b","created_at":"2026-11-14T18:00:00Z"}]}"#,
                     #"{"exceptions":[{"id":"x","subject":"a","action":"b","created_at":"yesterday"}]}"#, "{}"] {
            do { _ = try await client([(200, body)]).0.heldCalls(); throw Failure(description: "\(body) was read") } catch let error as KIFFError {
                try expectEqual(error, .unreadable)
            }
        }
    }),
    Test("the answer's message is one field per line, with empty lines for no next step and no note") {
        let message = KIFFMessage.answer(tenant: "t1", callID: "exc_1", answer: .reject, nextStep: nil, accountingVersion: 3, signedAt: "2026-11-14T18:00:00Z")
        try expectEqual(message, "kiff.answer.v1\nt1\nexc_1\nreject\n\n\n3\n2026-11-14T18:00:00Z")
        let full = KIFFMessage.answer(tenant: "t1", callID: "exc_1", answer: .approveOnce, nextStep: "return first", noteHash: "ab", accountingVersion: 3, signedAt: "T")
        try expectEqual(full, "kiff.answer.v1\nt1\nexc_1\napprove-once\nreturn first\nab\n3\nT")
    },
    Test("only a refusal grants nothing, and a Mac with no approval key sends approvals to the phone or a passkey") {
        try expectEqual([Answer.approveOnce, .reject, .changeCard].map(\.grants), [true, false, true])
        try expectEqual(ApprovalRoute.of(.passkey), .phoneOrPasskey)
        try expectEqual(ApprovalRoute.of(.key(Data([1]))), .touchID)
    },
    Test("a refusal is signed over the hold as the person saw it, and sent to that hold", awaiting: {
        var signed = ""
        let (account, transport) = client([(200, "{}")], signMessage: { signed = $0; return "SIG" })
        let call = try await calls()[0]
        try await account.refuse(call, nextStep: "return first", at: Date(timeIntervalSince1970: 1_794_679_200))
        try expectEqual(signed, "kiff.answer.v1\nt1\nexc_1\nreject\nreturn first\n\n3\n2026-11-14T18:00:00Z")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "POST /v1/me/card-exceptions/exc_1/reject")
        try expectEqual(String(decoding: transport.sent[0].body, as: UTF8.self),
                        #"{"next_step":"return first","signature":{"signed_at":"2026-11-14T18:00:00Z","value":"SIG"}}"#)
    }),
    Test("a refusal is not sent without a key, without the hold's version, or with a next step that isn't the hold's", awaiting: {
        let all = try await calls()
        let (keyless, a) = client([(200, "{}")], signMessage: nil)
        try await refusal(try await keyless.refuse(all[0]), is: "no_device_key")
        let (account, b) = client([(200, "{}")])
        try await refusal(try await account.refuse(all[1]), is: "no_accounting_version")
        try await refusal(try await account.refuse(all[0], nextStep: "pay anyway"), is: "not_a_next_step")
        try expectEqual(a.sent.count + b.sent.count, 0)
    }),
    Test("a call is announced once, never those already waiting, and again if it is held again", awaiting: {
        let all = try await calls()
        var announced = Announced()
        try expectEqual(announced.new(in: [all[0]]).map(\.id), [])
        try expectEqual(announced.new(in: all).map(\.id), ["exc_2"])
        try expectEqual(announced.new(in: all).map(\.id), [])
        try expectEqual(announced.new(in: [all[0]]).map(\.id), [])
        try expectEqual(announced.new(in: all).map(\.id), ["exc_2"])
    }),
    Test("a notification says the app's line, then KIFF's words for the call", awaiting: {
        let all = try await calls()
        let words = try Words(language: "fr", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let first = Announcement(all[0], words: words)
        try expectEqual(first.title, words("alert.needs_you"))
        try expectEqual(first.body, "Refund a payment · €640 is over its €500 limit.")
        try expectEqual(Announcement(all[1], words: words).body, words("push.open_needs_you"))
        try expectEqual(first.id, "exc_1")
    }),
    Test("KIFF's refusal of an answer reaches the person as its code", awaiting: {
        let (account, _) = client([(409, #"{"error":"already_answered"}"#)])
        let call = try await calls()[0]
        do { try await account.refuse(call); throw Failure(description: "taken") } catch let error as KIFFError {
            try expectEqual(error, .refused(status: 409, code: "already_answered"))
        }
    }),
]
