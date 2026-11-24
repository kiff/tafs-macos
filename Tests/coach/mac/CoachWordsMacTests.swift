import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

/// A chat whose approval still waits on a connection that isn't made.
private let waitingThread = #"""
{"working":false,"items":[
  {"type":"card","card":{"key":"s1#a1","session":"s1","at":"2026-11-20T09:01:00Z","component":{"id":"a1","type":"approval","title":"Connect Qonto","grant":"g_qonto","waits":"owner"}}}
]}
"""#

private let pendingGrant = #"""
[{"id":"g_qonto","status":"pending","vendor":"Qonto","text":"Read your Qonto invoices","request":{"server":"mcp.qonto.com","agent":"a","tools":[]}}]
"""#

private final class Reads: @unchecked Sendable { var count = 0 }

let coachWordsMacTests: [Test] = [
    Test("KIFF's words that couldn't be read aren't read again on every refresh, only for a new profile", awaiting: { @MainActor in
        var grants = try AccountClient.decoder.decode([AppConnections.Grant].self, from: Data(pendingGrant.utf8))
        grants[0].profile = .object(["v": .string("kiff.profile.v1"), "vendor": .string("qonto")])
        let shown = grants
        var current = shown
        let reads = Reads()
        let transport = CannedTransport([(200, setupAnswer), (200, noChats), (200, waitingThread)])
        let model = CoachModel(cloud: CloudClient(transport: transport, session: session), sleep: { _ in },
                               grants: { current }, drafts: { _ in throw KIFFError.unreadable },
                               profileWords: { _ in reads.count += 1; throw ProfileWords.Failure.otherProfile })
        await model.load()
        await model.readNamed()
        try expectEqual(reads.count, 1)
        try expectEqual(model.profileWordsFailed(for: shown[0]), ProfileWords.Failure.otherProfile.key)
        await model.readNamed()
        await model.readNamed()
        try expectEqual(reads.count, 1)
        // planque's request changed its profile: that one is read.
        current[0].profile = .object(["v": .string("kiff.profile.v1"), "vendor": .string("qonto"), "ops": .array([])])
        await model.readNamed()
        try expectEqual(reads.count, 2)
    }),
]
