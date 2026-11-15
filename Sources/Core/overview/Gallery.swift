import Foundation

/// Every ready-made job, reachable at any time (`GET /v1/recipes/gallery`), ported from the
/// iPad's `TafsCloud.Gallery` (TafsCloud.swift:2077-2183): the full gallery behind Start a new
/// taf, and the short strip under the tafs list. tafs cloud decides what each shows and in what
/// order; the app draws it. Everything reads leniently, as on the iPad: a category or job that
/// doesn't read is left out, never the gallery.
struct Gallery: Decodable, Equatable {
    /// The strip under the tafs list: shown or not, its title, and the jobs, in order.
    struct Strip: Decodable, Equatable {
        var shown = false
        var title = ""
        var ids: [String] = []
        private enum CodingKeys: String, CodingKey { case shown, title, ids }
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            shown = ((try? c.decodeIfPresent(Bool.self, forKey: .shown)) ?? nil) ?? false
            title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? ""
            ids = ((try? c.decodeIfPresent([String].self, forKey: .ids)) ?? nil) ?? []
        }
    }

    /// The gallery's own words: its title, and the row that opens Coach with nothing in it.
    struct Words: Decodable, Equatable {
        var title = ""
        /// The heading over every job ("All jobs").
        var all = ""
        var ownWords = ""
        var ownWordsLine = ""
        /// Browsing, with nothing created: the sidebar's row and the gallery's title ("Explore jobs").
        var explore = ""
        /// The row under the strip ("See all jobs").
        var seeAll = ""
        /// A browsed job's only action ("Try it with Coach").
        var tryIt = ""
        /// The label over a job's sample ("What it reported after its test run").
        var sample = ""
        private enum CodingKeys: String, CodingKey {
            case title, all, ownWords = "own_words", ownWordsLine = "own_words_line"
            case explore, seeAll = "see_all", tryIt = "try", sample
        }
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
            title = text(.title); all = text(.all); ownWords = text(.ownWords); ownWordsLine = text(.ownWordsLine)
            explore = text(.explore); seeAll = text(.seeAll); tryIt = text(.tryIt); sample = text(.sample)
        }
    }

    let categories: [Recipes.Category]
    let recipes: [Recipes.Recipe]
    let strip: Strip
    let words: Words
    /// The job sheet's words; nil from a tafs cloud that sends none with the gallery.
    let labels: Recipes.Labels?

    private enum CodingKeys: String, CodingKey { case categories, recipes, strip, words, labels }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = ((try? c.decodeIfPresent([GalleryItem<Recipes.Category>].self, forKey: .categories)) ?? nil)?.compactMap(\.value) ?? []
        recipes = ((try? c.decodeIfPresent([GalleryItem<Recipes.Recipe>].self, forKey: .recipes)) ?? nil)?.compactMap(\.value) ?? []
        strip = ((try? c.decodeIfPresent(Strip.self, forKey: .strip)) ?? nil) ?? Strip()
        words = ((try? c.decodeIfPresent(Words.self, forKey: .words)) ?? nil) ?? Words()
        labels = (try? c.decodeIfPresent(Recipes.Labels.self, forKey: .labels)) ?? nil
    }

    /// The gallery as recipes, so it draws as Home's list does, its sheet with `labels` (the
    /// gallery's, else `fallback`'s, from `/v1/recipes`).
    func asRecipes(labels fallback: Recipes.Labels? = nil) -> Recipes {
        Recipes(categories: categories, recipes: recipes, labels: labels ?? fallback)
    }

    /// The words of the row under the strip that opens every job: tafs cloud's "See all jobs"
    /// (`words.see_all`), else its heading for them ("All jobs") from a tafs cloud from before
    /// it. Nil when it sends neither, or the strip already shows every job.
    var seeAll: String? {
        guard recipes.count > stripRecipes.count else { return nil }
        return Self.said(words.seeAll) ?? Self.said(words.all)
    }

    /// The words of the row that opens the jobs to browse, with nothing created
    /// (`words.explore`). Nil when tafs cloud sends none or lists no job: then no row, and no
    /// words of the app's own.
    var explore: String? { recipes.isEmpty ? nil : Self.said(words.explore) }

    /// The gallery's title: browsing, tafs cloud's "Explore jobs" where it sends it; else, and
    /// from Start a new taf, its title.
    func title(browse: Bool) -> String { (browse ? Self.said(words.explore) : nil) ?? words.title }

    /// The words of a job's one button, which hands it to Coach: browsing, "Try it with Coach"
    /// (`words.try`); else, and from a tafs cloud from before it, the sheet's own
    /// (`labels.hand`). Nil when none came: no button.
    func handWords(browse: Bool, labels: Recipes.Labels?) -> String? {
        (browse ? Self.said(words.tryIt) : nil) ?? Self.said(labels?.hand ?? "")
    }

    /// The label over a job's sample; nil when tafs cloud sends none.
    var sampleLabel: String? { Self.said(words.sample) }

    private static func said(_ words: String) -> String? {
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return w.isEmpty ? nil : w
    }

    /// The strip's jobs, in tafs cloud's order: an id the gallery doesn't list is skipped. None
    /// when tafs cloud doesn't show it.
    var stripRecipes: [Recipes.Recipe] {
        guard strip.shown else { return [] }
        return strip.ids.compactMap { id in recipes.first { $0.id == id } }
    }

    /// The category a recipe is in, for its colour.
    func category(of recipe: Recipes.Recipe) -> Recipes.Category? { categories.first { $0.id == recipe.category } }
}

/// Why the gallery is open, as the iPad's `GalleryMode`: from Start a new taf, to start one; or
/// to browse the jobs, with nothing created until "Try it with Coach" is clicked on one.
enum GalleryMode: String, Identifiable {
    case create, browse
    var id: String { rawValue }
}

/// What a person chose in the gallery, as the iPad's `GalleryChoice`: a job to hand to Coach,
/// or their own words. Acted on once the gallery has closed.
enum GalleryChoice: Equatable {
    case recipe(Recipes.Recipe)
    case ownWords
}

extension Recipes {
    /// Recipes drawn from the gallery, as the iPad's `Recipes(categories:recipes:labels:)`:
    /// shown, with no Home words of their own.
    init(categories: [Category], recipes: [Recipe], labels: Labels?) {
        self.categories = categories
        self.recipes = recipes
        self.shown = true
        self.home = nil
        self.labels = labels
    }
}

/// Reads one item of a list, or nothing, as the iPad's `LenientItem`.
private struct GalleryItem<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension CloudClient {
    /// Every ready-made job, as tafs cloud lists them for the gallery and the strip.
    func recipesGallery() async throws -> Gallery { try await get("/v1/recipes/gallery") }
}
