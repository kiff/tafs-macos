import SwiftUI

/// A taf's Card as the iPad draws it: in the taf's colour, its title, what is left as the
/// large figure, how many tools, and when it ends.
struct CardFace: View {
    @Environment(\.words) private var words
    let card: TafCard
    let color: Color
    /// Who issued it, at its bottom left, as the iPad's `TafCardFace` (TafDetailView.swift:1270-1283):
    /// "You" for whoever manages the taf (`TafCard.issuer`).
    var issuedBy: String

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
                VStack(alignment: .leading, spacing: 1) {
                    Text(words("card.issued_by")).font(.system(size: 10)).opacity(0.75)
                    Text(verbatim: issuedBy).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if !card.active {
                        Text(words("card.ended")).font(.system(size: 12, weight: .semibold))
                    } else if let expires = card.expires {
                        Text(words("card.until")).font(.system(size: 10)).opacity(0.85)
                        Text(verbatim: day.string(from: expires)).font(.system(size: 12, weight: .semibold))
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

    /// A day as the app shows it, in its language.
    private var day: DateFormatter { AppDates.formatter(words, date: .medium) }
}

/// A taf's page, to the iPad's: its mark and name, its tabs, and the tab's content.
struct TafView: View {
    /// Whether a taf's Halt shows, as the iPad's `TafDetailView.swift:404`: only for whoever
    /// manages it, as KIFF says, and not for a revoked taf (`KIFFMapping.swift:114-127` maps every
    /// state Home doesn't name for a live taf to revoked). Revoke shows on the same taf.
    static func halts(manages: Bool, state: String) -> Bool {
        manages && ["working", "waiting", "idle", "paused", "halted"].contains(state)
    }

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
    /// Plan & usage, from a health fix.
    var openUsage: () -> Void = {}
    /// Who is signed in: Setup's account time zone and email, and the account the Card names
    /// as its issuer for anyone who doesn't manage the taf.
    var me: Me? = nil
    /// Its doors, for whoever manages it; nil for anyone else, or a taf tafs cloud doesn't run.
    var doors: DoorsModel? = nil
    /// tafs cloud offers doors here.
    var doorsOffered = false
    /// This person's sign-in email, for their own key on a door.
    var myEmail: String? = nil
    /// Who uses the taf, under its head for whoever manages it; nil where nothing reads it.
    var shareLine: ShareLine? = nil
    /// The signed-in app's one dictation, for the taf's chat.
    var dictation: Dictation? = nil
    /// Coach on this taf, a new conversation, as the iPad's `improveTaf` with `coachOpen`: only
    /// for someone who manages the taf and may use Coach; nil draws no Improve in Coach.
    var improveInCoach: (() -> Void)? = nil
    /// Coach on this taf with these words in its box, nothing sent, as the iPad's `askCoachAbout`;
    /// nil for someone who may not, who reads an `ask_coach` card alone.
    var askCoach: ((String) -> Void)? = nil
    /// Connect apps, from the ring's +, for whoever manages the taf; nil draws no +.
    var openConnect: (() -> Void)? = nil
    /// The Card in front of the stack; nil for the first, the live one.
    @State private var frontCard: String?
    @State var tab: Tab = .chat
    /// The version and share lines folded away while the chat scrolls down, as the iPad's `folded`.
    @State private var folded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Under the header, as the iPad's `headerLine`: its live version, which opens
            // Versions, then who it's shared with, for whoever manages the taf.
            if manages && !folded {
                VStack(alignment: .leading, spacing: 6) {
                    if let pages { versionLine(pages) }
                    if let shareLine { shareLine }
                }
                .transition(.opacity)
            }
            tabs
            tabContent
        }
        .onChange(of: tab) { _ in folded = false }
        .padding(.horizontal, Look.inset - 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    /// Folds the header's line going down, and brings it back going up, as the iPad's `fold`.
    private func fold(_ down: Bool) {
        guard down != folded else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { folded = down }
    }

    /// As the iPad's head: its avatar, its name, and tafs cloud's state at the right.
    private var header: some View {
        HStack(spacing: 10) {
            TafAvatar(name: taf.name, color: taf.color, size: 34)
            Text(verbatim: taf.name).font(Theme.display(20)).foregroundColor(Theme.ink).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let chip = TafState.chip(state: taf.state, attention: taf.attention) { stateChip(chip.key, chip.tone) }
        }
        .padding(.top, 40)
    }

    /// The four tabs, as the iPad's switch.
    private var tabs: some View {
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
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .chat: chatTab
        case .card: cardTab
        case .activity: activityTab
        case .setup: setupTab
        }
    }

    /// Who issued its Cards, on their faces, as the iPad's `issuer(of:)`.
    private var issuedBy: String { TafCard.issuer(manages: manages, account: me?.account, words) }

    /// The chat, with the Card beside it as on the iPad.
    private var chatTab: some View {
        HStack(alignment: .top, spacing: 20) {
            // An open trial puts its bar over its own chat, as the iPad's `TrialScreen`; the live chat comes back after.
            if let pages, let trial = pages.trial, let trialChat = pages.trialChat {
                VStack(alignment: .leading, spacing: 10) {
                    TrialBar(model: pages, trial: trial, name: taf.name)
                    CoachView(model: trialChat, embedded: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CoachView(model: chat, embedded: true, dictation: dictation, askCoach: askCoach, onScroll: fold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            cardColumn
        }
        .task { await pages?.loadTrial() }
    }

    /// The Activity, with the Card beside it in the same column as the chat's, as the iPad's
    /// wide page (`TafDetailView.swift:66-72, 121-124`), never a bar above it.
    @ViewBuilder private var activityTab: some View {
        if let pages {
            HStack(alignment: .top, spacing: 20) {
                TafActivityTab(model: pages, taf: taf, openUsage: openUsage,
                               doors: manages ? doors : nil, doorsOffered: doorsOffered, manages: manages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                cardColumn
            }
        }
    }

    @ViewBuilder private var setupTab: some View {
        if let pages {
            // An app's week opens the taf's Activity of its calls, as on the iPad.
            TafSetupTab(model: pages, openActivity: { query in
                pages.show(activityQuery: query)
                tab = .activity
            }, halted: halted, doors: manages ? doors : nil, taf: taf, manages: manages, me: me, myEmail: myEmail,
               improveInCoach: improveInCoach, openConnect: manages ? openConnect : nil)
        }
    }

    /// The side column, as the iPad's `side`: "Card" or "Cards", the wallet, and a button to all
    /// of them on the Card tab.
    @ViewBuilder private var cardColumn: some View {
        if !taf.cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: words.count("card.heading", taf.cards.count))
                CardStack(cards: taf.cards, color: Theme.tafColor(taf.color), issuedBy: issuedBy, front: $frontCard)
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

    /// "Version 3 · live", which opens the taf's versions, as the iPad's `versionLine`.
    private func versionLine(_ pages: TafPagesModel) -> some View {
        VersionLine(model: pages)
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

    /// The Card tab, as the iPad's `card(_:)` (TafDetailView.swift:380-462).
    private var cardTab: some View {
        TafCardTab(taf: taf, pages: pages, manages: manages, issuedBy: issuedBy, improveInCoach: improveInCoach, front: $frontCard, halted: halted)
    }
}


/// A taf's Cards as the iPad's `CardStack`: as in a wallet, the furthest back on top, each a band
/// of 26 points above the one in front, a shade darker so Cards of one colour read apart. A click
/// brings one to the front. (The iPad's `WalletLayout` is a `Layout`, which macOS 12 hasn't: the
/// bands are padding in a `ZStack` here.)
struct CardStack: View {
    @Environment(\.words) private var words
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cards: [TafCard]
    let color: Color
    /// Who issued them, on each face.
    let issuedBy: String
    /// The Card in front; nil for the first, the live one.
    @Binding var front: String?

    /// How much of a Card behind shows.
    static let band: CGFloat = 26

    /// The Card in front: the one chosen, else the first.
    static func front(of cards: [TafCard], _ chosen: String?) -> TafCard? {
        cards.first { $0.id == chosen } ?? cards.first
    }

    /// The Cards top to bottom: the furthest back first, the front one last, as in a wallet.
    static func ordered(_ cards: [TafCard], front: String?) -> [TafCard] {
        let shown = Self.front(of: cards, front)
        return Array(cards.filter { $0.id != shown?.id }.reversed()) + (shown.map { [$0] } ?? [])
    }

    /// How much darker a Card `depth` places behind the front one is drawn, as the iPad's.
    static func shade(depth: Int) -> Double { depth <= 0 ? 0 : min(0.12 + 0.08 * Double(depth - 1), 0.32) }

    var body: some View {
        let ordered = Self.ordered(cards, front: front)
        ZStack(alignment: .top) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, card in
                Button {
                    // As the iPad's `withMotion`: the spring, unless motion is reduced.
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { front = card.id }
                } label: {
                    CardFace(card: card, color: color, issuedBy: issuedBy)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(Self.shade(depth: ordered.count - 1 - index))))
                        .shadow(color: .black.opacity(0.16), radius: 4, y: -2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words("taf.show_card", ["title": card.title]))
                .padding(.top, CGFloat(index) * Self.band)
            }
        }
        .frame(maxWidth: CardFace.width)
    }
}

/// The header's way into the taf's versions: its mark, "Version 3 · live" (else "Versions") and
/// a caret, in the line's quiet colour, opening the Versions sheet.
struct VersionLine: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                Text(TafVersions.headerLine(model.versionList, words)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim).accessibilityHidden(true)
            }
            .foregroundColor(Theme.soft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await model.loadVersions() }
        .sheet(isPresented: $open) { VersionsView(model: model) { open = false } }
    }
}

/// The taf's versions, as the iPad's `VersionsPanel`: newest first, the live one marked, each
/// with what changed, who made it and when, and what each ended trial came to; a switch under
/// way, with Cancel. Installing one and trying one are signed by the phone, so this Mac lists
/// them only.
struct VersionsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let close: () -> Void
    /// The version whose trial is being started.
    @State private var trying: TafVersions.Version?

