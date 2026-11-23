import Foundation

/// A chat with Coach or a taf, as tafs cloud orders it (`GET /v1/tafs/{id}/conversation`):
/// one list of messages, cards and held calls by time. The app draws the list as it comes,
/// and places or folds nothing itself.
enum Thread {
    struct Message: Equatable {
        /// tafs cloud's id for it, when it sends one.
        let id: String?
        let at: Date?
        /// `owner` (the person) or `taf`.
        let from: String
        /// `kickoff` (a job's instruction, shown as a small note) or `message`.
        let kind: String
        let text: String
        /// What the run did before these words: how long it worked, and its steps.
        var work: Work?
        /// The chat it's in, as tafs cloud names it: a report of it names the chat too.
        var session: String? = nil
        /// The files sent with it, by name, as the iPad's `ChatMessage.attachments`.
        var attachments: [AttachmentRef] = []
        /// On a job run's report: where its result went, in tafs cloud's words ("Sent to Google Sheets · Refunds 2026"),
        /// as the iPad's `delivered`. Drawn as written, above the taf's words; none where tafs cloud sends none or a blank.
        var delivered: String? = nil
        /// On a run's last message: what the run did, counted from the record, in tafs cloud's words ("From the record:
        /// 5 done · 1 refused"), as the iPad's `counted`. Drawn as written, under the taf's words. This app counts nothing.
        var counted: String? = nil
        /// A connection its work asked for that the connection server refused, as the iPad's `refused`: tafs cloud's
        /// lines, drawn under the taf's words, never folded.
        var refused: Refused? = nil

        var fromPerson: Bool { from == "owner" }
        var isNote: Bool { kind == "kickoff" }

        /// tafs cloud's lines around a taf's words, as the iPad's `runLines`: where the run's result went above, what
        /// the run did under. The person's message and a run's kickoff have none.
        var runLines: (above: String?, under: String?) {
            guard from == "taf", !isNote else { return (nil, nil) }
            return (delivered, counted)
        }

        /// The refused connection drawn under a taf's words, as the iPad's `refusedLines`: none on the person's message
        /// or a run's kickoff.
        var refusedLines: Refused? { from == "taf" && !isNote ? refused : nil }

        /// A refused connection's lines, each tafs cloud's words, as the iPad's `ChatMessage.Refused`: the step's
        /// ("Coach couldn't connect Shippo yet"), the server's reason, and what to do next.
        struct Refused: Equatable {
            let words: String
            let why: String?
            let next: String
            /// Its lines, in order, the blank ones left out.
            var lines: [String] { [words, why ?? "", next].compactMap(Message.line) }
        }

        /// One of tafs cloud's lines as the app draws it, as the iPad's `ChatMessage.line`: as written, without the
        /// space around it; none for a blank one.
        static func line(_ words: String?) -> String? {
            guard let trimmed = words?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }

    /// A run's work, on its first message: the time from its start to its last words, and the
    /// steps it took, in tafs cloud's words. A step with no words isn't shown; its tool's name
    /// never is.
    struct Work: Equatable {
        struct Step: Equatable {
            let words: String
            let failed: Bool
            /// tafs cloud's one line of why it failed.
            let why: String?
            /// Refused back unmade: nothing reached KIFF or the app, so it isn't a failure.
            let notMade: Bool
        }
        let ms: Int
        let steps: [Step]

        /// How long it worked, in the shared words by the iPad's rule: "32 s" under a minute,
        /// else "1 min 59 s".
        func took(_ words: Words) -> String {
            let seconds = max(1, Int((Double(ms) / 1000).rounded()))
            if seconds < 60 { return words("work.duration.seconds", ["seconds": String(seconds)]) }
            return words("work.duration.minutes", ["minutes": String(seconds / 60), "seconds": String(seconds % 60)])
        }
    }

