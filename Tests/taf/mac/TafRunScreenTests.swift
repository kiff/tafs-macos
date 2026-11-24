import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)
private let detail = #"""
{"id":"r7","from":"From the door","line":"Refund for order 1042",
 "steps":[{"label":"Read the order","line":"Order 1042, €42","state":"done"},{"label":"Reply to the customer","line":"Slack didn't answer","state":"failed"}],
 "deliveries":[{"place":"door_reply","state":"not_sent","line":"Not sent yet","send_again":true}]}
"""#

let tafRunMacTests: [Test] = [
    Test("a run opened reads itself; Send again goes once, only for whoever manages the taf, then the run is read again", awaiting: { @MainActor in
        let transport = CannedTransport([(200, detail), (200, #"{"state":"sent"}"#), (200, detail)])
        let model = TafRunModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1", run: "r7")
        await model.load()
        guard let delivery = model.detail?.deliveries.first else { throw Failure(description: "not read") }
        await model.sendAgain(delivery, manages: false)
        try expectEqual(transport.sent.count, 1)
        await model.sendAgain(delivery, manages: true)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path },
                        ["GET /v1/tafs/taf-1/requests/r7", "POST /v1/tafs/taf-1/requests/r7/deliveries/door_reply/send", "GET /v1/tafs/taf-1/requests/r7"])
        try expectEqual(model.error, nil)
    }),
    Test("a run that can't be read says tafs cloud's words, with Try again", awaiting: { @MainActor in
        let transport = CannedTransport([(404, #"{"error":"not_found","words":"This run isn't kept any more."}"#)])
        let model = TafRunModel(cloud: CloudClient(transport: transport, session: session), taf: "taf-1", run: "r7")
        await model.load()
        try expectEqual(model.detail, nil)
        try expectEqual(model.error, "This run isn't kept any more.")
    }),
    Test("the screenshot: a run, its steps and Send again", awaiting: { @MainActor in
        let words = Words.load(folder: URL(fileURLWithPath: ".shared/app/strings"), preferred: ["en"])
        let model = TafRunModel(cloud: CloudClient(transport: CannedTransport([(200, detail)]), session: session), taf: "taf-1", run: "r7")
        await model.load()
        guard let bitmap = Snapshot.bitmap(of: TafRunSheet(model: model, manages: true, close: {}).environment(\.words, words), size: CGSize(width: 520, height: 520)),
              let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "build/screenshots"), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "build/screenshots/taf-run-en.png"))
    }),
]
