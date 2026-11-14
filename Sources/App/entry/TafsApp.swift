import AppKit
import SwiftUI

@main
struct TafsApp: App {
    private let words = Words.load()
    @StateObject private var signIn = TafsApp.signInModel(words: Words.load())

    var body: some Scene {
        WindowGroup {
            Group {
                if signIn.session == nil { SignInView(model: signIn) } else { ShellView() }
            }
            .frame(minWidth: ShellView.minimumSize.width, minHeight: ShellView.minimumSize.height)
            .environment(\.words, words)
        }
    }

    /// This Mac's device key, from the Keychain or the Secure Enclave. If neither can keep one,
    /// a key for this launch only: it signs in, and the next launch signs in again.
    private static let key: SigningKey = (try? DeviceKey.load(from: KeychainStore())) ?? SoftwareKey(key: .init())

    /// Signing in on this Mac. It has no approval key yet, so it says it approves on the phone
    /// or with a passkey; Touch ID's approval key arrives in its own pull request.
    @MainActor private static func signInModel(words: Words) -> SignInModel {
        SignInModel(client: KIFFClient(transport: NetworkTransport()), key: key, approval: .passkey,
                    sessions: SessionStore(store: KeychainStore()), deviceName: words("pair.device_name", ["device": words("device.mac")]),
                    open: { NSWorkspace.shared.open($0) })
    }
}
