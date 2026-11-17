import Foundation

/// The sidebar's Halt all, as the iPad's `showsAccountHalt` (AppModel.swift:3892-3897): for someone
/// who manages the account's Cards (KIFF's `cards.manage`), while a taf runs at tafs cloud, and
/// whenever the account is halted or halting, tafs or not, since that row is where it stands.
enum AccountHalt {
    static func shown(managesCards: Bool, tafs: [Home.Taf], halt: Halt.State) -> Bool {
        managesCards && (tafs.contains { $0.tafID != nil } || halt != .running)
    }

    /// Whether the account's halt is read with the list, as the iPad's `refresh` reads it when no
    /// taf runs (AppModel.swift:2231-2237): its row reads it for itself, and without a taf there
    /// would be no row to read it.
    static func readsWithList(managesCards: Bool, tafs: [Home.Taf]) -> Bool {
        managesCards && !tafs.contains { $0.tafID != nil }
    }
}
