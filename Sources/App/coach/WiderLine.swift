import SwiftUI

/// A sign-in wider than the job, in tafs cloud's words (`wider.words`), as the iPad's
/// `WiderLine`: in amber, above an approval's or a sign-in card's buttons, so no card stands
/// unsaid under a line that calls the sign-in harmless. The words are shown as sent.
struct WiderLine: View {
    let words: String

    var body: some View {
        Text(verbatim: words)
            .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.amberText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("card.wider")
    }
}
