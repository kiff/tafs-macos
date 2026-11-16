import Foundation

/// The approved first-time and empty-state drawings, one per board, as the iPad's
/// (kiff/tafs `ios/Tafs/Design/Illustrations.swift`, docs/window.md › Illustrations), and which a
/// screen draws in which state. The drawings themselves are the app's (`Illustration`); here is
/// only when each shows, so it's tested on any machine. Boards 11 and 12 are the watches'.
enum ArtBoard: Int, CaseIterable {
    case firstRun = 1, noTafs, briefClear, allHalted, appConnected, nothingWaiting, coachFirst, newTaf, coachStarting, overview

    /// Boards whose screen this Mac doesn't have yet: an app connected is drawn on connecting's
    /// receipt (the iPad's `ConnectApprovalSheet`), and this Mac doesn't connect an app yet.
    static let notOnThisMac: Set<ArtBoard> = [.appConnected]

    /// The Overview's board, as the iPad's Home with no taf and its Overview's header: no taf
    /// yet (board 2) where the list was read empty and tafs cloud lists no job, above the empty
    /// line; else the Overview's own (board 10) under its title. One drawing a screen, never both.
    /// `tafs` is nil until the list is read.
    static func overview(tafs: Int?, listsRecipes: Bool) -> ArtBoard {
        tafs == 0 && !listsRecipes ? .noTafs : .overview
    }

    /// Your brief with no decision left to answer here: a calm sun where the decisions go.
    static func brief(openDecisions: Int) -> ArtBoard? {
        openDecisions == 0 ? .briefClear : nil
    }

    /// Halt all, once every taf reads halted; never one taf's halt, and never while halting.
    static func halt(all: Bool, state: Halt.State) -> ArtBoard? {
        all && state == .halted ? .allHalted : nil
    }

    /// Coach's empty chat, as the iPad's `SetupChatView`: before Coach is started on the account,
    /// its start (board 9, the iPad's and the Mac's width); once started, with no taf or one, its
    /// spark beside one card (board 7). A new conversation on a taf draws none.
    static func coach(started: Bool, improving: Bool, tafs: Int) -> ArtBoard? {
        if improving { return nil }
        if !started { return .coachStarting }
        return tafs <= 1 ? .coachFirst : nil
    }
}
