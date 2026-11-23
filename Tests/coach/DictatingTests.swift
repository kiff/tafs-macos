import Foundation

let coachDictatingTests: [Test] = [
    Test("dictated words join the box with one space, and the hints are each once, at most 100, as the iPad's Dictation") {
        try expectEqual(Dictating.joined("", "hello"), "hello")
        try expectEqual(Dictating.joined("Hi", "there"), "Hi there")
        try expectEqual(Dictating.joined("Hi ", "there"), "Hi there")
        try expectEqual(Dictating.joined("Hi", "  "), "Hi")
        try expectEqual(Dictating.cleaned(["Stripe", " stripe ", "", "Rayo"]), ["Stripe", "Rayo"])
        try expectEqual(Dictating.cleaned((0..<150).map { "w\($0)" }).count, 100)
        try expectEqual(Dictating.hints(tafs: ["Refunds", "refunds", " "]), ["tafs", "Coach", "KIFF", "Solo", "Team", "Company", "Refunds"])
    },
    Test("the box splits at its insertion point, and what was after it stays after the words heard") {
        try expectEqual(Dictating.split("Hello world", at: 5).0, "Hello")
        try expectEqual(Dictating.split("Hello world", at: 5).1, " world")
        try expectEqual(Dictating.split("Hello", at: nil).0, "Hello")
        try expectEqual(Dictating.split("Hello", at: 5).1, "")
        try expectEqual(Dictating.split("Hello", at: -1).0, "Hello")
        try expectEqual(Dictating.rest(""), "")
        try expectEqual(Dictating.rest("world"), " world")
        try expectEqual(Dictating.rest(" world"), " world")
        try expectEqual(Dictating.rest(", then"), ", then")
    },
    Test("a new stretch of speech is told from a revision, as the iPad's startsAfresh") {
        try expectEqual(Dictating.startsAfresh("", "hello"), false)
        // A revision keeps its start.
        try expectEqual(Dictating.startsAfresh("refund ten", "refund 10"), false)
        try expectEqual(Dictating.startsAfresh("refund", "refund order"), false)
        try expectEqual(Dictating.startsAfresh("refund order 4471", "and"), true)
        // Longer: still being heard.
        try expectEqual(Dictating.startsAfresh("hi", "and tell the customer"), false)
    },
    Test("dictation starts in the language last chosen, else the app's, else the device's first, as the iPad's") {
        let have = [DictationLanguage(id: "en-US"), DictationLanguage(id: "fr-CA"), DictationLanguage(id: "es-ES")]
        try expectEqual(Dictating.starting(have: have, last: nil, app: "fr")?.id, "fr-CA")
        // The device's order picks the form.
        try expectEqual(Dictating.starting(have: have, last: nil, app: "fr-FR")?.id, "fr-CA")
        // The chip's choice is kept; a choice the device lost isn't.
        try expectEqual(Dictating.starting(have: have, last: "en-US", app: "fr")?.id, "en-US")
        try expectEqual(Dictating.starting(have: [DictationLanguage(id: "fr-CA"), DictationLanguage(id: "en-US")], last: "es-ES", app: "fr")?.id, "fr-CA")
        try expectEqual(Dictating.starting(have: have, last: nil, app: "de")?.id, "en-US")
        try expectEqual(Dictating.starting(have: [], last: nil, app: "fr"), nil)
    },
    Test("the device's own languages, one form each, the person's first, as the iPad's Dictation.Language") {
        let supported = ["en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "fr-CA", "de-DE"]
        try expectEqual(DictationLanguage.ordered(supported: supported, preferred: ["es-CO", "fr_CA"]).map(\.id), ["es-ES", "fr-CA", "de-DE", "en-GB"])
        try expectEqual(DictationLanguage.ordered(supported: ["fr-FR"], preferred: ["es-CO", "en-US"]).map(\.id), ["fr-FR"])
        try expectEqual(DictationLanguage.ordered(supported: [], preferred: ["es-CO"]), [])
        try expectEqual(DictationLanguage.bestForm(of: "en", among: ["en-AU", "en-GB", "en-US"]), "en-GB")
        try expectEqual(DictationLanguage.bestForm(of: "en", among: ["en-AU", "en-US"]), "en-US")
        try expectEqual(DictationLanguage.bestForm(of: "fr", among: ["fr-CA", "fr-FR"]), "fr-FR")
        try expectEqual(DictationLanguage.bestForm(of: "pt", among: ["pt-BR"]), "pt-BR")
        try expectEqual(DictationLanguage.bestForm(of: "fr", among: ["en-US"]), nil)
        try expectEqual(DictationLanguage.ordered(supported: ["en-AU", "en-GB", "en-US"], preferred: ["en-FR"]).map(\.id), ["en-GB"])
        try expectEqual(DictationLanguage.owners(supported: supported, keyboards: ["es-ES", "fr-FR"], preferred: ["en-US"]).map(\.id), ["es-ES", "fr-FR", "en-US"])
        // None of theirs on the device: every language it has.
        try expectEqual(DictationLanguage.owners(supported: ["de-DE"], keyboards: ["es-ES"], preferred: ["en-US"]).map(\.id), ["de-DE"])
        // On a Mac, with no keyboards to read, the preferred languages lead.
        try expectEqual(DictationLanguage.owners(supported: supported, keyboards: [], preferred: ["fr-FR", "en-US"]).map(\.id), ["fr-FR", "en-US"])
        try expectEqual(DictationLanguage(id: "fr-FR").label, "FR")
    },
    Test("a stretch of sound's level is its loudness from a quiet room to speech up close, 0 to 1") {
        let silence = [Float](repeating: 0, count: 64)
        let loud = [Float](repeating: 0.5, count: 64)
        try expectEqual(silence.withUnsafeBufferPointer(Dictating.level), 0)
        try expectEqual(loud.withUnsafeBufferPointer(Dictating.level), 1)
        try expectEqual([Float]().withUnsafeBufferPointer(Dictating.level), 0)
    },
    Test("the app asks for the microphone and speech recognition with the shared words, as the iPad's Info.plist") {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "App/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else { throw Failure(description: "no plist") }
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(info["NSMicrophoneUsageDescription"] as? String, words("voice.tafs_turns_your_voice_into"))
        try expectEqual(info["NSSpeechRecognitionUsageDescription"] as? String, words("voice.tafs_turns_your_voice_into"))
        // The camera, for Take photo, in the iPad's words (its project.yml) without the pairing code, which a Mac never reads.
        try expectEqual(info["NSCameraUsageDescription"] as? String,
                        "tafs takes a photo to attach to your message. A photo goes only with that message, to your own chat.")
        // Under the hardened runtime: the microphone and the camera, and nothing else.
        let ent = try Data(contentsOf: URL(fileURLWithPath: "App/tafs.entitlements"))
        guard let rights = try PropertyListSerialization.propertyList(from: ent, format: nil) as? [String: Any] else { throw Failure(description: "no entitlements") }
        try expectEqual(Set(rights.keys), ["com.apple.security.device.audio-input", "com.apple.security.device.camera"])
    },
]
