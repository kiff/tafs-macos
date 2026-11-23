import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The picture before a Chrome step, decoded on this Mac (`ChromeShotSheet.decoded`): never larger than
/// `ChromeShots.decodedSide` on its longest side, whatever size the file declares; bytes that aren't a picture are none.
let chromeShotSheetTests: [Test] = [
    Test("a picture is decoded at most 2048 on its longest side, its shape kept; bytes that aren't one decode to none") {
        func png(width: Int, height: Int) throws -> Data {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage() else { throw Failure(description: "no picture") }
            let out = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { throw Failure(description: "no destination") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure(description: "not written") }
            return out as Data
        }
        let tall = ChromeShotSheet.decoded(try png(width: 300, height: 6000))
        // 300 × 2048 / 6000 is 102.4: ImageIO rounds it, and the longest side is the cap.
        try expectEqual(tall?.height, 2048)
        try expect((100...103).contains(tall?.width ?? 0), "the shape kept: \(tall?.width ?? 0) wide")
        let small = ChromeShotSheet.decoded(try png(width: 40, height: 20))
        try expectEqual(small.map { [$0.width, $0.height] }, [40, 20])
        try expectEqual(ChromeShotSheet.decoded(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP not really".utf8)) == nil, true)
    },
]
