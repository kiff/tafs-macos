import AppKit
import SwiftUI

@main
struct TafsApp: App {
    /// The app's language, kept for this Mac and changed from Account › Language.
    @StateObject private var language = AppLanguage()
    @StateObject private var signIn = TafsApp.signInModel(words: Words.load())

    init() {
        // The launch's time, for how long the first window and the first list take.
        _ = LaunchClock.started
    }

    private var words: Words { language.words }

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = signIn.session, !signIn.isPairing {
                    // Every read the window makes is watched: one KIFF or tafs cloud refuses with 401
                    // ends the session once, and sign-in opens (`SessionWatch`).
                    let watch = signIn.sessionWatch(session)
                    // The session's own key: after a pairing it is the new one.
                    SignedInView(account: AccountClient(session: session, key: signIn.key, language: words.language,
                                                        transport: WatchedTransport(inner: NetworkTransport(), watch: watch)),
                                 cloud: CloudClient(transport: WatchedTransport(inner: NetworkTransport(base: URL(string: CloudClient.base)!), watch: watch),
                                                    session: session, language: words.language),
                                 route: ApprovalRoute.of(.passkey, securityKey: securityKey != nil), streamer: NetworkLineStream(),
                                 signedOut: { signIn.signedOut() }, addThisMac: { Task { await signIn.pair() } },
                                 softwareKey: signIn.key.keyStore == "software", deviceKey: signIn.key.publicKeyDER, securityKey: securityKey,
                                 startOn: language.changedIn == session.accessToken ? .account : .overview)
                        // A new language makes every client again, so every request's
                        // Accept-Language follows; the window opens on Account, where it was chosen.
                        .id(session.accessToken + "|" + words.language)
                        .environment(\.languageChooser, language.chooser(session: session.accessToken))
                } else {
                    SignInView(model: signIn)
                }
            }
            // A session just gained, on either path: celebrated once, over home.
            .overlay(Group { if signIn.justConnected { ConnectedView { signIn.celebrated() } } })
            // Then, the first time on this Mac with the new onboarding on, the three cards on how tafs works.
            .overlay(Group { if signIn.showsCards { OnboardingCards { signIn.cardsDone() } } })
            .frame(minWidth: ShellView.minimumSize.width, minHeight: ShellView.minimumSize.height)
            // The iPad's frame at first launch, remembered after (`WindowSize`).
            .background(WindowFrame())
            // The words, mirrored for a language written right to left (`inLanguage`).
            .inLanguage(words)
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
                           // KIFF's sign-in page for the new welcome's Continue (`Onboarding.on`): the system's private sheet.
                           sheet: SystemKIFFSheet(),
                           // Touch ID's ending key, made at sign-in, deleted at sign-out (`EndingKey`).
                           endingKey: EndingKey.hook(store: store),
                           // The view-only session a pairing replaced is ended at KIFF with its own key.
                           endSession: { old, oldKey in
                               try? await AccountClient(session: old, key: oldKey, language: words.language).signOut()
                           })
    }
}
