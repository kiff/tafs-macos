import AppKit
import SwiftUI

@main
struct TafsApp: App {
    private let words = Words.load()
    @StateObject private var signIn = TafsApp.signInModel(words: Words.load())

    init() {
        Words.app = words
        // The launch's time, for how long the first window and the first list take.
        _ = LaunchClock.started
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = signIn.session, !signIn.isPairing {
                    // The session's own key: after a pairing it is the new one.
                    SignedInView(account: AccountClient(session: session, key: signIn.key, language: words.language),
                                 cloud: CloudClient(transport: NetworkTransport(base: URL(string: CloudClient.base)!), session: session, language: words.language),
                                 route: ApprovalRoute.of(.passkey, securityKey: securityKey != nil), streamer: NetworkLineStream(),
                                 signedOut: { signIn.signedOut() }, addThisMac: { Task { await signIn.pair() } },
                                 softwareKey: signIn.key.keyStore == "software", deviceKey: signIn.key.publicKeyDER, securityKey: securityKey)
                        .id(session.accessToken)
                } else {
                    SignInView(model: signIn)
                }
            }
            .frame(minWidth: ShellView.minimumSize.width, minHeight: ShellView.minimumSize.height)
            .environment(\.words, words)
            // The theme the person chose, from the last launch.
            .onAppear { ThemeChoice.saved().apply() }
        }
    }

    /// The security key that goes with this Mac, registered through its pairing: its credential
    /// id, read from the Keychain (`SecurityKeyStore`). Its route is given only once passkey
    /// approvals are on (`ApprovalRoute.of(_:securityKey:)`).
    private var securityKey: Data? { SecurityKeyStore(store: KeychainStore()).load() }

    /// This Mac's device key, from the Keychain or the Secure Enclave. If neither can keep one,
    /// a key for this launch only: it signs in, and the next launch signs in again.
    private static let key: SigningKey = (try? DeviceKey.load(from: KeychainStore())) ?? SoftwareKey(key: .init())

    /// This Mac's keys and session, from the Keychain. A Mac with no Secure Enclave has a
    /// software device key and no approval key: it approves on the phone or with a passkey.
    @MainActor private static func signInModel(words: Words) -> SignInModel {
        let store = KeychainStore()
        return SignInModel(client: KIFFClient(transport: NetworkTransport()), key: key, approval: .passkey,
                           sessions: SessionStore(store: store), deviceName: words("pair.device_name", ["device": words("device.mac")]),
                           open: { NSWorkspace.shared.open($0) },
                           // The security key that goes with this Mac, registered by its pairing once
                           // passkey approvals are on (`PairingSecurityKey.enabled`).
                           securityKey: PairingSecurityKey(words: words, authenticator: FidoKey(), readTries: { try await FidoKey().triesLeft() }),
                           // The view-only session a pairing replaced is ended at KIFF with its own key.
                           endSession: { old, oldKey in
                               try? await AccountClient(session: old, key: oldKey, language: words.language).signOut()
                           })
    }
}
