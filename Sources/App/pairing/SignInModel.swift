import CryptoKit
import Foundation

/// How a pairing asks this Mac's security key for its credential: through the PIN sheet, in the
/// app's words (kiff/tafs `docs/computer-passkeys.md`, "A security key goes with its computer").
struct PairingSecurityKey {
    let words: Words
    let authenticator: PasskeyAuthenticator
    /// The PIN tries left, read before the PIN is asked.
    let readTries: () async throws -> Int
    /// Only with passkey approvals on (`Features.macPasskeyApprovals`) is the key asked: a key this
    /// Mac couldn't approve with isn't registered for it.
    var enabled = Features.macPasskeyApprovals
    /// Whether the claim proves the credential (`Features.macPairingPasskeyProof`).
    var proving = Features.macPairingPasskeyProof
}

/// Signing in and adding this Mac, step by step, for the screen to draw.
@MainActor
final class SignInModel: ObservableObject {
    /// A pairing's code on screen: the QR code's text, and the 6 characters the phone asks about.
    struct Code: Equatable {
        let text: String
        let check: String
    }

    enum Step: Equatable {
        case welcome
        /// Waiting for the person to approve in their browser, with the code to check.
        case browser(DeviceStart)
        /// Waiting for the phone to scan and approve.
        case pairing(Code)
        /// The pairing's code ran out before the phone approved.
        case codeExpired
        /// It didn't work: KIFF's code or the network's own words, and whether it was a pairing.
        case failed(why: String, pairing: Bool)
    }

    @Published private(set) var step: Step = .welcome
    /// The session, once this Mac has one.
    @Published private(set) var session: Session?
    /// The security key's PIN sheet, while a pairing asks the key for its credential.
    @Published var pinSheet: PINSheetModel?
    /// A session was just gained, on either path: the window celebrates it once, over home
    /// (`ConnectedView`), until the person moves on. Never set by a session kept from the last launch.
    @Published var justConnected = false

    // MARK: The new onboarding's welcome (`Onboarding.on`, docs/pairing.md, "Signing in inside the app")

    /// The welcome's one tick for the Terms: Continue, and the phone's code, wait on it.
    @Published var tick = ConsentTick()
    /// The Terms version in force, read as the tick shows: the one sent with the sign-in is the one the person saw.
    @Published private(set) var termsVersion: String?
    /// KIFF said the Terms changed since the tick: the box is unticked, and the welcome says why.
    @Published private(set) var termsChanged = false
    /// Why the last in-app sign-in didn't work; nil when the sheet was closed, or nothing went wrong.
    @Published private(set) var problem: String?
    /// The three cards on how tafs works, over the window after the celebration: once on this Mac, with the onboarding on.
    @Published private(set) var showsCards = false
    /// Where this Mac keeps that the cards were seen (`Onboarding.cardsSeenKey`).
    var cardsSeen: UserDefaults = .standard
    /// KIFF's sign-in is open in the system's sheet, or its session is being made.
    @Published private(set) var signingInApp = false
    /// Whether the welcome is the new onboarding's: `Onboarding.on`, or a test's say.
    let onboarding: Bool
    /// Where KIFF's sign-in page opens: the system's private sheet, or a test's stand-in.
    private let sheet: KIFFSheet?
    /// A code KIFF refused only for changed Terms, kept so the new tick sends it again with the new version without
    /// opening KIFF's page twice, as the iPad's: only within `AppSignIn.codeLifetime`, and only for that refusal.
    private var keptCode: (code: String, verifier: String, at: Date)?

    private let client: KIFFClient
    /// This Mac's device key: the one its session is bound to.
    private(set) var key: SigningKey
    private let approval: ApprovalMeans
    private let sessions: SessionStore
    /// The name this Mac gives itself in the QR: the phone shows it as this Mac's own claim.
    let deviceName: String
    private let sleep: (TimeInterval) async throws -> Void
    private let open: (URL) -> Void
    private let now: () -> Date
    private var attempt = 0
    /// The screen is a still picture (`show`): nothing starts by itself.
    private var still = false
    /// Where Export my chats writes its files: removed at every session change, as the iPad's
    /// `removeOpenedFiles` in `useSession` and `forgetSession`, so a person's chats never stay
    /// on the Mac after them.
    var exportFolder = ChatsExport.folder
    /// Where the list last read is kept: an earlier session's tafs never show in this one, so
    /// it's forgotten with each session kept or ended, as the iPad's `useSession` and
    /// `forgetSession` (AppModel.swift:868, 1323).
    var rememberedList: UserDefaults = .standard
    /// Ends a session at KIFF, signed in with its own key: for the view-only session a
    /// pairing replaces.
    private let endSession: (Session, SigningKey) async -> Void
    /// Whether the keys are made in the Secure Enclave. Tests say no.
    private let enclave: Bool?
    /// This Mac's security key, for a pairing to register; nil asks no key.
    private let securityKey: PairingSecurityKey?
    /// The ending key's hook (`EndingKeyHook`): told when a session is kept, to make this sign-in's
    /// ending key, and when it's forgotten, to delete it. It asks nothing and never fails a sign-in.
    private let endingKey: EndingKeyHook
    /// The last attempt's credential, with the device key it was made for: a new code uses it again
    /// when the claim doesn't prove it, so the key isn't asked again (Windows' `PairingAttempt`).
    private var kept: (passkey: PairingPasskey, deviceKey: Data)?

