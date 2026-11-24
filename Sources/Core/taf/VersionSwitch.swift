import Foundation

/// Installing a version, forward or back, as the iPad's `prepareSwitch` and `useVersion` (`AppModel.swift:4974-5155`):
/// tafs cloud begins the switch, with the KIFF draft that brings the version's Card, if any; the owner reads that Card,
/// now and after; then it's confirmed and tafs cloud makes the version live.
///
/// - **A version that brings a Card:** this Mac reads KIFF's draft itself, and only if it's still the version the owner
///   was shown does the security key confirm it (`KeyAct.confirmDraft`, KIFF's `POST /v1/me/agent-drafts/{id}/confirm`,
///   one of `PhoneApprovalRules`), as the trial's install does. One KIFF already took (confirmed, or its key claimed) isn't
///   confirmed again.
/// - **One that brings none, or whose Card KIFF already took:** the owner confirms (Touch ID or the Mac's password),
///   where the iPad's Face ID signs `tafs.version.v1`, a signature it keeps to itself.
/// - Then tafs cloud's `makeLive`, on the session. A prompt or the key's sheet closed cancels the switch, so the taf runs
///   as it was; a confirm that failed leaves it, to finish or cancel, as on the iPad.
enum VersionSwitch {
    /// What beginning a switch came to.
    enum Prepared: Equatable {
        /// Begun: the owner reads its Card first when it brings one (`switching.draft`).
        case begun(TafVersions.Begun)
        /// A run is in the way: tafs cloud's words, and Stop it and install is offered (kiff/tafs#206).
        case blocked(String)
        case failed(String)
    }

    /// Begins the switch, as the iPad's `prepareSwitch`.
    static func prepare(n: Int, words: Words, begin: () async throws -> TafVersions.Begun) async -> Prepared {
        do {
            return .begun(try await begin())
        } catch let refusal as CloudRefusal where refusal.status == 409 && refusal.blocks {
            return .blocked(refusal.words ?? cantGoLive(n, refusal.why(words), words))
        } catch {
            return .failed(cantGoLive(n, why(error, words), words))
        }
    }

    /// What installing came to.
    enum Done: Equatable {
        case live(TafVersions.Begun)
        /// The version brings a Card no one was shown: it's read first, and nothing is signed.
        case read
        /// The Card changed since it was shown (kiff/tafs#115): it's put on screen again, and the switch cancelled.
        case changed(AccountClient.Draft)
        /// A Card changed since this version's was drafted: KIFF refused it, and Draft its Card again is offered.
        case stale(String)
        /// The prompt or the key's sheet closed: the switch is cancelled, and nothing said.
        case closed
        /// The person is told why; the switch stays, to finish or cancel.
        case failed(String)
    }

    /// Installs version `n`, as the iPad's `useVersion`. `shownDraft` is the version of the draft the owner's screen
    /// showed: the security key confirms exactly that, and a version that brings a Card with nothing shown signs nothing.
    static func use(n: Int, shownDraft: String?, words: Words,
                    begin: () async throws -> TafVersions.Begun,
                    readDraft: (String) async throws -> AccountClient.Draft,
                    confirmOwner: () async throws -> Void,
                    confirm: (KeyAct) async throws -> Data,
                    cancel: () async -> Void,
                    makeLive: () async throws -> Void) async -> Done {
        let begun: TafVersions.Begun
        do { begun = try await begin() } catch {
            return .failed(cantGoLive(n, why(error, words), words))
        }
        var draft: AccountClient.Draft?
        if let id = begun.switching.draft {
            guard shownDraft != nil else { return .read }
            do { draft = try await readDraft(id) } catch {
                return .failed(words("version.card_not_read", ["why": why(error, words)]))
            }
        }
        if let draft, !draft.signed {
            guard draft.version == shownDraft else {
                await cancel()
                return .changed(draft)
            }
            do {
                _ = try await confirm(.confirmDraft(id: draft.id, version: draft.version))
            } catch is CancellationError {
                await cancel()
                return .closed
            } catch is ApproveOnPhone {
                return .failed(words("approval.device_can_not_approve_approve"))
            } catch KIFFError.refused(409, "card_revised") {
                return .stale(words("version.card_out_of_date", ["n": String(n)]))
            } catch {
                return .failed(words("version.install_unconfirmed", ["n": String(n), "why": why(error, words)]))
            }
        } else {
            do { try await confirmOwner() } catch {
                await cancel()
                return error is OwnerPrompt.Closed ? .closed : .failed(words("common.not_sent_unconfirmed"))
            }
        }
        do { try await makeLive() } catch {
            let key = begun.switching.draft == nil ? "version.not_live" : "version.install_unfinished"
            return .failed(words(key, ["n": String(n), "why": why(error, words)]))
        }
        return .live(begun)
    }

    /// The security key's prompt or the owner's, naming the version and the taf.
    static func prompt(n: Int, taf: String, withCard: Bool, words: Words) -> String {
        words(withCard ? "version.prompt.use_with_card" : "version.prompt.use", ["n": String(n), "taf": taf])
    }

    private static func cantGoLive(_ n: Int, _ why: String, _ words: Words) -> String {
        words("version.cant_go_live", ["n": String(n), "why": why])
    }

    /// tafs cloud's words when it sent some, else the app's plain line, as the trial's.
    private static func why(_ error: Error, _ words: Words) -> String {
        if let refusal = error as? CloudRefusal { return refusal.why(words) }
        return CoachStart.why(error, words: words)
    }
}
