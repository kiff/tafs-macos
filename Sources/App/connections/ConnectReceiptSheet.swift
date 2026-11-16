import SwiftUI

/// An app connected: its receipt, as the iPad's `ConnectApprovalSheet.receipt` (kiff/tafs
/// `ios/Tafs/Views/ConnectAppsView.swift:952-981`): board 5, the heading with its lock, a green
/// check with tafs cloud's line for the connection, and Done. Shown over Coach once Coach's chat
/// marks a connection made (`ConnectReceipt`, docs/connections.md › The receipt).
///
/// Every word is tafs cloud's, from the card, or a shared key: "Connected" when tafs cloud gives
/// no line, and Done. Left out, as nothing here can sign: the iPad's Disconnect, which asks Face
/// ID; and the key's last 4 characters, as no key is given on this Mac.
struct ConnectReceiptSheet: View {
    @Environment(\.words) private var words
    let receipt: ConnectReceipt
    let done: () -> Void

    /// The sheet's width: board 5 at its own width (280) with room round it.
    static let width: CGFloat = 460
    /// Board 5's height at its own width (280 on its 490 by 215 grid): a sheet takes its content's height,
    /// so the drawing has its own, as Halt all's (`HaltView.artHeight`).
    static let artHeight: CGFloat = 123

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Board 5, an app connected (docs/window.md › Illustrations): the moment the sign-in finished.
            Illustration.appConnected.frame(height: Self.artHeight).frame(maxWidth: .infinity)
            if let heading = receipt.heading { self.heading(heading) }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok).accessibilityHidden(true)
                Text(verbatim: receipt.line ?? words("connect.status.connected"))
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: done) { Text(words("common.done")) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Theme.background)
    }

    /// The lock, then tafs cloud's title for the card, as the iPad's `heading` (`:891-911`). The
    /// iPad's logo and host are its key sheet's; Coach's card carries neither.
    private func heading(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lock.fill").foregroundColor(Theme.ok).accessibilityHidden(true)
            Text(verbatim: title).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
