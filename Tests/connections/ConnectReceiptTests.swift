import Foundation

/// Coach's chat with one connection card, as tafs cloud sends it: `connection` is its mark
/// once planque shows the connection made.
private func chat(_ cards: [String], working: Bool = false) throws -> Thread.Page {
    let items = cards.map { #"{"type":"card","card":"# + $0 + "}" }.joined(separator: ",")
    return try JSONDecoder().decode(Thread.Page.self, from: Data(#"{"working":\#(working),"items":[\#(items)]}"#.utf8))
}

private let waitingApproval = #"{"key":"s1:approval-1","session":"s1","component":{"id":"approval-1","type":"approval","title":"Connect Qonto","waits":"owner"}}"#
private let approvedApproval = #"{"key":"s1:approval-1","session":"s1","answer":{"state":"answered","words":"Approved"},"component":{"id":"approval-1","type":"approval","title":"Connect Qonto"}}"#
private let connectedApproval = #"{"key":"s1:approval-1","session":"s1","answer":{"state":"answered","words":"Approved"},"component":{"id":"approval-1","type":"approval","title":"Connect Qonto","connection":{"done":true,"words":"Qonto is connected (read only)"}}}"#
private let waitingSignIn = #"{"key":"s1:signin-1","component":{"id":"signin-1","type":"sign_in","service":"Google Sheets","waits":"owner"}}"#
private let connectedSignIn = #"{"key":"s1:signin-1","answer":{"state":"answered","words":"Signed in"},"component":{"id":"signin-1","type":"sign_in","service":"Google Sheets","connection":{"done":true}}}"#
private let choice = #"{"key":"s1:plan-1","component":{"id":"plan-1","type":"confirm","title":"Refunds up to €100","options":[{"label":"Agree","value":"agree"}],"waits":"owner"}}"#

let connectReceiptTests: [Test] = [
    Test("a connection card shown before, read again with its connection made, shows the receipt in tafs cloud's words") {
        let receipt = ConnectReceipt.made(before: try chat([choice, waitingApproval]), after: try chat([choice, connectedApproval]))
        try expectEqual(receipt, ConnectReceipt(id: "s1:approval-1", heading: "Connect Qonto", line: "Qonto is connected (read only)"))
        // Approved on the phone first, its sign-in finishing after: the same.
        try expectEqual(ConnectReceipt.made(before: try chat([approvedApproval]), after: try chat([connectedApproval]))?.id, "s1:approval-1")
    },
    Test("a sign-in made: the app's name as the heading, and no line, so the screen says the shared Connected") {
        let receipt = ConnectReceipt.made(before: try chat([waitingSignIn]), after: try chat([connectedSignIn]))
        try expectEqual(receipt, ConnectReceipt(id: "s1:signin-1", heading: "Google Sheets", line: nil))
    },
    Test("no receipt on a first read, for a card first seen connected, for one not made, or for a card that isn't a connection") {
        try expectEqual(ConnectReceipt.made(before: nil, after: try chat([connectedApproval])), nil)
        // Connected before this Mac looked: nothing was seen to finish.
        try expectEqual(ConnectReceipt.made(before: try chat([connectedApproval]), after: try chat([connectedApproval])), nil)
        try expectEqual(ConnectReceipt.made(before: try chat([choice]), after: try chat([choice, connectedApproval])), nil)
        // Not made yet, or answered without its connection made.
        try expectEqual(ConnectReceipt.made(before: try chat([waitingApproval]), after: try chat([waitingApproval])), nil)
        try expectEqual(ConnectReceipt.made(before: try chat([waitingApproval]), after: try chat([approvedApproval])), nil)
        // A choice carrying a connection mark is not a connection card.
        let marked = #"{"key":"s1:plan-1","component":{"id":"plan-1","type":"confirm","connection":{"done":true,"words":"x"}}}"#
        try expectEqual(ConnectReceipt.made(before: try chat([choice]), after: try chat([marked])), nil)
        // An empty chat (a new conversation) read before: nothing to compare.
        try expectEqual(ConnectReceipt.made(before: .empty, after: try chat([connectedApproval])), nil)
    },
    Test("two connections made between two reads: the receipt is the newest's") {
        let receipt = ConnectReceipt.made(before: try chat([waitingSignIn, waitingApproval]), after: try chat([connectedSignIn, connectedApproval]))
        try expectEqual(receipt?.id, "s1:approval-1")
    },
    Test("the receipt draws board 5, an app connected") {
        try expectEqual(ConnectReceipt.board, .appConnected)
        try expectEqual(ConnectReceipt.board.rawValue, 5)
    },
    Test("Coach is read again while a connection waits for the person, or its run works on it; never once it's made") {
        try expectEqual(ConnectReceipt.watches(try chat([waitingApproval])), true)
        try expectEqual(ConnectReceipt.watches(try chat([waitingSignIn])), true)
        // Approved on the phone, its sign-in under way while the run works.
        try expectEqual(ConnectReceipt.watches(try chat([approvedApproval], working: true)), true)
        try expectEqual(ConnectReceipt.watches(try chat([approvedApproval], working: false)), false)
        try expectEqual(ConnectReceipt.watches(try chat([connectedApproval], working: true)), false)
        try expectEqual(ConnectReceipt.watches(try chat([choice], working: true)), false)
        try expectEqual(ConnectReceipt.watches(.empty), false)
    },
    Test("the card's connection mark is read with words or without, and only when done") {
        let page = try chat([connectedApproval, connectedSignIn, waitingApproval])
        let cards = page.items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }
        try expectEqual(cards.map(\.connected), [true, true, false])
        try expectEqual(cards.map(\.connectionWords), ["Qonto is connected (read only)", nil, nil])
        let notDone = #"{"key":"k","component":{"id":"a","type":"approval","connection":{"done":false,"words":"Qonto is connected"}}}"#
        let card = try chat([notDone]).items.compactMap { item -> Thread.Card? in if case .card(let card, _) = item { return card } else { return nil } }[0]
        try expectEqual(card.connected, false)
        try expectEqual(card.connectionWords, nil)
    },
    Test("the receipt's words are shared keys, in each of the 8 languages: nothing is worded here") {
        let folder = URL(fileURLWithPath: ".shared/app/strings")
        let languages = try Words.shipped(folder: folder)
        try expectEqual(Set(languages), ["en", "de", "es", "fr", "it", "nl", "pl", "pt"])
        for language in languages {
            let words = try Words(language: language, folder: folder)
            for key in ["connect.status.connected", "common.done"] {
                try expect(words(key) != key && !words(key).isEmpty, "\(key) in \(language)")
            }
        }
    },
]
