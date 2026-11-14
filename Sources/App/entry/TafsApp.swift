import AppKit
import SwiftUI

@main
struct TafsApp: App {
    private let words = Words.load()
    @StateObject private var signIn = TafsApp.signInModel(words: Words.load())

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = signIn.session {
                    SignedInView(account: AccountClient(session: session, key: TafsApp.key, language: words.language),
                                 cloud: CloudClient(transport: NetworkTransport(base: URL(string: CloudClient.base)!), session: session, language: words.language),
                                 route: .phoneOrPasskey, signedOut: { signIn.signedOut() })
                        .id(session.accessToken)
                } else {
                    SignInView(model: signIn)
                }
            }
            .frame(minWidth: ShellView.minimumSize.width, minHeight: ShellView.minimumSize.height)
            .environment(\.words, words)
        }
    }

    /// This Mac's device key, from the Keychain or the Secure Enclave. If neither can keep one,
    /// a key for this launch only: it signs in, and the next launch signs in again.
    private static let key: SigningKey = (try? DeviceKey.load(from: KeychainStore())) ?? SoftwareKey(key: .init())

    /// This Mac's keys and session, from the Keychain. A Mac with no Secure Enclave has a
    /// software device key and no approval key: it approves on the phone or with a passkey.
    @MainActor private static func signInModel(words: Words) -> SignInModel {
        let store = KeychainStore()
        return SignInModel(client: KIFFClient(transport: NetworkTransport()), key: key, approval: .passkey,
                           sessions: SessionStore(store: store), deviceName: words("pair.device_name", ["device": words("device.mac")]),
                           open: { NSWorkspace.shared.open($0) })
    }
}
