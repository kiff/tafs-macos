import SwiftUI

/// Previous conversations, as the iPad's `SetupChatsList` (SetupChatView.swift:803-857): Coach's
/// past chats, newest first as tafs cloud lists them, each by its title and when it was last
/// written to, the one shown marked; one click reopens it. Done (Esc) closes the list.
struct CoachChatsSheet: View {
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CoachModel
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(words("coach.chats.previous")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(words("record.filter.done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.chats) { chat in
                        Button { open(chat.session) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: chat.title).font(.system(size: 15)).foregroundColor(Theme.ink).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(verbatim: Self.when(chat.updated)).font(.system(size: 12)).foregroundColor(Theme.dim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.chat == chat.session ? Theme.raised : Theme.panel))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.chat == chat.session ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .overlay {
                if model.chats.isEmpty {
                    Text(words("coach.chats.none")).font(.system(size: 14)).foregroundColor(Theme.dim)
                }
            }
        }
        .frame(width: 420, height: 460)
        .background(Theme.background)
        .task { await model.loadChats() }
    }

    /// When a chat was last written to: the date abbreviated and the time short, as the iPad's
    /// `shown(date: .abbreviated, time: .shortened)`.
    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
