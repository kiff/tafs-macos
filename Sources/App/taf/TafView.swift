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
                    Text(words.count("card.hero.calls_left_of", left, ["window": window, "limit": words.number(limit)])
                            .replacingOccurrences(of: words.number(left) + " ", with: ""))
                        .font(.system(size: 13))
                case .money(let left, let limit, let window):
                    Text(verbatim: left.written(language: words.language)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(words("card.hero.left_of", ["window": window, "limit": limit.written(language: words.language)])).font(.system(size: 13))
                }
            }
            Text(words.count("card.tools", card.rules.count)).font(Theme.mono(11))
            Spacer(minLength: 8)
            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(words("card.ends")).font(.system(size: 10)).opacity(0.85)
                    Text(verbatim: card.expires.map { Self.day.string(from: $0) } ?? words("card.no_end_date")).font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 180)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18).fill(color)
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: 150, height: 150).offset(x: 50, y: -70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        )
        .accessibilityElement(children: .combine)
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

/// A taf's page, to the iPad's: its mark and name, its tabs, and the tab's content.
struct TafView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case chat, card
        var id: String { rawValue }
        var titleKey: String { "taf.section.\(rawValue)" }
    }

    @Environment(\.words) private var words
    let taf: Home.Taf
    @ObservedObject var chat: CoachModel
    @State var tab: Tab = .chat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9).fill(Theme.tafColor(taf.color)).frame(width: 36, height: 36)
                    .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                    .accessibilityHidden(true)
                Text(verbatim: taf.name).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
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
                    Eyebrow(text: words("taf.section.card"))
                    CardFace(card: card, color: Theme.tafColor(taf.color))
                    Button { tab = .card } label: {
                        Text(words.count("card.all_of", taf.cards.count)).font(.system(size: 14)).foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.soft.opacity(0.5))).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 260)
                .padding(.top, 8)
            }
        }
    }

    /// The Card itself, then each thing it lets the taf do and what happens outside it.
    private var cardTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if taf.cards.isEmpty {
                    Text(words("card.card_revoked")).font(.system(size: 14)).foregroundColor(Theme.soft)
                }
                ForEach(taf.cards) { card in
                    CardFace(card: card, color: Theme.tafColor(taf.color)).frame(maxWidth: 300)
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
                    if let count = rule.countPerWindow, let each = rule.each {
                        // The limit as KIFF counts it: the number, and tafs cloud's words for its window.
                        Text(verbatim: "\(words.number(count)) · \(each)").font(Theme.mono(12)).foregroundColor(Theme.ink)
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