    /// A card Coach or a taf showed. The run pauses on one that waits, and its answer goes
    /// back as data, never as text in the chat.
    struct Card: Equatable {
        struct Option: Equatable {
            let label: String
            let value: String
        }
        /// Unique in the thread: a card is known by it, never only by the name the model gave it.
        let key: String
        /// When it was shown, as tafs cloud keeps it.
        var at: Date?
        /// The name the model gave it: what an answer is sent to.
        let id: String
        /// `confirm`, `questions`, `approval`, `sign_in`, or a kind that only shows something.
        let type: String
        /// The chat it is in.
        let session: String?
        let title: String?
        let text: String?
        let options: [Option]
        /// `owner` when its run waits on the person; `service` when tafs cloud answers it.
        let waits: String?
        /// tafs cloud's answer to it: `answered`, `wrote` (the person wrote past it) or
        /// `no_answer` (it stopped waiting). Nil while none is recorded.
        let answerState: String?
        /// What was answered, in tafs cloud's words: only for an answer the person chose.
        let answered: String?
        /// A plan's steps (`steps`): each with its label and whether it is done.
        var plan: [PlanStep] = []
        /// `info`, `success`, `warning` or `error`, for a notice.
        var tone: String?
        /// tafs cloud's line for a plan ("Done · 2 of 2", "Step 2 of 3: …").
        var planLine: String?
        /// The taf a hand-over (`result`) is about: its name, and its KIFF agent.
        var tafName: String?
        var tafAgent: String?
        /// The tafs cloud id of the taf a result is the next version of (`taf.improves`), as the
        /// iPad's `SetupComponent.Taf.improves`: an improvement, never a new taf.
        var improves: String?
        /// What changed, in the owner's language (`taf.note`), on an improvement.
        var tafNote: String?
        /// What came of a hand-over, once tafs cloud answered it.
        var outcome: Outcome?
        /// The tools a hand-over lists, in KIFF's words for them.
        var tools: [String] = []
        /// On an approval whose connection is already made: tafs cloud's line for it.
        var connectionWords: String?
        /// tafs cloud marks the card's connection made (`connection.done`), with words or not:
        /// planque shows it connected, so its sign-in finished (`ConnectReceipt`).
        var connected = false
        /// A sign-in's app, as tafs cloud names it ("Google Sheets"); nil when it names none.
        var service: String?
        /// A card's note under its words, as Coach wrote it.
        var note: String?
        /// A card's own words for its yes and its no, as tafs cloud sends them.
        var yes: String?
        var no: String?
        /// tafs cloud's words for a sign-in wider than the job (`wider: {words}`, in the reader's
        /// language, as sent): the app's sign-in can't be narrowed to what the taf uses, so it asks
        /// for more access than the job. Drawn above an approval's or a sign-in's buttons, as the
        /// iPad's `SetupComponent.widerWords`. None when tafs cloud doesn't say, says it blank, or
        /// in another shape: that is no line, never a card unread.
        var widerWords: String?
        /// A questions card's questions, each Coach's own (`Question`). A card whose questions, or
        /// any one of them, don't read isn't read at all, as the iPad's `LenientShown`.
        var questions: [Question] = []
        /// planque's grant an approval or a sign-in asks about (`grant`), as the iPad's
        /// `SetupComponent.grant`: what a newer request for the same connection is known by.
        var grant: String? = nil
        /// KIFF's draft of the taf's Cards an approval signs (`draft`), as the iPad's
        /// `SetupComponent.draft`: read from KIFF by this id (`AccountClient.draft(id:)`).
        var draft: String? = nil
        /// tafs cloud's mark of what an approval's fingerprint covers (`signs`), as the iPad's
        /// `SetupComponent.Signs`; nil from a tafs cloud that doesn't say.
        var signs: Signs? = nil
        /// An approval's answer as tafs cloud stores it, settled and in no language (`answer.answer`):
        /// `approved`, `already approved`, `connected`, `declined` or `failed: <why>`, as the iPad's
        /// `CardAnswer.answer`. Nil from a tafs cloud that doesn't send it.
        var stored: String? = nil

        /// tafs cloud's mark on an approval (`signs`), read leniently as the iPad's
        /// `SetupComponent.Signs`: a field of another shape is none, never the card unread.
        struct Signs: Equatable {
            /// The taf's Card is in this fingerprint; nil when tafs cloud didn't say.
            var card: Bool?
            /// The Card section's heading when it isn't: "Its Card: you approve it next".
            var words: String?
            /// `tap` or `fingerprint`, as tafs cloud decides Approve; nil when it didn't say.
            var takes: String?
            /// The Card isn't signed by this approval: it comes next.
            var cardNext: Bool { card == false }
        }

        /// A hand-over's outcome (`answer.outcome`): the taf made, the version it became, why it
        /// failed, or the plan it needs.
        struct Outcome: Equatable {
            var tafID: String?
            var version: Int?
            var failed: String?
            var planNeeded: String?
        }

        struct PlanStep: Equatable {
            let label: String
            /// pending, active, done, failed or skipped.
            let status: String
        }

