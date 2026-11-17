import Foundation

/// Coach's results as tafs cloud sends them: a new version made, one being made, one not made, and
/// a new taf's hand-over, as the iPad's `SetupComponent.Taf` reads `improves` and `note`.
let improvementThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1:result-2","session":"s1","answer":{"state":"answered","words":"Version 3","by":"tafs","outcome":{"version":3}},"component":{"id":"result-2","type":"result","text":"Morning inbox now reads your calendar too, to say what each email is about.","taf":{"agent":"agent_inbox","name":"Morning inbox","improves":"taf-inbox","note":"Can now list your Google Calendar events."},"tools":["list_emails","read_conversation","list_events"]}}},
  {"type":"card","card":{"key":"s1:result-3","session":"s1","component":{"id":"result-3","type":"result","text":"Morning inbox skips newsletters.","taf":{"agent":"agent_inbox","name":"Morning inbox","improves":"taf-inbox","note":"  "}}}},
  {"type":"card","card":{"key":"s1:result-4","session":"s1","answer":{"state":"answered","words":"","by":"tafs","outcome":{"failed":"Its draft was refused."}},"component":{"id":"result-4","type":"result","taf":{"agent":"agent_inbox","name":"Morning inbox","improves":"taf-inbox"}}}},
  {"type":"card","card":{"key":"s1:result-1","session":"s1","answer":{"state":"answered","words":"Set up","by":"tafs","outcome":{"taf_id":"taf-1"}},"component":{"id":"result-1","type":"result","taf":{"agent":"agent_1","name":"Unanswered emails","note":"A first version."},"tools":["bxkwf7vi_list_emails","gmail.read_conversation","Read my Mail address"]}}}
]}
"""#

/// The tafs listed, as Home lists them: by KIFF agent, with tafs cloud's id.
let improvementTafs: [Home.Taf] = {
    let json = #"{"tafs":[{"name":"Morning inbox","kiff_agent":"agent_inbox_2","id":"taf-inbox","color":1,"state":"idle"},{"name":"Unanswered emails","kiff_agent":"agent_1","id":"taf-1","color":4,"state":"idle"},{"name":"Refunds","kiff_agent":"taf-refunds","id":"taf-r","color":2,"state":"idle"}]}"#
    return (try? JSONDecoder().decode(Home.Page.self, from: Data(json.utf8)))?.tafs ?? []
}()

private func results() throws -> [Thread.Card] {
    try JSONDecoder().decode(Thread.Page.self, from: Data(improvementThread.utf8)).items.compactMap { if case .card(let card, _) = $0 { return card } else { return nil } }
}

/// One card of this kind, answered as `answer` says (nothing when nil).
private func card(_ type: String, answer: String?) throws -> Thread.Card {
    let answered = answer.map { #","answer":\#($0)"# } ?? ""
    let json = #"{"items":[{"type":"card","card":{"key":"s1:c-1","session":"s1"\#(answered),"component":{"id":"c-1","type":"\#(type)","title":"Connect Qonto","text":"What it asks","waits":"owner","options":[{"label":"Agree","value":"agree"}]}}}]}"#
    let page = try JSONDecoder().decode(Thread.Page.self, from: Data(json.utf8))
    guard case .card(let card, _) = page.items.first else { throw Failure(description: "no card") }
    return card
}

let coachImprovementTests: [Test] = [
    Test("a result that improves a taf is its new version's card, with tafs cloud's note, never a hand-over's") {
        let all = try results()
        try expectEqual(all.map(\.isImprovement), [true, true, true, false])
        try expectEqual(all[0].improves, "taf-inbox")
        try expectEqual(all[0].tafName, "Morning inbox")
        try expectEqual(all[0].tafNote, "Can now list your Google Calendar events.")
        // A blank note is none; a hand-over's note is read, though its card doesn't draw one.
        try expectEqual(all[1].tafNote, nil)
        try expectEqual(all[3].tafNote, "A first version.")
        try expectEqual(all[3].isHandOver, true)
        try expectEqual(all[3].improves, nil)
    },
    Test("what became of the new version is tafs cloud's answer: the version made, why none was, or being made") {
        let all = try results()
        try expectEqual(all[0].improvement, .made(3))
        try expectEqual(all[1].improvement, .preparing)
        try expectEqual(all[2].improvement, .failed("Its draft was refused."))
        // tafs cloud's why without its own ending: the shared line ends it.
        try expectEqual(Thread.Card.notImprovedWhy("Its draft was refused. "), "Its draft was refused")
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        try expectEqual(words("coach.result.new_version", ["taf": "Morning inbox"]), "New version · Morning inbox")
        try expectEqual(words("coach.result.see_version", ["version": "3"]), "See version 3")
        let line = words("coach.not_improved", ["owner": "Morning inbox", "why": Thread.Card.notImprovedWhy("Its draft was refused.")])
        try expect(line.hasSuffix("new version wasn't made: Its draft was refused."), line)
    },
    Test("the new version's taf is the one tafs cloud knows by improves, else by its agent, as the iPad's improvedTaf") {
        let all = try results()
        // By tafs cloud's id, though the result names another agent.
        try expectEqual(all[0].improvedTaf(in: improvementTafs)?.name, "Morning inbox")
        // Not listed: none, and See version opens nothing.
        try expectEqual(all[0].improvedTaf(in: []), nil)
        // `improves` naming an agent, then the result's own agent.
        var byAgent = all[0]
        byAgent.improves = "taf-refunds"
        try expectEqual(byAgent.improvedTaf(in: improvementTafs)?.name, "Refunds")
        byAgent.improves = "taf-gone"
        byAgent.tafAgent = "agent_1"
        try expectEqual(byAgent.improvedTaf(in: improvementTafs)?.name, "Unanswered emails")
    },
    Test("a hand-over's tools are in words, never a tool's own name") {
        try expectEqual(try results()[3].toolWords, ["list emails", "read conversation", "Read my Mail address"])
    },
    Test("an answered approval folds to a line that opens again; a choice, a sign-in and questions to a line; the rest stay whole") {
        let approved = #"{"state":"answered","words":"Approved"}"#
        try expectEqual(try card("approval", answer: approved).fold, .opens)
        try expectEqual(try card("approval", answer: #"{"state":"answered","words":"Declined"}"#).fold, .opens)
        try expectEqual(try card("approval", answer: nil).fold, .whole)
        try expectEqual(try card("confirm", answer: #"{"state":"answered","words":"Agree"}"#).fold, .line)
        try expectEqual(try card("sign_in", answer: #"{"state":"answered","words":"Signed in"}"#).fold, .line)
        try expectEqual(try card("questions", answer: #"{"state":"answered","words":"Weekdays at 9"}"#).fold, .line)
        // Written past, or no longer waiting: no answer the person chose, so nothing folds.
        try expectEqual(try card("confirm", answer: #"{"state":"wrote","words":"Make it hourly"}"#).fold, .whole)
        try expectEqual(try card("approval", answer: #"{"state":"no_answer","words":""}"#).fold, .whole)
        // A hand-over, a plan and a note show what they are, answered or not.
        try expectEqual(try card("result", answer: #"{"state":"answered","words":"Set up"}"#).fold, .whole)
        try expectEqual(try card("notice", answer: approved).fold, .whole)
        try expectEqual(try card("steps", answer: approved).fold, .whole)
    },
    Test("Coach's panel opens at its width, never narrower than its narrowest, and leaves the screen behind in view") {
        try expectEqual(CoachPanelWidth.remembered(nil), 440)
        try expectEqual(CoachPanelWidth.remembered(100), 440)
        try expectEqual(CoachPanelWidth.remembered(.nan), 440)
        try expectEqual(CoachPanelWidth.remembered(620), 620)
        // In the Mac's first window (1366 wide, 300 of sidebar): 1066 of screen, of which 240 stays.
        try expectEqual(CoachPanelWidth.drawn(440, detail: 1066), 440)
        try expectEqual(CoachPanelWidth.drawn(2000, detail: 1066), 826)
        try expectEqual(CoachPanelWidth.drawn(200, detail: 1066), 380)
        // The smallest window (900 wide): the narrowest still, even over most of the screen.
        try expectEqual(CoachPanelWidth.drawn(440, detail: 600), 380)
        try expectEqual(CoachPanelWidth.drawn(440, detail: 300), 300)
        // The edge dragged left widens it, right narrows it, within the same bounds.
        try expectEqual(CoachPanelWidth.dragged(from: 440, moved: -100, detail: 1066), 540)
        try expectEqual(CoachPanelWidth.dragged(from: 440, moved: 200, detail: 1066), 380)
        try expectEqual(CoachPanelWidth.dragged(from: 440, moved: -900, detail: 1066), 826)
        try expectEqual(CoachPanelWidth.widthKey, "coach.width")
        try expectEqual(CoachPanelWidth.fullKey, "coach.full")
    },
    Test("every word of the new version's card and of Coach's panel is a shared line, in every shipped language") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        let keys = ["coach.result.new_version", "coach.result.see_version", "coach.result.version_made", "coach.result.preparing",
                    "coach.not_improved", "coach.coach_knows", "coach.full_screen", "coach.back_width", "coach.coach_mode_width",
                    "coach.drag_make_wider_narrower", "coach.plan.fold_short", "coach.shows_approval",
                    "coach.answer.approved_short", "coach.answer.declined_short", "common.back"]
        for language in try Words.shipped(folder: folder) {
            let words = try Words(language: language, folder: folder)
            for key in keys { try expect(words(key) != key, "\(key) in \(language)") }
        }
    },
]
