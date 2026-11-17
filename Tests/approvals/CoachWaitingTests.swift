import Foundation

private let words = try! Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))

/// Home with Coach's waiting chats, as tafs cloud sends `coach_waiting` and `coach_waiting_clear`
/// (the iPad's `TafsCloud+CoachWaiting.swift`): two it can draw, one with no way in, one with no chat.
let coachWaitingHome = #"""
{"tafs":[{"id":"taf_1","name":"Support","kiff_agent":"agent_support","state":"working"}],
 "needs_you":{"count":3,"words":"3 need you."},
 "coach_waiting":[
  {"taf":"taf_1","session":"chat/1","run":"r1","since":"2026-11-14T09:12:00Z","words":{"line":" Support: Coach is waiting for your approval since 09:12. ","open":"Open Coach","set_aside":"Set aside"}},
  {"taf":"taf_1","session":"chat-2","words":{"line":"Coach is waiting for your answer since 10:40.","open":"Open Coach"}},
  {"taf":"taf_1","session":"chat-3","words":{"line":"No way in."}},
  {"taf":"taf_1","words":{"line":"No chat.","open":"Open Coach"}},
  7],
 "coach_waiting_clear":{"words":{"button":"Set all aside","title":"End 2 waiting Coach chats?","text":"Coach stops waiting on them.","yes":"End them","no":""}},
 "card_unit_exceptions":[{"id":"cu_1","title":"A refund in CHF"},{"title":"no id"}]}
