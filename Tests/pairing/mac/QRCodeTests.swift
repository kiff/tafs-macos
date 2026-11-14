import AppKit
import Foundation

let pairingQRTests: [Test] = [
    Test("the screenshots: welcome, the browser's code and the pairing code, in three languages", awaiting: { @MainActor in
        try signInScreenshots()
    }),
    Test("the QR code reads back as the pairing's exact text") {
        let payload = PairingPayload(pub: String(repeating: "A", count: 122), approvalPub: String(repeating: "B", count: 122),
                                     name: "tafs on this Mac", kind: .enclave, nonce: String(repeating: "n", count: 43), exp: "2026-11-14T18:05:00Z")
        let text = try payload.text()
        guard let image = QRCode.image(text, side: 220) else { throw Failure(description: "no code") }
        try expectEqual(image.size, CGSize(width: 220, height: 220))
        try expectEqual(QRCode.read(image), text)
    },
    Test("two texts give two codes, and a blank image holds none") {
        guard let a = QRCode.image("a", side: 100)?.tiffRepresentation, let b = QRCode.image("b", side: 100)?.tiffRepresentation else {
            throw Failure(description: "no code")
        }
        try expect(a != b, "two codes")
        try expectEqual(QRCode.read(NSImage(size: CGSize(width: 50, height: 50), flipped: false) { NSColor.white.setFill(); $0.fill(); return true }), nil)
    },
]

/// The sign-in screens, drawn for the pull request: English, French and Portuguese.
@MainActor
func signInScreenshots() throws {
    let strings = URL(fileURLWithPath: ".shared/app/strings")
    Mascot.file = URL(fileURLWithPath: ".shared/ios/Shared/Mascot.xcassets/Mascot.imageset/mascot.png")
    let folder = URL(fileURLWithPath: "build/screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let start = DeviceStart(deviceCode: "dc", userCode: "ABCD-EFGH", verificationURI: "", verificationURIComplete: "", expiresIn: 600, interval: 5)
    let payload = PairingPayload(pub: String(repeating: "A", count: 122), approvalPub: nil, name: "tafs", kind: .passkey,
                                 nonce: String(repeating: "n", count: 43), exp: "2026-11-14T18:05:00Z")
    let steps: [(String, SignInModel.Step)] = [("welcome", .welcome), ("browser", .browser(start)),
                                               ("pairing", .pairing(.init(text: try payload.text(), check: "K7Q2MX")))]
    for language in ["en", "fr", "pt"] {
        for (name, step) in steps {
            let store = MemoryStore()
            let model = SignInModel(client: KIFFClient(transport: CannedTransport([])), key: try DeviceKey.load(from: store, enclave: false),
                                    approval: .passkey, sessions: SessionStore(store: store), deviceName: "A Mac", open: { _ in })
            model.show(step)
            let view = SignInView(model: model).environment(\.words, Words.load(folder: strings, preferred: [language]))
            guard let bitmap = Snapshot.bitmap(of: view, size: CGSize(width: 1280, height: 800)), let png = Snapshot.png(bitmap) else {
                throw Failure(description: "no PNG for \(name) in \(language)")
            }
            try png.write(to: folder.appendingPathComponent("sign-in-\(name)-\(language).png"))
        }
    }
}
