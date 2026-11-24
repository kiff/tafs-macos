import Foundation

// The guards that read every source file, whichever part a change touches: `scripts/parts.sh` runs this part on every
// change, as it runs strings and contracts, so a guard can't be skipped by a change in another part (docs/building.md).

/// Every Swift file under `Sources`, as text: what the app is built from.
private func sources() throws -> [(path: String, text: String)] {
    let root = URL(fileURLWithPath: "Sources")
    guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { throw Failure(description: "no Sources") }
    return try walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        .map { ($0.path, try String(contentsOf: $0, encoding: .utf8)) }
}

/// What no source may name: planque's approve and confirm, and any grant's route but the grants read. One exception, in the
/// open: KIFF's draft confirm, exactly this line, in `KeyAct` alone, signed by the security key.
enum PlanqueBan {
    static let kiffDraftConfirm = #"case .confirmTrial(let id, _), .confirmDraft(let id, _): return "/v1/me/agent-drafts/\(CloudClient.escaped(id))/confirm""#

    /// What no source names (#178's list): planque's approve and confirm, a fresh connection, a grant's own path beyond the
    /// DELETE's, and the grants list by its bare name.
    static let banned = ["/approve", "/confirm", "/connect-fresh", "grants/\\(CloudClient.escaped(grantID))/", "\"grants\""]
    /// No grant's sub-route at all, however a path is put together (planque `server.go`). `/keys` isn't one.
    static let subRoute = try! NSRegularExpression(pattern: #"/(key|approve|confirm|connect-fresh|sign-in|tools|chrome|describe|read|catalog|channels)\b"#)

    /// The banned text this source names, else nil. KIFF's draft confirm line is taken out first, in `KeyAct` only. A line that
    /// is only a comment names no route (a doc's path, `docs/chrome.md`, isn't one), as `code(_:)` below reads them; a route in
    /// code, a comment after it included, is still read.
    static func names(path: String, text: String) -> String? {
        var text = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        if path.hasSuffix("Sources/Core/approvals/KeyApproval.swift") { text = text.replacingOccurrences(of: kiffDraftConfirm, with: "") }
        if let named = banned.first(where: { text.contains($0) }) { return named }
        return subRoute.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) > 0 ? "a grant's sub-route" : nil
    }
}

