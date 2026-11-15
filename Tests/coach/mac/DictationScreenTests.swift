import Foundation
import SwiftUI

/// A recognizer the test drives, as the iPad's `FakeSpeech`: what permission says, whether the
/// language runs on the device, and what it hears.
@MainActor
private final class StandInSpeech: SpeechEngine {
    var refused: String?
    var notHere: String?
    var have: [Dictation.Language] = [.english, .spanish]
    var startedWith: (language: Dictation.Language, hints: [String])?
    var stops = 0
    var starts = 0
    /// From this start on, starting throws: the microphone was taken.
    var failFrom: Int?
    private var onText: (@Sendable (String, Bool) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onEnd: (@Sendable (String?) -> Void)?

    func authorize() async -> String? { refused }
    func languages() -> [Dictation.Language] { have }
    var noLanguage: String { "no language" }
    func unavailable(_ language: Dictation.Language) -> String? { notHere }
    func start(language: Dictation.Language, hints: [String], onText: @escaping @Sendable (String, Bool) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void, onEnd: @escaping @Sendable (String?) -> Void) throws {
        starts += 1
        if let failFrom, starts >= failFrom { throw URLError(.cannotConnectToHost) }
        startedWith = (language, hints)
        self.onText = onText
        self.onLevel = onLevel
        self.onEnd = onEnd
    }
    func stop() { stops += 1 }

    func hear(_ words: String, done: Bool = false) { onText?(words, done) }
    func sound(_ level: Float) { onLevel?(level) }
    func end(_ why: String? = nil) { onEnd?(why) }
}

/// Lets the main actor run what the recognizer handed it.
@MainActor
private func settle() async {
    for _ in 0..<4 { await Task.yield() }
}

let coachDictationMacTests: [Test] = [
    Test("a refused permission says why and how, and writes nothing, as the iPad's", awaiting: { @MainActor in
        let speech = StandInSpeech()
        speech.refused = Words.app("voice.microphone_off_tafs_turn_settings")
        let dictation = Dictation(engine: speech, language: .english)
        var box = "Refund"
        await dictation.start(text: box, hints: []) { box = $0 }
        try expectEqual(dictation.state, .blocked(Words.app("voice.microphone_off_tafs_turn_settings")))
        try expect(speech.startedWith == nil, "nothing listens without permission")
        try expectEqual(box, "Refund")
        dictation.dismiss()
        try expectEqual(dictation.state, .idle)
    }),
    Test("a language not on the device, or none at all, says so and listens to nothing", awaiting: { @MainActor in
        let speech = StandInSpeech()
        speech.notHere = Words.app("voice.dictation_not_available_right_try")
        let dictation = Dictation(engine: speech, language: .english)
        await dictation.start(text: "", hints: []) { _ in }
        try expectEqual(dictation.state, .blocked(Words.app("voice.dictation_not_available_right_try")))
        let none = StandInSpeech()
        none.have = []
        let empty = Dictation(engine: none, language: .english)
        await empty.start(text: "", hints: []) { _ in }
        try expectEqual(empty.state, .blocked("no language"))
        try expect(speech.startedWith == nil && none.startedWith == nil, "nothing listened")
    }),
    Test("words go into the box after what was there, and stay there unsent once stopped", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        var box = "Please"
        var writes = 0
        await dictation.start(text: box, hints: ["Rayo", "Stripe", "rayo"]) { box = $0; writes += 1 }
        try expectEqual(dictation.state, .listening)
        try expectEqual(speech.startedWith?.hints ?? [], ["Rayo", "Stripe"])
        speech.hear("refund order")
        await settle()
        speech.hear("refund order 4471")
        await settle()
        try expectEqual(box, "Please refund order 4471")
        dictation.stop()
        try expectEqual(dictation.state, .idle)
        try expectEqual(speech.stops, 1)
        speech.hear("late words")
        await settle()
        try expectEqual(box, "Please refund order 4471")
        try expectEqual(writes, 2)
    }),
    Test("after a pause the next words go after the earlier ones, never over them", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        var box = "Hi"
        await dictation.start(text: box, hints: []) { box = $0 }
        speech.hear("refund order")
        await settle()
        speech.hear("refund order 4471", done: true)
        await settle()
        speech.hear("and tell")
        await settle()
        speech.hear("and tell the customer")
        await settle()
        try expectEqual(box, "Hi refund order 4471 and tell the customer")
        speech.hear("thanks")
        await settle()
        try expectEqual(box, "Hi refund order 4471 and tell the customer thanks")
        speech.hear("thanks a lot")
        await settle()
        try expectEqual(box, "Hi refund order 4471 and tell the customer thanks a lot")
    }),
    Test("cancel puts the box back as it was before dictating", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        var box = "Hi"
        await dictation.start(text: box, hints: []) { box = $0 }
        speech.hear("refund everything")
        await settle()
        try expectEqual(box, "Hi refund everything")
        dictation.cancel()
        try expectEqual(box, "Hi")
        try expectEqual(dictation.state, .idle)
    }),
    Test("the recognizer's own end listens again until it's quiet; a failed restart and repeated errors say why", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        var box = ""
        await dictation.start(text: box, hints: []) { box = $0 }
        speech.hear("Halt the refunds")
        await settle()
        speech.end()
        await settle()
        try expectEqual(dictation.state, .listening)
        try expectEqual(speech.starts, 2)
        speech.hear("now")
        await settle()
        try expectEqual(box, "Halt the refunds now")
        speech.end(Words.app("voice.stopped"))
        await settle()
        speech.end()
        await settle()
        try expectEqual(dictation.state, .listening)
        speech.end()
        await settle()
        try expectEqual(dictation.state, .idle)
        try expectEqual(box, "Halt the refunds now")

        let failing = StandInSpeech()
        failing.failFrom = 2
        let broken = Dictation(engine: failing, language: .english)
        var kept = ""
        await broken.start(text: kept, hints: []) { kept = $0 }
        failing.hear("Refund")
        await settle()
        failing.end()
        await settle()
        guard case .blocked(let why) = broken.state else { throw Failure(description: "state \(broken.state)") }
        try expect(why != Words.app("voice.stopped"), "the restart's own why")
        try expectEqual(kept, "Refund")

        let erring = StandInSpeech()
        let erred = Dictation(engine: erring, language: .english)
        await erred.start(text: "", hints: []) { _ in }
        for _ in 0..<3 {
            erring.end(Words.app("voice.stopped"))
            await settle()
        }
        try expectEqual(erred.state, .blocked(Words.app("voice.stopped")))
        try expectEqual(erring.starts, 3)
    }),
    Test("switching language listens again in the other, after what was heard; the levels are the latest only", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        var box = ""
        await dictation.start(text: box, hints: []) { box = $0 }
        speech.hear("Refund")
        await settle()
        await dictation.switchLanguage(text: box, hints: []) { box = $0 }
        try expectEqual(dictation.language, .spanish)
        try expectEqual(speech.startedWith?.language, .spanish)
        try expectEqual(dictation.state, .listening)
        speech.hear("el pedido")
        await settle()
        try expectEqual(box, "Refund el pedido")
        for i in 0..<60 { speech.sound(Float(i % 10) / 10) }
        await settle()
        try expectEqual(dictation.levels.count, Dictation.levelCount)
        dictation.stop()
        try expectEqual(dictation.levels, [])
    }),
    Test("the screenshot: the mic, the language switch and the listening bar in Coach's message bar", awaiting: { @MainActor in
        let speech = StandInSpeech()
        let dictation = Dictation(engine: speech, language: .english)
        await dictation.start(text: "", hints: []) { _ in }
        for i in 0..<48 { speech.sound(Float((i * 7) % 10) / 10) }
        await settle()
        let view = VStack(spacing: 0) {
            HStack {
                Spacer()
                MicButton(dictation: dictation, text: .constant("Refund order 4471"))
            }
            .padding(12)
            DictationBar(dictation: dictation)
        }
        .frame(width: 480, height: 140)
        .background(Theme.background)
        .environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 480, height: 140)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/coach-mic-en.png"))
    }),
]
