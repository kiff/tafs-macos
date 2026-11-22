import SwiftUI

/// The three cards on how tafs works, as the iPad's `OnboardingCards` (kiff/tafs `ios/Tafs/Views/OnboardingCards.swift`):
/// after signing in, before the first Home, and again from How tafs works. Each draws the app's own components with
/// the sample's words, so the person knows them a minute later and reads them in their language.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case tafs, card, control

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .tafs: return "onboarding.tafs_title"
        case .card: return "onboarding.card_title"
        case .control: return "onboarding.control_title"
        }
    }

    /// The last card names this Mac's own way to approve: a desktop that approves on the phone (`control_lead_desktop`),
    /// since a Mac on macOS 12 has no Touch ID to approve with (kiff/work#9).
    var leadKey: String {
        switch self {
        case .tafs: return "onboarding.tafs_lead"
        case .card: return "onboarding.card_lead"
        case .control: return "onboarding.control_lead_desktop"
        }
    }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
}

/// Where the person is in the cards: Next goes on, the last card's button ends them, and Skip ends them from any card.
struct OnboardingSteps: Equatable {
    private(set) var page: OnboardingPage
    private(set) var finished = false

    init(start: OnboardingPage = .tafs) { page = start }

    var isLast: Bool { page.next == nil }

    /// Next, or Get started on the last card.
    mutating func advance() {
        if let next = page.next { page = next } else { finished = true }
    }

    mutating func skip() { finished = true }
}

struct OnboardingCards: View {
    @Environment(\.words) private var words
    @State private var steps: OnboardingSteps
    /// After signing in: Skip and Get started go to Home. Reopened from How tafs works: they close the cards.
    let done: () -> Void

    init(start: OnboardingPage = .tafs, done: @escaping () -> Void) {
        _steps = State(initialValue: OnboardingSteps(start: start))
        self.done = done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()
                Button(words("onboarding.skip")) { steps.skip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.soft)
                    .keyboardShortcut(.cancelAction)
            }

