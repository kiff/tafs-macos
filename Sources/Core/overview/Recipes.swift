import Foundation

/// The ready-made jobs tafs cloud lists for an account with no live taf (`GET /v1/recipes`),
/// ported from the iPad's `TafsCloud.Recipes`: categories, each recipe led by the problem it ends,
/// its Card in plain zones, and `say`, what handing it to Coach puts in Coach's box for the person
/// to edit and send. Every word is tafs cloud's.
struct Recipes: Decodable, Equatable {
    struct Category: Decodable, Equatable {
        let id: String
        let title: String
        /// The category's colour for light and dark, for its chip and its cards' edge; nil when
        /// either one isn't `#RRGGBB`: the app never guesses one.
        let color: Shade?

        enum Keys: String, CodingKey { case id, title, color }
        enum ColorKeys: String, CodingKey { case light, dark }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            let tint = try? c.nestedContainer(keyedBy: ColorKeys.self, forKey: .color)
            func hex(_ key: ColorKeys) -> UInt32? { ((try? tint?.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(Recipes.hex) }
            if let light = hex(.light), let dark = hex(.dark) { color = Shade(light: light, dark: dark) } else { color = nil }
        }
    }

    /// One of the apps a recipe's taf uses, as tafs cloud names it.
    struct App: Decodable, Equatable {
        let name: String
    }

    /// The Card a recipe's taf would have: what it does on its own, asks first, and never does.
    struct Card: Decodable, Equatable {
        let allows: [String]
        let holds: [String]
        let never: [String]

        enum Keys: String, CodingKey { case allows, holds, never }
        init(allows: [String] = [], holds: [String] = [], never: [String] = []) { self.allows = allows; self.holds = holds; self.never = never }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            allows = ((try? c.decodeIfPresent([String].self, forKey: .allows)) ?? nil) ?? []
            holds = ((try? c.decodeIfPresent([String].self, forKey: .holds)) ?? nil) ?? []
            never = ((try? c.decodeIfPresent([String].self, forKey: .never)) ?? nil) ?? []
        }
    }

    struct Recipe: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let category: String
        let line: String
        /// What handing it to Coach puts in Coach's box.
        let say: String
        /// The problem it ends: it leads the recipe on Home and on its sheet.
        let headline: String
        /// What that costs today.
        let today: String
        let card: Card
        let apps: [App]
        /// tafs cloud's line for a job whose proof run passed, and what it reported after it.
        let proved: String
        let sample: String

        enum Keys: String, CodingKey { case id, title, category, line, say, headline, today, card, apps, proved, sample }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            func text(_ key: Keys) -> String { (((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            category = text(.category); line = text(.line); say = text(.say); headline = text(.headline)
            today = text(.today); proved = text(.proved); sample = text(.sample)
            card = ((try? c.decodeIfPresent(Card.self, forKey: .card)) ?? nil) ?? Card()
            apps = ((try? c.decodeIfPresent([Lenient<App>].self, forKey: .apps)) ?? nil)?.compactMap(\.value) ?? []
        }

        /// What leads it: the problem it ends; its title from a tafs cloud from before headlines.
        var lead: String { headline.isEmpty ? title : headline }
    }

    /// One zone of a recipe's Card on its sheet: its title and its lines.
    struct Zone: Equatable, Identifiable {
        let id: String
        let title: String
        let lines: [String]
    }

    let categories: [Category]
    let recipes: [Recipe]
    /// Home with no taf: `shown`, the recipes are listed under `words`.
    let homeShown: Bool
    let homeWordsLine: String?
    /// "Say it in your own words", leading Home's list, with its line; nil when none came.
    let ownWords: (title: String, line: String)?
    /// The sheet's words: its three zones' titles and its button's.
    let labels: [String: String]?

    enum Keys: String, CodingKey { case categories, recipes, home, labels }
    enum HomeKeys: String, CodingKey { case shown, words, ownWords = "own_words" }
    enum OwnKeys: String, CodingKey { case title, line }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        categories = ((try? c.decodeIfPresent([Lenient<Category>].self, forKey: .categories)) ?? nil)?.compactMap(\.value) ?? []
        recipes = ((try? c.decodeIfPresent([Lenient<Recipe>].self, forKey: .recipes)) ?? nil)?.compactMap(\.value) ?? []
        let home = try? c.nestedContainer(keyedBy: HomeKeys.self, forKey: .home)
        homeShown = ((try? home?.decodeIfPresent(Bool.self, forKey: .shown)) ?? nil) ?? false
        homeWordsLine = ((try? home?.decodeIfPresent(String.self, forKey: .words)) ?? nil)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let own = try? home?.nestedContainer(keyedBy: OwnKeys.self, forKey: .ownWords)
        func ownText(_ key: OwnKeys) -> String { (((try? own?.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        // A row with no title isn't one.
        ownWords = ownText(.title).isEmpty ? nil : (ownText(.title), ownText(.line))
        labels = (try? c.decodeIfPresent([String: String].self, forKey: .labels)) ?? nil
    }

    static func == (a: Recipes, b: Recipes) -> Bool {
        a.categories == b.categories && a.recipes == b.recipes && a.homeShown == b.homeShown && a.homeWordsLine == b.homeWordsLine
            && a.ownWords?.title == b.ownWords?.title && a.ownWords?.line == b.ownWords?.line && a.labels == b.labels
    }

    /// The categories with their recipes, in tafs cloud's order; a category with none is left out.
    var byCategory: [(category: Category, recipes: [Recipe])] {
        categories.map { c in (c, recipes.filter { $0.category == c.id }) }.filter { !$0.recipes.isEmpty }
    }

    /// Whether Home with no taf lists the recipes: tafs cloud says so, and the sheet's words came.
    var listed: Bool { homeShown && labels != nil && !byCategory.isEmpty }

    /// The categories listed, narrowed to `picked` when one is: nothing picked is all of them,
    /// and a category no longer listed narrows nothing.
    func groups(picked: String?) -> [(category: Category, recipes: [Recipe])] {
        let all = byCategory
        guard let picked, all.contains(where: { $0.category.id == picked }) else { return all }
        return all.filter { $0.category.id == picked }
    }

    /// The zones a recipe's sheet draws, in order (does on its own, asks first, never does),
    /// titled by the labels: a zone its Card leaves empty isn't one.
    func zones(of recipe: Recipe) -> [Zone] {
        [Zone(id: "allows", title: labels?["allows"] ?? "", lines: recipe.card.allows),
         Zone(id: "holds", title: labels?["holds"] ?? "", lines: recipe.card.holds),
         Zone(id: "never", title: labels?["never"] ?? "", lines: recipe.card.never)]
            .filter { !$0.lines.isEmpty }
    }

    /// The words of the sheet's button that hands the recipe to Coach; nil when none came.
    var handWords: String? {
        guard let words = labels?["hand"]?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return words
    }

    /// `#RRGGBB`, and only that.
    static func hex(_ s: String) -> UInt32? {
        guard s.count == 7, s.first == "#" else { return nil }
        let digits = s.dropFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/// Reads one item of a list, or nothing: an item that doesn't read is left out, never the list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension CloudClient {
    /// The ready-made jobs for an account with no live taf, and Home's words with them.
    func recipes() async throws -> Recipes { try await get("/v1/recipes") }
}
