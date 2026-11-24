import Foundation

/// What a taf's chat draws besides tafs cloud's thread, as the iPad's `chatItems` (AppModel.swift:6211-6290): what
/// became of the calls the owner answered, from the Record, and a door's knocks, each at its own time among the
/// messages. Read only: nothing here answers anything.
enum TafChatTimeline {
    /// One thing placed among the thread's items: the thread's own by its index, or an extra by its index.
    enum Slot: Equatable {
        case item(Int)
        case extra(Int)
    }

    /// The thread's items in tafs cloud's order, with the extras placed by time, as the iPad sorts its chat (by
    /// time, the earlier first; on a tie the thread's own first). An item tafs cloud sends no time for keeps its place
    /// after the one before it. Extras later than every item come last.
    static func placed(items: [Date?], extras: [Date]) -> [Slot] {
        let waiting = extras.enumerated().sorted { a, b in a.element != b.element ? a.element < b.element : a.offset < b.offset }
        var next = 0
        var out: [Slot] = []
        for (i, at) in items.enumerated() {
            if let at {
                while next < waiting.count, waiting[next].element < at {
                    out.append(.extra(waiting[next].offset))
                    next += 1
                }
            }
            out.append(.item(i))
        }
        while next < waiting.count {
            out.append(.extra(waiting[next].offset))
            next += 1
        }
        return out
    }

    /// The Record's lines a taf's chat shows, as the iPad's `chatItems`: a call approved or refused, or one the owner
    /// approved that then wasn't done, is still on its way, or whose outcome is unknown, since the chat's first
    /// message. None before it, and none without one.
    static func outcomes(_ entries: [Record.Entry], since first: Date?) -> [Record.Entry] {
        guard let first else { return [] }
        return entries.filter { entry in
            let shown = entry.kind == "approved" || entry.kind == "refused"
                || (entry.ownerApproved && ["not_done", "sending", "unknown"].contains(entry.kind))
            return shown && entry.at >= first
        }
    }

    /// An outcome's line, as the iPad's `outcomeText`: why it wasn't done in the Record's words; on its way, or not
    /// known; refused and not sent; approved, by the reader when KIFF says the reader answered it.
    static func text(_ entry: Record.Entry, _ words: Words) -> String {
        switch entry.kind {
        case "not_done": return words("chat.outcome.not_done", ["title": entry.title, "detail": entry.detail])
        case "sending": return words("chat.outcome.sending", ["title": entry.title])
        case "unknown": return words("chat.outcome.unknown", ["title": entry.title])
        case "refused": return words("chat.outcome.refused", ["title": entry.title])
        case "approved": return words(entry.answeredByYou ? "chat.outcome.approved" : "chat.outcome.approved_done", ["title": entry.title])
        default: return entry.title
        }
    }

    /// An outcome's tone and mark, as the iPad's `outcomeTone` and `outcomeMark`.
    enum Tone: Equatable { case ok, no, amber, dim }

    static func tone(_ kind: String) -> Tone {
        switch kind {
        case "approved": return .ok
        case "not_done": return .no
        case "sending", "unknown": return .amber
        default: return .dim
        }
    }

    static func mark(_ kind: String) -> String {
        switch kind {
        case "approved": return "checkmark.circle.fill"
        case "sending": return "clock.fill"
        case "unknown": return "questionmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }
}