            OnboardingPicture(page: steps.page)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                // A picture of the app, not a control: what it says is in the title and the lead.
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text(words(steps.page.titleKey))
                    .font(Theme.display(30))
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(words(steps.page.leadKey))
                    .font(.system(size: 16))
                    .foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(OnboardingPage.allCases) { page in
                    Circle()
                        .fill(page == steps.page ? Theme.amber : Theme.dim.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Button(steps.isLast ? words("onboarding.get_started") : words("common.next")) {
                withAnimation(.easeInOut(duration: 0.2)) { steps.advance() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
        // On a Mac window, a phone's width, centred, as the welcome reads.
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onChange(of: steps.finished) { if $0 { done() } }
    }
}

/// Each card's picture, drawn by the app's own components with the sample's words.
struct OnboardingPicture: View {
    @Environment(\.words) private var words
    let page: OnboardingPage

    var body: some View {
        switch page {
        case .tafs: tafs
        case .card: card
        case .control: control
        }
    }

    /// The sample's tafs as the sidebar and the Overview list them: each with its avatar, name and job.
    private var tafs: some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.sampleTafs.enumerated()), id: \.offset) { index, taf in
                HStack(spacing: 12) {
                    TafAvatar(name: words(taf.name), color: index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(words(taf.name)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                        Text(words(taf.job)).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            }
        }
        .frame(maxWidth: 420)
    }

    /// A taf's Card as its Card tab draws it: the sample's "Support replies · Zendesk" Card, 28 replies left of 40
    /// today, issued by you.
    @ViewBuilder private var card: some View {
        if let sample = Self.sampleCard(words) {
            CardFace(card: sample, color: Theme.tafColor(0), issuedBy: words("common.you")).frame(maxWidth: 340)
        }
    }

    /// Needs you's card: the sample's Deploys asks, nothing is sent until you approve, and the three answers.
    private var control: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("sample.deploys.name"))
            Text(words("sample.deploys.deploy_api")).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("sample.deploys.deploy_api_why")).font(.system(size: 14)).foregroundColor(Theme.soft)
            Text(words("needs_you.nothing_sent")).font(.system(size: 13)).foregroundColor(Theme.dim)
            Button(words("needs_you.approve_once")) {}.buttonStyle(PrimaryButtonStyle())
            Button(words("sample.deploys.next_step")) {}.buttonStyle(OutlineButtonStyle())
            Button(words("needs_you.refuse")) {}.buttonStyle(OutlineButtonStyle(color: Theme.no))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius).stroke(Theme.line))
        .frame(maxWidth: 420)
    }

    /// The sample's own tafs, in the order the iPad's Home shows them: the ones that never move money.
    static let sampleTafs: [(name: String, job: String)] = [
        ("sample.support.name", "sample.support.job"),
        ("sample.parcels.name", "sample.parcels.job"),
        ("sample.leads.name", "sample.leads.job"),
    ]

    /// The Card the iPad's screenshots show: "Support replies · Zendesk" with Support replies' own rules (40 replies a
    /// day, promises always ask, customer data never), 12 of 40 used today, so its title and its rules are one Card.
    static func sampleCard(_ words: Words) -> TafCard? {
        let day: [String: String] = ["each": words("card.window.a_day"), "now": words("card.window.today")]
        let card: [String: Any] = [
            "id": "onboarding-support", "title": words("sample.card.refunds_stripe"), "active": true,
            "rules": [
                ["label": words("sample.support.rule.replies"), "outside": "hold", "count_per_window": 40, "window_words": day],
                ["label": words("sample.support.rule.promises"), "outside": "hold"],
                ["label": words("sample.support.rule.customer_data"), "outside": "refuse"],
            ],
            "calls": ["limit": 40, "used": 12, "window_words": day],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: ["cards": [card]]) else { return nil }
        struct Cards: Decodable { let cards: [TafCard] }
        return (try? JSONDecoder().decode(Cards.self, from: data))?.cards.first
    }
}

/// How tafs works, any time (the first Home; Account), as the iPad's `HowTafsWorksView`: the three cards again, each
/// opening where it's clicked, and the privacy and terms pages, KIFF's and tafs's.
struct HowTafsWorksView: View {
    @Environment(\.words) private var words
    @State private var opened: OnboardingPage?
    let close: () -> Void

    /// The four legal pages as rows, each titled as its page is: standalone titles (`onboarding.row_*`), never the
    /// tick line's link words, which are written to sit inside its sentence ("the tafs Terms", German's dative).
    static func legalRows(_ words: Words) -> [(title: String, url: String)] {
        [(words("onboarding.row_kiff_privacy"), LegalPages.kiffPrivacy(words.language)),
         (words("onboarding.row_tafs_privacy"), LegalPages.privacy(words.language)),
         (words("onboarding.row_kiff_terms"), LegalPages.kiffTerms(words.language)),
         (words("onboarding.row_tafs_terms"), LegalPages.terms(words.language))]
    }

    var body: some View {
        if let opened {
            OnboardingCards(start: opened) { self.opened = nil }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(words("onboarding.how_it_works")).font(Theme.display(24)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
                }
                VStack(spacing: 0) {
                    ForEach(OnboardingPage.allCases) { page in
                        Button { opened = page } label: {
                            HStack {
                                Text(words(page.titleKey)).foregroundColor(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
                                    .flipsForRightToLeftLayoutDirection(true)
                            }
                            .padding(.vertical, 11).padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if page.next != nil { Divider().padding(.leading, 14) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.legalRows(words), id: \.url) { row in
                        if let url = URL(string: row.url) {
                            Link(LegalPages.saysEnglish(words.language) ? words("settings.legal_in_english", ["label": row.title]) : row.title,
                                 destination: url)
                                .foregroundColor(Theme.amberText)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
        }
    }
}
