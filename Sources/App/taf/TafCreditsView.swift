import SwiftUI

/// One taf's credits this period, with its runs, as the iPad's `readTafCredits`
/// (AppModel.swift:4012-4043): read when its sheet opens; More runs adds the next page after the
/// runs read. A read that fails keeps what was read and says why.
@MainActor
final class TafCreditsModel: ObservableObject {
    @Published private(set) var credits: TafCredits?
    /// Why the last read failed, as the iPad's `creditsWords`: tafs cloud's words, else the shared line.
    @Published private(set) var error: String?
    /// A read on this sheet is over, whatever it gave: an earlier read isn't shown as now.
    @Published private(set) var read = false

    /// The run whose request is open (`RequestDetailPage`), its read, and why it couldn't be read.
    @Published private(set) var opened: String?
    @Published private(set) var detail: RequestDetail?
    @Published private(set) var detailError: String?
    /// The runs whose reply is being sent again: their button waits.
    @Published private(set) var sendingAgain: Set<String> = []

    private let cloud: CloudClient
    let taf: String
    /// The last period, not this one, as the iPad's `TafCreditsView(previous:)`: the period
    /// Plan & usage showed when the taf's line was opened.
    let previous: Bool

    init(cloud: CloudClient, taf: String, previous: Bool = false) {
        self.cloud = cloud
        self.taf = taf
        self.previous = previous
    }

    /// Opens a run's request, as the iPad's `KnobRequestDetail`: read when it opens, again with Try again.
    func open(_ run: String) async {
        opened = run
        detail = nil
        detailError = nil
        await readDetail()
    }

    /// Back to the runs.
    func closeDetail() {
        opened = nil
        detail = nil
        detailError = nil
    }

    /// Reads the open run's request. A read that ends after another run was opened, or after Back, is dropped, as the
    /// iPad's `.task(id: run)` drops it.
    func readDetail() async {
        guard let run = opened else { return }
        let client = cloud, id = taf
        do {
            let read = try await client.request(of: id, run: run)
            guard opened == run else { return }
            detail = read
            detailError = nil
        } catch {
            guard opened == run else { return }
            detailError = Self.words(error, what: Words.app("knob.request_title"))
        }
    }

    /// Send again from a run's request, as the iPad's: tafs cloud's unsigned call, the same as WorkPanel's, then the
    /// request read again. A failure says why under it.
    func sendAgain(run: String, place: String) async {
        guard sendingAgain.insert(run).inserted else { return }
        let client = cloud, id = taf
        var failed: String?
        do { try await client.sendAgain(of: id, run: run, place: place) } catch {
            failed = Self.words(error, what: Words.app("work.request.try_reply_now"))
        }
        sendingAgain.remove(run)
        await readDetail()
        if let failed, opened == run { detailError = failed }
    }

    /// Reads its credits; with `more`, the runs after the ones read.
    func load(more: Bool = false) async {
        let client = cloud
        let id = taf
        let after = more ? credits?.next : nil
        if more, after == nil { return }
        do {
            let got = try await client.tafCredits(of: id, previous: previous, after: after)
            error = nil
            if more, var known = credits, let got {
                known.append(got)
                credits = known
            } else if let got {
                credits = got
            }
        } catch {
            self.error = Self.words(error, what: Words.app(more ? "usage.more_runs" : "work.its_runs"))
        }
        read = true
    }

    /// tafs cloud's words for a refusal, else "{what} couldn't be read: {why}", as the iPad's
    /// `creditsWords`.
    static func words(_ error: Error, what: String) -> String {
        if let refusal = error as? CloudRefusal, let words = refusal.words { return words }
        return Words.app("common.could_not_read_why", ["what": what, "why": NeedsYouModel.why(error)])
    }
}

