import CryptoKit
import Foundation

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

    private let client: KIFFClient
    /// This Mac's device key: the one its session is bound to.
    private(set) var key: SigningKey
    private let approval: ApprovalMeans
    private let sessions: SessionStore
    private let deviceName: String
    private let sleep: (TimeInterval) async throws -> Void
    private let open: (URL) -> Void
    private let now: () -> Date
    private var attempt = 0
    /// Where Export my chats writes its files: removed at every session change, as the iPad's
    /// `removeOpenedFiles` in `useSession` and `forgetSession`, so a person's chats never stay
    /// on the Mac after them.
    var exportFolder = ChatsExport.folder
    /// Ends a session at KIFF, signed in with its own key: for the view-only session a
    /// pairing replaces.
    private let endSession: (Session, SigningKey) async -> Void
    /// Whether the keys are made in the Secure Enclave. Tests say no.
    private let enclave: Bool?

    init(client: KIFFClient, key: SigningKey, approval: ApprovalMeans, sessions: SessionStore, deviceName: String,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         open: @escaping (URL) -> Void, now: @escaping () -> Date = Date.init, enclave: Bool? = nil,
         endSession: @escaping (Session, SigningKey) async -> Void = { _, _ in }) {
        self.endSession = endSession
        self.enclave = enclave
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
            try store.checkWritable([DeviceKey.account, SessionStore.account])
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
            let payload = PairingPayload(deviceKey: pairingKey.publicKeyDER, keyStore: pairingKey.keyStore, approvalKey: approvalDER, name: deviceName,
                                         nonce: nonce, exp: KIFFMessage.time(now().addingTimeInterval(PairingPayload.lifetime)))
            // The check code is made from exactly the keys the code carries.
            let carried = payload.approvalPub == nil ? nil : approvalDER
            step = .pairing(Code(text: try payload.text(), check: Signing.checkCode(deviceKey: pairingKey.publicKeyDER, approvalKey: carried)))
            let proof = try Signing.claimProof(key: pairingKey, nonce: nonce)
            let got = try await Waiting.until(interval: 3, expiresIn: PairingPayload.lifetime, sleep: sleep) {
                guard self.attempt == mine else { throw CancellationError() }
                return try await self.client.claimPairing(nonce: nonce, publicKey: payload.pub, proof: proof)
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
                ChatsExport.removeFiles(in: exportFolder)
                key = pairingKey
                session = got
                step = .welcome
                await endSession(replaced, oldKey)
            } else {
                try finish(got, mine)
            }
        } catch {
            if replaced != nil { DeviceKey.discardNext(in: store) }
            if case KIFFError.expired = error {
                if mine == attempt { step = .codeExpired }
            } else {
                fail(error, mine, pairing: true)
            }
        }
    }

    /// Puts the screen on a step, for a screenshot.
    func show(_ step: Step) { self.step = step }

    /// A pairing is on screen: its code, an expired code, or why it didn't work.
    var isPairing: Bool {
        switch step {
        case .pairing, .codeExpired, .failed(why: _, pairing: true): return true
        default: return false
        }
    }

    /// Back to the start: whatever was waiting stops asking, and a late answer is dropped.
    func cancel() {
        attempt += 1
        step = .welcome
    }

    /// Forgets the session on this Mac. Ending it at KIFF is the caller's, with the session.
    func signedOut() {
        ChatsExport.removeFiles(in: exportFolder)
        sessions.forget()
        session = nil
        step = .welcome
    }

    private func finish(_ got: Session, _ mine: Int) throws {
        guard mine == attempt else { return }
        try sessions.save(got)
        ChatsExport.removeFiles(in: exportFolder)
        session = got
        step = .welcome
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
