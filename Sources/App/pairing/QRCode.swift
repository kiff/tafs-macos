import AppKit
import CoreImage

/// A QR code of a text, as the pairing contract asks: bytes, error correction M.
enum QRCode {
    /// The code as sharp black squares on white, `side` points wide, with its quiet margin.
    static func image(_ text: String, side: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let small = filter.outputImage, small.extent.width > 0 else { return nil }
        // Whole pixels for each square, twice over for a Retina screen.
        let scale = max(1, (side * 2 / small.extent.width).rounded(.down))
        let large = small.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(large, from: large.extent) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: side, height: side))
    }

    /// The text of the QR code in an image, if it holds one: what a phone's camera would read.
    static func read(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString
    }
}
