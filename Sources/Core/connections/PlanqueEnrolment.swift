import Foundation

/// Setting this Mac up with planque, as the iPad's `enrolPlanque` (`AppModel.swift:6267-6310`):
/// planque gets this device's key, and a KIFF key that connects tools and does nothing else,
/// minted with a signed setup call and never kept on this Mac. The caller has set planque's
/// `tenant`, `signer`, `bodyHash` and `transport`, and the account's `sign`: both sign with the
/// device key, which asks no one.
enum PlanqueEnrolment {
    /// Why enrolment stopped. Nothing was minted, or the one key minted went to planque.
    enum Stop: Equatable {
        /// planque's code-less 409: another device connects this account's apps
        /// (`coach.connect_other_device`).
        case otherDevice
        /// KIFF's 403 on the mint: only an admin connects apps (`coach.connect_admin_only`).
        case adminOnly
        /// Anything else: connecting apps isn't set up, with why (`coach.connecting_not_set_up`).
        case notSetUp(why: Why)
        /// The session ended while it ran: nothing more is done or said, as the iPad's
        /// `gen == accountGeneration`.
        case ended

        /// The person's line for it, in the shared words; nil says nothing.
        func words(_ say: Words) -> String? {
            switch self {
            case .otherDevice: return say("coach.connect_other_device")
            case .adminOnly: return say("coach.connect_admin_only")
            case .notSetUp(let why): return say("coach.connecting_not_set_up", ["why": why.words(say)])
            case .ended: return nil
            }
        }
    }

    /// Why enrolment didn't go, as the iPad's `error.localizedDescription` for each error: planque's
    /// own words, else the plain line for its status; KIFF's plain line, never its code.
    enum Why: Equatable {
        case planque(status: Int, words: String?)
        case kiff(status: Int)
        /// Not signed: the step wasn't confirmed (`error.needs_confirmation_first`).
        case notSigning
        /// This device's id couldn't be read (`error.no_device_name`).
        case noDevice
        /// An answer that wasn't in its shape.
        case unreadable
        /// Not reached, with the system's own words.
        case other(String)

        init(_ error: Error) {
            switch error {
            case PlanqueClient.PlanqueError.server(let status, _, let words): self = .planque(status: status, words: words)
            // Only on the first enrolment does `needs_key` mint; on the second it's a refusal like any other.
            case PlanqueClient.PlanqueError.needsKey: self = .planque(status: 409, words: nil)
            case PlanqueClient.PlanqueError.notSigning: self = .notSigning
            case PlanqueClient.PlanqueError.noDevice: self = .noDevice
            // The mint with no device key to sign it: the same as planque with no signer.
            case KIFFError.refused(_, "no_device_key"): self = .notSigning
            case KIFFError.refused(let status, _): self = .kiff(status: status)
            case KIFFError.unreadable: self = .unreadable
            default: self = .other(error.localizedDescription)
            }
        }

        func words(_ say: Words) -> String {
            switch self {
            case .planque(let status, let words): return words ?? say(StepRefusal.plainKey(status: status))
            case .kiff(401): return say("error.signed_out")
            case .kiff(let status): return say(StepRefusal.plainKey(status: status))
            case .notSigning: return say("error.needs_confirmation_first")
            case .noDevice: return say("error.no_device_name")
            case .unreadable: return say("error.ours")
            case .other(let words): return words
            }
        }
    }

    /// Enrols this device with planque, and hands it a fresh connector key only when planque says
    /// it needs one. Nil once done; else why it stopped.
    ///
    /// planque's enrolled connector key, while KIFF still takes it, is kept: asked first with no
    /// key, it answers `kept`, and no key is minted that would only be left live in KIFF (a device
    /// can't revoke a connector key). A key is minted only on `409 needs_key`. Any other answer
    /// (not reached, a 5xx, a refused signature, a 400 for a body it couldn't read) mints nothing:
    /// a second enrolment would likely fail too and leave the key live. It says why, and the next
    /// try asks again.
    static func enrol(planque: PlanqueClient, account: AccountClient, deviceKey: Data) async -> Stop? {
        do {
            let standing = try await planque.enrol(deviceKey: deviceKey, connectorKey: nil)
            guard !Task.isCancelled else { return .ended }
            if standing.kept == true { return nil }
        } catch PlanqueClient.PlanqueError.needsKey {
        } catch PlanqueClient.PlanqueError.server(409, _, _) where planque.lastRefusalCode == nil {
            // A code-less 409 is an older planque's other device; a coded one (a replayed signature,
            // a changed enrolment) says why below, never "another device".
            return .otherDevice
        } catch {
            return .notSetUp(why: Why(error))
        }
        guard !Task.isCancelled else { return .ended }
        do {
            let key = try await account.mintConnectorKey()
            guard !Task.isCancelled else { return .ended }
            _ = try await planque.enrol(deviceKey: deviceKey, connectorKey: key)
        } catch KIFFError.refused(403, _) {
            return .adminOnly
        } catch PlanqueClient.PlanqueError.server(409, _, _) where planque.lastRefusalCode == nil {
            return .otherDevice
        } catch {
            return .notSetUp(why: Why(error))
        }
        guard !Task.isCancelled else { return .ended }
        return nil
    }
}
