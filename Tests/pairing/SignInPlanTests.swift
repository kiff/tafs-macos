/// The sign-in window's two halves, and when the phone's code is shown by itself (`SignInPlan`).
let pairingSignInPlanTests: [Test] = [
    Test("the window opens with KIFF's Continue on the left and the phone's code started on the right") {
        try expectEqual(SignInPlan.halves(.welcome, signedIn: false, asksKey: false), .init(kiff: .start, phone: .starting))
        try expectEqual(SignInPlan.showsCode(.welcome, signedIn: false, asksKey: false), true)
        try expectEqual(SignInPlan.halves(.pairing, signedIn: false, asksKey: false), .init(kiff: .start, phone: .code))
    },
    Test("a code that runs out is renewed by itself, with nothing to press") {
        try expectEqual(SignInPlan.showsCode(.codeExpired, signedIn: false, asksKey: false), true)
        try expectEqual(SignInPlan.halves(.codeExpired, signedIn: false, asksKey: false).phone, .starting)
        // A view-only Mac adding itself renews too.
        try expectEqual(SignInPlan.showsCode(.codeExpired, signedIn: true, asksKey: false), true)
    },
    Test("while the browser's sign-in waits, the phone offers Continue and starts nothing") {
        try expectEqual(SignInPlan.halves(.browser, signedIn: false, asksKey: false), .init(kiff: .code, phone: .offer))
        try expectEqual(SignInPlan.showsCode(.browser, signedIn: false, asksKey: false), false)
        try expectEqual(SignInPlan.halves(.failed(pairing: false), signedIn: false, asksKey: false), .init(kiff: .failed, phone: .offer))
    },
    Test("a failed pairing says why on the phone's half and isn't started again by itself") {
        try expectEqual(SignInPlan.halves(.failed(pairing: true), signedIn: false, asksKey: false), .init(kiff: .start, phone: .failed))
        try expectEqual(SignInPlan.showsCode(.failed(pairing: true), signedIn: false, asksKey: false), false)
        try expectEqual(SignInPlan.showsCode(.pairing, signedIn: false, asksKey: false), false)
    },
    Test("when showing the code would ask the security key (a prompt), it waits for Continue, and isn't renewed by itself") {
        for now in [SignInPlan.Now.welcome, .codeExpired] {
            try expectEqual(SignInPlan.showsCode(now, signedIn: false, asksKey: true), false)
            try expectEqual(SignInPlan.halves(now, signedIn: false, asksKey: true).phone, .offer)
        }
    },
    Test("a view-only Mac adding itself sees the phone's half alone, and a signed-in welcome starts nothing") {
        for now in [SignInPlan.Now.welcome, .pairing, .codeExpired, .failed(pairing: true)] {
            try expectEqual(SignInPlan.halves(now, signedIn: true, asksKey: false).kiff, nil)
        }
        try expectEqual(SignInPlan.showsCode(.welcome, signedIn: true, asksKey: false), false)
    },
    Test("the code's panel: the check code first, then this Mac's name") {
        let lines = SignInPlan.codeLines(eyebrow: "Your code", check: "K7Q2MX", name: "tafs on this Mac", waiting: "Waiting…")
        try expectEqual(lines, [.eyebrow("Your code"), .code("K7Q2MX"), .name("tafs on this Mac"), .waiting("Waiting…")])
        guard let code = lines.firstIndex(of: .code("K7Q2MX")), let name = lines.firstIndex(of: .name("tafs on this Mac")) else {
            throw Failure(description: "no code or name")
        }
        try expect(code < name, "the code before the name")
    },
]
