import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

@MainActor
private func make(_ answers: [(Int, String)]) async -> (CoachModel, CannedTransport) {
    let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, experienceThread)] + answers)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return (model, transport)
}

@MainActor
private func cards(_ model: CoachModel) -> [Thread.Card] {
    guard case .loaded(_, let page) = model.state else { return [] }
    return page.items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

let coachExperienceMacTests: [Test] = [
    Test("Decline on an approval sends \"declined\" once, and nothing else is ever sent to it", awaiting: { @MainActor in
        let (model, transport) = await make([(200, "{}"), (200, experienceThread)])
        let approval = cards(model)[1]
        await model.decline(approval)
        let posts = transport.sent.filter { $0.method == "POST" }
        try expectEqual(posts.count, 1)
        try expectEqual(try JSONDecoder().decode([String: String].self, from: posts[0].body)["answer"], "declined")
        // The choice route still refuses it, whatever option is passed.
        await model.answer(approval, with: .init(label: "Approve", value: "approved"))
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
    }),
    Test("only an approval or a sign-in that waits can be declined", awaiting: { @MainActor in
        let (model, transport) = await make([(200, "{}"), (200, "{}"), (200, "{}")])
        let all = cards(model)
        for card in [all[0], all[2], all[3], all[4]] { await model.decline(card) }
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 0)
    }),
    Test("the screenshots: a whole conversation with Coach, as on the iPad, in three languages", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in ["en", "fr", "pt"] {
            let (model, _) = await make([])
            let view = CoachView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 860)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("coach-experience-\(language).png"))
        }
    }),
]
