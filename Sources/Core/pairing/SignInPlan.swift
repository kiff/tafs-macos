/// What the sign-in window shows in each of its two halves, and when the phone's code is shown by
/// itself (docs/pairing.md, "The screens"): KIFF on the left, the phone on the right.
enum SignInPlan {
    /// The window's step, as `SignInModel` has it, without its data.
    enum Now: Equatable {
        case welcome, browser, pairing, codeExpired
        case failed(pairing: Bool)
    }

    /// The left half: **Sign in with KIFF**.
    enum KIFFHalf: Equatable {
        /// The title and **Continue**.
        case start
        /// The browser's code, and that this Mac is waiting.
        case code
        /// Why it didn't work, and **Try again**.
        case failed
    }

    /// The right half: **Sign in with your phone**.
    enum PhoneHalf: Equatable {
        /// The QR, where to scan it, and the check code.
        case code
        /// A code on its way: shown by itself, with nothing to press.
        case starting
        /// The title and **Continue**: the code is shown when the person asks.
        case offer
        /// Why it didn't work, and **Try again**.
        case failed
    }

    struct Halves: Equatable {
        /// None for a Mac that is signed in and adding itself: only the phone adds it.
        let kiff: KIFFHalf?
        let phone: PhoneHalf
    }

    static func halves(_ now: Now, signedIn: Bool, asksKey: Bool) -> Halves {
        let kiff: KIFFHalf?
        switch now {
        case _ where signedIn: kiff = nil
        case .browser: kiff = .code
        case .failed(pairing: false): kiff = .failed
        default: kiff = .start
        }
        let phone: PhoneHalf
        switch now {
        case .pairing: phone = .code
        case .failed(pairing: true): phone = .failed
        // A sign-in in the browser waits alone: one sign-in at a time.
        case .browser, .failed(pairing: false): phone = .offer
        case .welcome, .codeExpired: phone = showsCode(now, signedIn: signedIn, asksKey: asksKey) || signedIn ? .starting : .offer
        }
        return Halves(kiff: kiff, phone: phone)
    }

    /// Whether the phone's code is shown by itself: when the window opens with no session, and
    /// again, silently, each time a code runs out. Never while the browser's sign-in waits, never
    /// again after a failure (the person tries again), and never when showing it would ask this
    /// Mac's security key first: its PIN sheet is a prompt, so the person asks for the code.
    static func showsCode(_ now: Now, signedIn: Bool, asksKey: Bool) -> Bool {
        guard !asksKey else { return false }
        switch now {
        case .welcome: return !signedIn
        case .codeExpired: return true
        default: return false
        }
    }

    /// One line of the code's panel, in the order drawn.
    enum CodeLine: Equatable {
        case eyebrow(String)
        case code(String)
        /// This Mac's name as it gives it in the QR: its own claim, which the phone shows.
        case name(String)
        case waiting(String)
    }

    /// The code's panel: the check code first, then this Mac's name, as the phone asks about the
    /// code before it shows the name.
    static func codeLines(eyebrow: String, check: String, name: String, waiting: String) -> [CodeLine] {
        [.eyebrow(eyebrow), .code(check), .name(name), .waiting(waiting)]
    }
}