    init(client: KIFFClient, key: SigningKey, approval: ApprovalMeans, sessions: SessionStore, deviceName: String,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         open: @escaping (URL) -> Void, now: @escaping () -> Date = Date.init, enclave: Bool? = nil,
         securityKey: PairingSecurityKey? = nil, sheet: KIFFSheet? = nil, onboarding: Bool = Onboarding.on,
         endingKey: EndingKeyHook = .none,
         endSession: @escaping (Session, SigningKey) async -> Void = { _, _ in }) {
        self.endSession = endSession
        self.endingKey = endingKey
        self.sheet = sheet
        self.onboarding = onboarding
        self.enclave = enclave
        self.securityKey = securityKey
        self.client = client; self.key = key; self.approval = approval; self.sessions = sessions
        self.deviceName = deviceName; self.sleep = sleep; self.open = open; self.now = now
        session = sessions.load()
    }

    /// Signs in through the browser: the account's first device, or a view-only session.
    func signIn() async {
        attempt += 1
        let mine = attempt
        do {
            let start = try await client.startSignIn(publicKey: key.publicKeyDER, keyStore: key.keyStore, name: deviceName, approval: approval)
            guard mine == attempt else { return }
            step = .browser(start)
            // Only KIFF's own page is ever opened, over HTTPS.
            if let url = URL(string: start.verificationURIComplete), url.scheme == "https", url.host?.hasSuffix("kiff.dev") == true { open(url) }
            let got = try await Waiting.until(interval: TimeInterval(start.interval), expiresIn: TimeInterval(start.expiresIn), sleep: sleep) {
                guard self.attempt == mine else { throw CancellationError() }
                return try await self.client.token(deviceCode: start.deviceCode)
            }
            try finish(got, mine)
        } catch {
            fail(error, mine, pairing: false)
        }
    }

