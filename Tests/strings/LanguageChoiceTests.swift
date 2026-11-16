import Foundation

private func scratch() -> UserDefaults {
    let name = "tafs.tests.language.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let shipped = ["en", "de", "fr", "es", "it", "pt", "nl", "pl"]

let languageChoiceTests: [Test] = [
    Test("a chosen language is kept for this Mac and read back; none kept follows the Mac") {
        let defaults = scratch()
        try expectEqual(LanguageChoice.saved(defaults), nil)
        LanguageChoice.save("pl", defaults)
        try expectEqual(LanguageChoice.saved(defaults), "pl")
        LanguageChoice.save(nil, defaults)
        try expectEqual(LanguageChoice.saved(defaults), nil)
    },
    Test("the chosen language wins over the Mac's, and nil follows the Mac's preferred languages") {
        try expectEqual(LanguageChoice.language(chosen: "de", preferred: ["fr-FR", "en"], shipped: shipped), "de")
        try expectEqual(LanguageChoice.language(chosen: nil, preferred: ["fr-FR", "en"], shipped: shipped), "fr")
        try expectEqual(LanguageChoice.language(chosen: nil, preferred: ["ja"], shipped: shipped), "en")
    },
    Test("a kept code that isn't shipped falls back to the Mac's language, never to no words") {
        try expectEqual(LanguageChoice.language(chosen: "ja", preferred: ["es-ES"], shipped: shipped), "es")
        try expectEqual(LanguageChoice.language(chosen: "", preferred: [], shipped: shipped), "en")
    },
    Test("every request follows the chosen language, as Accept-Language", awaiting: {
        let transport = CannedTransport([(200, #"{"devices":[]}"#)])
        let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
        let language = LanguageChoice.language(chosen: "nl", preferred: ["en"], shipped: shipped)
        _ = try await AccountClient(transport: transport, session: session, language: language).devices()
        try expectEqual(transport.sent[0].headers["Accept-Language"], "nl")
    }),
]
