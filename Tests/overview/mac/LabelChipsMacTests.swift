import Foundation
import SwiftUI

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let labelChipsMacTests: [Test] = [
    Test("the Overview filters its list by a chip and back to All, opening on All, as the iPad's", awaiting: { @MainActor in
        let overview = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, labelledHome), (404, "")]), session: session))
        await overview.load()
        try expectEqual(overview.listLabel, nil)
        try expectEqual(overview.labels.map(\.name), ["Money", "Shop", "Customers"])
        try expectEqual(overview.filtered(overview.tafs).map(\.name), ["Refunds", "Invoices", "Replies", "Bare"])
        overview.filterList("lab_shop")
        try expectEqual(overview.filtered(overview.tafs).map(\.name), ["Refunds", "Replies"])
        overview.filterList(nil)
        try expectEqual(overview.filtered(overview.tafs).count, 4)
    }),
    Test("the first chip is Home's word, else the app's own All", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let fr = Words.load(folder: strings, preferred: ["fr"])
        let sent = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, labelledHome), (404, "")]), session: session))
        await sent.load()
        try expectEqual(sent.labelsAll(fr), "All")
        let none = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, labelledHome.replacingOccurrences(of: #","labels_words":{"all":"All"}"#, with: "")), (404, "")]), session: session))
        await none.load()
        try expectEqual(none.labelsAll(fr), fr("record.filter.all"))
    }),
    Test("the screenshots: the Overview's label chips, All and one label chosen, in English and French", awaiting: { @MainActor in
        let strings = URL(fileURLWithPath: ".shared/app/strings")
        let folder = URL(fileURLWithPath: "build/screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (language, label, name) in [("en", nil, "overview-labels-en"), ("en", "lab_money", "overview-labels-money-en"), ("fr", nil, "overview-labels-fr")] as [(String, String?, String)] {
            let overview = OverviewModel(cloud: CloudClient(transport: CannedTransport([(200, labelledHome), (404, "")]), session: session))
            await overview.load()
            overview.filterList(label)
            let view = OverviewView(model: overview).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 980, height: 700)), let png = Snapshot.png(bitmap) else { throw Failure(description: "no PNG") }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }),
]
