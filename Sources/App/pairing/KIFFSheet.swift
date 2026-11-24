import AppKit
import AuthenticationServices

/// Where KIFF's sign-in page opens for the in-app sign-in (`AppSignIn`): the address to open, and the address KIFF
/// sent back on the app's own scheme. A test stands in for it.
@MainActor
protocol KIFFSheet {
    func open(_ url: URL, callbackScheme: String) async throws -> URL
}

/// The system's own sign-in sheet (`ASWebAuthenticationSession`, macOS 10.15 and later), as the iPad's
/// `VendorSignIn.kiffSheet()`: a private browser session, so no earlier sign-in or cookie comes in and every authorize
/// goes through KIFF's form. The sheet catches `dev.kiff.tafs:` itself: nothing is registered with macOS for it, so no
/// other app can be handed KIFF's code. Closing it is `AppSignIn.Failure.closed`, which says nothing.
@MainActor
final class SystemKIFFSheet: NSObject, KIFFSheet, ASWebAuthenticationPresentationContextProviding {
    /// The sheet open now, kept until it ends: the system lets go of one nobody holds.
    private var current: ASWebAuthenticationSession?
    /// The window the sheet opens over, read as it opens (on the main actor), for the system's ask, which comes
    /// on the main thread but outside the actor.
    private let anchor = AnchorBox()

    private final class AnchorBox: @unchecked Sendable {
        var window = NSWindow?.none
    }

    /// The one host whose pages this sheet opens: KIFF's sign-in by default, or tafs cloud's for WhatsApp's signup
    /// (`WhatsAppSignup`, made with `CloudClient.base`'s host). Any other address is refused before anything opens.
    private let host: String

    init(host: String = "api.kiff.dev") {
        self.host = host
        super.init()
    }

    func open(_ url: URL, callbackScheme: String) async throws -> URL {
        // Only the one host's own page, over HTTPS.
        guard url.scheme == "https", url.host == host else { throw AppSignIn.Failure.refused("not_kiff") }
        anchor.window = NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { back, error in
                // The sheet has ended: this one holds it no longer (the system calls back on the main thread).
                DispatchQueue.main.async { self.current = nil }
                if let back {
                    continuation.resume(returning: back)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AppSignIn.Failure.closed)
                } else {
                    continuation.resume(throwing: error ?? AppSignIn.Failure.refused("no_answer"))
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            current = session
            if !session.start() {
                current = nil
                continuation.resume(throwing: AppSignIn.Failure.refused("sheet_not_started"))
            }
        }
    }

    /// The sheet opens over the app's window, as it was when the sheet was asked for.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Set before the sheet starts, so the system never asks before it's there.
        anchor.window!
    }
}
