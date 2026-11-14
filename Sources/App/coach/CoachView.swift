import SwiftUI

@MainActor
final class CoachModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// Coach hasn't been started on this account.
        case notStarted
        case loaded(Coach, Thread.Page)
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    private let cloud: CloudClient

    init(cloud: CloudClient) { self.cloud = cloud }

    func load() async {
        do {
            guard let coach = try await cloud.coach() else { state = .notStarted; return }
            state = .loaded(coach, try await cloud.thread(of: coach.id))
        } catch {
            state = .unread(why: NeedsYouModel.why(error))
        }
    }
}

/// Coach's chat, to read. Writing to Coach, and answering its cards, arrive in their own
/// pull requests: until then nothing is sent from this screen.
struct CoachView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(words("coach.title")).font(Theme.display(28)).foregroundColor(Theme.coach)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .notStarted:
                    intro
                case .unread(let why):
                    Text(words("coach.conversation_not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(_, let page):
                    if page.items.isEmpty { intro }
                    ForEach(page.items) { item($0) }
                    if page.working {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(words("chat.working")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.coachWash)
        .task { await model.load() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(words("coach.ask_anything")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
            Text(words("coach.ask_anything_line")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }

    @ViewBuilder private func item(_ item: Thread.Item) -> some View {
        switch item {
        case .message(let message, _):
            if message.isNote {
                Text(verbatim: message.text).font(.system(size: 12)).foregroundColor(Theme.dim)
            } else {
                HStack {
                    if message.fromPerson { Spacer(minLength: 80) }
                    // The words are a person's or the model's: plain text, never a line of the app's.
                    Text(verbatim: message.text).font(.system(size: 14)).foregroundColor(message.fromPerson ? Theme.onFill : Theme.ink)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(message.fromPerson ? Theme.coach : Theme.panel))
                    if !message.fromPerson { Spacer(minLength: 80) }
                }
            }
        case .card(_, let waits, _):
            if waits == "owner" { waiting(words("coach.needs_you_question")) }
        case .held:
            waiting(words("coach.needs_you_approve"))
        case .other:
            EmptyView()
        }
    }

    private func waiting(_ line: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(line).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }
}
