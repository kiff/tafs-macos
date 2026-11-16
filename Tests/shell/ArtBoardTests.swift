import Foundation

/// The app's source, read as text.
private func source(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: "Sources/App/" + path), encoding: .utf8)
}

/// Each board on this Mac, the screen's file that draws it, and how.
private let drawn: [(board: ArtBoard, file: String)] = [
    (.firstRun, "pairing/SignInView.swift"),
    (.noTafs, "overview/OverviewView.swift"),
    (.briefClear, "brief/BriefView.swift"),
    (.allHalted, "taf/HaltView.swift"),
    (.nothingWaiting, "approvals/NeedsYou.swift"),
    (.coachFirst, "coach/CoachView.swift"),
    (.newTaf, "overview/RecipeGalleryView.swift"),
    (.coachStarting, "coach/CoachView.swift"),
    (.overview, "overview/OverviewView.swift"),
]

/// A board's name in `Illustration`, as the iPad's.
private func name(_ board: ArtBoard) -> String {
    switch board {
    case .firstRun: return "firstRun"
    case .noTafs: return "noTafs"
    case .briefClear: return "briefClear"
    case .allHalted: return "allHalted"
    case .appConnected: return "appConnected"
    case .nothingWaiting: return "nothingWaiting"
    case .coachFirst: return "coachFirst"
    case .newTaf: return "newTaf"
    case .coachStarting: return "coachStarting"
    case .overview: return "overview"
    }
}

let shellArtBoardTests: [Test] = [
    Test("the Overview draws no taf yet only once its list is read empty and no job is listed, else its own, never both") {
        try expectEqual(ArtBoard.overview(tafs: 0, listsRecipes: false), .noTafs)
        try expectEqual(ArtBoard.overview(tafs: 0, listsRecipes: true), .overview)
        try expectEqual(ArtBoard.overview(tafs: 3, listsRecipes: false), .overview)
        // Not read yet, or not readable: nobody is told there's no taf.
        try expectEqual(ArtBoard.overview(tafs: nil, listsRecipes: false), .overview)
    },
    Test("the brief draws its calm sun only with no decision left to answer") {
        try expectEqual(ArtBoard.brief(openDecisions: 0), .briefClear)
        try expectEqual(ArtBoard.brief(openDecisions: 2), nil)
    },
    Test("Halt all draws every taf halted once it holds; never one taf's halt, never while running or halting") {
        try expectEqual(ArtBoard.halt(all: true, state: .halted), .allHalted)
        try expectEqual(ArtBoard.halt(all: true, state: .halting), nil)
        try expectEqual(ArtBoard.halt(all: true, state: .running), nil)
        try expectEqual(ArtBoard.halt(all: false, state: .halted), nil)
    },
    Test("Coach's empty chat: its start before Coach is started, one card with no taf or one, none with more or on a taf") {
        try expectEqual(ArtBoard.coach(started: false, improving: false, tafs: 0), .coachStarting)
        try expectEqual(ArtBoard.coach(started: false, improving: false, tafs: 4), .coachStarting)
        try expectEqual(ArtBoard.coach(started: true, improving: false, tafs: 0), .coachFirst)
        try expectEqual(ArtBoard.coach(started: true, improving: false, tafs: 1), .coachFirst)
        try expectEqual(ArtBoard.coach(started: true, improving: false, tafs: 2), nil)
        try expectEqual(ArtBoard.coach(started: true, improving: true, tafs: 0), nil)
    },
    Test("ten boards, the iPad's, and only an app connected waits for its screen on this Mac") {
        try expectEqual(ArtBoard.allCases.map(\.rawValue), Array(1...10))
        try expectEqual(ArtBoard.notOnThisMac, [.appConnected])
        try expectEqual(Set(drawn.map(\.board)).union(ArtBoard.notOnThisMac), Set(ArtBoard.allCases))
    },
    Test("rule 14: the drawings are shapes in the theme's colours, never a word, a number, an image or a symbol") {
        let file = try source("base/Illustrations.swift")
        try expect(!file.contains("Text("), "a drawing has no text")
        try expect(!file.contains("\""), "a drawing has no string literal, not even a symbol's name")
        try expect(!file.contains("Image("), "a drawing is shapes, never an image or a symbol")
        try expect(!file.contains("Color(") && !file.contains("Shade("), "a drawing's colours are the theme's, for light and dark")
        try expect(file.contains("Theme.brand"), "the mark is the brand's sweep, as the sign-in's")
        try expect(file.contains(".accessibilityHidden(true)"), "hidden from VoiceOver")
        try expect(file.contains(".frame(maxWidth: shown)"), "scaled to a width, never a fixed screen size")
        try expectEqual(file.components(separatedBy: "Board(width:").count - 1, 10)
        for board in ArtBoard.allCases {
            try expect(file.contains("/// Board \(board.rawValue), "), "board \(board.rawValue)'s doc comment")
            try expect(file.contains("static var \(name(board)): some View {"), name(board))
        }
        // No image file anywhere in the app: every drawing is code.
        let images = FileManager.default.enumerator(atPath: "Sources")?.compactMap { $0 as? String }
            .filter { path in [".png", ".jpg", ".jpeg", ".pdf", ".svg"].contains { path.lowercased().hasSuffix($0) } } ?? []
        try expectEqual(images, [])
    },
    Test("each screen draws its board where its state says, and the sign-in's KIFF half the first run") {
        for (board, file) in drawn {
            try expect(try source(file).contains("Illustration.\(name(board))"), "\(file) draws board \(board.rawValue)")
        }
        try expect(try source("overview/OverviewView.swift").contains("ArtBoard.overview(tafs:"), "the Overview asks which")
        try expect(try source("brief/BriefView.swift").contains("ArtBoard.brief(openDecisions:"), "the brief asks")
        try expect(try source("taf/HaltView.swift").contains("ArtBoard.halt(all: model.taf == nil"), "Halt all asks")
        try expect(try source("coach/CoachView.swift").contains("ArtBoard.coach(started: model.state != .notStarted"), "Coach asks")
        let signIn = try source("pairing/SignInView.swift")
        try expect(!signIn.contains("SignInArt.kiff"), "the KIFF half's placeholder is gone")
        try expect(!(try source("pairing/SignInArt.swift")).contains("static func kiff"), "and its drawing")
    },
]
