import SwiftUI

/// Previous conversations, as the iPad's `SetupChatsList` (SetupChatView.swift:800-873): Coach's
/// past chats, newest first as tafs cloud lists them, each by its title and when it was last
/// written to, the one shown marked; one click reopens it. Each can be archived, once the
/// person confirms, and Archived at the end lists those to open or put back
/// (`ArchivedSetupChats`, :875-925). Done (Esc) closes the list.
///
/// A Mac has no swipe: Archive and Put back are each row's own button at its end, and its
/// right-click menu. Delete conversation sits beside them, in both lists, only in tafs cloud's words and once a read has
/// brought them all (kiff/tafs#2107): its question names the conversation, then says what goes and what stays.
struct CoachChatsSheet: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CoachModel
    /// The watch's conversations, one a day (W11, "From your watch"), after the chats.
    @StateObject private var watch: WatchDaysModel
    let open: (String) -> Void
    /// Archived is shown in place of the list.
    @State private var archived: Bool
    /// A day from the watch, shown in place of the list.
    @State private var watchDay: String?
    /// The conversation waiting for the person's yes to archive it.
    @State private var confirming: CoachChat?
    /// Why the last archive or put-back didn't go through, said in the sheet.
    @State private var notMoved: String?
    /// The conversation waiting for the person's yes to delete it for good.
    @State private var deleting: CoachChat?

    init(model: CoachModel, watch: WatchDaysModel, open: @escaping (String) -> Void, archived: Bool = false) {
        self.model = model
        _watch = StateObject(wrappedValue: watch)
        self.open = open
        _archived = State(initialValue: archived)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            if let notMoved {
                Text(verbatim: notMoved).font(.system(size: 13)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            if let watchDay { WatchDayView(model: watch, date: watchDay) } else if archived { archivedList } else { list }
        }
        .frame(width: 420, height: 460)
        .background(Theme.background)
        .task { await model.loadChats() }
        .task { await watch.load() }
        .confirmationDialog(words("coach.chats.archive_title"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { chat in
            Button(words("coach.chats.archive")) { archive(chat.session) }
            Button(words("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(words("coach.chats.archive_body"))
        }
        .background(EmptyView().confirmationDialog(model.deleteWords?.confirmTitle ?? "",
                                                   isPresented: Binding(get: { deleting != nil && model.deleteWords != nil },
                                                                        set: { if !$0 { deleting = nil } }),
                                                   titleVisibility: .visible, presenting: deleting) { chat in
            if let delete = model.deleteWords {
                Button(delete.confirmButton, role: .destructive) { remove(chat.session) }
            }
            Button(words("common.cancel"), role: .cancel) {}
        } message: { chat in
            Text(verbatim: "\(chat.title)\n\n\(model.deleteWords?.confirmBody ?? "")")
        })
    }

    /// The sheet's name, with ‹ Back on Archived, and Done.
    private var title: some View {
        HStack(spacing: 10) {
            if archived || watchDay != nil {
                Button(words("coach.chats.back")) { archived = false; watchDay = nil; notMoved = nil }.buttonStyle(.plain).foregroundColor(Theme.coach)
            }
            Text(verbatim: heading).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(words("record.filter.done")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// The sheet's name: the day's from the watch, Archived, or Previous conversations.
    private var heading: String {
        if let watchDay { return WatchDays.title(watchDay, today: watch.today, locale: Locale(identifier: words.language), words: words) }
        return words(archived ? "coach.chats.archived" : "coach.chats.previous")
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.chats) { chat in
                    ChatRow(chat: chat, shown: model.chat == chat.session, action: words("coach.chats.archive"), symbol: "archivebox",
                            deleteItem: model.deleteWords?.item,
                            open: { open(chat.session) }, act: { confirming = chat }, delete: { deleting = chat })
                }
                if !watch.days.isEmpty { watchSection }
                Button { archived = true; notMoved = nil } label: {
                    Label(words("coach.chats.archived"), systemImage: "archivebox").font(.system(size: 15)).foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .overlay {
            if model.chats.isEmpty {
                Text(words("coach.chats.none")).font(.system(size: 14)).foregroundColor(Theme.dim)
            }
        }
    }

    /// "From your watch", as the iPad's `WatchDaysSection`: the watch's conversations, one a day, newest first, apart from
    /// the chats started here. Each opens that day, read only.
    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: words("coach.chats.from_your_watch")).padding(.top, 10)
            ForEach(watch.days) { day in
                Button { watchDay = day.date } label: {
                    HStack {
                        Label(WatchDays.title(day.date, today: watch.today, locale: Locale(identifier: words.language), words: words), systemImage: "applewatch")
                            .font(.system(size: 15)).foregroundColor(Theme.ink)
                        Spacer()
                        Text(verbatim: words.number(day.count)).font(.system(size: 13)).foregroundColor(Theme.dim)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("coach.chats.watch")
    }

    private var archivedList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.archivedChats) { chat in
                    ChatRow(chat: chat, shown: false, action: words("coach.chats.put_back"), symbol: "tray.and.arrow.up",
                            deleteItem: model.deleteWords?.item,
                            open: { open(chat.session) }, act: { putBack(chat.session) }, delete: { deleting = chat })
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .overlay {
            if model.archivedChats.isEmpty {
                Text(words("coach.chats.nothing_archived")).font(.system(size: 14)).foregroundColor(Theme.dim)
            }
        }
        .task { await model.loadArchivedChats() }
    }

    private func archive(_ session: String) {
        notMoved = nil
        Task { notMoved = await model.archive(chat: session) }
    }

    private func putBack(_ session: String) {
        notMoved = nil
        Task { notMoved = await model.putBack(chat: session) }
    }

    private func remove(_ session: String) {
        notMoved = nil
        Task { notMoved = await model.delete(chat: session) }
    }

    /// When a chat was last written to: the date abbreviated and the time short, as the iPad's
    /// `shown(date: .abbreviated, time: .shortened)`.
    static func when(_ date: Date, words: Words) -> String {
        AppDates.formatter(words, date: .medium, time: .short).string(from: date)
    }
}

/// One conversation: its title and when, opened by a click, with its one move (Archive, or
/// Put back) as a button at its end and in its right-click menu, and Delete conversation beside it when tafs cloud has
/// sent its words (`deleteItem`).
private struct ChatRow: View {
    @Environment(\.words) private var words
    let chat: CoachChat
    let shown: Bool
    let action: String
    let symbol: String
    /// tafs cloud's "Delete conversation"; nil, and there's no Delete.
    let deleteItem: String?
    let open: () -> Void
    let act: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: chat.title).font(.system(size: 15)).foregroundColor(Theme.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: CoachChatsSheet.when(chat.updated, words: words)).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: act) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
            }
            .buttonStyle(.plain)
            .help(action)
            .accessibilityLabel(action)
            if let deleteItem {
                Button(action: delete) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
                }
                .buttonStyle(.plain)
                .help(deleteItem)
                .accessibilityLabel(deleteItem)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(shown ? Theme.raised : Theme.panel))
        .contextMenu {
            Button(action, action: act)
            if let deleteItem { Button(deleteItem, role: .destructive, action: delete) }
        }
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}

/// One day from the watch, as the iPad's `WatchDayView`: oldest first, each thing said, labelled as sent from the watch,
/// then where it went and what came of it. Read only: a reply goes on in a Coach chat, as any other.
private struct WatchDayView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: WatchDaysModel
    let date: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch model.day {
                case .reading:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                case .failed(let why):
                    Text(verbatim: why).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    Button(words("common.try_again")) { Task { await model.open(date) } }
                case .loaded(let turns):
                    ForEach(turns) { turn in
                        WatchTurnRow(turn: turn).padding(.leading, turn.replyTo == nil ? 0 : 16)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .task(id: date) { await model.open(date) }
        .onDisappear { model.close() }
    }
}

/// One turn, as the iPad's `WatchTurnRow`: "⌚ Sent from your watch" and when, the person's words, then the taf that took
/// it and its line, or tafs cloud's words for where it is.
struct WatchTurnRow: View {
    @Environment(\.words) private var words
    let turn: WatchDays.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(words("coach.chats.sent_from_your_watch"))
                if let at = WatchDays.time(turn.saidAt, locale: Locale(identifier: words.language)) { Text(verbatim: "· " + at) }
            }
            .font(.system(size: 12)).foregroundColor(Theme.dim)
            Text(verbatim: turn.said).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let taf = turn.taf { Text(verbatim: taf.name).font(.system(size: 13, weight: .bold)) }
                Text(verbatim: turn.outcome).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(Theme.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }
}
