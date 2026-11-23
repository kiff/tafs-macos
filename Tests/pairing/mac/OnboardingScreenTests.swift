import AppKit
import Foundation
import SwiftUI

// The new onboarding's screens, drawn in the languages a pull request shows (en, fr, the two right-to-left ones and
// Japanese), light and dark: the welcome with its tick, the three cards, and How tafs works.

private let strings = URL(fileURLWithPath: ".shared/app/strings")

@MainActor
private func welcomeModel() -> SignInModel {
    let model = SignInModel(client: KIFFClient(transport: CannedTransport([])), key: SoftwareKey(key: .init()), approval: .passkey,
                            sessions: SessionStore(store: MemoryStore()), deviceName: "tafs on this Mac", sleep: { _ in }, open: { _ in },
                            enclave: false, onboarding: true)
    // A still picture: the phone's code isn't started by itself.
    model.show(.welcome)
    return model
}

@MainActor
private func shoot<V: View>(_ view: V, _ name: String, size: CGSize, dark: Bool) throws -> NSBitmapImageRep {
    guard let bitmap = Snapshot.settled(of: view, size: size, dark: dark, until: { _ in true }), let png = Snapshot.png(bitmap) else {
        throw Failure(description: "no PNG for \(name)")
    }
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("\(name)\(dark ? "-dark" : "").png"))
    return bitmap
}

let pairingOnboardingScreenTests: [Test] = [
    Test("the screenshots: the welcome with its tick, the three cards and How tafs works, in en, fr, ar, he and ja, light and dark",
         awaiting: { @MainActor in
        for language in ["en", "fr", "ar", "he", "ja"] {
            let words = try Words(language: language, folder: strings)
            for dark in [false, true] {
                let model = welcomeModel()
                let welcome = try shoot(SignInView(model: model).inLanguage(words), "onboarding-welcome-\(language)",
                                        size: CGSize(width: 1366, height: 900), dark: dark)
                try expect(welcome.pixelsWide > 0, "the welcome drawn")
                for page in OnboardingPage.allCases {
                    _ = try shoot(OnboardingCards(start: page) {}.inLanguage(words), "onboarding-card-\(page.rawValue + 1)-\(language)",
                                  size: CGSize(width: 900, height: 820), dark: dark)
                }
                _ = try shoot(HowTafsWorksView(chromeOffered: true) {}.inLanguage(words), "onboarding-how-it-works-\(language)",
                              size: CGSize(width: 640, height: 860), dark: dark)
            }
        }
    }),
    Test("the welcome's Continue is off until the box is ticked, and the phone's half waits with it", awaiting: { @MainActor in
        let model = welcomeModel()
        try expect(!model.tick.canContinue, "unticked at first")
        model.tick.toggle()
        try expect(model.tick.canContinue, "ticked")
        // The sample Card the second card draws reads from the shared words, in every language.
        for language in ["en", "ar", "ja"] {
            let words = try Words(language: language, folder: strings)
            guard let card = OnboardingPicture.sampleCard(words) else { throw Failure(description: "no sample Card in \(language)") }
            try expectEqual(card.title, words("sample.card.refunds_stripe"))
            try expectEqual(card.rules.count, 3)
        }
    }),
]
