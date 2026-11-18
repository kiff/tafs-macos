import AppKit
import Foundation
import SwiftUI

// The Mac App Store's screenshots: the whole window at 1440×900, drawn at 2× (2880×1800), with
// the samples the iPad shows (Support replies, Late parcels, Lead follow-up, Deploys and Access).
// No sample moves money, so no amount is drawn anywhere. Five frames: the Overview, Needs you,
// Support replies' page, the Record and Start a new taf. They're written to build/screenshots as
// store-<n>-<frame>-en.png, which the CI's screenshots artifact carries.

private let storeSession = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: "dev_1")
private let storeSize = CGSize(width: 1440, height: 900)

/// The moment every frame is drawn at, and a time that many minutes before it, as tafs cloud
/// and KIFF write them.
private let storeNow = Date()
private func storeAt(minutesAgo: Double) -> String {
    ISO8601DateFormatter().string(from: storeNow.addingTimeInterval(-minutesAgo * 60))
}

private func storeWords() -> Words {
    Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
}

/// A Card counted in calls, as tafs cloud sends a taf's Card: `used` of `limit` today.
private func storeCard(_ id: String, _ title: String, limit: Int, used: Int) -> String {
    #"{"cards":[{"id":"\#(id)","title":"\#(title)","active":true,"rules":[{"label":"\#(title)","outside":"hold","count_per_window":\#(limit),"window_words":{"each":"a day","now":"today"}}],"calls":{"limit":\#(limit),"used":\#(used),"window_words":{"each":"a day","now":"today"}}}]}"#
}

