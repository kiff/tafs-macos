import AppKit
import Foundation
import SwiftUI

@MainActor
private func sheet(_ language: String = "en", purpose: SecurityKeySheetPurpose = .approve,
                   attempt: @escaping (SecurityKeyPIN) async throws -> Void = { _ in },
                   tries: Int? = 8, done: @escaping (Error?) -> Void = { _ in }) -> (PINSheetModel, NSSecureTextField) {
    let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
    let model = PINSheetModel(words: words, purpose: purpose, attempt: attempt, readTries: {
        guard let tries else { throw SecurityKeyFailure.noKey }
        return tries
    }, done: done)
    let field = NSSecureTextField()
    model.reader.field = field
    return (model, field)
}

let approvalsPINSheetMacTests: [Test] = [
    Test("the PIN is read from the secure field as UTF-8 bytes, and the field is emptied", awaiting: { @MainActor in
        let (model, field) = sheet()
        field.stringValue = "4821é"
        try expectEqual(model.reader.takeBytes(), Array("4821é".utf8))
        try expectEqual(field.stringValue.isEmpty, true)
        try expectEqual(model.reader.takeBytes(), [])
    }),
    Test("the PIN reaches the key once, as typed, then its buffer is cleared and freed", awaiting: { @MainActor in
        var handed: SecurityKeyPIN?
        var seen: [UInt8]?
        var finished: [String] = []
        let (model, field) = sheet(attempt: { pin in handed = pin; seen = pin.heldBytesForTests() }, done: { finished.append($0 == nil ? "approved" : "closed") })
        field.stringValue = "4821"
        await model.approve()
        try expectEqual(seen, Array("4821".utf8))
        try expectEqual(handed?.isHeld, false)
        try expectEqual(field.stringValue.isEmpty, true)
        try expectEqual(finished, ["approved"])
    }),
    Test("a wrong PIN says the tries left, empties the field, and the sheet stays open to try again", awaiting: { @MainActor in
        var finished = 0
        let (model, field) = sheet(attempt: { _ in throw SecurityKeyFailure.wrongPIN(triesLeft: 2) }, done: { _ in finished += 1 })
        field.stringValue = "1111"
        await model.approve()
        try expectEqual(model.message, "Wrong PIN. 2 tries left before the key locks.")
        try expectEqual(model.phase, .entering)
        try expectEqual(model.locked, false)
        try expectEqual(field.stringValue.isEmpty, true)
        try expectEqual(finished, 0)
    }),
    Test("a PIN too short is refused before the key is asked", awaiting: { @MainActor in
        var asked = 0
        let (model, field) = sheet(attempt: { _ in asked += 1 })
        field.stringValue = "12"
        await model.approve()
        try expectEqual(asked, 0)
        try expectEqual(model.message, "A security key's PIN has at least 4 characters.")
    }),
    Test("authenticator data without user verification says the key couldn't sign, never its decline", awaiting: { @MainActor in
        let (model, field) = sheet(attempt: { _ in throw PasskeyRefusal.notVerified })
        field.stringValue = "4821"
        await model.approve()
        try expect(model.message?.hasPrefix("The security key couldn't sign") == true, model.message ?? "")
    }),
    Test("a locked key closes the way: nothing more is asked", awaiting: { @MainActor in
        var asked = 0
        let (model, field) = sheet(attempt: { _ in asked += 1; throw SecurityKeyFailure.pinBlocked })
        field.stringValue = "4821"
        await model.approve()
        field.stringValue = "4821"
        await model.approve()
        try expectEqual(asked, 1)
        try expectEqual(model.locked, true)
    }),
    Test("Cancel closes the sheet once, with nothing approved", awaiting: { @MainActor in
        var heard: [Bool] = []
        let (model, field) = sheet(done: { heard.append($0 is CancellationError) })
        field.stringValue = "4821"
        model.cancel()
        model.cancel()
        try expectEqual(heard, [true])
        try expectEqual(field.stringValue.isEmpty, true)
    }),
    Test("the tries left are read before the PIN is asked; a key not plugged in says nothing yet", awaiting: { @MainActor in
        let (model, _) = sheet(tries: 3)
        await model.appeared()
        try expectEqual(model.triesLine, "3 tries left before the key locks.")
        let (none, _) = sheet(tries: nil)
        await none.appeared()
        try expectEqual(none.triesLine, nil)
        try expectEqual(none.message, nil)
    }),
    Test("the screenshots: the PIN sheet asking, in English and French, and waiting for the touch", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (asking, _) = sheet()
        asking.triesLine = SecurityKeyWords.triesLeft(8, words: Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"]))
        let (wrong, _) = sheet("fr")
        wrong.message = SecurityKeyWords.line(SecurityKeyFailure.wrongPIN(triesLeft: 2),
                                              words: Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["fr"]))
        let (touching, _) = sheet()
        touching.phase = .touching
        for (name, model, language) in [("pin-sheet-en", asking, "en"), ("pin-sheet-wrong-fr", wrong, "fr"), ("pin-sheet-touch-en", touching, "en")] {
            let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
            guard let bitmap = Snapshot.bitmap(of: PINSheet(model: model).environment(\.words, words), size: CGSize(width: 440, height: 320)),
                  let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }),
    Test("an approval's sheet is the approval's, unless it's made for adding the key", awaiting: { @MainActor in
        let (approving, _) = sheet()
        try expectEqual(approving.purpose, .approve)
        let (adding, _) = sheet(purpose: .addKey)
        try expectEqual(adding.purpose, .addKey)
    }),
    Test("adding the key: Pair without a key closes the sheet once, as closing it does, and the key is never asked", awaiting: { @MainActor in
        var asked = 0
        var heard: [Bool] = []
        let (model, field) = sheet(purpose: .addKey, attempt: { _ in asked += 1 }, done: { heard.append($0 is CancellationError) })
        field.stringValue = "4821"
        model.cancel()
        try expectEqual(heard, [true])
        try expectEqual(asked, 0)
        try expectEqual(field.stringValue.isEmpty, true)
    }),
    Test("the screenshots: the sheet adding the key, in English and French", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr"] {
            let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language])
            let (adding, _) = sheet(language, purpose: .addKey)
            adding.triesLine = SecurityKeyWords.triesLeft(8, words: words)
            guard let bitmap = Snapshot.bitmap(of: PINSheet(model: adding).environment(\.words, words), size: CGSize(width: 440, height: 320)),
                  let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for pin-sheet-add-\(language)") }
            try png.write(to: folder.appendingPathComponent("pin-sheet-add-\(language).png"))
        }
    }),
]
