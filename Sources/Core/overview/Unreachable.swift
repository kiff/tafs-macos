import Foundation

/// What a list read couldn't do, said quietly at the sidebar's foot, never as an alert, as the iPad's `unreachable`
/// (AppModel.swift:2515-2550, the 930 test): "Can't reach KIFF" when the network failed, "Couldn't load from KIFF" when
/// an answer was an error. The app reads again by itself, a moment later, then less often, then waits for the person.
enum Unreachable {
    /// The waits between the app's own tries, in seconds: then no more until the person reads again.
    static let retryWaits: [UInt64] = [2, 10, 30, 60, 120]

    /// The network's failures, which say "Can't reach KIFF"; every other failure is an answer that was an error.
    static let network: Set<URLError.Code> = [.networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost,
                                              .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                                              .secureConnectionFailed]

    /// The words key true to what failed, as the iPad's `refreshWords`.
    static func wordsKey(_ error: Error) -> String {
        if let e = error as? URLError, network.contains(e.code) { return "home.cant_reach_kiff" }
        return "home.couldnt_load_from_kiff"
    }

    /// The wait before the app's try number `tries` (0 first), or nil once it has tried them all.
    static func wait(after tries: Int) -> UInt64? { tries < retryWaits.count ? retryWaits[tries] : nil }

    /// The line itself: while the app still tries, "{words} · trying again", as the iPad's `UnreachableLine`.
    static func line(_ words: String, retrying: Bool, _ book: Words) -> String {
        retrying ? book("home.status_retrying", ["words": words]) : words
    }

    /// KIFF's status page, beside the line.
    static let statusPage = URL(string: "https://status.kiff.dev")!
}
