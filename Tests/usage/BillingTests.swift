import Foundation

private func usage(_ json: String) throws -> KIFFUsage {
    try AccountClient.decoder.decode(KIFFUsage.self, from: Data(json.utf8))
}

/// Who bills the plan, as the iPad's `KIFFClient.Usage.Billing` and `UsageView.billingPanel`
/// (`billingLine`, `managedByApple`, `soloStillRenews`).
let usageBillingTests: [Test] = [
    Test("who bills the plan is one line, by its source, as the iPad's billingLine") {
        try expectEqual(try usage(#"{"plan":"solo","billing":{"source":"apple"}}"#).billingLine, "billing.by_apple")
        try expectEqual(try usage(#"{"plan":"solo","billing":{"source":"google"}}"#).billingLine, "billing.by_google_play")
        try expectEqual(try usage(#"{"plan":"team","billing":{"source":"stripe"}}"#).billingLine, "billing.by_kiff")
        try expectEqual(try usage(#"{"plan":"company","billing":{"source":"contract"}}"#).billingLine, "billing.by_agreement")
        // No plan billed, a source this app doesn't know, or one that doesn't read: no line.
        try expectEqual(try usage(#"{"plan":null}"#).billingLine, nil)
        try expectEqual(try usage(#"{"billing":{"source":"paypal"}}"#).billingLine, nil)
        try expectEqual(try usage(#"{"billing":{"source":7}}"#).billingLine, nil)
        try expectEqual(try usage(#"{"billing":{}}"#).billing, nil)
    },
    Test("Manage only where Apple bills the plan") {
        try expect(try usage(#"{"billing":{"source":"apple"}}"#).managedByApple, "Apple's plan is managed in the Apple account")
        for source in ["google", "stripe", "contract"] {
            try expect(!(try usage(#"{"billing":{"source":""# + source + #""}}"#).managedByApple), "\(source) has no Manage")
        }
    },
    Test("Solo still renewing with Apple is said only after a move to Company that KIFF bills") {
        let moved = try usage(#"{"plan":"team","billing":{"source":"stripe","apple_solo_until":"2026-12-03T10:00:00Z"}}"#)
        try expectEqual(moved.soloStillRenews, ISO8601DateFormatter().date(from: "2026-12-03T10:00:00Z"))
        try expectEqual(moved.billingLine, "billing.by_kiff")
        // Apple still bills it, or no date: nothing to say.
        try expectEqual(try usage(#"{"billing":{"source":"apple","apple_solo_until":"2026-12-03T10:00:00Z"}}"#).soloStillRenews, nil)
        try expectEqual(try usage(#"{"billing":{"source":"stripe"}}"#).soloStillRenews, nil)
        // A date that doesn't read makes the billing none, as the iPad's, and never the rest of the read.
        let broken = try usage(#"{"plan":"team","billing":{"source":"stripe","apple_solo_until":"soon"},"requests":[]}"#)
        try expectEqual(broken.billing, nil)
        try expectEqual(broken.plan, "team")
    },
    Test("Manage and Cancel Solo open Apple's own subscriptions page, nothing else") {
        try expectEqual(KIFFUsage.appleSubscriptions.absoluteString, "https://apps.apple.com/account/subscriptions")
    },
]