/// The five sample tafs, in the iPad's Overview order: the three a call waits on first.
private let storeHome = #"""
{"tafs":[
  {"id":"taf-deploys","name":"Deploys","kiff_agent":"agent_deploys","color":1,"state":"waiting","waiting":1,
   "job_summary":"Ships the services and rolls them back when a check fails.","card":\#(storeCard("c-deploys", "Deploys", limit: 10, used: 1))},
  {"id":"taf-parcels","name":"Late parcels","kiff_agent":"agent_parcels","color":3,"state":"waiting","waiting":1,
   "job_summary":"Tells customers when a parcel runs late.","card":\#(storeCard("c-parcels", "Delay messages", limit: 100, used: 1))},
  {"id":"taf-support","name":"Support replies","kiff_agent":"agent_support","color":4,"state":"waiting","waiting":1,
   "job_summary":"Answers the support tickets it can.","card":\#(storeCard("c-support", "Support replies · Zendesk", limit: 40, used: 12))},
  {"id":"taf-leads","name":"Lead follow-up","kiff_agent":"agent_leads","color":0,"state":"working","waiting":0,"next_run_words":"Next run 14:00",
   "job_summary":"Replies to new leads and books the first call.","card":\#(storeCard("c-leads", "First replies", limit: 50, used: 2))},
  {"id":"taf-access","name":"Access","kiff_agent":"agent_access","color":2,"state":"idle","waiting":0,
   "job_summary":"Gives and takes away access as people join and leave.","card":\#(storeCard("c-access", "Approved roles", limit: 40, used: 1))}
],"headline":{"words":"5 tafs, 3 waiting for you."},"needs_you":{"count":3,"words":"3 need you."}}
"""#

/// The three calls each Card always asks about, as KIFF holds them.
private func storeHeld() -> String {
    let expires = ISO8601DateFormatter().string(from: storeNow.addingTimeInterval(9 * 60 + 37))
    func call(_ id: String, _ agent: String, _ action: String, _ title: String, _ reason: String, _ about: String, _ why: String, _ ago: Double) -> String {
        #"{"id":"\#(id)","subject":"\#(agent)","action":"\#(action)","title":"\#(title)","reason_text":"\#(reason)","taf_about":"\#(about)","taf_reason":"\#(why)","created_at":"\#(storeAt(minutesAgo: ago))","expires_at":"\#(expires)"}"#
    }
    return #"{"exceptions":["#
        + [call("exc_deploys", "agent_deploys", "migration", "Run migration 0042_orders_index", "Schema migrations: always asks you", "api, production", "Adds an index, 3M rows", 3),
           call("exc_parcels", "agent_parcels", "send_parcel", "Send a new parcel for order #5098", "Reships: always asks you", "Order #5098", "Lost in transit, 10 days without a scan", 2),
           call("exc_support", "agent_support", "promise", "Promise a replacement on ticket #7802", "Promises: always asks you", "Ticket #7802", "Arrived broken, photo attached", 1)]
            .joined(separator: ",")
        + "]}"
}

/// Today's Record, newest first: each taf's second round, its first, and each taf's start.
private func storeRecord() -> String {
    let clock = DateFormatter()
    clock.dateFormat = "HH:mm"
    func entry(_ id: String, _ ago: Double, _ kind: String, _ title: String, _ detail: String, _ taf: String, _ name: String) -> String {
        let time = clock.string(from: storeNow.addingTimeInterval(-ago * 60))
        return #"{"id":"\#(id)","at":"\#(storeAt(minutesAgo: ago))","kind":"\#(kind)","title":"\#(title)","detail":"\#(detail)","time":"\#(time)","taf":{"id":"\#(taf)","name":"\#(name)"}}"#
    }
    let within = "Within the Card", issued = "Card issued by You"
    let entries = [
        entry("r1", 1, "done", "Confirm the call with Nord Atelier", within, "taf-leads", "Lead follow-up"),
        entry("r2", 3, "held", "Held: Run migration 0042_orders_index", "Schema migrations: always asks you", "taf-deploys", "Deploys"),
        entry("r3", 4, "done", "Deactivate Tom's accounts", within, "taf-access", "Access"),
        entry("r4", 5, "held", "Held: Send a new parcel for order #5098", "Reships: always asks you", "taf-parcels", "Late parcels"),
        entry("r5", 6, "held", "Held: Promise a replacement on ticket #7802", "Promises: always asks you", "taf-support", "Support replies"),
        entry("r6", 8, "done", "Reply to Studio Kaya", within, "taf-leads", "Lead follow-up"),
        entry("r7", 9, "done", "Deploy api v2.14.1", within, "taf-deploys", "Deploys"),
        entry("r8", 10, "done", "Give Ana the Sales role", within, "taf-access", "Access"),
        entry("r9", 11, "done", "Tell order #5120 it's running late", within, "taf-parcels", "Late parcels"),
        entry("r10", 12, "done", "Reply to ticket #7781", within, "taf-support", "Support replies"),
        entry("r11", 14, "started", "Support replies started", issued, "taf-support", "Support replies"),
        entry("r12", 15, "started", "Late parcels started", issued, "taf-parcels", "Late parcels"),
        entry("r13", 16, "started", "Access started", issued, "taf-access", "Access"),
        entry("r14", 17, "started", "Deploys started", issued, "taf-deploys", "Deploys"),
        entry("r15", 18, "started", "Lead follow-up started", issued, "taf-leads", "Lead follow-up"),
    ].joined(separator: ",")
    return #"{"q":"","entries":[\#(entries)],"groups":[{"id":"today","title":"Today","entries":[\#(entries)]}],"end_words":"That's everything."}"#
}

/// Support replies' Activity: its held promise, its reply, and its start.
private let storeActivity = #"""
{"groups":[{"id":"today","title":"Today","entries":[
  {"id":"a1","kind":"held","title":"Held: Promise a replacement on ticket #7802","detail":"Promises: always asks you","time":"now"},
  {"id":"a2","kind":"done","title":"Reply to ticket #7781","detail":"Within the Card","time":"12 min ago"},
  {"id":"a3","kind":"started","title":"Support replies started","detail":"Card issued by You","time":"14 min ago"}]}],
 "filters":[{"id":"all","title":"All"},{"id":"done","title":"Done"},{"id":"held","title":"Held"},{"id":"refused","title":"Refused"}],"filter":"all"}
"""#

/// The jobs to start a taf from, the samples' own.
private let storeGallery = #"""
{"categories":[{"id":"support","title":"Support"},{"id":"shop","title":"Shop"},{"id":"sales","title":"Sales"},{"id":"team","title":"Team"}],
 "recipes":[{"id":"support-replies","title":"Support replies","category":"support","headline":"Tickets wait overnight","line":"Answers the tickets it can, and asks you before it promises anything","say":"Answer my support tickets","apps":[{"name":"Zendesk"},{"name":"Gmail"}]},
            {"id":"late-parcels","title":"Late parcels","category":"shop","headline":"Customers chase their parcels","line":"Tells customers when a parcel runs late, and asks you before it sends a new one","say":"Tell customers when a parcel is late"},
            {"id":"lead-follow-up","title":"Lead follow-up","category":"sales","headline":"New leads wait for a reply","line":"Replies to new leads and books the first call","say":"Follow up on new leads","apps":[{"name":"Gmail"}]},
            {"id":"access","title":"Access","category":"team","headline":"Access lags behind the team","line":"Gives and takes away access as people join and leave","say":"Keep access in step with the team"}],
 "strip":{"shown":true,"title":"Jobs to try","ids":["support-replies","late-parcels","lead-follow-up"]},
 "words":{"title":"Start a new taf","all":"All jobs","own_words":"Say it in your own words","own_words_line":"Coach builds the taf with you.","explore":"Explore jobs","see_all":"See all jobs","try":"Try it with Coach","sample":"What it reported after its test run"}}
"""#

/// Draws a frame at 2×, in a window off screen with the run loop turned a few times, so a
/// screen whose scrolled content is laid out a turn later is drawn whole.
@MainActor
private func storeShot<V: View>(_ view: V, _ name: String) throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: storeSize.width, height: storeSize.height))
    host.frame = CGRect(origin: .zero, size: storeSize)
    host.appearance = NSAppearance(named: .aqua)
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: storeSize.width, height: storeSize.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    for _ in 0..<5 {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(storeSize.width) * 2, pixelsHigh: Int(storeSize.height) * 2,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        throw Failure(description: "no bitmap for \(name)")
    }
    bitmap.size = storeSize
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG for \(name)") }
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("\(name)-en.png"))
    return bitmap
}

let storeScreenshotMacTests: [Test] = [
    Test("the Store's screenshots: the whole window at 2880×1800, with the iPad's samples and no amount", awaiting: { @MainActor in
        let words = storeWords()
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(storeHome.utf8))
        try expectEqual(page.tafs.map(\.name), ["Deploys", "Late parcels", "Support replies", "Lead follow-up", "Access"])
        struct Held: Decodable { let exceptions: [HeldCall] }
        let calls = try AccountClient.decoder.decode(Held.self, from: Data(storeHeld().utf8)).exceptions
        let held = calls.map { HeldRow($0, tafs: page.tafs) }
        try expectEqual(held.count, 3)
        // No sample moves money: nothing any frame reads holds a currency.
        for fixture in [storeHome, storeHeld(), storeRecord(), storeActivity, storeGallery] {
            try expect(!["€", "$", "£"].contains { fixture.contains($0) }, "an amount in a fixture")
        }

        Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
        func shell(_ selection: Screen, tafPage: AnyView? = nil, openTaf: String? = nil, screen: @escaping (Screen) -> AnyView?) -> AnyView {
            AnyView(ShellView(selection: .constant(selection), needsYou: held.count, tafs: page.tafs, held: held, tafPage: tafPage,
                              openTaf: openTaf, accountLine: "you@example.com", screen: screen)
                .environment(\.words, words))
        }

        // 1. The Overview: the three waiting calls, and each taf's line and Card.
        let overview = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, storeHome), (404, ""), (404, ""), (404, "")]), session: storeSession))
        await overview.load()
        let one = try storeShot(shell(.overview) { _ in AnyView(OverviewView(model: overview, held: held, needsCount: held.count)) }, "store-1-overview")

        // 2. Needs you: the three calls, each with its reason and the time left.
        let needsYou = NeedsYouModel(account: AccountClient(transport: CannedTransport([(200, storeHeld())]), session: storeSession), route: .touchID)
        await needsYou.load()
        let two = try storeShot(shell(.needsYou) { _ in AnyView(NeedsYouView(model: needsYou, tafs: page.tafs, now: storeNow)) }, "store-2-needs-you")

        // 3. Support replies' page, on its Activity.
        guard let support = page.tafs.first(where: { $0.name == "Support replies" }) else { throw Failure(description: "no Support replies") }
        let pageCloud = CloudClient(transport: CannedTransport([(200, #"{"working":false,"items":[]}"#), (200, storeActivity)]), session: storeSession)
        let chat = CoachModel(cloud: pageCloud, taf: Coach(id: "taf-support", name: "Support replies"), sleep: { _ in })
        await chat.load()
        let pages = TafPagesModel(cloud: pageCloud, taf: "taf-support")
        await pages.loadActivity()
        let tafPage = AnyView(TafView(taf: support, chat: chat, pages: pages, manages: true, tab: .activity).environment(\.words, words))
        let three = try storeShot(shell(.overview, tafPage: tafPage, openTaf: support.kiffAgent) { _ in nil }, "store-3-support-replies")

        // 4. The Record: today's fifteen lines, with each taf's chip.
        let record = RecordModel(cloud: CloudClient(transport: CannedTransport([(200, storeRecord())]), session: storeSession))
        await record.load()
        let four = try storeShot(shell(.record) { _ in AnyView(RecordView(model: record, tafs: page.tafs)) }, "store-4-record")

        // 5. Start a new taf: the jobs, and Coach for your own words.
        let gallery = try JSONDecoder().decode(Gallery.self, from: Data(storeGallery.utf8))
        let five = try storeShot(shell(.coach) { _ in
            AnyView(RecipeGallerySheet(gallery: gallery, mode: .create, labels: nil, canHand: true, choose: { _ in }, close: {}))
        }, "store-5-start")

        for (shot, name) in [(one, "overview"), (two, "needs you"), (three, "Support replies"), (four, "record"), (five, "start")] {
            try expect(shot.pixelsWide == 2880 && shot.pixelsHigh == 1800, "\(name) at 2880×1800, not \(shot.pixelsWide)×\(shot.pixelsHigh)")
        }
    }),
]