        var isPlan: Bool { type == "steps" && !plan.isEmpty }
        var isHandOver: Bool { type == "result" && tafName != nil }
        /// A result that is a taf's next version, as the iPad's `result(_:)` tells them apart
        /// (`c.taf?.improves != nil`, SetupChatView.swift:1376-1378): drawn as the new version's card.
        var isImprovement: Bool { type == "result" && improves != nil }

        /// What became of an improvement, from tafs cloud's answer to it, as the iPad's
        /// `SetupThread.improvement` (SetupComponent.swift:464-478): the version made, why none was
        /// (Coach hears it from tafs cloud), or not answered yet.
        enum Improvement: Equatable {
            case made(Int)
            case failed(String)
            case preparing
        }

        var improvement: Improvement {
            if let why = outcome?.failed { return .failed(why) }
            if let n = outcome?.version { return .made(n) }
            return .preparing
        }

        /// The taf an improvement is the next version of, among those listed, as the iPad's
        /// `improvedTaf` (AppModel.swift:9807-9811): the one tafs cloud knows by `improves`, else
        /// the one whose agent it names, else the result's own taf's agent. Nil when none is listed.
        func improvedTaf(in tafs: [Home.Taf]) -> Home.Taf? {
            if let improves {
                if let taf = tafs.first(where: { $0.tafID == improves }) { return taf }
                if let taf = tafs.first(where: { $0.id == improves }) { return taf }
            }
            return tafAgent.flatMap { agent in tafs.first { $0.id == agent } }
        }

        /// tafs cloud's why for a version not made, without its own ending, as the iPad's
        /// `SetupThread.notImproved` trims it before the shared line adds one.
        static func notImprovedWhy(_ why: String) -> String {
            why.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }

        /// A hand-over's tools in words, as the iPad's `KIFFMapping.toolWords`, never a tool's
        /// own name ("list_emails" is "list emails").
        var toolWords: [String] { tools.map(CallNames.toolWords) }

        /// How a card is drawn once it is answered, as the iPad's: an approval approved or
        /// declined folds to one line with a ⌄ that opens it again (`SetupApproval`,
        /// SetupChatView.swift:1513-1530); a choice, a sign-in and questions fold to one line
        /// (`OutcomeLine`, :1302, :1335, QuestionsCard.swift:18). A plan, a note, a hand-over, a
        /// card with no answer the person chose, are drawn whole.
        enum Fold: Equatable {
            case whole
            case line
            case opens
        }

        var fold: Fold {
            switch type {
            case "approval": return answered != nil ? .opens : .whole
            case "questions": return answerState == "answered" ? .line : .whole
            // A plan, a note, a hand-over and a taf's ask show what they are, answered or not.
            case "steps", "notice", "result", "ask_coach": return .whole
            default: return answered != nil ? .line : .whole
            }
        }
        /// A taf's card handing a setting to Coach (`ask_coach`), as the iPad's `AskCoachCard`
        /// (TafsCloud.swift:1178-1195): the person's request in the taf's words, which Ask Coach
        /// writes into Coach's box on that taf. Nil for any other card, or one with no words.
        var askCoach: String? { type == "ask_coach" ? text : nil }
        var planDone: Int { plan.filter { $0.status == "done" }.count }

        var waitsForPerson: Bool { waits == "owner" && answerState == nil }
        /// A choice between a few answers, which grants nothing: the only kind answered here.
        var isChoice: Bool { type == "confirm" && !options.isEmpty }
        /// A card whose answer is a signature: approving a connection or a Card.
        var grants: Bool { type == "approval" || type == "sign_in" }
        /// A card drawn as what it asks, with its pills or "Needs you · a question": a card with
        /// words or an answer, never a drive's. A drive card is Coach asking to drive the phone's
        /// own screen, approved only there (docs/drive.md): never a question to this Mac.
        var drawsAsChoice: Bool {
            type != "drive" && (title != nil || text != nil || waitsForPerson || answered != nil)
        }
    }

    enum Item: Identifiable, Equatable {
        case message(Message, position: Int)
        /// A card that waits for an answer (`owner`), or that tafs cloud answers (`service`).
        case card(Card, position: Int)
        /// A call KIFF held, at the point it was held. Only KIFF's keys: it is answered in Needs you.
        case held(exception: String, position: Int)
        /// Something this app doesn't draw yet (a drive's end, a kind it doesn't know).
        case other(type: String, position: Int)

