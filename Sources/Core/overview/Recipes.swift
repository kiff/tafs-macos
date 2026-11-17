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

    /// One of the apps a recipe's taf uses, as tafs cloud names it, with its logo, as the iPad's
    /// `Recipes.App` (`TafsCloud.swift:1943-1953`): only tafs cloud's own `/v1/logos/` path is
    /// kept (`Apps.logoPath`); anything else is none, and the name stands alone.
    struct App: Decodable, Equatable {
        let name: String
        let logo: String?

        init(name: String, logo: String? = nil) { self.name = name; self.logo = logo.flatMap(Apps.logoPath) }
        enum CodingKeys: String, CodingKey { case name, logo }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            logo = ((try? c.decodeIfPresent(String.self, forKey: .logo)) ?? nil).flatMap(Apps.logoPath)
        }
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

    /// One recipe, read as the iPad's `Recipe` (TafsCloud.swift:1892-1941): `category`, `line`
    /// and `say` fail the read when they aren't words; the rest read leniently. Nothing is
    /// trimmed but `proved` and `sample`.
    struct Recipe: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let category: String
        let line: String
        /// What handing it to Coach puts in Coach's box, as sent.
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
            category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
            line = try c.decodeIfPresent(String.self, forKey: .line) ?? ""
            say = try c.decodeIfPresent(String.self, forKey: .say) ?? ""
            headline = ((try? c.decodeIfPresent(String.self, forKey: .headline)) ?? nil) ?? ""
            today = ((try? c.decodeIfPresent(String.self, forKey: .today)) ?? nil) ?? ""
            card = ((try? c.decodeIfPresent(Card.self, forKey: .card)) ?? nil) ?? Card()
            apps = ((try? c.decodeIfPresent([Lenient<App>].self, forKey: .apps)) ?? nil)?.compactMap(\.value) ?? []
            // Anything but words (a flag, a list) is no line: the sheet draws only what reads.
            proved = (((try? c.decodeIfPresent(String.self, forKey: .proved)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            sample = (((try? c.decodeIfPresent(String.self, forKey: .sample)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// What leads it: the problem it ends, as sent; else its title.
        var lead: String { headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : headline }
    }

    /// Home with no taf, as the iPad's `Home`: `shown`, the recipes are listed under `words`;
    /// not shown, `words` is Home's empty line. `ownWords` leads Home's list; nil when none came.
    struct Home: Decodable, Equatable {
        /// "Say it in your own words" and its line, trimmed.
        struct OwnWords: Decodable, Equatable {
            let title: String, line: String
            enum Keys: String, CodingKey { case title, line }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                title = (((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                line = (((try? c.decodeIfPresent(String.self, forKey: .line)) ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let shown: Bool, words: String, ownWords: OwnWords?

        enum Keys: String, CodingKey { case shown, words, ownWords = "own_words" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            shown = ((try? c.decodeIfPresent(Bool.self, forKey: .shown)) ?? nil) ?? false
            words = ((try? c.decodeIfPresent(String.self, forKey: .words)) ?? nil) ?? ""
            // A row with no title isn't one.
            ownWords = ((try? c.decodeIfPresent(OwnWords.self, forKey: .ownWords)) ?? nil).flatMap { $0.title.isEmpty ? nil : $0 }
        }
    }

    /// The sheet's words, as the iPad's `Labels`: each one that isn't words is "".
    struct Labels: Decodable, Equatable {
        let allows: String, holds: String, never: String, hand: String

        enum Keys: String, CodingKey { case allows, holds, never, hand }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            func text(_ key: Keys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
            allows = text(.allows); holds = text(.holds); never = text(.never); hand = text(.hand)
        }
    }

    /// One zone of a recipe's Card on its sheet: its title and its lines.
    struct Zone: Equatable, Identifiable {
        let id: String
        let title: String
        let lines: [String]
    }

    let categories: [Category]
    let recipes: [Recipe]
    /// Whether tafs cloud shows them now.
    let shown: Bool
    /// What Home shows with no taf; nil from a tafs cloud from before it.
    let home: Home?
    /// The sheet's words; nil from a tafs cloud from before them.
    let labels: Labels?

    enum Keys: String, CodingKey { case categories, recipes, shown, home, labels }

    /// As the iPad's `Recipes.init(from:)` (TafsCloud.swift:2013-2021): a category or recipe
    /// that doesn't read fails the whole read, and so does a `shown` that isn't a flag.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        shown = try c.decodeIfPresent(Bool.self, forKey: .shown) ?? true
        home = (try? c.decodeIfPresent(Home.self, forKey: .home)) ?? nil
        labels = (try? c.decodeIfPresent(Labels.self, forKey: .labels)) ?? nil
    }

    /// Home with no taf lists them: tafs cloud says so (`home.shown`), and the sheet's words came.
    var homeListsRecipes: Bool { home?.shown == true && labels != nil && !byCategory.isEmpty }
    /// "Say it in your own words", leading Home's list; nil when tafs cloud sent none.
    var homeOwnWords: Home.OwnWords? { home?.ownWords }
    /// tafs cloud's line for Home with no taf; nil when it sent none.
    var homeWords: String? {
        guard let words = home?.words.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return words
    }

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
        [Zone(id: "allows", title: labels?.allows ?? "", lines: recipe.card.allows),
         Zone(id: "holds", title: labels?.holds ?? "", lines: recipe.card.holds),
         Zone(id: "never", title: labels?.never ?? "", lines: recipe.card.never)]
            .filter { !$0.lines.isEmpty }
    }

    /// The words of the sheet's button that hands the recipe to Coach; nil when none came.
    var handWords: String? {
        guard let words = labels?.hand.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return words
    }

    /// Each category in tafs cloud's order, with its recipes; a category with none isn't shown.
    var byCategory: [(category: Category, recipes: [Recipe])] {
        categories.map { c in (c, recipes.filter { $0.category == c.id }) }.filter { !$0.recipes.isEmpty }
    }

    /// `#RRGGBB`, and only that.
    static func hex(_ s: String) -> UInt32? {
        guard s.count == 7, s.first == "#" else { return nil }
        let digits = s.dropFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

extension Access {
    /// Whether this person may use Coach, as the iPad's `AppModel.mayUseCoach`
    /// (AppModel.swift:2885-2889): KIFF's answer for Setup, else an account admin.
    static func mayUseCoach(setup: Access?, capabilities: [String]?) -> Bool {
        setup?.use ?? (capabilities?.contains("members.manage") ?? false)
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
