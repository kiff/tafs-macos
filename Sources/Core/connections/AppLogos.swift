import Foundation

/// The apps' logos, read from tafs cloud only, as the iPad loads them (`TafsCloud.logoURL`,
/// `TafsCloud.swift:2277-2287`): `/v1/logos/` and the 32 lowercase hex of the key tafs cloud mints
/// (`Apps.logoPath`). Any other address is dropped and nothing is asked for it.
///
/// tafs cloud's route (`runtime/src/cloud/handler.ts:653-654`, `:10443-10456`) takes no session,
/// "as image loaders send none", and answers a PNG it drew itself (`image/png`; an SVG source is
/// drawn to a PNG on tafs cloud, `logos.ts:149-165`), or a 404 for a key it doesn't keep. So none
/// is sent here either: no bearer, nothing but what asks for the image.
///
/// Each logo is asked once and kept in memory for the session, by its path; a logo being asked
/// isn't asked again meanwhile. A refusal or bytes that aren't a PNG or a JPEG keep nothing, and
/// the app's name stands alone.
final class AppLogos: @unchecked Sendable {
    /// What carries the read to tafs cloud: its own address, and no other.
    let transport: Transport
    private let lock = NSLock()
    private var kept: [String: Data] = [:]
    private var asking: [String: Task<Data?, Never>] = [:]

    init(transport: Transport) { self.transport = transport }

    /// What a logo's read sends: what it asks for, and who asks. Never the session.
    static let headers = ["Accept": "image/png, image/jpeg", "User-Agent": "tafs-macos"]
    /// The most a logo may weigh: tafs cloud's are a few KB, 96 pixels a side.
    static let largest = 512 * 1024

    /// The path a logo is read from, only as tafs cloud keeps it, else nil.
    static func path(_ logo: String?) -> String? { logo.flatMap(Apps.logoPath) }

    /// Whether bytes are an image the app draws: a PNG or a JPEG, by their first bytes.
    static func drawable(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= largest else { return false }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        let head = [UInt8](data.prefix(8))
        return head.starts(with: png) || head.starts(with: jpeg)
    }

    /// A logo already read, for the first frame.
    func cached(_ logo: String?) -> Data? {
        guard let path = Self.path(logo) else { return nil }
        lock.lock()
        let data = kept[path]
        lock.unlock()
        return data
    }

    /// The logo at `logo`, read once: nil for an address that isn't tafs cloud's own, a refusal,
    /// or bytes that aren't an image.
    func load(_ logo: String?) async -> Data? {
        guard let path = Self.path(logo) else { return nil }
        let task: Task<Data?, Never>
        lock.lock()
        if let data = kept[path] {
            lock.unlock()
            return data
        }
        if let waiting = asking[path] {
            task = waiting
        } else {
            let transport = transport
            task = Task {
                guard let (status, body) = try? await transport.send(HTTPRequest(method: "GET", path: path, headers: AppLogos.headers)),
                      (200..<300).contains(status), AppLogos.drawable(body) else { return nil }
                return body
            }
            asking[path] = task
        }
        lock.unlock()
        let data = await task.value
        lock.lock()
        asking[path] = nil
        if let data { kept[path] = data }
        lock.unlock()
        return data
    }
}
