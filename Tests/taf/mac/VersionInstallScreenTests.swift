import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")
private let versions = #"{"versions":[{"n":3,"created":"2026-11-01T09:00:00Z","live":true},{"n":4,"created":"2026-11-20T09:00:00Z","live":false,"note":"Refunds up to €100"}],"switching":null}"#
private let card = #"""
{"id":"d1","agent_id":"a","status":"draft","version":"v7",
 "cards":[{"lines":["Refund a payment: up to €100.00 each"],"current":{"lines":["Refund a payment: up to €50.00 each"]}},
          {"lines":["Send an email"]}],
 "retires":[{"id":"c9","current":{"lines":["Delete files"]}}]}
"""#

private func switching(_ draft: String?) -> String {
    #"{"switching":{"n":4,"draft":\#(draft.map { #""\#($0)""# } ?? "null"),"at":"2026-11-24T01:00:00Z"}}"#
}

/// A taf's page that installs versions: tafs cloud's and KIFF's answers canned, the key and the owner's prompt recorded.
@MainActor
private final class Install {
    let cloud: CannedTransport
    let kiff: CannedTransport
    let model: TafPagesModel
    var acts: [KeyAct] = []
    var prompts: [String] = []
    var refreshed = 0

    init(cloud answers: [(Int, String)], kiff: [(Int, String)] = [], key: Error? = nil, owner: Error? = nil) {
        cloud = CannedTransport([(200, versions)] + answers)
        self.kiff = CannedTransport(kiff)
        model = TafPagesModel(cloud: CloudClient(transport: cloud, session: session), taf: "taf-1")
        model.account = AccountClient(transport: self.kiff, session: session)
        model.tafName = "Refunds"
        model.confirmWithKey = { [unowned self] act, prompt in
            acts.append(act); prompts.append(prompt)
            if let key { throw key }
            return Data(#"{"status":"confirmed"}"#.utf8)
        }
        model.confirmOwner = { [unowned self] prompt in
            prompts.append(prompt)
            if let owner { throw owner }
        }
        model.refreshTafs = { [unowned self] in refreshed += 1 }
    }

    var sent: [String] { cloud.sent.map { $0.method + " " + $0.path } }
    func version() async throws -> TafVersions.Version {
        await model.loadVersions()
        guard let v = model.versionList?.first(where: { $0.n == 4 }) else { throw Failure(description: "no version 4") }
        return v
    }
}

let tafVersionInstallMacTests: [Test] = [
    Test("Install this version with a Card: the switch begins, its Card is read, the key confirms what was shown, then it's live", awaiting: { @MainActor in
        let i = Install(cloud: [(200, switching("d1")), (200, switching("d1")), (200, #"{"live":4}"#), (200, versions)],
                        kiff: [(200, card), (200, card)])
        let v = try await i.version()
        let read = await i.model.install(v)
        try expectEqual(read?.n, 4)
        let shown = try await i.model.versionCard(v)
        try expectEqual(shown.version, "v7")
        let done = await i.model.useVersion(v, shownDraft: shown.version)
        guard case .live? = done else { throw Failure(description: "\(String(describing: done))") }
        try expectEqual(i.acts, [.confirmDraft(id: "d1", version: "v7")])
        try expectEqual(i.prompts, ["Use version 4 of Refunds, with its Card"])
        try expectEqual(i.sent, ["GET /v1/tafs/taf-1/versions", "POST /v1/tafs/taf-1/versions/4/switch", "POST /v1/tafs/taf-1/versions/4/switch",
                                 "POST /v1/tafs/taf-1/versions/4/live", "GET /v1/tafs/taf-1/versions"])
        try expectEqual(i.refreshed, 1)
        try expectEqual(i.model.installing, nil)
        try expectEqual(i.model.versionError, nil)
    }),
    Test("Install this version with no Card: the owner confirms with Touch ID or the password, nothing on the key", awaiting: { @MainActor in
        let i = Install(cloud: [(200, switching(nil)), (200, switching(nil)), (200, #"{"live":4}"#), (200, versions)])
        let v = try await i.version()
        let read = await i.model.install(v)
        try expectEqual(read, nil)
        try expectEqual(i.acts, [])
        try expectEqual(i.prompts, ["Use version 4 of Refunds"])
        try expectEqual(i.sent.last, "GET /v1/tafs/taf-1/versions")
        try expectEqual(i.sent.contains("POST /v1/tafs/taf-1/versions/4/live"), true)
        try expectEqual(i.refreshed, 0)
    }),
    Test("the key's sheet closed: the switch is cancelled and nothing goes live; a refused Card offers Draft its Card again", awaiting: { @MainActor in
        let closed = Install(cloud: [(200, switching("d1")), (200, #"{"cancelled":true}"#), (200, versions)], kiff: [(200, card)], key: CancellationError())
        let v = try await closed.version()
        let done = await closed.model.useVersion(v, shownDraft: "v7")
        try expectEqual(done, .closed)
        try expectEqual(closed.sent.contains("DELETE /v1/tafs/taf-1/switching"), true)
        try expectEqual(closed.sent.contains("POST /v1/tafs/taf-1/versions/4/live"), false)
        let stale = Install(cloud: [(200, switching("d1")), (200, versions)], kiff: [(200, card)], key: KIFFError.refused(status: 409, code: "card_revised"))
        let again = try await stale.version()
        _ = await stale.model.useVersion(again, shownDraft: "v7")
        try expectEqual(stale.model.staleCard, 4)
        try expect(stale.model.versionError?.hasPrefix("Version 4") == true, "the out-of-date line")
    }),
    Test("someone view-only, or a Mac without KIFF's client or the key, installs nothing and is sent to the phone", awaiting: { @MainActor in
        let i = Install(cloud: [])
        i.model.viewOnly = true
        let v = try await i.version()
        let read = await i.model.install(v)
        try expectEqual(read, nil)
        try expectEqual(i.sent, ["GET /v1/tafs/taf-1/versions"])
        let bare = TafPagesModel(cloud: CloudClient(transport: CannedTransport([]), session: session), taf: "taf-1")
        try expectEqual(bare.installsVersions, false)
    }),
    Test("the screenshots: a version's Card, now and after, and the knob's change with Install this version", awaiting: { @MainActor in
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let words = Words.load(folder: strings, preferred: ["en"])
        let i = Install(cloud: [(200, switching("d1"))], kiff: [(200, card)])
        let v = try await i.version()
        _ = await i.model.prepareSwitch(v)
        let draft = try AccountClient.decoder.decode(AccountClient.Draft.self, from: Data(card.utf8))
        guard let sheet = Snapshot.bitmap(of: DraftCardsView(draft: draft).padding(20).frame(width: 520).environment(\.words, words), size: CGSize(width: 520, height: 520)),
              let png = Snapshot.png(sheet) else { throw Failure(description: "no PNG") }
        try png.write(to: folder.appendingPathComponent("version-card-en.png"))
        var knob = try JSONDecoder().decode(Knob.self, from: Data(knobAnswer.utf8))
        knob.pending = Knob.Pending(version: 4, changes: 2)
        let size = CGSize(width: 520, height: 200)
        guard let installs = Snapshot.bitmap(of: KnobPendingPanel(knob: knob, manages: true, pages: i.model).environment(\.words, words), size: size),
              let phone = Snapshot.bitmap(of: KnobPendingPanel(knob: knob, manages: true).environment(\.words, words), size: size),
              let installsPNG = Snapshot.png(installs) else { throw Failure(description: "no bitmap") }
        try expect(Snapshot.png(phone) != installsPNG, "Install this version only where this Mac installs")
        try installsPNG.write(to: folder.appendingPathComponent("knob-make-live-en.png"))
    }),
]