        var id: Int {
            switch self {
            case .message(_, let p), .card(_, let p), .held(_, let p), .other(_, let p): return p
            }
        }

        /// When it was shown, when tafs cloud says.
        var at: Date? {
            switch self {
            case .message(let message, _): return message.at
            case .card(let card, _): return card.at
            default: return nil
            }
        }
    }

    struct Page: Decodable, Equatable {
        let items: [Item]
        /// The taf is at work in this chat.
        let working: Bool

        enum Keys: String, CodingKey { case items, working }

        init(items: [Item], working: Bool) { self.items = items; self.working = working }
        /// A new conversation, before its first message: nothing to read yet.
        static let empty = Page(items: [], working: false)
        enum ItemKeys: String, CodingKey { case type, message, card, held }
        enum MessageKeys: String, CodingKey { case id, at, from, kind, text, work, session, attachments, delivered, counted, refused }
        enum RefusedKeys: String, CodingKey { case words, why, next }
        /// A card item is `{key, session, answer?, component: {…}}`: what the agent showed is
        /// under `component`, what tafs cloud keeps about it beside it.
        enum CardKeys: String, CodingKey { case key, session, answer, component, at }
        enum ComponentKeys: String, CodingKey { case id, type, title, text, options, waits, steps, line, tone, taf, tools, connection, service, note, yes, no, questions, wider, grant, draft, signs }
        enum PlanKeys: String, CodingKey { case label, status }
        enum TafKeys: String, CodingKey { case name, agent, improves, note }
        enum OutcomeKeys: String, CodingKey { case tafID = "taf_id", version, failed, planNeeded = "plan_needed" }
        enum ConnectionKeys: String, CodingKey { case done, words }
        enum WiderKeys: String, CodingKey { case words }
        enum SignsKeys: String, CodingKey { case card, words, takes }
        enum WorkKeys: String, CodingKey { case ms, steps }
        enum WorkStepKeys: String, CodingKey { case words, failed, error, why, notMade = "not_made" }
        enum OptionKeys: String, CodingKey { case label, value }
        enum AnswerKeys: String, CodingKey { case words, state, by, outcome, answer }
        enum HeldKeys: String, CodingKey { case exception }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            working = ((try? c.decodeIfPresent(Bool.self, forKey: .working)) ?? nil) ?? false
            // The ordered list must be there: an answer without it is unreadable.
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            var items: [Item] = []
            while !list.isAtEnd {
                let position = items.count
                guard let item = try? list.nestedContainer(keyedBy: ItemKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                let type = ((try? item.decodeIfPresent(String.self, forKey: .type)) ?? nil) ?? ""
                switch type {
                case "message":
                    guard let m = try? item.nestedContainer(keyedBy: MessageKeys.self, forKey: .message),
                          let from = try? m.decode(String.self, forKey: .from),
                          let text = try? m.decode(String.self, forKey: .text) else { continue }
                    let at = ((try? m.decodeIfPresent(String.self, forKey: .at)) ?? nil).flatMap(Thread.time)
                    var work: Work?
                    if let w = try? m.nestedContainer(keyedBy: WorkKeys.self, forKey: .work), let ms = try? w.decode(Int.self, forKey: .ms), ms >= 0 {
                        var steps: [Work.Step] = []
                        if var list = try? w.nestedUnkeyedContainer(forKey: .steps) {
                            while !list.isAtEnd {
                                guard let step = try? list.nestedContainer(keyedBy: WorkStepKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                                // A step is shown by tafs cloud's words for it, never by its tool's name.
                                guard let words = (try? step.decodeIfPresent(String.self, forKey: .words)) ?? nil,
                                      !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                                let failed = ((try? step.decodeIfPresent(Bool.self, forKey: .failed)) ?? nil) ?? ((try? step.decodeIfPresent(Bool.self, forKey: .error)) ?? nil) ?? false
                                steps.append(Work.Step(words: words, failed: failed, why: (try? step.decodeIfPresent(String.self, forKey: .why)) ?? nil,
                                                       notMade: ((try? step.decodeIfPresent(Bool.self, forKey: .notMade)) ?? nil) ?? false))
                            }
                        }
                        work = Work(ms: ms, steps: steps)
                    }
                    // A refused connection, as the iPad's `Refused`: kept only when some line of it says something.
                    var refused: Message.Refused?
                    if let r = try? m.nestedContainer(keyedBy: RefusedKeys.self, forKey: .refused) {
                        let read = Message.Refused(words: ((try? r.decodeIfPresent(String.self, forKey: .words)) ?? nil) ?? "",
                                                   why: Message.line((try? r.decodeIfPresent(String.self, forKey: .why)) ?? nil),
                                                   next: ((try? r.decodeIfPresent(String.self, forKey: .next)) ?? nil) ?? "")
                        refused = read.lines.isEmpty ? nil : read
                    }
                    items.append(.message(Message(id: (try? m.decodeIfPresent(String.self, forKey: .id)) ?? nil, at: at, from: from,
                                                  kind: ((try? m.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? "message", text: text, work: work,
                                                  session: (try? m.decodeIfPresent(String.self, forKey: .session)) ?? nil,
                                                  // As the iPad's: the files read whole, or none.
                                                  attachments: ((try? m.decodeIfPresent([AttachmentRef].self, forKey: .attachments)) ?? nil) ?? [],
                                                  delivered: Message.line((try? m.decodeIfPresent(String.self, forKey: .delivered)) ?? nil),
                                                  counted: Message.line((try? m.decodeIfPresent(String.self, forKey: .counted)) ?? nil),
                                                  refused: refused),
                                          position: position))
                case "card":
                    guard let card = try? item.nestedContainer(keyedBy: CardKeys.self, forKey: .card),
                          let shown = try? card.nestedContainer(keyedBy: ComponentKeys.self, forKey: .component) else { continue }
                    func outer(_ key: CardKeys) -> String? {
                        guard let value = (try? card.decodeIfPresent(String.self, forKey: key)) ?? nil,
                              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        return value
                    }
                    func text(_ key: ComponentKeys) -> String? {
                        guard let value = (try? shown.decodeIfPresent(String.self, forKey: key)) ?? nil,
                              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        return value
                    }
                    guard let id = text(.id) ?? outer(.key) else { continue }
                    var options: [Card.Option] = []
                    if var list = try? shown.nestedUnkeyedContainer(forKey: .options) {
                        while !list.isAtEnd {
                            guard let option = try? list.nestedContainer(keyedBy: OptionKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                            // An option with no value can't be answered, and one with no label can't be read.
                            guard let label = try? option.decode(String.self, forKey: .label), let value = try? option.decode(String.self, forKey: .value),
                                  !label.isEmpty, !value.isEmpty else { continue }
                            options.append(Card.Option(label: label, value: value))
                        }
                    }
                    // tafs cloud's answer, as the iPad's `CardAnswer` (TafsCloud.swift:1796-1802): a
                    // `state`, `words` or `by` that isn't text leaves the card unanswered; a missing
                    // `state` is "answered", missing `words` are none. It's shown as answered only
                    // when the person chose one, as on the iPad.
                    var state: String?
                    var words: String?
                    var answer: KeyedDecodingContainer<AnswerKeys>?
                    if let recorded = try? card.nestedContainer(keyedBy: AnswerKeys.self, forKey: .answer) {
                        do {
                            let readState = try recorded.decodeIfPresent(String.self, forKey: .state)
                            let readWords = try recorded.decodeIfPresent(String.self, forKey: .words)
                            _ = try recorded.decodeIfPresent(String.self, forKey: .by)
                            state = readState ?? "answered"
                            words = readWords ?? ""
                            answer = recorded
                        } catch {
                            // One of the three isn't text: no answer is read, its outcome neither.
                        }
                    }
                    let answered = state == "answered" ? words.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } : nil
                    var made = Card(key: outer(.key) ?? id, id: id, type: text(.type) ?? "", session: outer(.session), title: text(.title),
                                    text: text(.text), options: options, waits: text(.waits), answerState: state, answered: answered)
                    if var list = try? shown.nestedUnkeyedContainer(forKey: .steps) {
                        while !list.isAtEnd {
                            guard let step = try? list.nestedContainer(keyedBy: PlanKeys.self) else { _ = try? list.decode(Skipped.self); continue }
                            guard let label = try? step.decode(String.self, forKey: .label), !label.isEmpty else { continue }
                            made.plan.append(Card.PlanStep(label: label, status: ((try? step.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? "pending"))
                        }
                    }
                    made.at = outer(.at).flatMap(Thread.time)
                    // A card's questions read whole, as the iPad's `SetupComponent`: when they, or any
                    // one of them, don't read, the card isn't read (`LenientShown`, TafsCloud.swift:1812-1814).
                    if shown.contains(.questions), (try? shown.decodeNil(forKey: .questions)) != true {
                        guard let questions = try? shown.decode([Card.Question].self, forKey: .questions) else { continue }
                        made.questions = questions
                    }
                    made.planLine = text(.line)
                    made.tone = text(.tone)
                    made.service = text(.service)
                    made.note = text(.note)
                    made.yes = text(.yes)
                    made.no = text(.no)
                    if let taf = try? shown.nestedContainer(keyedBy: TafKeys.self, forKey: .taf) {
                        func named(_ key: TafKeys) -> String? { ((try? taf.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } }
                        made.tafName = named(.name)
                        made.tafAgent = named(.agent)
                        // As the iPad's `SetupComponent.Taf`: an improvement names the taf it
                        // makes the next version of, and what changed.
                        made.improves = named(.improves)
                        made.tafNote = ((try? taf.decodeIfPresent(String.self, forKey: .note)) ?? nil)
                            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    }
                    if let o = try? answer?.nestedContainer(keyedBy: OutcomeKeys.self, forKey: .outcome) {
                        var outcome = Card.Outcome()
                        outcome.tafID = (try? o.decodeIfPresent(String.self, forKey: .tafID)) ?? nil
                        outcome.version = (try? o.decodeIfPresent(Int.self, forKey: .version)) ?? nil
                        outcome.failed = (try? o.decodeIfPresent(String.self, forKey: .failed)) ?? nil
                        struct Needed: Decodable { let words: String? }
                        outcome.planNeeded = ((try? o.decodeIfPresent(Needed.self, forKey: .planNeeded)) ?? nil)?.words
                        made.outcome = outcome
                    }
                    made.tools = (((try? shown.decodeIfPresent([String].self, forKey: .tools)) ?? nil) ?? []).filter { !$0.isEmpty }
                    if let connection = try? shown.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .connection),
                       ((try? connection.decodeIfPresent(Bool.self, forKey: .done)) ?? nil) == true {
                        made.connected = true
                        made.connectionWords = ((try? connection.decodeIfPresent(String.self, forKey: .words)) ?? nil).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    }
                    // Read leniently, as the iPad's `SetupComponent.Wider`: a mark of another shape,
                    // or blank words, is no mark, and the card reads as before.
                    if let wider = try? shown.nestedContainer(keyedBy: WiderKeys.self, forKey: .wider) {
                        made.widerWords = ((try? wider.decodeIfPresent(String.self, forKey: .words)) ?? nil)
                            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    }
                    made.grant = text(.grant)
                    made.draft = text(.draft)
                    // As the iPad's `SetupComponent.Signs`: lenient, a field of another shape is none.
                    if let signs = try? shown.nestedContainer(keyedBy: SignsKeys.self, forKey: .signs) {
                        made.signs = Card.Signs(card: (try? signs.decodeIfPresent(Bool.self, forKey: .card)) ?? nil,
                                                words: ((try? signs.decodeIfPresent(String.self, forKey: .words)) ?? nil)
                                                    .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
                                                takes: (try? signs.decodeIfPresent(String.self, forKey: .takes)) ?? nil)
                    }
                    // The settled answer, as the iPad's `CardAnswer.answer`: text, or none.
                    made.stored = ((try? answer?.decodeIfPresent(String.self, forKey: .answer)) ?? nil)
                        .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
                    items.append(.card(made, position: position))
                case "held":
                    guard let held = try? item.nestedContainer(keyedBy: HeldKeys.self, forKey: .held),
                          let exception = try? held.decode(String.self, forKey: .exception) else { continue }
                    items.append(.held(exception: exception, position: position))
                default:
                    items.append(.other(type: type, position: position))
                }
            }
            self.items = items
        }

        private struct Skipped: Decodable {}

        /// Whether the thread has the message tafs cloud gave this id.
        func has(message id: String) -> Bool {
            items.contains { item in
                if case .message(let message, _) = item { return message.id == id }
                return false
            }
        }

        /// Whether the person's latest message in the thread is this text, sent at or after
        /// `since` (give or take a minute of clock difference): a first try that did arrive.
        /// Whether the person's words are in the thread, written at or after `since`: how a sent
        /// message tafs cloud gave no id for is found, as the iPad's `SentMessages.merge`.
        func hasPersons(_ text: String, since: Date) -> Bool {
            items.contains { item in
                guard case .message(let message, _) = item, message.fromPerson, let at = message.at else { return false }
                return message.text == text && at >= since
            }
        }

        func hasPersonsLast(_ text: String, since: Date, files: [String] = []) -> Bool {
            for item in items.reversed() {
                guard case .message(let message, _) = item, message.fromPerson else { continue }
                // Its files too: a message of files alone isn't taken for an earlier one.
                guard message.text.trimmingCharacters(in: .whitespacesAndNewlines) == text, message.attachments.map(\.id) == files,
                      let at = message.at else { return false }
                return at >= since.addingTimeInterval(-60)
            }
            return false
        }

        /// Whether the item at this place shows its time, by the iPad's rule: the first one, and
        /// any that comes an hour or more after the one before it. One with no time shows none.
        func showsTime(at index: Int) -> Bool {
            guard items.indices.contains(index), let at = items[index].at else { return false }
            guard index > 0, let before = items[index - 1].at else { return true }
            return at.timeIntervalSince(before) >= 3600
        }

        /// The cards in the chat, in its order.
        var cards: [Card] {
            items.compactMap { item in if case .card(let card, _) = item { return card } else { return nil } }
        }

        /// Whether a newer approval in the chat asks about the same connection, as the iPad's
        /// `SetupThread.replaced` (SetupComponent.swift:450-456, kiff/tafs#138): then this card is
        /// history, and never shows that connection's live state or its error. Newer is a later
        /// `at`, or a later place in the chat when either has none. A card with no grant never is.
        func replaced(_ card: Card) -> Bool {
            guard let grant = card.grant else { return false }
            let placed = items.enumerated().compactMap { index, item -> (Int, Card)? in
                if case .card(let shown, _) = item { return (index, shown) } else { return nil }
            }
            guard let mine = placed.first(where: { $0.1.key == card.key }) else { return false }
            return placed.contains { index, other in
                guard other.id != card.id, other.type == "approval", other.grant == grant else { return false }
                if let at = other.at, let before = mine.1.at { return at > before }
                return index > mine.0
            }
        }

        /// An answer the person sent the old way, as a message, as the iPad's
        /// `SetupThread.Answer(_:)` (SetupComponent.swift:306-313): "[<type> <id>] <answer>".
        /// Nil for any other message.
        static func answerMessage(_ text: String) -> (type: String, id: String, text: String)? {
            guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return nil }
            let head = text[text.index(after: text.startIndex)..<close].split(separator: " ", maxSplits: 1)
            guard head.count == 2, !head[0].isEmpty, !head[1].isEmpty, !head[1].contains(" ") else { return nil }
            return (String(head[0]), String(head[1]), text[text.index(after: close)...].trimmingCharacters(in: .whitespaces))
        }

        /// The person's answer to a card sent the old way, as the iPad's `SetupThread.answer(to:)`
        /// (SetupComponent.swift:330-339) when kiff/agents recorded none: the latest of their
        /// messages after the card, answering its type and id, that didn't fail. Nil when tafs
        /// cloud recorded an answer, or none was sent.
        func oldAnswer(_ card: Card) -> String? {
            guard card.answerState == nil,
                  let mine = items.firstIndex(where: { if case .card(let shown, _) = $0 { return shown.key == card.key } else { return false } })
            else { return nil }
            for item in items[(mine + 1)...].reversed() {
                guard case .message(let m, _) = item, m.fromPerson, let a = Self.answerMessage(m.text),
                      a.type == card.type, a.id == card.id, !a.text.hasPrefix("failed") else { continue }
                return a.text
            }
            return nil
        }

        /// Whether a message of the person's is an answer to a card this chat shows, as the iPad's
        /// `SetupChatView` (557-560): it reads once, on the card's folded line, so no bubble repeats
        /// it. One that didn't go through keeps its bubble, which says so.
        func answersCard(_ message: Message) -> Bool {
            guard message.fromPerson, let a = Self.answerMessage(message.text), !a.text.hasPrefix("failed") else { return false }
            return items.contains { if case .card(let shown, _) = $0 { return shown.id == a.id && shown.type == a.type } else { return false } }
        }

        /// Whether something in this chat waits for the person.
        var waitsForPerson: Bool {
            items.contains { item in
                switch item {
                case .card(let card, _): return card.waitsForPerson
                case .held: return true
                default: return false
                }
            }
        }
    }

    static func time(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The account's Coach, as tafs cloud names it; nil before Coach is started.
struct Coach: Decodable, Equatable {
    let id: String
    let name: String
}

/// A message as it may be sent: 1 to 2,000 characters once trimmed.
enum Outgoing {
    static let longest = 2000

    /// The text to send, or nil when there is nothing to send or it is too long.
    static func text(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > longest ? nil : trimmed
    }

    /// The text to send with files, as the iPad's `deliverSetupOnce` guard: words or files, never
    /// neither, and never too long. Nil when it can't go.
    static func text(_ typed: String, files: [AttachmentRef]) -> String? {
        guard !files.isEmpty else { return text(typed) }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > longest ? nil : trimmed
    }

    /// What tafs cloud answers a sent message: the thread gives the same message that id.
    struct Sent: Decodable, Equatable {
        struct Message: Decodable, Equatable { let id: String }
        let session: String
        /// tafs cloud started a new chat for it (the chat named had handed a taf over).
        let newSession: Bool
        let message: Message?
        enum CodingKeys: String, CodingKey { case session, message, newSession = "new_session" }
    }
}

extension CloudClient {
    /// The account's Coach. A plain read: it sends no time zone, so it changes nothing.
    func coach() async throws -> Coach? {
        struct Answer: Decodable { let setup: Coach? }
        let answer: Answer = try await get("/v1/setup")
        return answer.setup
    }

    /// Sends the person's message to a taf's chat: its live one unless `target` names one or
    /// asks for a new one. It starts a run: only ever called for what the person typed and sent.
    func send(_ text: String, to taf: String, target: ChatTarget = .live, files: [AttachmentRef] = []) async throws -> Outgoing.Sent {
        guard let text = Outgoing.text(text, files: files) else { throw CloudRefusal(status: 0, body: Data(#"{"error":"not_a_message"}"#.utf8)) }
        let body = try await post("/v1/tafs/\(Self.escaped(taf))/messages", body: ChatTarget.Message(text, target, files: files))
        guard let sent = try? JSONDecoder().decode(Outgoing.Sent.self, from: body) else { throw KIFFError.unreadable }
        return sent
    }

    /// Answers a card that waits with one of its own options, as data. The run that waited
    /// goes on. Only a choice is answered this way: never a card whose answer is a signature.
    func answer(_ card: Thread.Card, with option: Thread.Card.Option, in taf: String) async throws {
        guard card.isChoice, !card.grants, card.options.contains(option) else {
            throw CloudRefusal(status: 0, body: Data(#"{"error":"not_this_cards_answer"}"#.utf8))
        }
        var fields = ["answer": option.value]
        if let session = card.session { fields["session"] = session }
        _ = try await post("/v1/tafs/\(Self.escaped(taf))/components/\(Self.escaped(card.id))/answer", fields)
    }

    /// Says no to a card whose answer would be a signature: `declined` for an approval, `not now`
    /// for a sign-in. Saying no grants nothing, so it needs no signature. These two words are
    /// the only answers this app ever sends such a card.
    func decline(_ card: Thread.Card, in taf: String) async throws {
        let word: String
        switch card.type {
        case "approval": word = "declined"
        case "sign_in": word = "not now"
        default: throw CloudRefusal(status: 0, body: Data(#"{"error":"not_this_cards_answer"}"#.utf8))
        }
        var fields = ["answer": word]
        if let session = card.session { fields["session"] = session }
        _ = try await post("/v1/tafs/\(Self.escaped(taf))/components/\(Self.escaped(card.id))/answer", fields)
    }

    /// Allows AI use, for the version of the words the person read.
    func allowAI(version: String) async throws {
        _ = try await post("/v1/me/ai-consent", ["version": version])
    }

    /// The thread of the person's chats with a taf, or with Coach; with `session`, that chat's alone.
    /// `proof` is this device's signed read of its planque grants (`Planque-Device-Signature`), as the
    /// iPad's `setupThread(_:session:proof:can:)` sends with Coach's thread: with it, tafs cloud reads
    /// the account's grants and marks each waiting approval or sign-in whose sign-in can't be narrowed
    /// to the job (`wider`, kiff/tafs `markSigns`, `markWider`). Without it, the cards come unmarked.
    /// No `?can=`: this Mac signs no step past connect and cards.
    func thread(of taf: String, session: String? = nil, proof: String? = nil) async throws -> Thread.Page {
        try await get("/v1/tafs/\(Self.escaped(taf))/conversation" + (session.map { "/\(Self.escaped($0))" } ?? ""),
                      headers: proof.map { ["Planque-Device-Signature": $0] } ?? [:])
    }
}
