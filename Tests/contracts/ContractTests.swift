import Foundation

/// kiff/tafs's contract fixtures at the pin, as `scripts/shared.sh fetch` leaves them.
private let folder = URL(fileURLWithPath: ".shared/contracts")

/// The fixtures this app reads today, and the ones whose screens haven't arrived, each with
/// the pull request that will read it. A fixture in neither list fails the test below.
private let read = ["ai-consent.json", "recipes-home.json", "taf-runs.json", "taf-run-report.json", "taf-run-report-running.json", "taf-run-report-terminated.json", "taf-activity.json", "taf-setup.json"]
private let notYet = [
    "home.json": "the tafs list read from Home, in its own pull request after this pin",
    "home-paused.json": "the tafs list read from Home, in its own pull request after this pin",
    "tafs.json": "the tafs list read from GET /v1/tafs, in its own pull request after this pin",
    "tafs-paused.json": "the tafs list read from GET /v1/tafs, in its own pull request after this pin",
    "setup-start.json": "Coach's first start, with the Coach screens",
    "setup-start-draft-alone.json": "Coach's first start, with the Coach screens",
    "setup-time-zone.json": "a new account's zone, with the Coach screens",
    "taf-setup-connected.json": "a taf's Setup tab's connections, with the taf page",
    "taf-setup-reconnect.json": "a taf's Setup tab's connections, with the taf page",
]

/// A fixture's cases (`{about, cases: [{name, status, body}]}`), each body as the bytes the app would read.
private func cases(_ file: String) throws -> [(name: String, status: Int, body: Data)] {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(file))) as? [String: Any]
    guard let all = root?["cases"] as? [[String: Any]] else { throw Failure(description: "\(file) has no cases") }
    return try all.map { c in
        guard let name = c["name"] as? String, let status = c["status"] as? Int, let body = c["body"] else {
            throw Failure(description: "\(file): a case without a name, a status or a body")
        }
        return (name, status, try JSONSerialization.data(withJSONObject: body))
    }
}

/// A fixture's one answer (`{about, answer}`), as the bytes the app would read.
private func answer(_ file: String) throws -> Data {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(file))) as? [String: Any]
    guard let answer = root?["answer"] else { throw Failure(description: "\(file) has no answer") }
    return try JSONSerialization.data(withJSONObject: answer)
}

