import Foundation

/// Home with labels, in kiff/tafs `docs/labels.md`'s shape: each taf's ids, the account's labels in
/// the order to show them, and the first chip's word.
let labelledHome = #"""
{"tafs":[
  {"id":"taf_1","name":"Refunds","kiff_agent":"agent_refunds","state":"working","labels":["lab_money","lab_shop"]},
  {"id":"taf_2","name":"Invoices","kiff_agent":"agent_invoices","state":"idle","labels":["lab_money"]},
  {"id":"taf_3","name":"Replies","kiff_agent":"agent_replies","state":"waiting","labels":["lab_care","lab_money","lab_shop"]},
  {"id":"taf_4","name":"Bare","kiff_agent":"agent_bare","state":"stopped"}],
 "labels":[
  {"id":"lab_money","name":"Money","color":"money","count":3,"waiting":1,"headline":{"words":"3 tafs working · Money"}},
  {"id":"lab_shop","name":"Shop","color":"errands","count":2,"waiting":0},
  {"id":"lab_care","name":"Customers","color":"customers","count":1,"waiting":true},
  {"id":"","name":"No id"},
  "not a label"],
 "labels_words":{"all":"All"}}
"""#

private func page(_ body: String) throws -> Home.Page { try JSONDecoder().decode(Home.Page.self, from: Data(body.utf8)) }

let homeLabelsTests: [Test] = [
    Test("Home's labels are read as sent, in order: one the app can't read is left out, never Home") {
        let home = try page(labelledHome)
        try expectEqual(home.labels.map(\.id), ["lab_money", "lab_shop", "lab_care"])
        try expectEqual(home.labels[0], HomeLabel(id: "lab_money", name: "Money", color: "money", count: 3, waiting: 1, headline: "3 tafs working · Money"))
        // A yes/no from an earlier draft reads as one waiting.
        try expectEqual(home.labels[2].waiting, 1)
        try expectEqual(home.labelsAll, "All")
        try expectEqual(home.tafs.map(\.labels), [["lab_money", "lab_shop"], ["lab_money"], ["lab_care", "lab_money", "lab_shop"], []])
    },
    Test("with no labelled taf, Home sends no labels and the list has no chips") {
        let home = try page(#"{"tafs":[{"name":"Bare","kiff_agent":"a","state":"idle"}]}"#)
        try expectEqual(home.labels, [])
        try expectEqual(home.labelsAll, nil)
        try expectEqual(home.tafs[0].labels, [])
    },
    Test("labels of another shape read as none, and Home still reads") {
        let home = try page(#"{"tafs":[{"name":"T","kiff_agent":"a","state":"idle","labels":"lab_money"}],"labels":{"id":"x"},"labels_words":"All"}"#)
        try expectEqual(home.labels, [])
        try expectEqual(home.labelsAll, nil)
        try expectEqual(home.tafs[0].labels, [])
    },
    Test("a chip filters the list without reordering it, and a label that's gone shows them all") {
        let home = try page(labelledHome)
        try expectEqual(HomeLabels.filtered(home.tafs, by: nil, in: home.labels).map(\.name), ["Refunds", "Invoices", "Replies", "Bare"])
        try expectEqual(HomeLabels.filtered(home.tafs, by: "lab_money", in: home.labels).map(\.name), ["Refunds", "Invoices", "Replies"])
        try expectEqual(HomeLabels.filtered(home.tafs, by: "lab_shop", in: home.labels).map(\.name), ["Refunds", "Replies"])
        try expectEqual(HomeLabels.filtered(home.tafs, by: "lab_gone", in: home.labels).map(\.name), ["Refunds", "Invoices", "Replies", "Bare"])
    },
    Test("a taf's labels are in the account's order, not the taf's") {
        let home = try page(labelledHome)
        try expectEqual(HomeLabels.of(home.tafs[2], in: home.labels).map(\.name), ["Money", "Shop", "Customers"])
        try expectEqual(HomeLabels.of(home.tafs[3], in: home.labels), [])
    },
]
