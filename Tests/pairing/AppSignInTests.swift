import Foundation

// The in-app sign-in's own part (`AppSignIn`), KIFF's two routes for it, the welcome's tick and age line: the iPad's
// `AppSignInTests` and `OnboardingTests`, test for test where the Mac has the same thing.

private let session = #"{"access_token":"tok","token_type":"Bearer","expires_in":7776000,"tenant":"t1","subject":"u1"}"#
private let strings = URL(fileURLWithPath: ".shared/app/strings")
private func english() throws -> Words { try Words(language: "en", folder: strings) }
private func fields(_ request: HTTPRequest) throws -> [String: String] {
    try JSONDecoder().decode([String: String].self, from: request.body)
}
private func failure(_ url: String, state: String = "s_1") -> AppSignIn.Failure? {
    do { _ = try AppSignIn.code(from: URL(string: url)!, state: state); return nil } catch { return error as? AppSignIn.Failure }
}

let pairingAppSignInTests: [Test] = [
    // MARK: PKCE and the sheet's address

    Test("the challenge is S256 of the verifier: RFC 7636 Appendix B") {
        let pkce = AppSignIn.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        try expectEqual(pkce.challenge(sha256: testSHA256), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    },
    Test("a verifier and a state are 32 random bytes each: 43 base64url characters, never the same twice") {
        let a = AppSignIn.PKCE.make(), b = AppSignIn.PKCE.make()
        try expectEqual(a.verifier.count, 43)
        try expect(a.verifier != b.verifier, "random")
        let state = AppSignIn.makeState()
        try expectEqual(state.count, 43)
        try expect(state != AppSignIn.makeState(), "random")
        for s in [a.verifier, a.challenge(sha256: testSHA256), state] {
            try expect(s.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")) == nil, s)
        }
    },
    Test("the sheet opens KIFF's authorize with PKCE, the exact redirect and the state, in a language KIFF's page has") {
        let base = URL(string: "https://api.kiff.dev")!
        let url = AppSignIn.authorizeURL(base: base, challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", state: "s_1", language: "fr")
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw Failure(description: "no URL") }
        try expectEqual(parts.scheme! + "://" + parts.host! + parts.path, "https://api.kiff.dev/oauth/authorize")
        let q = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expectEqual(q, ["response_type": "code", "client_id": "tafs-app", "redirect_uri": "dev.kiff.tafs:/oauth",
                            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "code_challenge_method": "S256",
                            "state": "s_1", "ui_locales": "fr"])
        let japanese = AppSignIn.authorizeURL(base: base, challenge: "c", state: "s_1", language: "ja")
        try expect(!japanese.absoluteString.contains("ui_locales"), "a language KIFF's page doesn't have opens it in English")
        let hinted = AppSignIn.authorizeURL(base: base, challenge: "c", state: "s_1", language: "en", loginHint: "a@b.example")
        try expect(hinted.absoluteString.contains("login_hint=a@b.example"), "the hint")
    },

    // MARK: What comes back

    Test("only KIFF's redirect with this sign-in's state gives its code; anything else is refused before it's read") {
        try expectEqual(try AppSignIn.code(from: URL(string: "dev.kiff.tafs:/oauth?code=c_1&state=s_1")!, state: "s_1"), "c_1")
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1&state=s_2"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs:/oauth?error=access_denied&state=s_2"), .wrongState)
        try expectEqual(failure("tafs://oauth?code=c_1&state=s_1"), .wrongState)
    },
    Test("only the exact redirect, path included, with one state and one code") {
        try expectEqual(failure("dev.kiff.tafs:/elsewhere?code=c_1&state=s_1"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs://oauth?code=c_1&state=s_1"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1&state=s_1&state=s_1"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1&state=s_2&state=s_1"), .wrongState)
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1&code=c_2&state=s_1"), .refused("duplicate_code"))
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=c_1&state=s_1"), nil)
    },
    Test("KIFF's errors on the redirect, each told its own way: declined says nothing, not on says so") {
        try expectEqual(failure("dev.kiff.tafs:/oauth?error=access_denied&state=s_1"), .closed)
        try expectEqual(failure("dev.kiff.tafs:/oauth?error=temporarily_unavailable&state=s_1"), .unavailable)
        try expectEqual(failure("dev.kiff.tafs:/oauth?error=unsupported_client&state=s_1"), .refused("unsupported_client"))
        try expectEqual(failure("dev.kiff.tafs:/oauth?error=invalid_request&error_description=x&state=s_1"), .refused("invalid_request"))
        try expectEqual(failure("dev.kiff.tafs:/oauth?code=&state=s_1"), .refused("no_code"))
        let words = try english()
        try expectEqual(AppSignIn.why(AppSignIn.Failure.closed, words: words), nil)
        try expectEqual(AppSignIn.why(CancellationError(), words: words), nil)
        try expectEqual(AppSignIn.why(AppSignIn.Failure.unavailable, words: words), "Signing in didn't work.")
        try expectEqual(AppSignIn.why(AppSignIn.Failure.refused("unsupported_client"), words: words), "Signing in inside the app isn't on yet.")
        try expectEqual(AppSignIn.why(AppSignIn.Failure.refused("invalid_request"), words: words), "Signing in didn't work.")
        try expectEqual(AppSignIn.why(KIFFError.signInNotOn(words: "Bientôt."), words: words), "Bientôt.")
        try expectEqual(AppSignIn.why(KIFFError.signInNotOn(words: "  "), words: words), "Signing in inside the app isn't on yet.")
        try expectEqual(AppSignIn.why(KIFFError.termsOutdated, words: words), words("onboarding.terms_changed"))
    },

    // MARK: KIFF's routes

    Test("the terms version in force is read with no session", awaiting: {
        let transport = CannedTransport([(200, #"{"terms_version":"2026-11-20"}"#)])
        let version = try await KIFFClient(transport: transport).appTerms()
        try expectEqual(version, "2026-11-20")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/auth/app/terms")
        try expectEqual(transport.sent[0].headers["Authorization"], nil)
        let empty = CannedTransport([(200, #"{"terms_version":""}"#)])
        do { _ = try await KIFFClient(transport: empty).appTerms(); throw Failure(description: "an empty version was taken") }
        catch KIFFError.unreadable {}
    }),
    Test("the code goes to KIFF's app token route with its verifier, the terms version and this Mac as the device flow sends it", awaiting: {
        let transport = CannedTransport([(200, session)])
        let got = try await KIFFClient(transport: transport).appToken(code: "c_1", verifier: "v_1", termsVersion: "2026-11-20",
                                                                       publicKey: Data([1, 2, 3]), keyStore: "software", name: "A Mac",
                                                                       approval: .passkey)
        try expectEqual(got.accessToken, "tok")
        let sent = transport.sent[0]
        try expectEqual(sent.method + " " + sent.path, "POST /v1/auth/app/token")
        try expectEqual(sent.headers["Authorization"], nil)
        let device = KIFFClient.device(publicKey: Data([1, 2, 3]), keyStore: "software", name: "A Mac", approval: .passkey)
        try expectEqual(try fields(sent), device.merging(["client_id": "tafs-app", "code": "c_1", "code_verifier": "v_1",
                                                          "redirect_uri": "dev.kiff.tafs:/oauth", "terms_version": "2026-11-20"]) { a, _ in a })
        try expectEqual(device, ["public_key": "AQID", "key_store": "software", "device_name": "A Mac", "platform": "macos",
                                 "kind": "other", "approval": "passkey"])
    }),
    Test("changed terms and signing in inside the app being off are KIFF's own answers, never a plain refusal", awaiting: {
        let outdated = CannedTransport([(409, #"{"error":"terms_outdated"}"#)])
        do { _ = try await KIFFClient(transport: outdated).appToken(code: "c", verifier: "v", termsVersion: "old", publicKey: Data([1]),
                                                                    keyStore: "enclave", name: "M", approval: .passkey)
             throw Failure(description: "taken") } catch KIFFError.termsOutdated {}
        let off = CannedTransport([(400, #"{"error":"unsupported_client","words":"Pas encore."}"#)])
        do { _ = try await KIFFClient(transport: off).appTerms(); throw Failure(description: "taken") }
        catch KIFFError.signInNotOn(let words) { try expectEqual(words, "Pas encore.") }
    }),
    Test("a pairing's claim carries the ticked terms version, and none when the welcome has no tick", awaiting: {
        let transport = CannedTransport([(200, session), (200, session)])
        let client = KIFFClient(transport: transport)
        _ = try await client.claimPairing(nonce: "n", publicKey: "p", proof: "x", termsVersion: "2026-11-20")
        _ = try await client.claimPairing(nonce: "n", publicKey: "p", proof: "x")
        try expectEqual(try fields(transport.sent[0])["terms_version"], "2026-11-20")
        try expectEqual(try fields(transport.sent[1])["terms_version"], nil)
    }),

    // MARK: The welcome

    Test("the tick starts unticked, and Continue waits on it") {
        var tick = ConsentTick()
        try expect(!tick.canContinue, "unticked")
        tick.toggle()
        try expect(tick.canContinue, "ticked")
        tick.toggle()
        try expect(!tick.canContinue, "unticked again")
    },
    Test("the age line is the country's own age where it's above 16, else the line every country reads, from ages.json") {
        let words = try english(), ages = try MinimumAge(folder: strings)
        try expectEqual(ages.standard, 16)
        for country in ["IN", "BR", "CO", "ID", "br"] {
            try expectEqual(Onboarding.ageLine(region: country, ages: ages, words: words), "You must be at least 18.")
            try expectEqual(Onboarding.raisedAgeLine(region: country, ages: ages, words: words), "You must be at least 18.")
        }
        for country in ["US", "FR", nil] as [String?] {
            try expectEqual(Onboarding.ageLine(region: country, ages: ages, words: words), words("onboarding.age"))
            try expectEqual(Onboarding.raisedAgeLine(region: country, ages: ages, words: words), nil)
        }
        // The number as the language writes it.
        let arabic = try Words(language: "ar", folder: strings)
        try expect(Onboarding.ageLine(region: "IN", ages: ages, words: arabic).contains("١٨"), "Arabic digits")
    },
    Test("the cards show once, only with the onboarding on; the first Home takes tafs cloud's line first") {
        try expect(Onboarding.showsCards(on: true, seen: false), "first time")
        try expect(!Onboarding.showsCards(on: true, seen: true), "seen")
        try expect(!Onboarding.showsCards(on: false, seen: false), "off")
        try expect(Onboarding.showsFirstHome(on: true, mayUseCoach: true) && !Onboarding.showsFirstHome(on: true, mayUseCoach: false)
                   && !Onboarding.showsFirstHome(on: false, mayUseCoach: true), "first Home")
        let words = try english()
        let cloud = Onboarding.firstHomeLines(cloud: "Ask Coach for your first taf.", words: words)
        try expectEqual(cloud.title, "Ask Coach for your first taf.")
        try expectEqual(cloud.lead, nil)
        let none = Onboarding.firstHomeLines(cloud: "", words: words)
        try expectEqual(none.title, "No tafs yet.")
        try expectEqual(none.lead, words("onboarding.home_lead"))
    },
    Test("KIFF's own Terms and Privacy open in kiff.dev's language, beside tafs's") {
        try expectEqual(LegalPages.kiffTerms("fr"), "https://kiff.dev/fr/terms")
        try expectEqual(LegalPages.kiffPrivacy("zh-Hant"), "https://kiff.dev/zh/privacy")
        try expectEqual(LegalPages.kiffTerms("ar"), "https://kiff.dev/terms")
    },
]