    /// A version's time and a trial's day, as the app shows them, in its language.
    private var when: DateFormatter { AppDates.formatter(words, date: .medium, time: .short) }
    private var day: DateFormatter { AppDates.formatter(words, date: .medium) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(words("version.title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            Text(words("taf.try_version_first_you_chat")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            if let switching = model.switching { switchUnderWay(switching) }
            if let list = model.versionList {
                if list.isEmpty {
                    Text(words("version.first_only")).font(.system(size: 14)).foregroundColor(Theme.soft)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(list.reversed()) { row($0) }
                    }
                }
            } else if model.versionError == nil {
                ProgressView().controlSize(.small)
            }
            if let error = model.versionError {
                Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await model.loadVersions() }
        .sheet(item: $trying) { v in
            TrialStartSheet(model: model, version: v, close: { trying = nil }).environment(\.words, words)
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.background)
    }

    /// A switch that didn't finish, as the iPad's `switchUnderWay`: the taf doesn't run until it's
    /// finished or cancelled. Finishing it is signed by the phone; Cancel isn't.
    private func switchUnderWay(_ sw: TafVersions.Switching) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(words("version.installing_number", ["version": String(sw.n)])).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
            Text(words("version.doesnt_run_until")).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            Button(words("common.cancel")) { Task { await model.cancelSwitch() } }
                .buttonStyle(OutlineButtonStyle(color: Theme.no))
                .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func row(_ v: TafVersions.Version) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(words("version.number", ["version": String(v.n)])).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if v.live {
                    Text(words("version.live_now")).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.ok))
                }
                Spacer(minLength: 0)
            }
            if let note = v.note, !note.isEmpty {
                Text(verbatim: note).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: TafVersions.byline(v, words, when: { when.string(from: $0) })).font(.system(size: 12)).foregroundColor(Theme.dim)
            ForEach(Array(v.trials.enumerated()), id: \.offset) { _, trial in
                Text(verbatim: TafVersions.tried(trial, words, day: { day.string(from: $0) })).font(.system(size: 12)).foregroundColor(Theme.soft)
            }
            // Trying a version that isn't live, under a Card of its own, on the security key (`Trials`); one trial a taf.
            if !v.live, model.startsTrials, model.trial == nil {
                Button(words("version.try_it")) { trying = v }.buttonStyle(OutlineButtonStyle()).fixedSize()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}
