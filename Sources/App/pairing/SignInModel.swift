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
    private let key: SigningKey
    private let approval: ApprovalMeans
    private let sessions: SessionStore
    private let deviceName: String
    private let sleep: (TimeInterval) async throws -> Void
    private let open: (URL) -> Void
    private let now: () -> Date
    private var attempt = 0

    init(client: KIFFClient, key: SigningKey, approval: ApprovalMeans, sessions: SessionStore, deviceName: String,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         open: @escaping (URL) -> Void, now: @escaping () -> Date = Date.init) {
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
    func pair() async {
        attempt += 1
        let mine = attempt
        do {
            let nonce = Signing.nonce()
            var approvalDER: Data?
            if case .key(let der) = approval { approvalDER = der }
            let payload = PairingPayload(pub: Encoding.base64URL(key.publicKeyDER), approvalPub: approvalDER.map(Encoding.base64URL),
                                         name: deviceName, kind: approvalDER == nil ? .passkey : .enclave, nonce: nonce,
                                         exp: KIFFMessage.time(now().addingTimeInterval(PairingPayload.lifetime)))
            step = .pairing(Code(text: try payload.text(), check: Signing.checkCode(deviceKey: key.publicKeyDER, approvalKey: approvalDER)))
            let proof = try Signing.claimProof(key: key, nonce: nonce)
            let got = try await Waiting.until(interval: 3, expiresIn: PairingPayload.lifetime, sleep: sleep) {
                guard self.attempt == mine else { throw CancellationError() }
                return try await self.client.claimPairing(nonce: nonce, publicKey: payload.pub, proof: proof)
            }
            try finish(got, mine)
        } catch KIFFError.expired {
            if mine == attempt { step = .codeExpired }
        } catch {
            fail(error, mine, pairing: true)
        }
    }

    /// Puts the screen on a step, for a screenshot.
    func show(_ step: Step) { self.step = step }

    /// Back to the start: whatever was waiting stops asking, and a late answer is dropped.
    func cancel() {
        attempt += 1
        step = .welcome
    }

    /// Forgets the session on this Mac. Ending it at KIFF is the caller's, with the session.
    func signedOut() {
        sessions.forget()
        session = nil
        step = .welcome
    }

    private func finish(_ got: Session, _ mine: Int) throws {
        guard mine == attempt else { return }
        try sessions.save(got)
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
        default: why = error.localizedDescription
        }
        step = .failed(why: why, pairing: pairing)
    }
}
