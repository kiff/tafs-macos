import Foundation

private let strings = URL(fileURLWithPath: ".shared/app/strings")

/// The sidebar's foot: what a list read couldn't do (`Unreachable`, the iPad's `unreachable` and `UnreachableLine`).
let unreachableTests: [Test] = [
    Test("a network failure says KIFF can't be reached; an answer that was an error says it couldn't load") {
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost, .secureConnectionFailed] {
            try expectEqual(Unreachable.wordsKey(URLError(code)), "home.cant_reach_kiff")
        }
        try expectEqual(Unreachable.wordsKey(URLError(.badServerResponse)), "home.couldnt_load_from_kiff")
        try expectEqual(Unreachable.wordsKey(KIFFError.refused(status: 503, code: "unavailable")), "home.couldnt_load_from_kiff")
        try expectEqual(Unreachable.wordsKey(KIFFError.unreadable), "home.couldnt_load_from_kiff")
    },
    Test("the app tries again after 2, 10, 30, 60 and 120 seconds, then waits for the next read") {
        try expectEqual((0..<6).map { Unreachable.wait(after: $0) }, [2, 10, 30, 60, 120, nil])
    },
    Test("while it tries, the line says so, in the person's language; then the words alone") {
        let words = try Words(language: "en", folder: strings)
        try expectEqual(Unreachable.line("Can't reach KIFF", retrying: true, words), "Can't reach KIFF · trying again")
        try expectEqual(Unreachable.line("Can't reach KIFF", retrying: false, words), "Can't reach KIFF")
        try expectEqual(Unreachable.statusPage.absoluteString, "https://status.kiff.dev")
    },
]