    /// Shows a pairing code and waits for a phone that can approve to sign this Mac's keys.
    ///
    /// A Mac that is already signed in (view-only) pairs with a **new** device key: KIFF
    /// refuses a pairing for a key that is already a device's. Its view-only session is signed
    /// out by this Mac only after the pairing is claimed; if the pairing doesn't happen, the
    /// new key is forgotten and the session it had stays as it was.
    func pair() async {
        attempt += 1
        let mine = attempt
        let replaced = session
        let store = sessions.store
        do {
            try store.checkWritable([DeviceKey.account, SessionStore.account, SecurityKeyStore.account])
            let pairingKey: SigningKey
            if replaced == nil {
                pairingKey = key
            } else if let enclave {
                pairingKey = try DeviceKey.makeNext(in: store, enclave: enclave)
            } else {
                pairingKey = try DeviceKey.makeNext(in: store)
            }
            let nonce = Signing.nonce()
            var approvalDER: Data?
            if case .key(let der) = approval { approvalDER = der }
            let exp = KIFFMessage.time(now().addingTimeInterval(PairingPayload.lifetime))
            let offer = try await passkeyOffer(approvalKey: approvalDER, pairingKey: pairingKey, nonce: nonce, exp: exp)
            guard mine == attempt else {
                if replaced != nil { DeviceKey.discardNext(in: store) }
                return
            }
            let payload = offer?.payload
                ?? PairingPayload(deviceKey: pairingKey.publicKeyDER, keyStore: pairingKey.keyStore, approvalKey: approvalDER, name: deviceName,
                                  nonce: nonce, exp: exp)
            // The check code is made from exactly the keys the code carries.
            step = .pairing(Code(text: try payload.text(), check: Signing.checkCode(deviceKey: pairingKey.publicKeyDER, approvalKey: payload.checkedKeyDER)))
            let proof = try Signing.claimProof(key: pairingKey, nonce: nonce)
            let got = try await Waiting.until(interval: 3, expiresIn: PairingPayload.lifetime, sleep: sleep) {
                guard self.attempt == mine else { throw CancellationError() }
                return try await self.client.claimPairing(nonce: nonce, publicKey: payload.pub, proof: proof,
                                                          credentialProof: offer?.claimProof,
                                                          termsVersion: self.onboarding ? self.termsVersion : nil)
            }
            guard mine == attempt else {
                if replaced != nil { DeviceKey.discardNext(in: store) }
                return
            }
            if let replaced {
                // The new session is in hand: keep it and its key first, then end the old one.
                let oldKey = key
                try DeviceKey.promoteNext(in: store)
                try sessions.save(got)
                // This sign-in's ending key, made for the new device key; the old one's is deleted.
                endingKey.kept(got, pairingKey.keyStore)
                ChatsExport.removeFiles(in: exportFolder)
                RememberedHome.forget(in: rememberedList)
                key = pairingKey
                session = got
                step = .welcome
                justConnected = true
                // Last, once the screen holds what the store holds: it can't throw past this step.
                keepSecurityKey(offer, granted: got)
                await endSession(replaced, oldKey)
            } else {
                try finish(got, mine)
                keepSecurityKey(offer, granted: got)
            }
        } catch {
            if replaced != nil { DeviceKey.discardNext(in: store) }
            if case KIFFError.expired = error {
                if mine == attempt { step = .codeExpired }
            } else if case KIFFError.termsOutdated = error, mine == attempt {
                // As Continue does: the box unticked, why, and the new version for the new tick.
                await termsChangedSinceTick()
                step = .welcome
            } else {
                fail(error, mine, pairing: true)
            }
        }
    }

    /// The celebration's Let's go: then the three cards, the first time on this Mac with the onboarding on.
    func celebrated() {
        justConnected = false
        showsCards = Onboarding.showsCards(on: onboarding, seen: cardsSeen.bool(forKey: Onboarding.cardsSeenKey))
    }

    /// Get started or Skip on the cards: seen on this Mac, and How tafs works opens them again.
    func cardsDone() {
        cardsSeen.set(true, forKey: Onboarding.cardsSeenKey)
        showsCards = false
    }

    /// Reads the Terms version in force as the welcome shows its tick. Unreadable, it's read again at Continue or at
    /// the phone's code, and nothing is sent without one: consent is never skipped.
    func readTerms() async {
        guard onboarding, termsVersion == nil else { return }
        termsVersion = try? await client.appTerms()
    }

    /// Ticks or unticks the box. Unticked, the phone's code waits again; ticked, it's shown.
    func toggleTick() async {
        tick.toggle()
        if tick.canContinue { termsChanged = false }
        if !tick.canContinue, isPairing { cancel() }
        await showPhoneCode()
    }

    /// Continue: KIFF's sign-in in the system's sheet (`AppSignIn`), the code traded at KIFF's app token route with its
    /// verifier and the ticked Terms version, then the session as any sign-in's (the celebration, then the cards). The
    /// sheet closed or KIFF's page declined leave the welcome as it was; Terms that changed since the tick untick the box.
    func signInInApp(language: String) async {
        guard onboarding, tick.canContinue, !signingInApp, let sheet else { return }
        problem = nil
        termsChanged = false
        signingInApp = true
        attempt += 1
        let mine = attempt
        var pending: (code: String, verifier: String, at: Date)?
        do {
            if termsVersion == nil { termsVersion = try await client.appTerms() }
            guard let version = termsVersion else { throw KIFFError.unreadable }
            if let kept = keptCode, now().timeIntervalSince(kept.at) < AppSignIn.codeLifetime {
                pending = kept
            } else {
                let pkce = AppSignIn.PKCE.make(), state = AppSignIn.makeState()
                let url = AppSignIn.authorizeURL(base: URL(string: "https://api.kiff.dev")!, challenge: pkce.challenge(sha256: Self.sha256),
                                                 state: state, language: language)
                let back = try await sheet.open(url, callbackScheme: AppSignIn.callbackScheme)
                pending = (try AppSignIn.code(from: back, state: state), pkce.verifier, now())
            }
            keptCode = nil
            guard mine == attempt, let pending else { return }
            let got = try await client.appToken(code: pending.code, verifier: pending.verifier, termsVersion: version,
                                                publicKey: key.publicKeyDER, keyStore: key.keyStore, name: deviceName, approval: approval)
            try finish(got, mine)
        } catch {
            guard mine == attempt else { return }
            if case KIFFError.termsOutdated = error {
                // KIFF refuses the Terms before it spends the code: kept, for the new tick.
                keptCode = pending
                await termsChangedSinceTick()
            } else {
                keptCode = nil
                problem = AppSignIn.why(error, words: Words.app)
            }
        }
        if mine == attempt { signingInApp = false }
    }

