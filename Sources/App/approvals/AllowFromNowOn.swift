import Foundation

/// "Allow this from now on" on a held call (kiff/tafs `docs/allow-from-now-on.md`), as the iPad's `AppModel.allow`,
/// `openAllow`, `roundAllow`, `loadAllow` and `confirmAllow`. tafs cloud makes the offer on the tap; this Mac reads
/// KIFF's draft itself and confirms it with its security key only when it is what was offered.
///
/// KIFF answers a held call inside a draft's confirm only for Coach's install (`confirm_hold.go`): a refund, or any call
/// that moves something, is answered on its own. So the confirm never names the call, and "Let this one go out too"
/// is the call's own Approve once, right after, on the security key again, as Android does: the person approves twice,
/// and each approval says what it does.
struct AllowSheet: Identifiable, Equatable {
    let call: HeldCall
    /// tafs cloud's id for the call's taf.
    let taf: String
    var read: HoldAllow.Read?
    var busy = false
    var error: String?
    /// "Let this one go out too": the held call's own Approve once, once the Card has changed.
    var sendHeld = true
    /// The rounded figure was asked for: the sheet no longer offers to round.
    var rounded = false
    var id: String { call.id }

    var matches: Bool { read?.matches ?? false }
}

@MainActor
extension NeedsYouModel {
    /// "Allow this from now on" on `call`: for someone who manages Cards, on a hold a Card change can lift, from KIFF,
    /// once the service says the feature is live, on a Mac that approves with its security key. Decided from the held
    /// call and the account's capabilities, with no request.
    func offersAllow(_ call: HeldCall, taf: String?, managesCards: Bool, allowIsLive: Bool) -> Bool {
        allowIsLive && managesCards && taf != nil && cloud != nil && approveWithKey != nil && HoldAllow.allowable(call)
    }

    /// "Allow this from now on" tapped: the sheet opens, and tafs cloud makes the offer now.
    func openAllow(_ call: HeldCall, taf: String) {
        allow = AllowSheet(call: call, taf: taf, busy: true)
        Task { await loadAllow(round: false) }
    }

    /// Round up to the figure the offer named: tafs cloud makes the rounded draft, which is shown and checked the same
    /// way. The app never rounds.
    func roundAllow() {
        guard let open = allow, !open.busy else { return }
        allow?.busy = true
        allow?.error = nil
        Task { await loadAllow(round: true) }
    }

    /// tafs cloud's offer for the open sheet's held call, then KIFF's draft, read by this Mac. A late answer for a call
    /// whose sheet is no longer open changes nothing, and rounding up keeps the person's switch.
    @discardableResult
    func loadAllow(round: Bool) async -> Bool {
        guard let open = allow, let cloud else { return false }
        let call = open.call
        do {
            let read = try await HoldAllow.read(offer: { try await cloud.allowOffer(taf: open.taf, exception: call.id, round: $0) },
                                                draft: { try await self.account.draft(id: $0) }, call: call, round: round)
            guard var now = allow, now.call.id == call.id else { return false }
            now.read = read
            now.busy = false
            now.error = nil
            if !round { now.sendHeld = read.answer.offer?.sendHeld ?? true }
            now.rounded = round
            allow = now
            return read.matches
        } catch {
            guard allow?.call.id == call.id else { return false }
            allow?.busy = false
            allow?.error = Words.app("version.card_not_read", ["why": Self.why(error)])
            return false
        }
    }

    /// One approval on the security key: KIFF's draft as this Mac read it, confirmed. The Card changes; then, with the
    /// switch on, the list is read again and the call, if it's still waiting and can be, gets its own Approve once. A
    /// closed sheet sends nothing and says nothing; "Approve on your phone instead" says to approve elsewhere.
    @discardableResult
    func confirmAllow() async -> Bool {
        guard let open = allow, let draft = open.read?.draft, open.matches, !open.busy, !draft.confirmed,
              let approveWithKey else { return false }
        allow?.busy = true
        allow?.error = nil
        do {
            _ = try await approveWithKey(HoldAllow.confirm(draft), Words.app("needs_you.allow_title"))
        } catch is CancellationError {
            if allow?.call.id == open.call.id { allow?.busy = false }
            return false
        } catch {
            if allow?.call.id == open.call.id {
                allow?.busy = false
                allow?.error = error is ApproveOnPhone ? Self.why(error) : Words.app("version.card_not_read", ["why": Self.why(error)])
            }
            return false
        }
        allow = nil
        // The Card changed: Needs you reads again, and the call is answered on its own, as KIFF answers it.
        await load()
        if open.sendHeld, case .loaded(let calls) = state, let now = calls.first(where: { $0.id == open.call.id }), offersApproveOnce(now) {
            await approveOnce(now)
        }
        return true
    }
}
