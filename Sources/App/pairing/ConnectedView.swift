import SwiftUI

/// The moment a session is gained, on either path: "You're connected. Let's build great things
/// together." over the signed-in window, until **Let's go**. Shown once, never at a launch that
/// finds its session kept (`SignInModel.justConnected`).
struct ConnectedView: View {
    @Environment(\.words) private var words
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            SignInArt.connected()
            Text(words("sign_in.connected")).font(Theme.display(34)).foregroundColor(Theme.ink)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(words("sign_in.connected_line")).font(.system(size: 17)).foregroundColor(Theme.soft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: done) {
                Text(words("sign_in.lets_go")).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 30).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.brand))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
        }
        .frame(maxWidth: 440)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
