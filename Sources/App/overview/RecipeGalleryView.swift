import SwiftUI

/// Start a new taf: every ready-made job, at any time, as tafs cloud sends them, ported from the
/// iPad's `RecipeGallerySheet` (RecipeGallery.swift:23-72): a row that opens Coach with nothing in
/// it, to say the job in one's own words, then under its "All jobs" heading its chips and every
/// job by category with its apps and colour. Every word is tafs cloud's. Browsing (the sidebar's
/// "Explore jobs" and the row under the strip) is the same gallery under tafs cloud's "Explore
/// jobs", without the own-words row: each job's sheet only reads, with "Try it with Coach" as
/// its one action.
struct RecipeGallerySheet: View {
    @Environment(\.words) private var words
    let gallery: Gallery
    var mode: GalleryMode = .create
    /// The job sheet's words from `/v1/recipes`, for a tafs cloud whose gallery sends none.
    var labels: Recipes.Labels?
    /// Whether this person may use Coach: without it, no job is handed and there's no own-words row.
    let canHand: Bool
    let choose: (GalleryChoice) -> Void
    let close: () -> Void
    @State private var open: Recipes.Recipe?

    var body: some View {
        let recipes = gallery.asRecipes(labels: labels)
        VStack(alignment: .leading, spacing: 0) {
            // The title in the middle and Close at the side, as the iPad's navigation bar.
            ZStack {
                Text(verbatim: gallery.title(browse: mode == .browse)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button(words("common.close"), action: close).keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .create, canHand, !gallery.words.ownWords.isEmpty {
                        // "Say it in your own words": Coach, with nothing in its box.
                        OwnWordsRow(title: gallery.words.ownWords, line: gallery.words.ownWordsLine) { choose(.ownWords) }
                    }
                    if !gallery.words.all.isEmpty { Eyebrow(text: gallery.words.all) }
                    HomeRecipesView(recipes: recipes, ownWords: nil, canHand: canHand, hand: { _ in }, open: { open = $0 })
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 680, height: 640)
        .background(Theme.background)
        .sheet(item: $open) { recipe in
            RecipeSheet(recipe: recipe, recipes: recipes, canHand: canHand,
                        handWords: gallery.handWords(browse: mode == .browse, labels: recipes.labels),
                        sampleLabel: gallery.sampleLabel, close: { open = nil }) {
                open = nil
                choose(.recipe(recipe))
            }
        }
    }
}
