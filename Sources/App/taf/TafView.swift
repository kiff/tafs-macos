import SwiftUI

/// A taf's Card as the iPad draws it: in the taf's colour, its title, what is left as the
/// large figure, how many tools, and when it ends.
struct CardFace: View {
    @Environment(\.words) private var words
    let card: TafCard
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: card.title).font(Theme.mono(12)).lineLimit(1)
            Spacer(minLength: 8)
            if let figure = card.figure {
                switch figure {
                case .calls(let left, let limit, let window):
                    Text(verbatim: words.number(left)).font(.system(size: 34, weight: .bold, design: .rounded))
                    // The shared line as it is: the number is the figure above it.
                    Text(words.count("card.hero.calls_left_of", left, ["window": window, "limit": words.number(limit)]))
                        .font(.system(size: 13))
                case .money(let left, let limit, let window):
                    Text(verbatim: left.written(language: words.language)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(words("card.hero.left_of", ["window": window, "limit": limit.written(language: words.language)])).font(.system(size: 13))
                }
            }
            // The iPad's facts: the first limit for each call, and how many tools past one.
            if card.rules.isEmpty {
                Text(words("card.no_actions_short")).font(Theme.mono(11))
            } else if let fact = card.rules.lazy.compactMap({ $0.eachFact(words) }).first {
                Text(verbatim: fact).font(Theme.mono(11)).lineLimit(1)
            }
            if card.rules.count > 1 { Text(words.count("card.tools", card.rules.count)).font(Theme.mono(11)) }
            Spacer(minLength: 8)
            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if !card.active {
                        Text(words("card.ended")).font(.system(size: 12, weight: .semibold))
                    } else if let expires = card.expires {
                        Text(words("card.until")).font(.system(size: 10)).opacity(0.85)
                        Text(verbatim: Self.day.string(from: expires)).font(.system(size: 12, weight: .semibold))
                    } else {
                        Text(words("card.ends")).font(.system(size: 10)).opacity(0.85)
                        Text(words("card.no_end_date")).font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // A payment card's shape, 85.6 by 54, at most 300 wide, as the iPad's.
        .aspectRatio(Self.ratio, contentMode: .fit)
        .background(color)
        .overlay(
            Circle().stroke(Color.white.opacity(0.18)).frame(width: 130, height: 130).offset(x: 35, y: -45)
                .accessibilityHidden(true),
            alignment: .topTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: Self.width)
        // A Card that isn't active any more, faded as on the iPad.
        .opacity(card.active ? 1 : 0.4)
        .accessibilityElement(children: .combine)
    }

    /// At most this wide, as on the iPad.
    static let width: CGFloat = 300
    /// A payment card's proportions, 85.6 by 54 mm.
    static let ratio: CGFloat = 85.6 / 54

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

/// A taf's page, to the iPad's: its mark and name, its tabs, and the tab's content.
struct TafView: View {
    enum Tab: String, CaseIterable, Identifiable {
        // The iPad's order.
        case chat, activity, card, setup
        var id: String { rawValue }
        var titleKey: String { "taf.section.\(rawValue)" }
    }

    @Environment(\.words) private var words
    let taf: Home.Taf
    @ObservedObject var chat: CoachModel
    /// Its Activity and Setup, read when their tab opens; nil where nothing reads them.
    var pages: TafPagesModel?
    /// Whether this person manages the taf, as KIFF says: its halt is theirs.
    var manages = false
    /// Reads the list again after the taf was halted.
    var halted: () async -> Void = {}
    @State var tab: Tab = .chat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // As the iPad's head: its avatar, its name, and tafs cloud's state at the right.
            HStack(spacing: 10) {
                TafAvatar(name: taf.name, color: taf.color, size: 34)
                Text(verbatim: taf.name).font(Theme.display(20)).foregroundColor(Theme.ink).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let chip = TafState.chip(state: taf.state, attention: taf.attention) { stateChip(chip.key, chip.tone) }
            }
            .padding(.top, 40)
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { choice in
                    let chosen = tab == choice
                    Button { tab = choice } label: {
                        Text(words(choice.titleKey)).font(.system(size: 13, weight: chosen ? .semibold : .regular)).foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Capsule().fill(chosen ? Theme.panel : Color.clear)).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Capsule().fill(Theme.raised))
            switch tab {
            case .chat: chatTab
            case .card: cardTab
            case .activity:
                if let pages { TafActivityTab(model: pages, taf: taf) { tab = .card } }
            case .setup:
                if let pages {
                    // An app's week opens the taf's Activity of its calls, as on the iPad. Halt is not
                    // for a taf whose Card is no longer active (a state Home doesn't name).
                    TafSetupTab(model: pages, openActivity: { query in
                        pages.show(activityQuery: query)
                        tab = .activity
                    }, tafName: taf.name,
                                halts: manages && ["working", "waiting", "idle", "paused", "halted"].contains(taf.state), halted: halted)
                }
            }
        }
        .padding(.horizontal, Look.inset - 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    /// The chat, with the Card beside it as on the iPad.
    private var chatTab: some View {
        HStack(alignment: .top, spacing: 20) {
            CoachView(model: chat, embedded: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let card = taf.cards.first {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: words.count("card.heading", taf.cards.count))
                    CardFace(card: card, color: Theme.tafColor(taf.color))
                    Button { tab = .card } label: {
                        Text(words.count("card.all_of", taf.cards.count)).font(.system(size: 14)).foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.soft.opacity(0.5))).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 360)
                .padding(.top, 8)
            }
        }
    }

    /// The iPad's `StateChip`: the word on its tone at 15%, in a capsule.
    private func stateChip(_ key: String, _ tone: TafState.Tone) -> some View {
        let color: Color
        switch tone {
        case .ok: color = Theme.ok
        case .amber: color = Theme.amber
        case .no: color = Theme.no
        case .soft: color = Theme.soft
        }
        return Text(words(key)).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundColor(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    /// The Card itself, then each thing it lets the taf do and what happens outside it.
    private var cardTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // No Card listed says nothing: tafs cloud sends no field that says one was revoked.
                ForEach(taf.cards) { card in
                    CardFace(card: card, color: Theme.tafColor(taf.color))
                    // A Card with no rules has no panel under it, never an empty one.
                    if !card.rules.isEmpty { rules(card) }
                }
            }
            .padding(.bottom, Look.inset)
        }
    }

    /// Each thing a Card lets the taf do, and what happens outside it.
    private func rules(_ card: TafCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(card.rules.enumerated()), id: \.offset) { _, rule in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: rule.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                        if let outside = outsideWords(rule.outside) { Text(outside).font(.system(size: 12)).foregroundColor(Theme.soft) }
                    }
                    Spacer()
                    // Its limits as the iPad's summary: held or refused above them.
                    let summary = rule.summary(words)
                    if !summary.isEmpty {
                        Text(verbatim: summary).font(Theme.mono(12)).foregroundColor(Theme.ink).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    /// What happens outside a rule, in the shared words; nothing for a word tafs cloud may
    /// send that this app doesn't know.
    private func outsideWords(_ outside: TafCard.Rule.Outside) -> String? {
        switch outside {
        case .refuse: return words("card.outside_refused")
        case .hold: return words("card.outside_held")
        case .unknown: return nil
        }
    }
}
