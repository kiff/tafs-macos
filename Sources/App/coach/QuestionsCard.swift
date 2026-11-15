import SwiftUI

/// Several questions Coach asks at once, drawn from its card, as the iPad's `QuestionsCard`
/// (`Views/QuestionsCard.swift`): every question, option and line is Coach's. The app adds two
/// things to every card: "Something else…" under each question, for the person's own words,
/// and "Chat about this", which puts the card away so the person talks it through instead.
struct QuestionsCard: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel
    let card: Thread.Card
    /// Whether this person may use Coach: the model answers only then.
    let mayUseCoach: Bool

    @State private var selection = QuestionSelection()
    @State private var chatting = false

    private var questions: [Thread.Card.Question] { card.questions }

    var body: some View {
        if chatting {
            HStack(spacing: 8) {
                Text(words("coach.questions.talking")).font(.system(size: 13)).foregroundColor(Theme.soft)
                Button(words("coach.questions.show_again")) { chatting = false }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.coach)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let text = card.text, !text.isEmpty {
                    Text(verbatim: text).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Eyebrow(text: card.title ?? words("coach.setup_needs"))
                    Spacer()
                    Text(words("coach.questions.answered_of", ["answered": words.number(answeredCount), "total": words.number(questions.count)]))
                        .font(Theme.mono(12)).foregroundColor(Theme.dim)
                }
                ForEach(Array(questions.enumerated()), id: \.element.id) { i, q in
                    question(q, number: i + 1)
                }
                Divider()
                actions
                // The card's note, as the iPad's `CardNote`: "Your answer didn't reach Setup."
                if let note = model.notAnswered[model.refKey(card)] {
                    Text(verbatim: note).font(.system(size: 12)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        }
    }

    /// Send answers, once every question has one, and Chat about this.
    private var actions: some View {
        HStack(spacing: 12) {
            Button { send() } label: { Text(words(busy ? "coach.answering" : "coach.questions.send")) }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 260)
                .disabled(answeredCount < questions.count || busy)
            Button { chatting = true } label: {
                Label(words("coach.questions.chat_about"), systemImage: "bubble.left")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.coach)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    /// Being answered from this Mac: the card its id names now (`cardRef`).
    private var busy: Bool { model.answering == model.refKey(card) }

    private func question(_ q: Thread.Card.Question, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(number). \(q.text)").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            // Coach's options, then "Something else…", wrapping onto more rows, as the iPad's WrapRow.
            WrapRow(count: q.options.count + 1) { index in
                if index < q.options.count {
                    let o = q.options[index]
                    choice(o.label, detail: o.description, on: selection.picked[q.id]?.contains(o.value) == true) { selection.pick(q, o.value) }
                } else {
                    choice(words("coach.questions.something_else"), detail: nil, on: selection.ownOpen.contains(q.id)) { selection.toggleOwn(q) }
                }
            }
            if selection.ownOpen.contains(q.id) {
                TextField(words("coach.own_answer"), text: Binding(get: { selection.own[q.id] ?? "" }, set: { selection.own[q.id] = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.coach))
                    .accessibilityLabel(words("coach.questions.own_answer_to", ["text": q.text]))
            }
            if let note = q.note, !note.isEmpty {
                Text(verbatim: note).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choice(_ label: String, detail: String?, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.system(size: 15, weight: on ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail).font(.system(size: 12)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundColor(on ? Theme.onFill : Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(on ? Theme.coach : Theme.panel)
            // A rounded rectangle keeps an option that wraps to a second line inside, as the iPad's.
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(on ? Theme.coach : Theme.ink.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var answeredCount: Int { questions.filter { selection.answer($0) != nil }.count }

    private func send() {
        guard let answers = selection.answers(questions) else { return }
        Task { await model.answer(card, questions: answers, mayUseCoach: mayUseCoach) }
    }
}
