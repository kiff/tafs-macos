import SwiftUI

/// Members' requests on Plan & usage, as the iPad's `UsageView` helpers (UsageView.swift:187-236).
/// Every line is one both apps share.
extension UsageView {
    /// What someone who doesn't manage billing asks an admin for on this plan, as the iPad's
    /// `asks`: a raise of the spend limit on Company (KIFF's `team`), a pack on Solo while packs
    /// are on sale; nothing on others. `true` is a raise.
    static func asks(_ u: KIFFUsage) -> Bool? {
        switch u.plan {
        case "team": return true
        case "solo": return (u.store?.offered(firstMonth: false).isEmpty ?? true) ? nil : false
        default: return nil
        }
    }

    /// The member's own request still waiting.
    static func waiting(_ u: KIFFUsage, managesBilling: Bool) -> PackRequest? {
        guard !managesBilling else { return nil }
        return u.requests?.first { $0.status == "open" }
    }

    /// The member's request while it waits.
    static func askedLine(_ r: PackRequest, words: Words) -> String {
        words(r.kind == "raise" ? "billing.ask.asked_raise" : "billing.ask.asked_pack")
    }

    /// The member's latest answered request.
    static func lastAnswer(_ u: KIFFUsage, managesBilling: Bool, words: Words) -> String? {
        guard !managesBilling, let r = u.requests?.first else { return nil }
        switch r.status {
        case "approved": return words(r.kind == "raise" ? "billing.ask.raised" : "billing.ask.added_pack")
        case "declined":
            if let note = r.note, !note.isEmpty { return words("billing.ask.declined_note", ["note": note]) }
            return words("billing.ask.declined")
        case "expired": return words("billing.ask.expired")
        default: return nil
        }
    }

    /// An open request, as someone who manages billing reads it: "Someone asks to raise the
    /// spend limit.", "Someone asks for Rayo."
    static func requestLine(_ r: PackRequest, in u: KIFFUsage?, words: Words) -> String {
        r.kind == "raise" ? words("billing.ask.someone_raise") : words("billing.ask.someone_pack", ["pack": packLine(r.pack, in: u, words: words)])
    }

    /// Open requests, for someone who manages billing.
    static func openRequests(_ u: KIFFUsage, managesBilling: Bool) -> [PackRequest] {
        guard managesBilling else { return [] }
        return (u.requests ?? []).filter { $0.status == "open" }
    }

    /// A pack's line, as KIFF sells it; "a pack of credits" when it names none.
    static func packLine(_ id: String?, in u: KIFFUsage?, words: Words) -> String {
        guard let id else { return words("usage.pack_credits") }
        return u?.store?.packs.first { $0.id == id }?.line ?? id.capitalized
    }

    /// "Decline the request to raise the spend limit?", "Decline the request for Rayo?", as the
    /// iPad's `DeclineRequestView.question`.
    static func declineQuestion(_ r: PackRequest, in u: KIFFUsage?, words: Words) -> String {
        r.kind == "raise" ? words("billing.request.decline_raise_title")
            : words("billing.request.decline_pack_title", ["pack": packLine(r.pack, in: u, words: words)])
    }
}

/// Asking an admin, with a reason, for someone who doesn't manage billing, as the iPad's
/// `AskAdminView` (PlanViews.swift:64-133): on Company to raise the spend limit, on Solo for a pack.
struct AskAdminView: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: UsageModel
    /// `true` asks for a raise, `false` for a pack; nil asks for nothing.
    let raise: Bool?
    @State private var pack: String?
    @State private var reason = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(words("usage.requests.ask_admin")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            Text(words(raise == true ? "billing.ask.line_raise" : "billing.ask.line_pack"))
                .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            if raise == false { packs }
            Eyebrow(text: words("usage.requests.why_optional"))
            TextField(words("billing.what_credits"), text: $reason).textFieldStyle(.roundedBorder)
            if let message = model.planMessage {
                Text(verbatim: message).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(words("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(words(sending ? "usage.requests.asking" : "usage.requests.ask")) { ask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(raise == nil || (raise == false && pack == nil) || sending)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.background)
    }

    /// Which pack, as the iPad's: each pack KIFF offers, one chosen.
    private var packs: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: words("usage.requests.which_pack")).padding(.bottom, 6)
            ForEach(model.offeredPacks) { p in
                Button { pack = p.id } label: {
                    HStack {
                        Text(verbatim: p.line).font(.system(size: 14)).foregroundColor(Theme.ink)
                        Spacer()
                        Image(systemName: pack == p.id ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(pack == p.id ? Theme.amber : Theme.dim)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pack == p.id ? .isSelected : [])
            }
        }
    }

    private func ask() {
        guard let raise else { return }
        let chosen = model.offeredPacks.first { $0.id == pack }
        guard raise || chosen != nil else { return }
        sending = true
        Task {
            let asked = await model.askAdmin(raise: raise, pack: chosen, reason: String(reason.prefix(500)))
            sending = false
            if asked { dismiss() }
        }
    }
}

/// Declining a member's request, with a note they'll read, as the iPad's `DeclineRequestView`
/// (PlanViews.swift:135-177).
struct DeclineRequestView: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: UsageModel
    let request: PackRequest
    @State private var note = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: UsageView.declineQuestion(request, in: model.usage, words: words))
                .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Eyebrow(text: words("usage.requests.note_optional"))
            TextField(words("usage.requests.note_hint"), text: $note).textFieldStyle(.roundedBorder)
            if let message = model.planMessage {
                Text(verbatim: message).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(words("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(words(sending ? "usage.requests.declining" : "coach.approval.decline")) { decline() }
                    .disabled(sending)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.background)
    }

    private func decline() {
        sending = true
        // The model owns the decline, so sign-out stops it (`cancelAnswers`).
        model.startDecline(request, note: String(note.prefix(500))) { done in
            sending = false
            if done { dismiss() }
        }
    }
}
