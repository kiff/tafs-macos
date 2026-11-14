import Foundation

/// kiff/tafs's contract fixtures at the pin, as `scripts/shared.sh fetch` leaves them.
private let folder = URL(fileURLWithPath: ".shared/contracts")

/// The fixtures this app reads today, and the ones whose screens haven't arrived, each with
/// the pull request that will read it. A fixture in neither list fails the test below.
private let read = ["ai-consent.json"]
private let notYet = [
    "setup-start.json": "Coach's first start, with the Coach screens",
    "setup-start-draft-alone.json": "Coach's first start, with the Coach screens",
    "setup-time-zone.json": "a new account's zone, with the Coach screens",
    "recipes-home.json": "Home's recipes, with the Overview",
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
