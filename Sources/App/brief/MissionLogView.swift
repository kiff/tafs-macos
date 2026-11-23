import SwiftUI

/// A mission's log, as the iPad's `MissionLogView` (BriefView.swift:280-325): read only, newest
/// first, by day. Each entry says when, by whom, its kind and its words, with its evidence and
/// value; a removed taf's entries stay, greyed. A sheet of the Mac's own, closed with Esc.
struct MissionLogView: View {
    @Environment(\.words) private var words
    let title: String
    /// The account's time zone, as the Record draws its days.
    var zone: String?
    let load: () async -> MissionLog?
    let close: () -> Void
    /// Ask Coach about the mission, as the iPad's (BriefView.swift:311-315): its title in Coach's box, Coach open. Only
    /// for someone who may use Coach; nil otherwise.
    var askCoach: (() -> Void)? = nil
    @State private var log: MissionLog?
    @State private var read = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !title.isEmpty { Text(verbatim: title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Theme.ink) }
                Spacer()
                Button(words("common.close"), action: close).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(words("mission.read_only")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    if let askCoach {
                        Button(action: askCoach) { Label(words("coach.ask"), systemImage: "sparkle") }
                            .buttonStyle(OutlineButtonStyle(color: Theme.coach))
                            .frame(maxWidth: 220)
                            .accessibilityIdentifier("mission.ask-coach")
                    }
                    if let log {
                        ForEach(MissionLogDays.days(log.items, words: words, time: AccountTime(zone)), id: \.title) { day in
                            Eyebrow(text: day.title)
                            ForEach(day.items) { item in LogRow(item: item, time: AccountTime(zone)) }
                        }
                    } else if read {
                        Text(words("error.ours")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .frame(width: 560, height: 620)
        .background(Theme.background)
        .task {
            log = await load()
            read = true
        }
    }
}

/// The log's entries by day, newest first, as the iPad's `days` (BriefView.swift:315-325): each
/// day titled as the Record titles its days.
enum MissionLogDays {
    struct Day { let title: String; var items: [MissionLog.Item] }

    static func days(_ items: [MissionLog.Item], words: Words, time: AccountTime, now: Date = Date()) -> [Day] {
        var out: [Day] = []
        for item in items {
            let title = time.dayTitle(item.at ?? now, words: words, now: now)
            if out.last?.title == title { out[out.count - 1].items.append(item) } else { out.append(Day(title: title, items: [item])) }
        }
        return out
    }
}

/// One log entry, as the iPad's `LogRow` (BriefView.swift:327-376): who, its kind as a coloured
/// word, the time, its words, its evidence and value.
struct LogRow: View {
    @Environment(\.words) private var words
    let item: MissionLog.Item
    let time: AccountTime

    private var tint: Color {
        switch item.kind {
        case "delivered": return Theme.ok
        case "handed": return Theme.sky
        case "stuck": return Theme.amber
        case "decided": return Theme.ink
        default: return Theme.dim
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(item.removed ? Theme.line : tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: item.by { words($0) }).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    if !item.kindWords.isEmpty {
                        Text(verbatim: item.kindWords).font(.system(size: 11, weight: .medium)).foregroundColor(tint)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.12)))
                    }
                    Spacer()
                    if let at = item.at {
                        Text(verbatim: time.shortTime(at)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim)
                    }
                }
                Text(verbatim: item.words).font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if !item.evidence.isEmpty || item.value != nil { foot }
            }
            .padding(12)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .opacity(item.removed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var foot: some View {
        HStack(spacing: 6) {
            ForEach(item.evidence) { e in
                Text(verbatim: e.words).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.coach)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.coachWash))
            }
            if let value = item.value { Text(verbatim: value).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.ink) }
        }
    }
}
