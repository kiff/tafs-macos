import SwiftUI

/// The Overview with no taf, where tafs cloud lists the recipes, ported from the iPad's
/// `HomeRecipes`: its line, then "Say it in your own words", then a chip per category to narrow
/// the list, then each recipe led by the problem it ends with its line under it. A click opens
/// its sheet. Every word is tafs cloud's.
struct HomeRecipesView: View {
    let recipes: Recipes
    /// Coach with nothing in its box, from "Say it in your own words"; nil, the row isn't drawn.
    let ownWords: (() -> Void)?
    /// Whether this person may use Coach: without it, the sheet has no button.
    let canHand: Bool
    /// Hands a recipe to Coach: its words in Coach's box, to edit and send.
    let hand: (Recipes.Recipe) -> Void
    /// The label over a job's sample, the gallery's; nil when tafs cloud sends none.
    var sampleLabel: String? = nil
    /// Opens a job elsewhere, as the gallery does with its own sheet; nil opens this list's.
    var open: ((Recipes.Recipe) -> Void)? = nil
    /// A category picked narrows the list; picked again, every recipe shows.
    @State private var picked: String?
    @State private var opened: Recipes.Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = recipes.homeWords {
                Text(verbatim: line).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ownWords, let own = recipes.homeOwnWords { OwnWordsRow(title: own.title, line: own.line, action: ownWords) }
            let all = recipes.byCategory
            if all.count > 1 {
                WrapRow(count: all.count, spacing: 8) { index in chip(all[index].category) }
            }
            ForEach(recipes.groups(picked: picked), id: \.category.id) { group in
                Eyebrow(text: group.category.title)
                ForEach(group.recipes) { recipe in row(recipe, tint: group.category.color) }
            }
        }
        .sheet(item: $opened) { recipe in
            RecipeSheet(recipe: recipe, recipes: recipes, canHand: canHand, sampleLabel: sampleLabel, close: { opened = nil }) {
                opened = nil
                hand(recipe)
            }
        }
    }

    /// The category's colour, tafs cloud's token: its words in it, and its fill once picked.
    private func chip(_ category: Recipes.Category) -> some View {
        let on = picked == category.id
        let tint = category.color.map { Color($0) }
        return Button { picked = on ? nil : category.id } label: {
            Text(verbatim: category.title).font(.system(size: 13))
                .foregroundColor(on ? Theme.onFill : (tint ?? Theme.soft))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(Capsule().fill(on ? (tint ?? Theme.ink) : Theme.panel))
                .overlay(Capsule().strokeBorder(tint ?? (on ? Theme.ink : Theme.line), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// One recipe, as the iPad's `RecipeRow`: the problem it ends, its line, the apps it uses,
    /// on an edge in its category's colour.
    private func row(_ recipe: Recipes.Recipe, tint: Shade?) -> some View {
        Button { if let open { open(recipe) } else { opened = recipe } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: recipe.lead).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if !recipe.line.isEmpty {
                    Text(verbatim: recipe.line).font(.system(size: 14)).foregroundColor(Theme.soft)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                // As the iPad's `AppMarks`: each app its own mark, by name (the logos aren't here yet).
                if !recipe.apps.isEmpty {
                    WrapRow(count: recipe.apps.count, spacing: 8) { index in
                        Text(verbatim: recipe.apps[index].name).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(tint.map { Color($0).frame(width: 4) }, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Say it in your own words": Coach, with nothing in its box, as the iPad's `OwnWordsRow`.
/// Home's list leads with it, and Home with no job listed still draws it.
struct OwnWordsRow: View {
    let title: String
    let line: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !line.isEmpty {
                        Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.soft)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.dim).accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A recipe's sheet, as the iPad's `RecipeSheet`: what it ends and what that costs today, then
/// its Card in plain zones, where its proof run passed and what it reported, and one button that
/// hands it to Coach with the recipe's words, to edit and send.
struct RecipeSheet: View {
    @Environment(\.words) private var words
    let recipe: Recipes.Recipe
    let recipes: Recipes
    /// Whether this person may use Coach: without it, the sheet has no button.
    let canHand: Bool
    /// The button's words where the gallery says them ("Try it with Coach" while browsing);
    /// nil for the sheet's own (`labels.hand`).
    var handWords: String? = nil
    /// The label over the job's sample, tafs cloud's; nil when it sends none.
    var sampleLabel: String? = nil
    let close: () -> Void
    let hand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: recipe.lead).font(Theme.display(24)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if !recipe.line.isEmpty { Text(verbatim: recipe.line).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true) }
                    if !recipe.today.isEmpty { Text(verbatim: recipe.today).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true) }
                    ForEach(recipes.zones(of: recipe)) { zone in
                        VStack(alignment: .leading, spacing: 6) {
                            if !zone.title.isEmpty { Eyebrow(text: zone.title) }
                            ForEach(Array(zone.lines.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
                    }
                    if !recipe.proved.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "checkmark.seal").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.soft).accessibilityHidden(true)
                            Text(verbatim: recipe.proved).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                        }
                    }
                    if !recipe.sample.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if let sampleLabel { Eyebrow(text: sampleLabel) }
                            Text(verbatim: recipe.sample).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
                    }
                    if canHand, let handWords = handWords ?? recipes.handWords {
                        Button(action: hand) {
                            Text(verbatim: handWords).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.brand))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .frame(width: 560, height: 600)
        .background(Theme.background)
    }
}
