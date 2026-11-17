import AppKit
import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let strings = URL(fileURLWithPath: ".shared/app/strings")
private let shots = URL(fileURLWithPath: "build/screenshots")
private let panelChats = #"{"chats":[{"session":"s1","started":"2026-11-13T09:00:00Z","updated":"2026-11-13T10:00:00Z","title":"Old"},{"session":"w1","started":"2026-11-14T09:00:00Z","updated":"2026-11-14T10:00:00Z","title":"Waiting"}]}"#
private let panelThread = #"{"working":false,"items":[{"type":"message","message":{"id":"m1","from":"taf","text":"Approve the refund card?","session":"w1"}}]}"#
private let panelHome = #"{"tafs":[{"id":"taf-inbox","name":"Morning inbox","kiff_agent":"agent_inbox_2","color":1,"state":"working","work":{"line":"Reading 12 emails"}},{"id":"taf-1","name":"Unanswered emails","kiff_agent":"agent_1","color":4,"state":"idle","next_run_words":"Next run Mon 08:00"}]}"#

/// Whether a drawn colour is the one asked for, within the rounding of the display's colour space.
private func near(_ got: UInt32?, _ want: UInt32) -> Bool {
    guard let got else { return false }
    return [16, 8, 0].allSatisfy { abs(Int((got >> $0) & 0xFF) - Int((want >> $0) & 0xFF)) <= 2 }
}

/// This Mac's defaults for one test alone, empty.
private func defaults(_ name: String) -> UserDefaults {
    let suite = "tafs.tests.coach-panel.\(name)"
    let kept = UserDefaults(suiteName: suite) ?? .standard
    kept.removePersistentDomain(forName: suite)
    return kept
}

@MainActor
private func coach(_ answers: [(Int, String)]) async -> (CoachModel, CannedTransport) {
    let transport = CannedTransport([(200, setupAnswer)] + answers)
    let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in })
    await model.load()
    return (model, transport)
}

/// The window as it is signed in, with the Overview under Coach.
@MainActor
/// A recognizer with two languages, so the composer draws the mic and its language, as the app's.
@MainActor
private final class PanelSpeech: SpeechEngine {
    func authorize() async -> String? { nil }
    func languages() -> [Dictation.Language] { [.english, .spanish] }
    var noLanguage: String { "no language" }
    func unavailable(_ language: Dictation.Language) -> String? { nil }
    func start(language: Dictation.Language, hints: [String], onText: @escaping @Sendable (String, Bool) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void, onEnd: @escaping @Sendable (String?) -> Void) throws {}
    func stop() {}
}

@MainActor
private func window(_ panel: CoachPanelModel, coach: CoachModel, overview: OverviewModel, language: String) -> some View {
    Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
    let full = Binding(get: { panel.full }, set: { panel.full = $0 })
    return CoachPanelHost(panel: panel, leading: ShellView.sidebarWidth) {
        ShellView(selection: .constant(.overview), tafs: overview.listedTafs, accountLine: "you@example.com",
                  screen: { _ in AnyView(OverviewView(model: overview)) }, coachOpen: panel.open)
    } coach: {
        CoachView(model: coach, tafCount: 2, close: { panel.close() }, fullScreen: full, tafs: overview.tafs, versions: { _ in nil },
                  dictation: Dictation(engine: PanelSpeech(), language: .english))
    }
    .environment(\.words, Words.load(folder: strings, preferred: [language]))
}

