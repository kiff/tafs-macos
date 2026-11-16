import Foundation

/// The owner's confirmation (Touch ID or the Mac's password) as Core sees it, which can't read
/// the system's own errors: the app turns a prompt the person closed into `Closed`, so Core can
/// say so where it stops.
enum OwnerPrompt {
    /// The person closed the prompt: nothing was sent and nothing changed.
    struct Closed: Error, Equatable {}

    /// The words for a stop at the owner's confirmation, where nothing is pending afterwards:
    /// "Cancelled. Nothing changed." when the prompt was closed, else "Not sent: it wasn't
    /// confirmed." (`approval.cancelled`, `common.not_sent_unconfirmed`).
    static func stopped(_ error: Error, words: Words) -> String {
        error is Closed ? words("approval.cancelled") : words("common.not_sent_unconfirmed")
    }
}
