import Foundation

private func page(_ items: [String]) throws -> Thread.Page {
    try JSONDecoder().decode(Thread.Page.self, from: Data((#"{"working":false,"items":["# + items.joined(separator: ",") + "]}").utf8))
}

private let drive = #"{"type":"card","card":{"key":"s1#d","session":"s1","component":{"id":"d","type":"drive","text":"Run Chargebacks","waits":"owner"}}}"#

let coachDriveTests: [Test] = [
    Test("a drive's end reads as the iPad's DriveRecap: the request, each step with what it touched, and why it ended") {
        let p = try page([
            #"{"type":"drive","drive":{"id":"dr1","session":"s1","task":"Run Chargebacks","why":"owner_took_over","at":"2026-11-24T08:00:00Z","steps":[{"at":"x","line":"Looked"},{"at":"x","line":"Tapped Run","touched":{"words":"Run now","taf":"Chargebacks"}},{"at":"x","line":"Typed into the field","touched":{"taf":"Refunds"}},{"at":"x"},"noise"]}}"#,
            #"{"type":"drive","drive":{"id":"dr2"}}"#,
        ])
        guard case .drive(let d, let position) = p.items[0] else { throw Failure(description: "a drive") }
        try expectEqual(position, 0)
        try expectEqual(d.task, "Run Chargebacks")
        try expectEqual(d.at, Thread.time("2026-11-24T08:00:00Z"))
        // A step's taf is shown only beside what it touched; a step without its line is left out.
        try expectEqual(d.steps.map(\.shown), ["Looked", "Tapped Run · Run now · Chargebacks", "Typed into the field"])
        // One without its request stays a kind this Mac doesn't draw, in its place.
        try expectEqual(p.items[1], .other(type: "drive", position: 1))
    },
    Test("why a drive ended: tafs cloud's words as a sentence, else the app's for the reason, else Coach stopped") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        func ended(_ why: String?, _ said: String?) -> String { Thread.Drive(id: "d", task: "t", why: why, words: said).ended(words) }
        try expectEqual(ended("stopped", "  the owner stopped it "), "The owner stopped it")
        try expectEqual(ended("owner_took_over", nil), words("drive.ended.owner_took_over"))
        try expectEqual(ended("owner_took_over", nil), "You took over, so Coach let you carry on")
        try expectEqual(ended("left_app", " "), words("drive.ended.left_app"))
        try expectEqual(ended("something_new", nil), words("drive.ended.other"))
        try expectEqual(ended(nil, nil), "Coach stopped")
        for why in Thread.Drive.reasons { try expect(words("drive.ended.\(why)") != "drive.ended.\(why)", why) }
    },
    Test("a drive card is asked on the phone until answered: declined is Not now, any other answer is that Coach drove") {
        let asked = try page([drive])
        try expectEqual(asked.drive(asked.cards[0]), .asking)
        let declined = try page([#"{"type":"card","card":{"key":"s1#d","session":"s1","answer":{"state":"answered","answer":"declined"},"component":{"id":"d","type":"drive","text":"Run Chargebacks","waits":"owner"}}}"#])
        try expectEqual(declined.drive(declined.cards[0]), .declined)
        let drove = try page([#"{"type":"card","card":{"key":"s1#d","session":"s1","answer":{"state":"answered","answer":"approved: the drive is on"},"component":{"id":"d","type":"drive","text":"Run Chargebacks","waits":"owner"}}}"#])
        try expectEqual(drove.drive(drove.cards[0]), .drove)
        // Answered the old way, by the person's message after it.
        let old = try page([drive, #"{"type":"message","message":{"from":"owner","kind":"message","text":"[drive d] declined","session":"s1"}}"#])
        try expectEqual(old.drive(old.cards[0]), .declined)
    },
    Test("this Mac shows a drive card and never answers it: no Approve, no Not now, and Approve on your phone in their place") {
        let source = try String(contentsOf: URL(fileURLWithPath: "Sources/App/coach/DriveViews.swift"), encoding: .utf8)
        try expect(!source.contains("Button"), "no button on a drive's card")
        try expect(!source.contains("answer("), "nothing answered")
        try expect(source.contains(#"words("approval.security_key.on_phone")"#), "approve on the phone")
        let view = try String(contentsOf: URL(fileURLWithPath: "Sources/App/coach/CoachView.swift"), encoding: .utf8)
        try expect(view.contains("DriveAsk(card: card, state: model.drive(card))"), "the card is drawn")
        try expect(view.contains("DriveRecap(drive: drive)"), "what Coach did is drawn")
    },
]