    /// The Terms changed since the tick: unticked, said, and the new version read for the new tick.
    private func termsChangedSinceTick() async {
        tick = ConsentTick()
        termsChanged = true
        termsVersion = try? await client.appTerms()
    }

    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// Puts the screen on a step, for a screenshot: a still picture, so the phone's code isn't
    /// started by itself.
    func show(_ step: Step) {
        still = true
        self.step = step
    }

    /// Whether showing the phone's code asks this Mac's security key first (its PIN sheet): then
    /// the code is shown only when the person asks, never by itself.
    var asksKey: Bool { securityKey?.enabled == true }

    /// The step, without its data, for the plan of the window (`SignInPlan`).
    var phase: SignInPlan.Now {
        switch step {
        case .welcome: return .welcome
        case .browser: return .browser
        case .pairing: return .pairing
        case .codeExpired: return .codeExpired
        case .failed(_, let pairing): return .failed(pairing: pairing)
        }
    }

    /// Shows the phone's code by itself when the plan says so: when the window opens, and again,
    /// silently, each time a code runs out. Showing and renewing it signs only with the device
    /// key, which asks for nothing (`Signing.claimProof`).
    func showPhoneCode() async {
        guard !still, pinSheet == nil, SignInPlan.showsCode(phase, signedIn: session != nil, asksKey: asksKey) else { return }
        // The new welcome: the phone's code waits on the tick, and carries the version it agreed to, read now if it
        // couldn't be when the welcome showed. Without one, nothing is shown and the welcome says signing in didn't work.
        if onboarding, session == nil {
            guard tick.canContinue else { return }
            if termsVersion == nil { termsVersion = try? await client.appTerms() }
            guard termsVersion != nil else { problem = Words.app("sign_in.didnt_work"); return }
        }
        await pair()
    }

    /// A pairing is on screen: its code, an expired code, why it didn't work, or the security key's
    /// PIN sheet before the code (so a view-only Mac adding itself sees the sheet over this screen).
    var isPairing: Bool {
        if pinSheet != nil { return true }
        switch step {
        case .pairing, .codeExpired, .failed(why: _, pairing: true): return true
        default: return false
        }
    }

    /// Back to the start: whatever was waiting stops asking, and a late answer is dropped. A PIN
    /// sheet still open closes, and nothing is asked of the key.
    func cancel() {
        attempt += 1
        pinSheet?.cancel()
        step = .welcome
    }