/// planque's routes: only the DELETE names a grant's route, the client is made and armed in one place, and the ban holds.
let guardsPlanqueTests: [Test] = [
    Test("only the DELETE names a grant's route; no source names approve, confirm, a grant's key or a fresh connection") {
        let all = try sources()
        try expect(all.count > 50, "the app's sources: \(all.count)")
        for (path, text) in all {
            if let named = PlanqueBan.names(path: path, text: text) { throw Failure(description: "\(path) names \(named)") }
        }
        // KIFF's draft confirm, the one such path a source names: once, in `KeyAct`, where the security key signs it.
        // planque's approve and confirm, and every grant's sub-route, stay banned.
        let allowedIn = all.filter { $0.text.contains(PlanqueBan.kiffDraftConfirm) }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        try expectEqual(allowedIn, ["KeyApproval.swift"])
        // Every line of code that names planque's account routes or a grants list, exactly: the
        // enrolment's root, the grants read (its proof and the source's), the DELETE's path, and
        // KIFF's read of a taf's shares. A line built from any of them is a new line, and fails here.
        func code(_ needle: String) -> [String] {
            all.flatMap { file in
                file.text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.contains(needle) && !$0.hasPrefix("//") }
                    .map { "\(URL(fileURLWithPath: file.path).lastPathComponent): \($0)" }
            }.sorted()
        }
        try expectEqual(code("/v1/accounts/"), [
            #"AppConnections.swift: var path: String { "/v1/accounts/\(CloudClient.escaped(tenant))/grants" }"#,
            #"PlanqueClient.swift: "/v1/accounts/\(CloudClient.escaped(tenant))/grants/\(CloudClient.escaped(grantID))""#,
            #"PlanqueClient.swift: let account = "/v1/accounts/\(CloudClient.escaped(tenant))""#,
            #"PlanqueClient.swift: let path = "/v1/accounts/\(CloudClient.escaped(tenant))/grants""#,
            // Account › Chrome's safe routes (#173): `GET chromes` and `DELETE chromes/{id}`, built from `Safe.path`.
            #"PlanqueClient.swift: let uri = "/v1/accounts/\(CloudClient.escaped(tenant))/\(route.path)""#,
        ])
        try expectEqual(code("/grants"), [
            #"AppConnections.swift: var path: String { "/v1/accounts/\(CloudClient.escaped(tenant))/grants" }"#,
            // KIFF's sharing of a taf's agent, not planque's: an approval KIFF takes from the security key (`KeyAct.share`).
            #"KeyApproval.swift: case .share(let agent, _): return "/v1/agents/\(CloudClient.escaped(agent))/grants""#,
            #"KeyApproval.swift: return "/v1/agents/\(CloudClient.escaped(agent))/grants?\(query)""#,
            #"PlanqueClient.swift: "/v1/accounts/\(CloudClient.escaped(tenant))/grants/\(CloudClient.escaped(grantID))""#,
            #"PlanqueClient.swift: let path = "/v1/accounts/\(CloudClient.escaped(tenant))/grants""#,
            #"Shares.swift: let list: List = try read(try await send("GET", "/v1/agents/\(agent.addingPercentEncoding(withAllowedCharacters: allowed) ?? agent)/grants"))"#,
        ])
        // The two grants reads are read as paths, never added to: nothing follows them but a GET.
        for (path, text) in all {
            try expect(!text.contains("path + \"/") && !text.contains("path + \"\\(") && !text.contains("account + "), "\(path) adds to a path")
        }
        // `grants/` once, in the client, in the DELETE's path and nowhere else.
        let naming = all.filter { $0.text.contains("grants/") }
        try expectEqual(naming.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["PlanqueClient.swift"])
        let client = naming[0].text
        // Twice: the DELETE's path, and a Slack door's subscription stopped on planque's safe route (`Safe.deleteTrigger`,
        // deleting a trigger, which takes authority away and is the device key's), this exact line and no other.
        try expectEqual(client.components(separatedBy: "grants/").count - 1, 2)
        try expect(client.contains(#"case .deleteTrigger(let grant, let trigger): return "grants/\(CloudClient.escaped(grant))/triggers/\(CloudClient.escaped(trigger))""#),
                   "the second is the trigger's DELETE")
        try expect(client.contains(#""/v1/accounts/\(CloudClient.escaped(tenant))/grants/\(CloudClient.escaped(grantID))""#), "the DELETE's path, the grant's id last")
        // Two DELETEs in the client: the disconnect's (named twice, signed and sent), and Account › Chrome's unpair (#173,
        // `Safe.unpairChrome`, a safe route of its own). Each signs the empty body.
        try expectEqual(client.components(separatedBy: #""DELETE""#).count - 1, 4)
        try expect(client.contains(#"case .unpairChrome: return "DELETE""#), "the third is the Chrome's unpair")
        try expect(client.contains(#"case .deleteTrigger: return "DELETE""#), "the fourth is a trigger's, a safe route")
        try expect(client.contains(#"method: "DELETE", uri: uri, bodyHash: Self.emptyBodyHash"#), "the DELETE signs no body")
        try expect(client.contains(#"HTTPRequest(method: "DELETE", path: uri"#), "the DELETE is sent as signed")
        // The grants proof stays a read: GET, over the grants list, and nothing else.
        try expect(client.contains(#"method: "GET", uri: path"#), "the grants proof signs a GET")
        // One request to planque's account routes through `send`: the enrolment's.
        let planqueSends = try NSRegularExpression(pattern: #"send\("[A-Z]+", "[^/]"#)
        try expectEqual(planqueSends.numberOfMatches(in: client, range: NSRange(client.startIndex..., in: client)), 1)
        // The DELETE takes its signer: it never arms the client's.
        try expect(!client.contains("self.signer =") && !client.contains("signer = sign"), "the client never arms itself")
    },
    Test("the PlanqueClient is made in one place, and armed to sign only around the enrolment, then cleared") {
        let made = try sources().filter { $0.text.contains("PlanqueClient()") }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        try expectEqual(made, ["SignedInView.swift"])
        let arming = try sources().filter { $0.text.contains("planque.signer = ") }
        try expectEqual(arming.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["SignedInView.swift"])
        let text = arming[0].text
        try expectEqual(text.components(separatedBy: "planque.signer = account.signMessage").count - 1, 1)
        try expectEqual(text.components(separatedBy: "defer { planque.signer = nil }").count - 1, 1)
        // Armed, then cleared on every path, around the enrolment alone.
        guard let armedAt = text.range(of: "planque.signer = account.signMessage"),
              let enrolAt = text.range(of: "PlanqueEnrolment.enrol(planque: planque") else { throw Failure(description: "the enrolment step") }
        let between = String(text[armedAt.upperBound..<enrolAt.lowerBound])
        try expect(between.contains("defer { planque.signer = nil }"), "cleared on every path once the enrolment ends")
    },
    Test("the DELETE is called from one place, the connections' source, and only after Touch ID") {
        let calling = try sources().filter { $0.text.contains(".disconnect(grantID:") }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        try expectEqual(calling, ["AppConnections.swift"])
        let ending = try String(contentsOf: URL(fileURLWithPath: "Sources/Core/connections/ConnectionEnding.swift"), encoding: .utf8)
        guard let confirmAt = ending.range(of: "try await confirm(prompt, confirmation(tenant: tenant, ids: ids))"), let deleteAt = ending.range(of: "try await delete(id)") else {
            throw Failure(description: "the ending's steps")
        }
        try expect(confirmAt.lowerBound < deleteAt.lowerBound, "Touch ID comes before the DELETE")
    },
    Test("any other approve or confirm route still fails the ban: planque's, KIFF's elsewhere, or KIFF's spelt another way") {
        let fakes = [
            ("Sources/X.swift", #"let p = "/v1/accounts/t/grants/g1/confirm""#),
            ("Sources/X.swift", #"let p = "/v1/accounts/t/grants/g1/approve""#),
            ("Sources/X.swift", #"let p = "/v1/me/agent-drafts/\(id)/confirm""#),
            // KIFF's line itself, outside `KeyAct`: still banned.
            ("Sources/Other.swift", PlanqueBan.kiffDraftConfirm),
            ("Sources/Core/approvals/KeyApproval.swift", #"return "/v1/me/agent-drafts/" + "x/confirm""#),
            ("Sources/X.swift", #"let l = "grants""#),
            ("Sources/X.swift", #"let p = base + "/sign-in""#),
            // A sub-route in code still fails, with a comment after it or a comment line before it.
            ("Sources/X.swift", #"let p = base + "/chrome" // docs/chrome.md"#),
            ("Sources/X.swift", "/// docs/chrome.md\n" + #"let p = base + "/chrome""#),
        ]
        for (path, text) in fakes {
            try expect(PlanqueBan.names(path: path, text: text) != nil, "\(text) in \(path) slips through")
        }
        // The one allowed line, in `KeyAct`, passes.
        try expectEqual(PlanqueBan.names(path: "Sources/Core/approvals/KeyApproval.swift", text: PlanqueBan.kiffDraftConfirm), nil)
        // A comment naming a doc's path names no route.
        try expectEqual(PlanqueBan.names(path: "Sources/X.swift", text: "    /// kiff/tafs `docs/chrome.md`, \"never an allowing answer\""), nil)
    },
]

/// The account's deletion: no source names a deletion route; it's the phone's.
let guardsAccountTests: [Test] = [
    Test("deleting the account is the phone's: no source names a deletion route, and the Delete row only says to approve elsewhere") {
        // KIFF takes a deletion only signed by the session's approval key (`acceptDeletion`, `tafs.delete-account.v2`), and
        // this app signs in with a passkey, so its session holds none: the Delete row sends nothing (docs/account.md, the
        // checklist's DeleteAccountView).
        var texts: [String] = []
        let all = FileManager.default.enumerator(atPath: "Sources")?.compactMap { $0 as? String } ?? []
        for path in all where path.hasSuffix(".swift") {
            texts.append(try String(contentsOf: URL(fileURLWithPath: "Sources/" + path), encoding: .utf8))
        }
        try expect(!texts.isEmpty, "the sources were read")
        for route in ["/v1/account/delete", "/v1/me/delete", "delete-account.v", "eraseAccount"] {
            try expect(!texts.contains { $0.contains(route) }, "a source names \(route)")
        }
        let view = try String(contentsOf: URL(fileURLWithPath: "Sources/App/account/KiffAccountView.swift"), encoding: .utf8)
        try expect(view.contains(#"AccountRow.action(words("settings.delete_account.row"), color: Theme.no) { deleteRefused = true }"#),
                   "the row's click only sets what it says")
        try expect(view.contains(#"words("approval.device_can_not_approve_approve")"#), "it says to approve on another device")
    },
]