let contractsTests: [Test] = [
    Test("every fixture at the pin is read here, or named as not yet read") {
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
        try expect(!files.isEmpty, "fixtures in .shared/contracts")
        for file in files {
            try expect(read.contains(file) || notYet[file] != nil, "\(file) is new: read it, or say which screen will")
        }
        for file in read + Array(notYet.keys) {
            try expect(files.contains(file), "\(file) is no longer in kiff/tafs: take it off the list")
        }
    },
    Test("the AI consent reads as tafs cloud answers it") {
        let all = try cases("ai-consent.json")
        try expect(all.count >= 5, "at least 5 cases, got \(all.count)")
        for (name, status, body) in all {
            switch status {
            case 200:
                guard let consent = TafsCloud.consent(in: body) else { throw Failure(description: "\(name): no consent read") }
                try expect(consent.drawable, "\(name): the screen has its words")
                try expectEqual(consent.given, name == "given")
            case 403:
                let refusal = TafsCloud.Refusal(status: status, body: body)
                try expectEqual(refusal.code, TafsCloud.aiConsentRequired)
                try expect(refusal.error?.isEmpty == false, "\(name): tafs cloud's line for the person")
                try expectEqual(refusal.consent?.drawable, true)
            case 409:
                let refusal = TafsCloud.Refusal(status: status, body: body)
                try expectEqual(refusal.consent?.drawable, true)
                try expectEqual(refusal.consent?.given, false)
            default:
                throw Failure(description: "\(name): an answer the app doesn't read (\(status))")
            }
        }
    },
    Test("Home's line for an account with no taf reads as tafs cloud sends it") {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("recipes-home.json"))) as? [String: Any]
        guard let answer = root?["answer"] else { throw Failure(description: "recipes-home.json has no answer") }
        let words = try JSONDecoder().decode(HomeWords.self, from: JSONSerialization.data(withJSONObject: answer))
        try expectEqual(words.shown, true)
        try expect(words.line?.isEmpty == false, "Home's line")
        // Not shown, or no words: no line, and never a failure.
        try expectEqual(try JSONDecoder().decode(HomeWords.self, from: Data(#"{"home":{"shown":false,"words":"Pick a job."}}"#.utf8)).line, nil)
        try expectEqual(try JSONDecoder().decode(HomeWords.self, from: Data(#"{"home":7}"#.utf8)).line, nil)
        try expectEqual(try JSONDecoder().decode(HomeWords.self, from: Data("{}".utf8)).line, nil)
    },
    Test("a taf's runs and a run's report read as tafs cloud answers, and give the Overview's Last result") {
        let words = try Words(language: "en", folder: URL(fileURLWithPath: ".shared/app/strings"))
        let runs = try AccountClient.decoder.decode(Runs.Page.self, from: answer("taf-runs.json")).runs
        try expectEqual(runs.map(\.session), ["sess3", "sess1"])
        try expectEqual(runs[0].error, nil)
        try expect(runs[1].error?.isEmpty == false, "why the second stopped")
        let ended = try AccountClient.decoder.decode(Runs.Report.self, from: answer("taf-run-report.json"))
        let running = try AccountClient.decoder.decode(Runs.Report.self, from: answer("taf-run-report-running.json"))
        let stopped = try AccountClient.decoder.decode(Runs.Report.self, from: answer("taf-run-report-terminated.json"))
        try expectEqual([ended.status, running.status, stopped.status], ["idle", "running", "terminated"])
        let time: (Date) -> String = { _ in "12:00" }
        // An ended run: its answer's first line.
        try expectEqual(Runs.line(latest: runs[0], newest: runs[0], report: ended, words: words, time: time), ended.text.components(separatedBy: "\n")[0])
        // A run still working has no answer yet: when it last ran.
        try expectEqual(Runs.line(latest: runs[0], newest: runs[0], report: running, words: words, time: time), "Last ran at 12:00")
        // A run that stopped on an error: why, from the runs list, since a report never says.
        try expectEqual(Runs.line(latest: runs[1], newest: runs[1], report: stopped, words: words, time: time), runs[1].error)
        try expectEqual(Runs.line(latest: nil, newest: nil, report: nil, words: words, time: time), "Nothing yet")
    },
    Test("a taf's Activity reads as tafs cloud answers it") {
        let activity = try AccountClient.decoder.decode(TafActivity.self, from: answer("taf-activity.json"))
        try expectEqual(activity.groups.map(\.title), ["Today"])
        try expectEqual(activity.groups[0].entries.map(\.kind), ["done"])
        try expectEqual(activity.groups[0].entries[0].title, "Read a case")
        try expectEqual(activity.groups[0].entries[0].detail, "Done, within its Card")
        try expectEqual(activity.groups[0].entries[0].time, "12:00")
        try expectEqual(activity.filters.map(\.id), ["all", "done", "held", "refused"])
        try expectEqual(activity.filter, "all")
        try expect(activity.revision?.isEmpty == false, "a revision to send back")
        try expectEqual(activity.endWords, "Nothing older in this view")
        try expectEqual(activity.exceptions, [])
    },
    Test("a taf's Setup reads as tafs cloud answers it") {
        let setup = try AccountClient.decoder.decode(TafSetup.self, from: answer("taf-setup.json"))
        try expectEqual(setup.workflow, TafSetup.Part(title: "Workflow", summary: "Ask Coach to set its workflow"))
        try expectEqual(setup.memory, TafSetup.Part(title: "0 notes", summary: nil))
        try expectEqual(setup.versions, TafSetup.Part(title: "Changes to how it runs", summary: "Runs its original definition"))
        try expect(setup.connectionsError?.isEmpty == false, "tafs cloud's line for unread connections")
        try expectEqual(setup.exceptions.map(\.title), ["Rae needs a USD limit"])
        try expect(setup.exceptions[0].words?.isEmpty == false, "its words")
        try expect(setup.exceptions[0].history?.isEmpty == false, "its history")
    },
    Test("the consent's words come in the person's language, as sent") {
        let french = try cases("ai-consent.json").first { $0.name.contains("French") }
        guard let body = french?.body, let consent = TafsCloud.consent(in: body) else { throw Failure(description: "no French case") }
        try expect(consent.words.title != "Your data and the AI", "the French title")
    },
    Test("a consent without its words is no screen, and a refusal that doesn't read says nothing") {
        let bare = Data(#"{"consent":{"given":false,"version":"1","words":{"title":" ","lines":[],"allow":"Allow","not_now":"Not now","withdraw":"w","given":"g"}}}"#.utf8)
        try expectEqual(TafsCloud.consent(in: bare)?.drawable, false)
        try expectEqual(TafsCloud.consent(in: Data(#"{"consent":{"given":true}}"#.utf8)), nil)
        let refusal = TafsCloud.Refusal(status: 502, body: Data("<html>".utf8))
        try expectEqual(refusal, TafsCloud.Refusal(status: 502, body: Data()))
        try expectEqual(refusal.code, nil)
    },
]
