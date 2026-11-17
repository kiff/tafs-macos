import Foundation

/// Answers each request with bytes, as tafs cloud sends a logo, and keeps what was sent.
private final class LogoTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [(Int, Data)]
    private var made: [HTTPRequest] = []
    init(_ answers: [(Int, Data)]) { queued = answers }

    var sent: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return made
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.lock()
        made.append(request)
        let answer = queued.isEmpty ? (500, Data()) : queued.removeFirst()
        lock.unlock()
        if answer.0 == 0 { throw URLError(.notConnectedToInternet) }
        return answer
    }
}

private let key = "0123456789abcdef0123456789abcdef"
private let path = "/v1/logos/" + key
/// The first bytes of a PNG and of a JPEG: what tafs cloud serves, and what the app draws.
private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 16])

/// Addresses that aren't tafs cloud's own logo path, as `Apps.logoPath` keeps it.
private let others: [String] = {
    var list: [String] = ["https://cdn.example.com/x.png", "", "/v1/logos/0123456789abcdef0123456789abcdeg"]
    list.append("https://cloud.tafs.kiff.dev" + path)
    list.append("/v1/logos/" + key.uppercased())
    list.append("/v1/logos/" + String(key.dropLast()))
    list.append("/v1/logos/" + key + "0")
    list.append("/v1/logos/" + key + "/x")
    list.append("/v1/logo/" + key)
    list.append(" " + path)
    return list
}()

let appLogosTests: [Test] = [
    Test("a logo is read from tafs cloud's own path, with what asks for an image and never the session", awaiting: {
        let transport = LogoTransport([(200, png)])
        let logos = AppLogos(transport: transport)
        let data = await logos.load(path)
        try expectEqual(data, png)
        try expectEqual(transport.sent.count, 1)
        try expectEqual(transport.sent[0].method, "GET")
        try expectEqual(transport.sent[0].path, path)
        try expectEqual(transport.sent[0].headers, ["Accept": "image/png, image/jpeg", "User-Agent": "tafs-macos"])
        try expect(transport.sent[0].headers["Authorization"] == nil, "no bearer: tafs cloud's route takes no session")
    }),
    Test("only /v1/logos/ and 32 lowercase hex is read: any other address is dropped, and nothing is sent", awaiting: {
        let transport = LogoTransport([])
        let logos = AppLogos(transport: transport)
        for other in others {
            let data = await logos.load(other)
            try expect(data == nil, "\(other) was read")
        }
        let none = await logos.load(nil)
        try expect(none == nil, "nil was read")
        try expectEqual(transport.sent.count, 0)
    }),
    Test("a logo is kept by its path for the session: asked once, at the same time too", awaiting: {
        let transport = LogoTransport([(200, png), (200, jpeg)])
        let logos = AppLogos(transport: transport)
        try expect(logos.cached(path) == nil, "kept before it was read")
        async let first = logos.load(path)
        async let second = logos.load(path)
        let both = await [first, second]
        try expectEqual(both, [png, png])
        let again = await logos.load(path)
        try expectEqual(again, png)
        try expectEqual(logos.cached(path), png)
        try expectEqual(transport.sent.count, 1)
        // Another logo is its own read, and a JPEG is drawn too.
        let other = "/v1/logos/ffffffffffffffffffffffffffffffff"
        let read = await logos.load(other)
        try expectEqual(read, jpeg)
        try expectEqual(transport.sent.map(\.path), [path, other])
    }),
    Test("a refused or unreadable logo keeps nothing, so the mark is the name alone, and is asked again later", awaiting: {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)
        let json = Data(#"{"error":"no logo"}"#.utf8)
        let heavy = png + Data(repeating: 0, count: AppLogos.largest)
        let transport = LogoTransport([(404, json), (200, svg), (200, json), (200, Data()), (200, heavy), (0, Data()), (200, png)])
        let logos = AppLogos(transport: transport)
        for _ in 0..<6 {
            let data = await logos.load(path)
            try expect(data == nil, "an unreadable logo was kept")
            try expect(logos.cached(path) == nil, "an unreadable logo was kept")
        }
        let read = await logos.load(path)
        try expectEqual(read, png)
        try expectEqual(transport.sent.count, 7)
    }),
    Test("a PNG or a JPEG is drawn, by its first bytes; nothing else") {
        try expect(AppLogos.drawable(png), "a PNG")
        try expect(AppLogos.drawable(jpeg), "a JPEG")
        for other in [Data(), Data("GIF89a".utf8), Data("<svg/>".utf8), Data([0x89, 0x50, 0x4E, 0x47]), Data("RIFF....WEBP".utf8)] {
            try expect(!AppLogos.drawable(other), "\(other) was drawn")
        }
    },
]
