import Foundation

/// The account's labels on the tafs list (kiff/tafs `docs/labels.md`), as the iPad's
/// `TafsCloud.Brief.Label` (TafsCloud+Brief.swift:176-201): a name in the person's language, its
/// colour token, how many listed tafs carry it, how many of those wait for the person (the amber
/// dot), and Home's first line filtered to it. The apps only filter by them; they never change one.
struct HomeLabel: Decodable, Equatable, Identifiable {
    var id = "", name = "", color = ""
    var count = 0, waiting = 0
    var headline: String?

    enum CodingKeys: String, CodingKey { case id, name, color, count, waiting, headline }
    private enum HeadlineKeys: String, CodingKey { case words }

    init(id: String = "", name: String = "", color: String = "", count: Int = 0, waiting: Int = 0, headline: String? = nil) {
        self.id = id; self.name = name; self.color = color; self.count = count; self.waiting = waiting; self.headline = headline
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = HomeLabels.text(c, .id) ?? ""; name = HomeLabels.text(c, .name) ?? ""; color = HomeLabels.text(c, .color) ?? ""
        count = ((try? c.decodeIfPresent(Int.self, forKey: .count)) ?? nil) ?? 0
        // A count; a yes/no from an earlier draft reads as one waiting.
        waiting = ((try? c.decodeIfPresent(Int.self, forKey: .waiting)) ?? nil)
            ?? (((try? c.decodeIfPresent(Bool.self, forKey: .waiting)) ?? nil) == true ? 1 : 0)
        if let h = try? c.nestedContainer(keyedBy: HeadlineKeys.self, forKey: .headline) {
            headline = ((try? h.decodeIfPresent(String.self, forKey: .words)) ?? nil)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// One the app can draw and filter by.
    var usable: Bool { !id.isEmpty && !name.isEmpty }
}

enum HomeLabels {
    /// The account's labels in the order to show them, read one by one: one the app can't read is
    /// left out, and another shape is none, never Home unread (the iPad's `LabelList`).
    static func list<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [HomeLabel] {
        (((try? c.decodeIfPresent([Item<HomeLabel>].self, forKey: key)) ?? nil) ?? []).compactMap(\.value).filter(\.usable)
    }

    /// A taf's labels by id; another shape reads as none (the iPad's `LabelIDs`).
    static func ids<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
        (((try? c.decodeIfPresent([Item<String>].self, forKey: key)) ?? nil) ?? []).compactMap(\.value).filter { !$0.isEmpty }
    }

    /// Home's word for the first chip (`labels_words.all`); nil when it sent none.
    static func all<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        guard let w = try? c.nestedContainer(keyedBy: AllKeys.self, forKey: key) else { return nil }
        return text(w, .all)
    }
    private enum AllKeys: String, CodingKey { case all }

    /// A taf's labels, in the account's order, as the iPad's `labels(of:)` (AppModel.swift, #1173).
    static func of(_ taf: Home.Taf, in labels: [HomeLabel]) -> [HomeLabel] {
        guard !taf.labels.isEmpty else { return [] }
        return labels.filter { taf.labels.contains($0.id) }
    }

    /// The tafs under a chip: all, or those carrying it. The order never changes, and a label
    /// that's gone shows them all (the iPad's `filtered`).
    static func filtered(_ tafs: [Home.Taf], by label: String?, in labels: [HomeLabel]) -> [Home.Taf] {
        guard let label, labels.contains(where: { $0.id == label }) else { return tafs }
        return tafs.filter { $0.labels.contains(label) }
    }

    /// A line of text, trimmed; none when absent, blank or of another shape.
    static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        guard let s = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// One item of a list, or nothing, as the iPad's `LenientItem`.
    private struct Item<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}
