import SwiftUI

/// The new welcome's consent, as the iPad's `OnboardingView.consent` (docs/pairing.md, "Signing in inside the app"):
/// one tick for KIFF's Terms and the tafs Terms, each linked in its line; privacy as two links below it, never ticked;
/// and the age line for this Mac's country. The box is its own control, so clicking a link opens its page and never
/// ticks the box.
struct OnboardingConsent: View {
    @Environment(\.words) private var words
    @ObservedObject var model: SignInModel
    let region: String?
    let ages: MinimumAge

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.termsChanged {
                Text(words("onboarding.terms_changed")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { Task { await model.toggleTick() } } label: {
                    Image(systemName: model.tick.agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundColor(model.tick.agreed ? Theme.amber : Theme.dim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words("onboarding.consent_tick", ["kiff_terms": words("onboarding.kiff_terms"),
                                                                      "tafs_terms": words("onboarding.tafs_terms")]))
                .accessibilityAddTraits(model.tick.agreed ? .isSelected : [])
                Text(Linked.line(words("onboarding.consent_tick", ["kiff_terms": "\u{1}", "tafs_terms": "\u{2}"]),
                                 [(words("onboarding.kiff_terms"), LegalPages.kiffTerms(words.language)),
                                  (words("onboarding.tafs_terms"), LegalPages.terms(words.language))]))
                    .font(.system(size: 13)).foregroundColor(Theme.ink).tint(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Linked.line(words("onboarding.privacy_links", ["kiff_privacy": "\u{1}", "tafs_privacy": "\u{2}"]),
                             [(words("onboarding.kiff_privacy"), LegalPages.kiffPrivacy(words.language)),
                              (words("onboarding.tafs_privacy"), LegalPages.privacy(words.language))]))
                .font(.system(size: 12)).foregroundColor(Theme.soft).tint(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
            Text(Onboarding.ageLine(region: region, ages: ages, words: words))
                .font(.system(size: 11)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}

/// A line whose placeholders were filled with the markers `\u{1}`, `\u{2}`… in order, each marker replaced by its
/// link's words, linked: the line's language puts the links wherever it needs them. The iPad's `Legal.linked`; no
/// Markdown is read from the words, so a translated line can't make a link of its own.
enum Linked {
    static func line(_ line: String, _ links: [(words: String, url: String)]) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(line)
        let markers = links.indices.map { Character(UnicodeScalar(UInt8($0 + 1))) }
        while let i = rest.firstIndex(where: { markers.contains($0) }) {
            out += AttributedString(String(rest[..<i]))
            if let index = markers.firstIndex(of: rest[i]) {
                var link = AttributedString(links[index].words)
                link.link = URL(string: links[index].url)
                out += link
            }
            rest = rest[rest.index(after: i)...]
        }
        out += AttributedString(String(rest))
        return out
    }
}