"""#

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let approvalsCoachWaitingTests: [Test] = [
    Test("a caller's headers are added to tafs cloud's, never in place of the client's own: the bearer stays", awaiting: {
        let transport = CannedTransport([(200, "{}"), (200, "{}")])
        let cloud = CloudClient(transport: transport, session: session)
        let extra = ["Authorization": "Bearer other", "Planque-Device-Signature": "t=1,v1=s,d=dev_1"]
        _ = try await cloud.post("/v1/home/coach-waiting/s1/set-aside", body: [String: String](), headers: extra)
        _ = try await cloud.read("/v1/tafs/t1/setup", headers: extra)
        for request in transport.sent {
            try expectEqual(request.headers["Authorization"], "Bearer tok")
            try expectEqual(request.headers["Planque-Device-Signature"], "t=1,v1=s,d=dev_1")
        }
    }),
    Test("Home's Coach waiting is read as the iPad reads it: only those with a chat and both lines, its words trimmed") {
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(coachWaitingHome.utf8))
        try expectEqual(page.coachWaiting.map(\.session), ["chat/1", "chat-2"])
        try expectEqual(page.coachWaiting[0].words.line, "Support: Coach is waiting for your approval since 09:12.")
        try expectEqual(page.coachWaiting[0].words.open, "Open Coach")
        // Set aside only where tafs cloud sent its words.
        try expectEqual(page.coachWaiting.map(\.canSetAside), [true, false])
        try expectEqual(page.coachWaitingClear?.words.button, "Set all aside")
        try expectEqual(page.coachWaitingClear?.words.no, "")
        try expectEqual(page.cardUnits, 1)
        try expectEqual(page.needsYouCount, 3)
    },
    Test("Coach waiting that isn't a list, and a Set all aside with no yes, are none, never Home with them") {
        let odd = #"{"tafs":[],"coach_waiting":{"chat":"c1"},"coach_waiting_clear":{"words":{"button":"Set all aside","title":"End them?"}},"card_unit_exceptions":"x"}"#
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(odd.utf8))
        try expectEqual(page.coachWaiting, [])
        try expectEqual(page.coachWaitingClear, nil)
        try expectEqual(page.cardUnits, 0)
        // tafs cloud's own Home (the home.json contract) has none.
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ".shared/contracts/home.json"))) as? [String: Any]
        let live = try AccountClient.decoder.decode(Home.Page.self, from: try JSONSerialization.data(withJSONObject: root?["answer"] ?? [:]))
        try expectEqual(live.coachWaiting, [])
        try expectEqual(live.coachWaitingClear, nil)
    },
    Test("Needs you's count is tafs cloud's when sent, less the steps answered here and the chats left out; else the app's own, Coach's chats too") {
        // tafs cloud's count, as the iPad's `needsYouCount`.
        var parts = NeedsYouCount.Parts(home: 3, homeWords: "3 need you.", held: 0, coachWaiting: 2)
        try expectEqual(NeedsYouCount.count(parts), 3)
        try expectEqual(NeedsYouCount.words(parts, words), "3 need you.")
        // A chat open in Coach, or being set aside, leaves the count and tafs cloud's words.
        parts.coachWaiting = 1
        parts.coachWaitingHidden = 1
        try expectEqual(NeedsYouCount.count(parts), 2)
        try expectEqual(NeedsYouCount.words(parts, words), "2 need you.")
        parts.answeredStillCounted = 2
        try expectEqual(NeedsYouCount.count(parts), 0)
        try expectEqual(NeedsYouCount.words(parts, words), "Nothing needs you.")
        // No count from tafs cloud: held + Card units + steps + "Did this happen?" + Coach's chats.
        let own = NeedsYouCount.Parts(home: nil, held: 1, cardUnits: 1, steps: 1, unproven: 1, coachWaiting: 2, coachWaitingHidden: 5)
        try expectEqual(NeedsYouCount.count(own), 6)
        try expectEqual(NeedsYouCount.words(own, words), "6 need you.")
    },
    Test("Needs you leaves out the chat open in Coach and those being set aside, in Home's order") {
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(coachWaitingHome.utf8))
        try expectEqual(NeedsYouCount.shown(page.coachWaiting, onScreen: nil, settingAside: []).map(\.session), ["chat/1", "chat-2"])
        try expectEqual(NeedsYouCount.shown(page.coachWaiting, onScreen: "chat/1", settingAside: []).map(\.session), ["chat-2"])
        try expectEqual(NeedsYouCount.shown(page.coachWaiting, onScreen: nil, settingAside: ["chat-2"]).map(\.session), ["chat/1"])
    },
    Test("Set aside goes to its chat's path, escaped, or every chat's; with this device's read of its connections, and nothing signed", awaiting: {
        try expectEqual(CloudClient.setAsidePath("chat/1"), "/v1/home/coach-waiting/chat%2F1/set-aside")
        try expectEqual(CloudClient.setAsidePath("chat-2"), "/v1/home/coach-waiting/chat-2/set-aside")
        try expectEqual(CloudClient.setAsidePath(nil), "/v1/home/coach-waiting/set-aside")
        let transport = CannedTransport([(200, #"{"set_aside":["chat/1"],"withdrawn":1}"#), (200, #"{"set_aside":["chat/1","chat-2"],"already":true}"#), (409, #"{"error":"not_waiting","words":"That chat isn't waiting any more."}"#)])
        let cloud = CloudClient(transport: transport, session: session)
        let one = try await cloud.setAsideCoach("chat/1", proof: "t=1,v1=SIG,d=dev")
        try expectEqual(one, CoachSetAside(setAside: ["chat/1"], withdrawn: 1))
        let all = try await cloud.setAsideCoach(nil, proof: nil)
        try expectEqual(all.setAside, ["chat/1", "chat-2"])
        try expectEqual(all.already, true)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, ["POST /v1/home/coach-waiting/chat%2F1/set-aside", "POST /v1/home/coach-waiting/set-aside"])
        try expectEqual(transport.sent[0].headers["Planque-Device-Signature"], "t=1,v1=SIG,d=dev")
        try expectEqual(transport.sent[1].headers["Planque-Device-Signature"], nil)
        // No signature of the person's: it's "not now", never an approval.
        try expect(transport.sent.allSatisfy { $0.headers["KIFF-Device-Signature"] == nil }, "nothing signed")
        // A refusal says tafs cloud's words.
        do {
            _ = try await cloud.setAsideCoach("chat-2", proof: nil)
            throw Failure(description: "a refusal was taken")
        } catch let refusal as CloudRefusal {
            try expectEqual(refusal.why(words), "That chat isn't waiting any more.")
        }
    }),
]
