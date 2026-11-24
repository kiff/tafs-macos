import SwiftUI

/// What a taf's chat draws besides tafs cloud's thread, as the iPad's `chatItems` (AppModel.swift:6211-6290), handed
/// to its `CoachView` by the taf's page: the Record's outcomes of the calls the owner answered and the door's knocks,
/// each at its time among the messages (`TafChatTimeline.placed`), and KIFF's held calls where the taf made them.
struct TafChatExtras {
    /// One thing placed by its time.
    struct Extra {
        let id: String
        let at: Date
        let view: AnyView
    }

    var extras: [Extra] = []
    /// A held call's card in the chat, by KIFF's id for it: nil draws Needs you's line instead.
    var held: (String) -> AnyView? = { _ in nil }

    /// A taf's chat's extras, from what its page has read: the taf's Activity (its Record lines), its doors' open
    /// knocks, and Needs you's held calls. Nothing here answers a call: a held call is answered in Needs you, with
    /// this Mac's key or on the phone.
    @MainActor
    static func of(thread: Thread.Page?, activity: TafActivity?, doors: DoorsModel?, taf: Home.Taf, needsYou: NeedsYouModel?, words: Words) -> TafChatExtras {
        var extras: [Extra] = []
        // The chat's first message: no outcome before it, as the iPad's.
        let first = thread?.items.compactMap { item -> Date? in
            if case .message(let m, _) = item { return m.at }
            return nil
        }.min()
        let entries = activity?.groups.flatMap(\.entries).compactMap(\.record) ?? []
        for entry in TafChatTimeline.outcomes(entries, since: first) {
            extras.append(Extra(id: "o|" + entry.id, at: entry.at, view: AnyView(TafChatOutcomeLine(entry: entry))))
        }
        if let doors {
            for knock in doors.openKnocks {
                extras.append(Extra(id: "d|" + knock.id, at: knock.at, view: AnyView(KnockCard(knock: knock, taf: taf, doors: doors))))
            }
        }
        var made = TafChatExtras(extras: extras)
        if let needsYou {
            made.held = { exception in
                guard case .loaded(let calls) = needsYou.state else { return nil }
                // Answered since: Needs you no longer lists it, and the Record's line says what became of it.
                guard let call = calls.first(where: { $0.id == exception }) else { return AnyView(EmptyView()) }
                return AnyView(TafChatHeldCard(call: call))
            }
        }
        return made
    }
}

/// What became of a call the owner answered, in the taf's chat, as the iPad's `OutcomeLine` with `outcomeText`,
/// `outcomeTone` and `outcomeMark`.
struct TafChatOutcomeLine: View {
    @Environment(\.words) private var words
    let entry: Record.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: TafChatTimeline.mark(entry.kind)).foregroundColor(color).accessibilityHidden(true)
            Text(verbatim: TafChatTimeline.text(entry, words)).font(.system(size: 13)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch TafChatTimeline.tone(entry.kind) {
        case .ok: return Theme.ok
        case .no: return Theme.no
        case .amber: return Theme.amber
        case .dim: return Theme.dim
        }
    }
}

/// A call KIFF holds, where the taf made it in its chat, as the iPad's `HeldCallCard`: what it is, in KIFF's words and
/// the taf's, apart. It's answered in Needs you, with this Mac's key or on the phone, which its line says.
struct TafChatHeldCard: View {
    @Environment(\.words) private var words
    let call: HeldCall

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let amount = call.amount {
                Text(verbatim: amount.written(language: words.language)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
            }
            Text(verbatim: call.summary).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = call.reasonText {
                Text(verbatim: reason).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.amberText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.amber.opacity(0.14)))
            }
            HStack(spacing: 8) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(words("coach.needs_you_approve")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(Theme.amber.opacity(0.5)))
    }
}
