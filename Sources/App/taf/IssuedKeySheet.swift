import AppKit
import SwiftUI

/// New key, as the iPad's `NewKeySheet`: its name (the door's own when left blank), then the security key.
struct NewKeySheet: View {
    @Environment(\.words) private var words
    let door: TafDoors.Door
    @ObservedObject var doors: DoorsModel
    let close: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(words("door.api.new_key")).font(Theme.display(22)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
            Text(words("door.api.two_keys")).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            Text(words("door.api.key_name")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
            TextField(words("door.api.key_name_hint"), text: $name)
                .textFieldStyle(.roundedBorder).disableAutocorrection(true)
                // tafs cloud takes at most 80; 60, as the iPad and Android, so a name never comes back refused.
                .onChange(of: name) { typed in
                    if typed.count > APIInstructions.maxKeyName { name = String(typed.prefix(APIInstructions.maxKeyName)) }
                }
            if let error = doors.error {
                Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(words("common.cancel"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(words("door.api.new_key")) {
                    Task { if await doors.newKey(door, name: name) { close() } }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(doors.busy)
                .accessibilityIdentifier("door.api.new_key.make")
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .background(Theme.background)
    }
}

/// The key, shown this once, as the iPad's `IssuedKeyView`: Copy, where to send work, and an example that reads the key
/// from the caller's own secret. Leaving it forgets the key (`DoorsModel.keyShown`). As the iPad covers it from the
/// app switcher and recording, the sheet's window is kept out of screenshots and screen recording (`CaptureShield`),
/// and a copied key leaves the clipboard after a minute unless something else was copied since (`SecretClipboard`).
struct IssuedKeySheet: View {
    @Environment(\.words) private var words
    let key: CloudClient.IssuedKey
    let door: TafDoors.Door
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        let endpoint = APIInstructions.endpoint(door.address)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("door.api.shown_once")).font(Theme.display(22)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
                Text(words("door.api.shown_once_body", ["app": door.label])).font(.system(size: 15)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: key.key).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Theme.ink)
                    .textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("door.api.key")
                Button(words(copied ? "door.api.copied" : "door.api.copy_key")) {
                    SecretClipboard.copy(key.key)
                    copied = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("door.api.copy_key")
                Eyebrow(text: words("door.api.where"))
                Text(verbatim: endpoint).font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.ink).textSelection(.enabled)
                Eyebrow(text: words("door.api.example"))
                ScrollView(.horizontal) {
                    Text(verbatim: APIInstructions.example(endpoint: endpoint)).font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.ink).textSelection(.enabled).padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                .environment(\.layoutDirection, .leftToRight)
                Button(words("common.done"), action: done).buttonStyle(OutlineButtonStyle()).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("door.api.key_done")
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Theme.background)
        .background(CaptureShield())
    }
}

/// Keeps its window out of screenshots and screen recording (`NSWindow.sharingType = .none`, macOS 10.5 and later) while
/// it's shown, and gives the window back as it was when it goes.
struct CaptureShield: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ShieldView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class ShieldView: NSView {
        private weak var shielded: NSWindow?
        private var before: NSWindow.SharingType = .readOnly

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, window !== shielded {
                shielded?.sharingType = before
                before = window.sharingType
                window.sharingType = .none
                shielded = window
            } else if window == nil {
                shielded?.sharingType = before
                shielded = nil
            }
        }
    }
}

/// A secret on the clipboard for a minute, as Android's timed clear: it's taken off after `wait` unless something else
/// was copied since (the pasteboard's change count moved), so the person's own copy is never cleared.
enum SecretClipboard {
    static let wait: TimeInterval = 60

    static func copy(_ secret: String, pasteboard: NSPasteboard = .general, wait: TimeInterval = SecretClipboard.wait) {
        pasteboard.clearContents()
        pasteboard.setString(secret, forType: .string)
        let mine = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if pasteboard.changeCount == mine, pasteboard.string(forType: .string) == secret { pasteboard.clearContents() }
        }
    }
}
