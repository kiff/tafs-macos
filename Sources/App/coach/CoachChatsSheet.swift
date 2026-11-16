import SwiftUI

/// Previous conversations, as the iPad's `SetupChatsList` (SetupChatView.swift:800-873): Coach's
/// past chats, newest first as tafs cloud lists them, each by its title and when it was last
/// written to, the one shown marked; one click reopens it. Each can be archived, once the
/// person confirms, and Archived at the end lists those to open or put back
/// (`ArchivedSetupChats`, :875-925). Done (Esc) closes the list.
///
/// A Mac has no swipe: Archive and Put back are each row's own button at its end, and its
/// right-click menu.
struct CoachChatsSheet: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CoachModel
    let open: (String) -> Void
    /// Archived is shown in place of the list.
    @State private var archived: Bool
    /// The conversation waiting for the person's yes to archive it.
    @State private var confirming: CoachChat?
    /// Why the last archive or put-back didn't go through, said in the sheet.
    @State private var notMoved: String?

    init(model: CoachModel, open: @escaping (String) -> Void, archived: Bool = false) {
        self.model = model
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
            if archived { archivedList } else { list }
        }
        .frame(width: 420, height: 460)
        .background(Theme.background)
        .task { await model.loadChats() }
        .confirmationDialog(words("coach.chats.archive_title"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { chat in
            Button(words("coach.chats.archive")) { archive(chat.session) }
            Button(words("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(words("coach.chats.archive_body"))
        }
    }

    /// The sheet's name, with ‹ Back on Archived, and Done.
    private var title: some View {
        HStack(spacing: 10) {
            if archived {
                Button(words("coach.chats.back")) { archived = false; notMoved = nil }.buttonStyle(.plain).foregroundColor(Theme.coach)
            }
            Text(words(archived ? "coach.chats.archived" : "coach.chats.previous")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(words("record.filter.done")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.chats) { chat in
                    ChatRow(chat: chat, shown: model.chat == chat.session, action: words("coach.chats.archive"), symbol: "archivebox",
                            open: { open(chat.session) }, act: { confirming = chat })
                }
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

    private var archivedList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.archivedChats) { chat in
                    ChatRow(chat: chat, shown: false, action: words("coach.chats.put_back"), symbol: "tray.and.arrow.up",
                            open: { open(chat.session) }, act: { putBack(chat.session) })
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

    /// When a chat was last written to: the date abbreviated and the time short, as the iPad's
    /// `shown(date: .abbreviated, time: .shortened)`.
    static func when(_ date: Date, words: Words) -> String {
        AppDates.formatter(words, date: .medium, time: .short).string(from: date)
    }
}

/// One conversation: its title and when, opened by a click, with its one move (Archive, or
/// Put back) as a button at its end and in its right-click menu.
private struct ChatRow: View {
    @Environment(\.words) private var words
    let chat: CoachChat
    let shown: Bool
    let action: String
    let symbol: String
    let open: () -> Void
    let act: () -> Void

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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(shown ? Theme.raised : Theme.panel))
        .contextMenu { Button(action, action: act) }
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}