    /// One attempt's offer with this Mac's security key (`SecurityKeyPairing.offer`), or nil when no
    /// key is asked: a Mac with an approval key, no key given, or passkey approvals off.
    private func passkeyOffer(approvalKey: Data?, pairingKey: SigningKey, nonce: String, exp: String) async throws -> PasskeyPairingOffer? {
        guard approvalKey == nil, let securityKey, securityKey.enabled else { return nil }
        let deviceKey = pairingKey.publicKeyDER, name = SecurityKeyPairing.userName(email: nil, macName: deviceName)
        let offer = try await SecurityKeyPairing.offer(
            deviceKeyDER: deviceKey, keyStore: pairingKey.keyStore, name: deviceName, nonce: nonce, exp: exp,
            kept: kept?.deviceKey == deviceKey ? kept?.passkey : nil, proving: securityKey.proving,
            make: { challenge in
                try await self.askKey(securityKey) { pin in
                    try await SecurityKeyPairing.make(challenge: challenge, deviceKeyDER: deviceKey, name: name,
                                                      authenticator: securityKey.authenticator, pin: pin,
                                                      sha256: PasskeyCrypto.sha256, isOnCurve: P256Curve.contains,
                                                      enabled: securityKey.enabled)
                }
            },
            sha256: PasskeyCrypto.sha256, random: { Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }) })
        kept = offer.passkey.map { (passkey: $0, deviceKey: deviceKey) }
        return offer
    }

    /// Asks the security key through the PIN sheet, as many tries as the person makes: it answers
    /// once the key made the credential, or throws `CancellationError` once the sheet is closed. A
    /// sheet already up is closed first, so its own ask resumes (as cancelled) and never hangs.
    func askKey(_ key: PairingSecurityKey, _ ask: @escaping (SecurityKeyPIN) async throws -> PairingPasskey) async throws -> PairingPasskey {
        pinSheet?.cancel()
        return try await withCheckedThrowingContinuation { continuation in
            var answer: PairingPasskey?
            pinSheet = PINSheetModel(words: key.words, purpose: .addKey, attempt: { pin in answer = try await ask(pin) }, readTries: key.readTries,
                                     done: { [weak self] error in
                                         self?.pinSheet = nil
                                         if let error { continuation.resume(throwing: error) }
                                         else if let answer { continuation.resume(returning: answer) }
                                         else { continuation.resume(throwing: CancellationError()) }
                                     })
        }
    }

    /// Once a pairing is claimed, last of all: the credential its QR named is kept as the security
    /// key that goes with this Mac; with none, any earlier one is forgotten, as it went with another
    /// device key. A store that refuses it (checked writable before the code, so not expected) keeps
    /// none: this Mac then approves on the phone, and the pairing stands as the screen shows it.
    /// Keeps the pairing's security key for this Mac, only when KIFF's claim granted `passkey`: any other answer
    /// keeps none, and this Mac stays view-only. The app never claims more than KIFF granted (kiff/cloud#96).
    private func keepSecurityKey(_ offer: PasskeyPairingOffer?, granted: Session) {
        let keys = SecurityKeyStore(store: sessions.store)
        guard let id = offer?.keptCredentialID, granted.approvalMode == "passkey" else { return keys.forget() }
        do { try keys.save(id) } catch { keys.forget() }
    }

    /// The watch on the signed-in window's reads, for the session it was made for.
    private var watching: SessionWatch?

    /// The watch for `session`'s window: the same one while the session is, so a window rebuilt
    /// (a new language) keeps it.
    func sessionWatch(_ session: Session) -> SessionWatch {
        if let watching, watching.token == session.accessToken { return watching }
        let token = session.accessToken
        // Held weakly through a box, a constant: Swift 5.7 refuses a weak `self` in a `@Sendable` closure.
        let me = WeakBox(self)
        let watch = SessionWatch(token: token) {
            Task { @MainActor in me.object?.sessionRefused(token) }
        }
        watching = watch
        return watch
    }

    /// KIFF refused the stored sign-in (`SessionWatch`): it's forgotten, as Sign out forgets it, and
    /// sign-in opens. Nothing is ended at KIFF, which already ended it. A session that has moved
    /// on since (a new pairing) stays.
    func sessionRefused(_ token: String) {
        guard session?.accessToken == token else { return }
        signedOut()
    }

    /// Forgets the session on this Mac, and the security key and ending key that went with it. Ending it at KIFF
    /// is the caller's, with the session.
    func signedOut() {
        ChatsExport.removeFiles(in: exportFolder)
        // Files' private copies go with the session, open or not.
        FilesModel.clearCopies()
        RememberedHome.forget(in: rememberedList)
        SecurityKeyStore(store: sessions.store).forget()
        endingKey.forgotten()
        sessions.forget()
        session = nil
        justConnected = false
        showsCards = false
        // The next sign-in starts at an unticked box, with the Terms read again.
        tick = ConsentTick()
        termsVersion = nil
        termsChanged = false
        problem = nil
        keptCode = nil
        step = .welcome
    }

    private func finish(_ got: Session, _ mine: Int) throws {
        guard mine == attempt else { return }
        try sessions.save(got)
        // This sign-in's ending key, next to its session: made or not, the sign-in goes on.
        endingKey.kept(got, key.keyStore)
        ChatsExport.removeFiles(in: exportFolder)
        RememberedHome.forget(in: rememberedList)
        session = got
        step = .welcome
        justConnected = true
    }

    private func fail(_ error: Error, _ mine: Int, pairing: Bool) {
        guard mine == attempt, !(error is CancellationError) else { return }
        let why: String
        switch error {
        case KIFFError.refused(_, let code) where !code.isEmpty: why = code
        case KIFFError.refused(let status, _): why = String(status)
        case let error as KIFFError: why = String(describing: error)
        // The Keychain's status number alone: never the item, and never the error's type.
        case let refused as KeychainStore.Refused: why = String(refused.status)
        default: why = error.localizedDescription
        }
        step = .failed(why: why, pairing: pairing)
    }
}
