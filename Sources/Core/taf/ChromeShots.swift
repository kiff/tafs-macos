import Foundation

/// The page as a paired Chrome showed it just before a taf's step acted, kept for 30 days (kiff/tafs's Chrome contract,
/// "Screenshots of a run's acts"), as the iPad's `ChromeShotView`, `PlanqueClient.chromeShots(op:)` and
/// `chromeScreenshot(step:)`. A Record line's receipt lists the pictures kept for its operation (KIFF's `proposal_id`), and
/// each opens its step's. Both are planque's safe reads, signed by this Mac's device key for that one request
/// (`PlanqueClient.Safe.chromeShots`, `.chromeShot`), never with a session token; planque keeps none while its switch is off.
///
/// A picture is shown only if it checks out: base64url as planque writes it, WebP, at most 120 KB, its SHA-256 the one
/// planque kept, the step asked for, and a time it was taken. Anything else is no picture, never shown.
enum ChromeShots {
    /// The most a picture may weigh: planque keeps none over 120 KB.
    static let largest = 120 * 1024
    /// The longest side a picture is decoded to on this Mac: a 120 KB WebP can still declare a very large canvas.
    static let decodedSide = 2048

    /// One picture kept for an operation's Chrome step: the step it came before and when it was taken. No bytes.
    struct Ref: Equatable, Identifiable {
        let step: String
        let takenAt: Date
        var id: String { step }
    }

    /// A step's picture, checked: the step, when it was taken, and its WebP bytes as kept.
    struct Shot: Equatable {
        let step: String
        let takenAt: Date
        let image: Data
    }

    /// What reading a step's picture came to.
    enum Read: Equatable {
        case shown(Shot)
        /// planque keeps none for this step (404): past its 30 days, never kept, or its switch is off.
        case none
        /// Any other answer, or a picture that didn't check out.
        case failed
    }

    /// The operation as it goes into the signed query: its `&`, `=`, `+` and `#` escaped, so it can't add a parameter.
    static func queryEscaped(_ operation: String) -> String {
        operation.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? operation
    }

    /// planque's list for an operation (`{"shots":[{"step","taken_at","sha256"}]}`, oldest first): an entry without a step
    /// or a readable time is left out, and the order is kept. None when it isn't that shape.
    static func readList(_ data: Data) -> [Ref]? {
        struct Raw: Decodable { let step: String?; let taken_at: String? }
        struct List: Decodable { let shots: [Raw] }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
        return list.shots.compactMap { shot in
            guard let step = shot.step?.trimmingCharacters(in: .whitespaces), !step.isEmpty,
                  let at = shot.taken_at.flatMap(time) else { return nil }
            return Ref(step: step, takenAt: at)
        }
    }

    /// planque's answer for `step`, or nil when it isn't a picture to show: not the shape, not the step asked for (a misrouted
    /// answer is never shown under another step), not base64url without padding, too big, not WebP, bytes whose SHA-256 isn't
    /// the one planque kept, or no time it was taken.
    static func read(_ data: Data, step asked: String, sha256: (Data) -> Data) -> Shot? {
        struct Raw: Decodable { let step: String; let taken_at: String; let sha256: String; let image: String }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), raw.step == asked,
              !raw.image.isEmpty, raw.image.unicodeScalars.allSatisfy(isBase64URL),
              let bytes = Encoding.fromBase64URL(raw.image), bytes.count >= 12, bytes.count <= largest,
              bytes.prefix(4) == Data("RIFF".utf8), bytes.subdata(in: 8..<12) == Data("WEBP".utf8),
              Encoding.hex(sha256(bytes)) == raw.sha256.lowercased(),
              let at = time(raw.taken_at) else { return nil }
        return Shot(step: raw.step, takenAt: at, image: bytes)
    }

    /// What a step's read came to, by planque's status and answer: a 404 is none kept; anything else that isn't a checked
    /// picture failed.
    static func read(status: Int, _ data: Data, step: String, sha256: (Data) -> Data) -> Read {
        if status == 404 { return .none }
        guard (200..<300).contains(status), let shot = read(data, step: step, sha256: sha256) else { return .failed }
        return .shown(shot)
    }

    private static func isBase64URL(_ c: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(c) || ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "-" || c == "_"
    }

    /// An RFC 3339 time, with or without fractions of a second.
    static func time(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

extension PlanqueClient {
    /// The pictures kept for the Chrome steps of one operation, oldest first: `[]` when none are kept or planque keeps none
    /// (404). A list that doesn't read is an error.
    func chromeShots(operation: String, signedBy sign: (String) throws -> String) async throws -> [ChromeShots.Ref] {
        do {
            let data = try await safe(.chromeShots(operation: operation), signedBy: sign)
            guard let shots = ChromeShots.readList(data) else { throw KIFFError.unreadable }
            return shots
        } catch PlanqueError.server(let status, _, _) where status == 404 {
            return []
        }
    }

    /// One step's picture, checked (`ChromeShots.read`): none kept on a 404, failed on anything else that isn't a picture.
    func chromeShot(step: String, signedBy sign: (String) throws -> String, sha256: (Data) -> Data) async -> ChromeShots.Read {
        do {
            let data = try await safe(.chromeShot(step: step), signedBy: sign)
            return ChromeShots.read(status: 200, data, step: step, sha256: sha256)
        } catch PlanqueError.server(let status, _, _) where status == 404 {
            return .none
        } catch {
            return .failed
        }
    }
}
