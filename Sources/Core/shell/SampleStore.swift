import Foundation

/// The sample kept between launches, as the iPad's `SampleStore`: one local file of what changed in it (the rounds
/// played, what was said in each taf's chat, the tafs paused), read when the app opens with no one signed in, and
/// removed by Clear the sample or a sign-in. Everything else in the sample is built again from its scripts.
struct SampleStore {
    /// What changed in the sample, as kept.
    struct Saved: Codable, Equatable {
        var rounds: Int
        var said: [String: [Said]]
        var paused: [String]

        struct Said: Codable, Equatable {
            let text: String
            let reply: String
            let at: Date
        }
    }

    let url: URL

    /// The app's own folder in Application Support (`tafs/sample.json`).
    static var standard: SampleStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("tafs", isDirectory: true)
        return SampleStore(url: folder.appendingPathComponent("sample.json"))
    }

    /// What was kept; nil with none, or one that doesn't read (then it's as new).
    func load() -> Saved? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Saved.self, from: data)
    }

    func save(_ saved: Saved) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(saved) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
