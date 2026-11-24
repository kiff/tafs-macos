import Foundation

/// WhatsApp's signup (`WhatsAppSignup`), as the other desktops take it: the page with a one-use state, and only its own
/// return, once read, for that taf, within 15 minutes.
let tafWhatsAppTests: [Test] = [
    Test("the page is tafs cloud's, with the taf and a fresh one-use state of 43 base64url characters") {
        let signup = WhatsAppSignup(taf: "taf-1", state: "s7aTe_0123456789abcdef")
        try expectEqual(signup.page()?.absoluteString,
                        "https://cloud.tafs.kiff.dev/doors/whatsapp/connect?taf=taf-1&state=s7aTe_0123456789abcdef")
        // A taf id is a query value, escaped as one.
        try expectEqual(WhatsAppSignup(taf: "a b&c+d", state: "s").page()?.query, "taf=a%20b%26c%2Bd&state=s")
        let state = WhatsAppSignup.newState()
        try expectEqual(state.count, 43)
        try expect(state.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }, state)
        try expect(WhatsAppSignup.newState() != state, "each signup its own")
    },
    Test("only this signup's return is taken: its state and taf, a code, each field once, the right address, in 15 minutes") {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        let signup = WhatsAppSignup(taf: "taf-1", state: "S1", opened: opened)
        func back(_ query: String, _ prefix: String = "tafs://doors/whatsapp") -> URL { URL(string: "\(prefix)?\(query)")! }
        let ok = "taf=taf-1&state=S1&code=c9&phone_number_id=p1&waba_id=w1"
        try expectEqual(signup.answer(back(ok), now: opened.addingTimeInterval(60)),
                        WhatsAppSignup.Back(code: "c9", phoneNumberID: "p1", wabaID: "w1"))
        // The ids may come empty, as the page sends them when Meta gave none.
        try expectEqual(signup.answer(back("taf=taf-1&state=S1&code=c9"), now: opened)?.phoneNumberID, "")
        // Another state, another taf, no code, a field twice, another address, or too late: none.
        for refused in ["taf=taf-1&state=S2&code=c9", "taf=taf-2&state=S1&code=c9", "taf=taf-1&state=S1",
                        "taf=taf-1&state=S1&code=", "taf=taf-1&state=S1&state=S1&code=c9", "taf=taf-1&taf=taf-1&state=S1&code=c9"] {
            try expectEqual(signup.answer(back(refused), now: opened), nil)
        }
        for prefix in ["tafs://doors/whatsapp/x", "tafs://other/whatsapp", "https://doors/whatsapp", "tafs://me@doors/whatsapp",
                       "tafs://doors:8080/whatsapp"] {
            try expectEqual(signup.answer(back(ok, prefix), now: opened), nil)
        }
        try expectEqual(signup.answer(URL(string: "tafs://doors/whatsapp?\(ok)#x")!, now: opened), nil)
        try expectEqual(signup.answer(back(ok), now: opened.addingTimeInterval(15 * 60 + 1)), nil)
        try expectEqual(signup.answer(back(ok), now: opened.addingTimeInterval(-1)), nil)
    },
    Test("the door is made with Meta's code and the number's ids, as the other apps send them") {
        try expectEqual(WhatsAppSignup.doorFields(.init(code: "c9", phoneNumberID: "p1", wabaID: "w1")),
                        ["code": "c9", "phone_number_id": "p1", "waba_id": "w1"])
    },
]