/// One taf's credits in the period, with its runs, newest first, as the iPad's `TafCreditsView`
/// (CreditsViews.swift:103-147): tafs cloud's words for each. A run opens its request while tafs
/// cloud says it can (`opens`), as the iPad's `CreditsRunRow` opens `KnobRequestDetail`: in this
/// sheet, with Back.
struct TafCreditsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafCreditsModel
    let name: String
    /// Whoever manages the taf: a request's Send again is theirs.
    var manages = false
    /// Coach, for a run's Ask Coach: given only where Coach may be used and the taf is managed, as the iPad's
    /// `offersAskCoach`; nil draws none.
    var askCoach: (() -> Void)? = nil
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if model.opened != nil {
                    Button { model.closeDetail() } label: { Label(words("common.back"), systemImage: "chevron.backward") }
                        .buttonStyle(.plain).foregroundColor(Theme.amberText)
                }
                Text(verbatim: model.opened == nil ? name : words("knob.request_title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.opened != nil {
                        RequestDetailPage(model: model, manages: manages, askCoach: askCoach.map { ask in { close(); ask() } })
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.background)
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if model.read, let mine = model.credits {
            panel {
                Text(verbatim: mine.words).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !mine.items.isEmpty { runs(mine) }
        } else if model.read {
            panel {
                Text(verbatim: model.error ?? words("usage.runs_could_not_read_pull")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            panel { ProgressView().controlSize(.small) }
        }
    }

    private func runs(_ mine: TafCredits) -> some View {
        panel {
            ForEach(mine.items) { run($0) }
            if mine.next != nil {
                Button(words("usage.more_runs")) { Task { await model.load(more: true) } }
                    .buttonStyle(OutlineButtonStyle())
            }
            if let why = model.error {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One run, as the iPad's `CreditsRunRow`: tafs cloud's words, and when it ended; it opens its request while tafs
    /// cloud says it can.
    @ViewBuilder private func run(_ run: TafCredits.Run) -> some View {
        if run.opens {
            Button { Task { await model.open(run.run) } } label: {
                HStack(spacing: 8) {
                    runLine(run)
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.dim)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            runLine(run)
        }
    }

    private func runLine(_ run: TafCredits.Run) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: run.words).font(.system(size: 14, weight: run.counted ? .semibold : .regular))
                .foregroundColor(run.counted ? Theme.ink : Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: AppDates.formatter(words, time: .short).string(from: run.at)).font(.system(size: 13)).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}

/// A run's request, as the iPad's `KnobRequestDetail` (TafDialPanel.swift:171-237): where it came from and its line,
/// what it did step by step (a done step's tick, the next one's clock, anything else stopped), Send again for a reply
/// given up on, for whoever manages the taf, and Ask Coach. Each line is tafs cloud's words. A read that fails says why,
/// with Try again.
struct RequestDetailPage: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafCreditsModel
    let manages: Bool
    let askCoach: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let detail = model.detail {
                panel {
                    Text(verbatim: detail.from).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.soft)
                    Text(verbatim: detail.line).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                if !detail.steps.isEmpty { panel { ForEach(Array(detail.steps.enumerated()), id: \.offset) { _, step in self.step(step) } } }
                actions(detail)
            } else if model.detailError == nil {
                ProgressView().controlSize(.small)
            }
            if let why = model.detailError {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                Button(words("common.try_again")) { Task { await model.readDetail() } }.buttonStyle(OutlineButtonStyle())
            }
        }
    }

    private func step(_ step: RequestDetail.Step) -> some View {
        HStack(alignment: .top, spacing: 10) {
            mark(RequestDetail.mark(step))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: step.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = step.line {
                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ mark: RequestDetail.Mark) -> some View {
        switch mark {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok).accessibilityHidden(true)
        case .next: Image(systemName: "clock").foregroundColor(Theme.amberText).accessibilityHidden(true)
        case .stopped: Image(systemName: "exclamationmark.circle").foregroundColor(Theme.amberText).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func actions(_ detail: RequestDetail) -> some View {
        // The run opened, as the iPad sends it (`run`), not the detail's own id.
        let run = model.opened ?? detail.id
        ForEach(Array(detail.deliveries.enumerated()), id: \.offset) { _, delivery in
            if delivery.sendAgain, manages {
                let sending = model.sendingAgain.contains(run)
                Button(words(sending ? "work.sending_again" : "work.request.try_reply_now")) {
                    Task { await model.sendAgain(run: run, place: delivery.sendPlace) }
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(sending)
            }
        }
        if let askCoach {
            Button(words("coach.ask"), action: askCoach).buttonStyle(OutlineButtonStyle())
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}
