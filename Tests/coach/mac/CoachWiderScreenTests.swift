import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// tafs cloud's wider line in each screenshot's language, as its `card_wider` writes it for Google Sheets.
private let widerSaidIn = [
    "en": widerLine,
    "fr": "La connexion à Google Sheets ne peut pas être limitée à cette tâche : elle demande plus d'accès que le taf n'en utilise. Le taf n'utilise toujours que ses propres outils.",
    "pt": "O início de sessão em Google Sheets não pode ser limitado a esta tarefa: pede mais acesso do que o taf usa. O taf continua a usar apenas as suas próprias ferramentas.",
]

/// A chat with a waiting approval and a waiting sign-in for Google Sheets, each with `more` in its component.
private func widerThread(_ more: String) -> String {
    #"""
    {"working":false,"items":[
      {"type":"message","message":{"id":"m1","at":"2026-11-16T09:00:00Z","from":"owner","kind":"message","text":"Read my orders sheet each morning","session":"s1"}},
      {"type":"card","card":{"key":"s1:connect","session":"s1","component":{"id":"connect","type":"approval","title":"Connect Google Sheets","text":"Your orders taf reads the Orders sheet. It changes nothing.","grant":"g_01","waits":"owner"\#(more)}}},
      {"type":"card","card":{"key":"s1:in","session":"s1","component":{"id":"in","type":"sign_in","service":"Google Sheets","grant":"g_01","waits":"owner"\#(more)}}}
    ]}
    """#
}

private func widerMarked(_ words: String) -> String {
    let json = try! JSONEncoder().encode(["words": words])
    return #","wider":"# + String(decoding: json, as: UTF8.self)
}

@MainActor
private func widerCoach(_ thread: String) async -> CoachModel {
    let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, thread)])
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return model
}

/// The points drawn in amber, at any strength above the panel, one in four read: the cards' outline and
/// eyebrows, and the wider line.
private func amberPoints(_ bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: Int(bitmap.size.height), by: 2) {
        for x in stride(from: 0, to: Int(bitmap.size.width), by: 2) {
            // As stored or as sRGB: a runner's virtual screen keeps the drawn numbers.
            if Snapshot.hexes(bitmap, x: x, y: y).contains(where: { got in
                let r = Int(got >> 16 & 0xFF), g = Int(got >> 8 & 0xFF), b = Int(got & 0xFF)
                return r >= 0x90 && r - b >= 70 && g < r
            }) { count += 1 }
        }
    }
    return count
}

private let widerSize = CGSize(width: 980, height: 1000)

@MainActor
private func widerDrawn(_ thread: String, language: String = "en") async throws -> NSBitmapImageRep {
    let model = await widerCoach(thread)
    guard case .loaded = model.state else { throw Failure(description: "the thread wasn't read") }
    let view = CoachView(model: model).environment(\.words, Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: [language]))
    // Drawn again until both cards' amber outlines show: a runner can lay out the scrolled content a turn later.
    guard let bitmap = Snapshot.settled(of: view, size: widerSize, until: { amberPoints($0) > 400 }) else { throw Failure(description: "nothing drawn") }
    return bitmap
}

let coachWiderMacTests: [Test] = [
    Test("Coach's thread is read with this device's proof, and tafs cloud's wider card reaches Coach's card; a taf's chat sends none", awaiting: { @MainActor in
        var asked = 0
        let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, try widerConversation(stripeWider))])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in }, proof: { asked += 1; return "t=1,v1=c2ln,d=dev_mac" })
        await model.load()
        let read = transport.sent.filter { $0.path.contains("/conversation") }
        try expectEqual(read.count, 1)
        try expectEqual(read[0].headers["Planque-Device-Signature"], "t=1,v1=c2ln,d=dev_mac")
        try expectEqual(asked, 1)
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "the thread wasn't read") }
        let marked = page.items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item, card.widerWords != nil { return card } else { return nil } }
        try expectEqual(marked.map(\.type), ["approval", "sign_in"])
        try expectEqual(marked.map(\.widerWords), [stripeWider, stripeWider])

        let tafTransport = CannedTransport([(200, try widerConversation(stripeWider))])
        let taf = CoachModel(cloud: CloudClient(transport: tafTransport, session: session), taf: Coach(id: "taf-1", name: "Refunds"), sleep: { _ in },
                             proof: { asked += 1; return "t=1,v1=c2ln,d=dev_mac" })
        await taf.load()
        try expectEqual(tafTransport.sent.map(\.path), ["/v1/tafs/taf-1/conversation"])
        try expectEqual(tafTransport.sent[0].headers["Planque-Device-Signature"], nil)
        try expectEqual(asked, 1)
    }),
    Test("an approval and a sign-in draw tafs cloud's wider words, in amber, only when it sends some", awaiting: { @MainActor in
        let model = await widerCoach(widerThread(widerMarked(widerLine)))
        guard case .loaded(_, let page) = model.state else { throw Failure(description: "the thread wasn't read") }
        let cards = page.items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }
        try expectEqual(cards.map(\.type), ["approval", "sign_in"])
        try expectEqual(cards.map(\.widerWords), [widerLine, widerLine])

        let plain = try await widerDrawn(widerThread(""))
        let wide = try await widerDrawn(widerThread(widerMarked(widerLine)))
        let (without, with) = (amberPoints(plain), amberPoints(wide))
        try expect(with - without > 150, "the two wider lines are drawn in amber (\(without) amber points without, \(with) with)")
        // A mark tafs cloud didn't send, sent blank or in another shape draws exactly the card without one.
        for odd in [#","wider":{"words":"  "}"#, #","wider":"yes""#, #","wider":null"#] {
            let bitmap = try await widerDrawn(widerThread(odd))
            let shown = amberPoints(bitmap)
            try expect(abs(shown - without) <= 20, "\(odd) draws the cards as before (\(shown) amber points, \(without) without a mark)")
        }
    }),
    Test("the wider line alone is tafs cloud's words in amber text", awaiting: { @MainActor in
        guard let bitmap = Snapshot.bitmap(of: WiderLine(words: widerLine).padding(16).background(Theme.panel), size: CGSize(width: 520, height: 120)) else {
            throw Failure(description: "nothing drawn")
        }
        try expect(amberPoints(bitmap) > 60, "the words are drawn in amber (\(amberPoints(bitmap)) amber points)")
        guard let panel = Snapshot.bitmap(of: Color.clear.background(Theme.panel), size: CGSize(width: 520, height: 120)) else { throw Failure(description: "no panel drawn") }
        try expectEqual(amberPoints(panel), 0)
    }),
    Test("the screenshots: an approval and a sign-in that ask for more than the job, in three languages", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let bitmap = try await widerDrawn(widerThread(widerMarked(widerSaidIn[language] ?? widerLine)), language: language)
            guard let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("coach-wider-\(language).png"))
        }
    }),
]
