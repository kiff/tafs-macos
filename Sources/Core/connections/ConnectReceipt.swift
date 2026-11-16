import Foundation

/// The receipt of an app connected, as the iPad's (kiff/tafs `ios/Tafs/Views/ConnectAppsView.swift`,
/// `ConnectApprovalSheet.receipt`, `:952-981`): board 5, the app's heading, a green check with tafs
/// cloud's line for the connection, and Done (docs/connections.md › The receipt).
///
/// On this Mac an app is connected through Coach, and its approval and sign-in are made on the
/// phone: the Mac sees the sign-in finish when Coach's chat, read again, marks a connection card
/// it showed before as made (`connection.done`, `Thread.Card.connected`). That is when the
/// receipt shows. Its words are all tafs cloud's, from that card; with none, the shared
/// "Connected" (`connect.status.connected`), the iPad's own fallback.
struct ConnectReceipt: Equatable, Identifiable {
    /// The card it is the receipt of, by its key in the thread.
    let id: String
    /// tafs cloud's title for the card, else the app's name as the card names it (a sign-in's
    /// `service`), else the card's own words; nil only when the card has none of them, and then
    /// the screen's heading is its line (`title(_:)`), so it's never empty.
    let heading: String?
    /// tafs cloud's line for the connection ("Qonto is connected (read only)"); nil draws the
    /// shared "Connected".
    let line: String?

    /// The drawing on it: board 5, an app connected, as the iPad's receipt (docs/window.md ›
    /// Illustrations).
    static let board = ArtBoard.appConnected

    init(id: String, heading: String?, line: String?) {
        self.id = id
        self.heading = heading
        self.line = line
    }

    init(_ card: Thread.Card) {
        self.init(id: card.key, heading: Self.named(card.title) ?? Self.named(card.service) ?? Self.named(card.text),
                  line: card.connectionWords)
    }

    /// The receipt's heading as drawn: the card's heading, else its line, else the shared
    /// "Connected". Never empty, so the person always sees what was connected, or at least that
    /// it was.
    func title(_ words: Words) -> String {
        heading ?? line ?? words("connect.status.connected")
    }

    /// Whether the green check's line shows under the heading: not when the heading already is
    /// that line, so it's never said twice.
    var showsLine: Bool { heading != nil }

    private static func named(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The receipt to show for the chat read again: the newest connection card that `before`
    /// had without its connection made and `after` marks made. None on a first read (`before`
    /// nil), for a card first seen already connected (connected before this Mac looked), or for
    /// one whose connection isn't made. `before` and `after` are the same chat, read twice.
    static func made(before: Thread.Page?, after: Thread.Page) -> ConnectReceipt? {
        guard let before else { return nil }
        let unconnected = Set(cards(before).filter { $0.grants && !$0.connected }.map(\.key))
        return cards(after).last { $0.grants && $0.connected && unconnected.contains($0.key) }.map(ConnectReceipt.init)
    }

    /// Whether Coach's chat waits on a connection, so it is read again while Coach is on screen
    /// (`CoachModel.watchConnection`): a connection card not made yet, that waits for the person
    /// or whose run is still at work (approved on the phone, its sign-in under way).
    static func watches(_ page: Thread.Page) -> Bool {
        cards(page).contains { $0.grants && !$0.connected && ($0.waitsForPerson || page.working) }
    }

    private static func cards(_ page: Thread.Page) -> [Thread.Card] {
        page.items.compactMap { item in
            if case .card(let card, _) = item { return card }
            return nil
        }
    }
}
