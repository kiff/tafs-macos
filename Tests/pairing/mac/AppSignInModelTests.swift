import Foundation

// Continue on the new welcome, as the iPad's `AppSignInTests` "Signing in" group: the sheet, the code traded with its
// verifier and the ticked Terms version, and each way it ends.

private let terms = (200, #"{"terms_version":"2026-11-20"}"#)
private let newTerms = (200, #"{"terms_version":"2026-12-01"}"#)
private let sessionAnswer = (200, #"{"access_token":"tok","token_type":"Bearer","expires_in":60,"tenant":"t1","subject":"u1","device_id":"dev_1"}"#)
private let outdated = (409, #"{"error":"terms_outdated"}"#)

/// The sheet, as a test drives it: it answers with KIFF's redirect for the state it was opened with, or as told.
@MainActor
private final class StandInSheet: KIFFSheet {
    enum Answer { case code(String), state(String), error(Error), query(String) }
    var answers: [Answer]
    private(set) var opened: [URL] = []
    init(_ answers: [Answer]) { self.answers = answers }

    func open(_ url: URL, callbackScheme: String) async throws -> URL {
        opened.append(url)
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
        switch answers.removeFirst() {
        case .code(let code): return URL(string: "\(callbackScheme):/oauth?code=\(code)&state=\(state)")!
        case .state(let other): return URL(string: "\(callbackScheme):/oauth?code=c_9&state=\(other)")!
        case .query(let query): return URL(string: "\(callbackScheme):/oauth?\(query)&state=\(state)")!
        case .error(let error): throw error
        }
    }
}

@MainActor
private final class Clock { var now = Date(timeIntervalSince1970: 1_794_679_200) }

@MainActor
private func model(_ answers: [(Int, String)], sheet: StandInSheet, clock: Clock? = nil,
                   store: MemoryStore = MemoryStore(), phone: Bool = false) throws -> (SignInModel, CannedTransport) {
    let clock = clock ?? Clock()
    let transport = CannedTransport(answers)
    let key = try DeviceKey.load(from: store, enclave: false)
    let model = SignInModel(client: KIFFClient(transport: transport), key: key, approval: .passkey, sessions: SessionStore(store: store),
                            deviceName: "A Mac", sleep: { _ in }, open: { _ in }, now: { clock.now }, sheet: sheet, onboarding: true)
    Words.app = (try? Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))) ?? Words.app
    // Continue's tests hold the phone's half still: ticking the box would show its code, and claim, by itself.
    if !phone { model.show(.welcome) }
    return (model, transport)
}

private func fields(_ request: HTTPRequest) throws -> [String: String] {
    try JSONDecoder().decode([String: String].self, from: request.body)
}

let pairingAppSignInMacTests: [Test] = [
    Test("Continue: the Terms read with the tick, the sheet with PKCE, then the code, its verifier and that version to KIFF", awaiting: { @MainActor in
        let sheet = StandInSheet([.code("c_1")])
        let (model, transport) = try model([terms, sessionAnswer], sheet: sheet)
        await model.readTerms()
        try expectEqual(model.termsVersion, "2026-11-20")
        await model.signInInApp(language: "fr")
        try expectEqual(transport.sent.count, 1)
        await model.toggleTick()
        await model.signInInApp(language: "fr")
        try expectEqual(model.session?.tenant, "t1")
        try expectEqual(model.justConnected, true)
        guard let url = sheet.opened.first, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw Failure(description: "no sheet") }
        let q = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expectEqual(url.host, "api.kiff.dev")
        try expectEqual(q["code_challenge_method"], "S256")
        try expectEqual(q["ui_locales"], "fr")
        let sent = try fields(transport.sent[1])
        try expectEqual(transport.sent[1].path, "/v1/auth/app/token")
        try expectEqual(sent["code"], "c_1")
        try expectEqual(sent["terms_version"], "2026-11-20")
        // The verifier sent is the one whose S256 the sheet carried.
        try expectEqual(AppSignIn.PKCE(verifier: sent["code_verifier"] ?? "").challenge(sha256: testSHA256), q["code_challenge"])
        try expectEqual(sent["platform"], "macos")
        try expectEqual(sent["key_store"], "software")
    }),
    Test("closing the sheet or declining on KIFF's page signs nothing in and says nothing", awaiting: { @MainActor in
        let sheet = StandInSheet([.error(AppSignIn.Failure.closed), .query("error=access_denied")])
        let (model, transport) = try model([terms], sheet: sheet)
        await model.toggleTick()
        await model.signInInApp(language: "en")
        await model.signInInApp(language: "en")
        try expectEqual(model.session, nil)
        try expectEqual(model.problem, nil)
        try expectEqual(model.tick.canContinue, true)
        try expectEqual(transport.sent.map(\.path), ["/v1/auth/app/terms"])
    }),
    Test("another state's code is never traded, and signing in didn't work is said", awaiting: { @MainActor in
        let (model, transport) = try model([terms], sheet: StandInSheet([.state("someone-else")]))
        await model.toggleTick()
        await model.signInInApp(language: "en")
        try expectEqual(model.session, nil)
        try expectEqual(model.problem, "Signing in didn't work.")
        try expect(!transport.sent.contains { $0.path == "/v1/auth/app/token" }, "nothing traded")
    }),
    Test("signing in inside the app being off is said in KIFF's words", awaiting: { @MainActor in
        let (model, _) = try model([terms, (400, #"{"error":"unsupported_client","words":"Not yet."}"#)], sheet: StandInSheet([.code("c_1")]))
        await model.toggleTick()
        await model.signInInApp(language: "en")
        try expectEqual(model.problem, "Not yet.")
    }),
    Test("changed Terms untick the box and say so; the new tick sends the kept code with the new version, the page not opened twice", awaiting: { @MainActor in
        let sheet = StandInSheet([.code("c_1")])
        let (model, transport) = try model([terms, outdated, newTerms, sessionAnswer], sheet: sheet)
        await model.toggleTick()
        await model.signInInApp(language: "en")
        try expectEqual(model.tick.canContinue, false)
        try expectEqual(model.termsChanged, true)
        try expectEqual(model.termsVersion, "2026-12-01")
        try expectEqual(model.problem, nil)
        await model.toggleTick()
        try expectEqual(model.termsChanged, false)
        await model.signInInApp(language: "en")
        try expectEqual(sheet.opened.count, 1)
        try expectEqual(model.session?.tenant, "t1")
        let again = try fields(transport.sent[3])
        try expectEqual(again["code"], "c_1")
        try expectEqual(again["terms_version"], "2026-12-01")
    }),
    Test("a kept code is sent again only within its 50 seconds; past them, the page opens again", awaiting: { @MainActor in
        let clock = Clock()
        let sheet = StandInSheet([.code("c_1"), .code("c_2")])
        let (model, transport) = try model([terms, outdated, newTerms, sessionAnswer], sheet: sheet, clock: clock)
        await model.toggleTick()
        await model.signInInApp(language: "en")
        clock.now = clock.now.addingTimeInterval(51)
        await model.toggleTick()
        await model.signInInApp(language: "en")
        try expectEqual(sheet.opened.count, 2)
        try expectEqual(try fields(transport.sent[3])["code"], "c_2")
    }),
    Test("only changed Terms keep the code: after any other refusal, the next Continue opens the page again", awaiting: { @MainActor in
        let sheet = StandInSheet([.code("c_1"), .code("c_2")])
        let (model, transport) = try model([terms, (400, #"{"error":"invalid_grant"}"#), sessionAnswer], sheet: sheet)
        await model.toggleTick()
        await model.signInInApp(language: "en")
        try expectEqual(model.problem, "Signing in didn't work.")
        try expectEqual(model.tick.canContinue, true)
        await model.signInInApp(language: "en")
        try expectEqual(sheet.opened.count, 2)
        try expectEqual(try fields(transport.sent[2])["code"], "c_2")
    }),
    Test("the phone's code waits on the tick, and its claim carries the ticked version", awaiting: { @MainActor in
        let (model, transport) = try model([terms, (400, #"{"error":"authorization_pending"}"#), (400, #"{"error":"expired_token"}"#)],
                                           sheet: StandInSheet([]), phone: true)
        await model.showPhoneCode()
        try expectEqual(model.phase, .welcome)
        try expectEqual(transport.sent.count, 0)
        await model.toggleTick()
        try expect(transport.sent.contains { $0.path == "/v1/pair/claim" }, "the code shown once ticked")
        let claim = try fields(transport.sent.first { $0.path == "/v1/pair/claim" }!)
        try expectEqual(claim["terms_version"], "2026-11-20")
    }),
    Test("the cards follow the celebration once on this Mac; a sign-out leaves an unticked box", awaiting: { @MainActor in
        let defaults = UserDefaults(suiteName: "cards-\(UUID().uuidString)")!
        let (model, _) = try model([terms, sessionAnswer], sheet: StandInSheet([.code("c_1")]))
        model.cardsSeen = defaults
        await model.toggleTick()
        await model.signInInApp(language: "en")
        model.celebrated()
        try expectEqual(model.showsCards, true)
        model.cardsDone()
        try expectEqual(model.showsCards, false)
        model.celebrated()
        try expectEqual(model.showsCards, false)
        model.signedOut()
        try expectEqual(model.tick.canContinue, false)
        try expectEqual(model.termsVersion, nil)
    }),
]