let coachPanelMacTests: [Test] = [
    Test("the screenshots: a new version's card, light and dark: New version, tafs cloud's note, and See version", awaiting: { @MainActor in
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        for dark in [false, true] {
            let (model, _) = await coach([(200, noChats), (200, improvementThread)])
            let view = CoachView(model: model, tafs: improvementTafs, versions: { _ in nil })
                .environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 520, height: 1000), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: shots.appendingPathComponent("coach-version-card-en\(dark ? "-dark" : "").png"))
        }
    }),
    Test("the screenshots: Coach as a panel over the Overview, which stays in view, and full, light and dark", awaiting: { @MainActor in
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let size = CGSize(width: 1366, height: 860)
        for dark in [false, true] {
            for full in [false, true] {
                let overview = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, panelHome)]), session: session))
                await overview.load()
                let (model, _) = await coach([(200, noChats), (200, improvementThread)])
                let panel = CoachPanelModel(defaults: defaults("shot"))
                panel.full = full
                panel.openCoach()
                guard let bitmap = Snapshot.bitmap(of: window(panel, coach: model, overview: overview, language: "en"), size: size, dark: dark),
                      let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
                try png.write(to: shots.appendingPathComponent("coach-panel-\(full ? "full" : "overview")-en\(dark ? "-dark" : "").png"))
                let middle = Int(size.height) / 2
                let wash = dark ? Palette.coachWash.dark : Palette.coachWash.light
                // Coach's wash near the window's right edge, either way, left of any scroller.
                try expect(near(Snapshot.hex(bitmap, x: Int(size.width) - 24, y: middle), wash), "Coach at the right, full: \(full), dark: \(dark)")
                // Over the screen, the sidebar stays in view; full, Coach covers it.
                let left = Snapshot.hex(bitmap, x: 6, y: middle)
                if full {
                    try expect(near(left, wash), "Coach over the sidebar, dark: \(dark)")
                } else {
                    try expect(near(left, dark ? Palette.raised.dark : Palette.raised.light), "the sidebar in view, dark: \(dark)")
                }
            }
        }
    }),
    Test("the screenshots: an answered approval folded to one line with its ⌄, light and dark", awaiting: { @MainActor in
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        for dark in [false, true] {
            let (model, _) = await coach([(200, noChats), (200, experienceThread)])
            let view = CoachView(model: model).environment(\.words, Words.load(folder: strings, preferred: ["en"]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 520, height: 1100), dark: dark), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: shots.appendingPathComponent("coach-folded-card-en\(dark ? "-dark" : "").png"))
        }
    }),
    Test("the sidebar's Coach opens the panel on the chat Coach had; Back closes it and keeps the chat", awaiting: { @MainActor in
        let (model, _) = await coach([(200, panelChats), (200, panelThread)])
        let panel = CoachPanelModel(defaults: defaults("sidebar"))
        try expectEqual(panel.open, false)
        panel.openCoach()
        try expectEqual(panel.open, true)
        try expectEqual(model.shownSession, "w1")
        panel.close()
        try expectEqual(panel.open, false)
        try expectEqual(model.shownSession, "w1")
    }),
    Test("Needs you's Open Coach opens the panel on that chat", awaiting: { @MainActor in
        let (model, transport) = await coach([(200, noChats), (200, threadAnswer), (200, panelThread)])
        let panel = CoachPanelModel(defaults: defaults("waiting"))
        await panel.openWaiting("w1", in: model)
        try expectEqual(panel.open, true)
        try expectEqual(model.chat, "w1")
        try expectEqual(transport.sent.last?.path, "/v1/tafs/taf-coach/conversation/w1")
        // A waiting chat with no session: Coach alone.
        let (alone, _) = await coach([(200, panelChats), (200, panelThread)])
        let other = CoachPanelModel(defaults: defaults("waiting-alone"))
        await other.openWaiting("", in: alone)
        try expectEqual(other.open, true)
        try expectEqual(alone.shownSession, "w1")
    }),
    Test("Ask Coach on a taf's card opens the panel on a new conversation about the taf, its words in the box, nothing sent", awaiting: { @MainActor in
        let (model, transport) = await coach([(200, noChats), (200, threadAnswer)])
        let panel = CoachPanelModel(defaults: defaults("ask"))
        let refunds = CoachModel.Improving(id: "taf-1", name: "Refunds")
        panel.ask(about: refunds, words: "Refund up to €200 on its own", mayUseCoach: true, manages: true, in: model)
        try expectEqual(panel.open, true)
        try expectEqual(model.improving, refunds)
        try expectEqual(model.fresh, true)
        try expectEqual(model.draft, "Refund up to €200 on its own")
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 0)
        // Someone who may not: Coach doesn't open, and nothing changes.
        let (other, _) = await coach([(200, noChats), (200, threadAnswer)])
        let closed = CoachPanelModel(defaults: defaults("ask-not"))
        closed.ask(about: refunds, words: "Refund more", mayUseCoach: false, manages: true, in: other)
        try expectEqual(closed.open, false)
        try expectEqual(other.improving, nil)
    }),
    Test("Improve in Coach opens the panel on a new conversation about the taf", awaiting: { @MainActor in
        let (model, _) = await coach([(200, panelChats), (200, panelThread)])
        let panel = CoachPanelModel(defaults: defaults("improve"))
        let inbox = CoachModel.Improving(id: "taf-inbox", name: "Morning inbox")
        panel.improve(inbox, in: model)
        try expectEqual(panel.open, true)
        try expectEqual(model.improving, inbox)
        try expectEqual(model.fresh, true)
        try expectEqual(model.shownSession, nil)
    }),
    Test("Start a new taf, a job handed to Coach and the brief's next move each open the panel on the right chat", awaiting: { @MainActor in
        let (model, _) = await coach([(200, panelChats), (200, panelThread)])
        let panel = CoachPanelModel(defaults: defaults("new"))
        panel.startNewTaf(in: model)
        try expectEqual(panel.open, true)
        try expectEqual(model.fresh, true)
        try expectEqual(model.improving, nil)
        // A job's words, in the box of the chat shown, nothing sent.
        let (handed, transport) = await coach([(200, panelChats), (200, panelThread)])
        let other = CoachPanelModel(defaults: defaults("hand"))
        other.hand("Refund orders under €50", to: handed)
        try expectEqual(other.open, true)
        try expectEqual(handed.draft, "Refund orders under €50")
        try expectEqual(handed.shownSession, "w1")
        try expectEqual(transport.sent.filter { $0.method == "POST" }.count, 0)
    }),
    Test("the panel's width and ⤢ are kept on this Mac for the next time", awaiting: { @MainActor in
        let kept = defaults("kept")
        let panel = CoachPanelModel(defaults: kept)
        try expectEqual(panel.width, CoachPanelWidth.opening)
        try expectEqual(panel.full, false)
        panel.width = 620
        panel.full = true
        let again = CoachPanelModel(defaults: kept)
        try expectEqual(again.width, 620)
        try expectEqual(again.full, true)
        // Opening isn't kept: Coach opens when asked.
        try expectEqual(again.open, false)
    }),
]
