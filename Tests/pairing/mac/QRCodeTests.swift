import AppKit
import Foundation

let pairingQRTests: [Test] = [
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
