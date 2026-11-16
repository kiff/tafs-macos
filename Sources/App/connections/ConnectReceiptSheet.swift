import SwiftUI

/// An app connected: its receipt, as the iPad's `ConnectApprovalSheet.receipt` (kiff/tafs
/// `ios/Tafs/Views/ConnectAppsView.swift:952-981`): board 5, the heading with its lock, a green
/// check with tafs cloud's line for the connection, and Done. Shown over Coach once Coach's chat
/// marks a connection made (`ConnectReceipt`, docs/connections.md › The receipt).
///
/// Every word is tafs cloud's, from the card, or a shared key: "Connected" when tafs cloud gives
/// no line, Done, and Remove access. **Disconnect** is drawn as the iPad's, for someone who
/// manages the Cards (the iPad's `canManageCards`), but this Mac can't sign: tapping it says to
/// approve on another device (`approval.device_can_not_approve_approve`, the iPad's
/// `ApprovalGate` where an approval can't be made), and nothing is asked or sent. Left out: the
/// key's last 4 characters, as this Mac never holds the key; and the app's logo and host, which
/// Coach's card doesn't carry yet.
struct ConnectReceiptSheet: View {
    @Environment(\.words) private var words
    let receipt: ConnectReceipt
    /// Whether this person manages the account's Cards (KIFF's `cards.manage`): only then is
    /// Disconnect drawn, as on the iPad.
    var managesCards = true
    let done: () -> Void
    /// Disconnect was tapped: the gate's words show under it.
    @State private var disconnecting: Bool

    /// `disconnecting` starts the sheet as after a tap on Disconnect (its screenshot).
    init(receipt: ConnectReceipt, managesCards: Bool = true, disconnecting: Bool = false, done: @escaping () -> Void) {
        self.receipt = receipt
        self.managesCards = managesCards
        self.done = done
        _disconnecting = State(initialValue: disconnecting)
    }

    /// The sheet's width: board 5 at its own width (280) with room round it.
    static let width: CGFloat = 460
    /// Board 5's height at its own width (280 on its 490 by 215 grid): a sheet takes its content's height,
    /// so the drawing has its own, as Halt all's (`HaltView.artHeight`).
    static let artHeight: CGFloat = 123

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Board 5, an app connected (docs/window.md › Illustrations): the moment the sign-in finished.
            Illustration.appConnected.frame(height: Self.artHeight).frame(maxWidth: .infinity)
            heading(receipt.title(words))
            if receipt.showsLine {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok).accessibilityHidden(true)
                    Text(verbatim: receipt.line ?? words("connect.status.connected"))
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: done) { Text(words("common.done")) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            if managesCards { disconnect }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Theme.background)
    }

    /// The lock and the heading on one line (`ConnectReceipt.title`: never empty). The iPad's
    /// `heading` (`:891-911`) puts its logo, the lock and the host above the title; Coach's card
    /// carries no logo or host yet, so here the lock leads the title.
    private func heading(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock.fill").foregroundColor(Theme.ok).accessibilityHidden(true)
            Text(verbatim: title).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The iPad's Disconnect (`:965-978`), in the shared "Remove access" (the iPad's takes tafs cloud's
    /// key sheet's words, which Coach's card doesn't carry). This Mac can't sign,
    /// so a tap asks nothing and sends nothing: it says to approve on another device, as every
    /// approval this Mac can't make (docs/approvals.md).
    private var disconnect: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(role: .destructive) { disconnecting = true } label: {
                Text(words("connect.disconnect_button")).foregroundColor(Theme.no)
            }
            .buttonStyle(BorderlessButtonStyle())
            if disconnecting {
                Text(words("approval.device_can_not_approve_approve"))
                    .font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
