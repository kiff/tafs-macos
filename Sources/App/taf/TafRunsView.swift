import SwiftUI

/// A taf's runs on tafs cloud, as the iPad's `RunsPanel`: when it runs next (or that it works
/// from its chat), and Run now, with tafs cloud's words when Run now started nothing.
struct RunsPanel: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let taf: Home.Taf
    /// Set on the click itself, before the request starts, so a second click can't send one.
    @State private var runTapped = false

    var body: some View {
        let inFlight = runTapped || model.runInFlight
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("taf.runs"))
            if taf.unscheduled {
                // Its tools can't find its work by themselves: no schedule.
                Text(words("taf.works_from_chat")).font(.system(size: 15)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // tafs cloud's words, with the day when it isn't today; the app's own only when it sends none.
                Text(verbatim: Self.next(taf, words: words)).font(.system(size: 15)).foregroundColor(Theme.ink)
                Button {
                    guard !runTapped else { return }
                    runTapped = true
                    Task {
                        // The run it started shows among the runs it kept.
                        if await model.runNow(words: words) != nil { await model.loadRunPage() }
                        runTapped = false
                    }
                } label: {
                    Text(words(inFlight ? "taf.starting_run" : "taf.run_now")).padding(.horizontal, 16)
                }
                .buttonStyle(OutlineButtonStyle())
                .fixedSize()
                .disabled(inFlight)
                // Run now started no run: tafs cloud's words, as they are.
                if let said = model.runNowWords {
                    Text(verbatim: said).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
                if let why = model.runNotStarted {
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    /// Paused (tafs cloud's `status`, as the iPad's `cloud.paused`); else tafs cloud's next-run
    /// words; else "Next run at 14:05"; else On its schedule.
    static func next(_ taf: Home.Taf, words: Words) -> String {
        if taf.paused { return words("taf.state.paused") }
        if let said = taf.nextRunWords { return said }
        if let at = taf.nextRun { return words("taf.next_run_at", ["time": shortTime(at)]) }
        return words("taf.on_its_schedule")
    }

    /// The time of day, as 14:05 or 2:05 PM, as the iPad's `shortTime`: on this Mac's clock (`AccountTime.shortTime`).
    static func shortTime(_ date: Date, zone: TimeZone = .current, twentyFour: Bool = Clock.macTwentyFour) -> String {
        AccountTime(zone.identifier).shortTime(date, twentyFour: twentyFour)
    }
}

/// The runs a taf kept, as the iPad's `RetainedRuns`: tafs cloud's heading, each run's line
/// with what it used and where its result went, and the firings that started no run, dim. The
/// panel shows the first few, with tafs cloud's line to see all of them; all of them come a
/// page at a time.
struct RetainedRuns: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    var all = false
    /// Whether this person manages the taf: a run's Send again and Ask Coach.
    var manages = false
    /// Opens Coach from a run, for someone who may use it.
    var askCoach: (() -> Void)? = nil
    @State private var showAll = false
    /// The run opened from its line.
    @State private var opened: OpenRun?

    var body: some View {
        Group {
            if all {
                LazyVStack(alignment: .leading, spacing: 14) { content }
            } else {
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            }
        }
        .task(id: model.taf) { await model.loadRunPage(all: all) }
        .sheet(item: $opened) { open in
            TafRunSheet(model: open.model, manages: manages, askCoach: askCoach) { opened = nil }.environment(\.words, words)
        }
        .sheet(isPresented: $showAll) {
            // Titled as the panel is, in tafs cloud's words for the runs it kept.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    Spacer()
                    Button(words("common.done")) { showAll = false }.keyboardShortcut(.defaultAction)
                }
                .padding(16)
                ScrollView { RetainedRuns(model: model, all: true, manages: manages, askCoach: askCoach).padding(16) }
            }
            .frame(width: 520, height: 560)
            .background(Theme.background)
            .environment(\.words, words)
        }
    }

    /// tafs cloud's heading for the runs it kept, read from the panel's first page.
    private var title: String { model.runPages[false]?.pages.first?.title ?? words("taf.its_work") }

    @ViewBuilder private var content: some View {
        let cache = model.runPages[all] ?? TafRuns.Pages()
        Eyebrow(text: cache.pages.first?.title ?? words("taf.its_work"))
        ForEach(Array(cache.pages.enumerated()), id: \.offset) { index, page in
            // The runs and, on the first page, the firings that started no run, each in its place by time.
            ForEach(page.rows(first: index == 0)) { row in
                switch row {
                case .request(let request):
                    // Each run opens itself, as the iPad's `NavigationLink` to `KnobRequestDetail`.
                    Button { opened = OpenRun(model: TafRunModel(cloud: model.cloud, taf: model.taf, run: request.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: request.line).font(.system(size: 14)).foregroundColor(Theme.ink)
                            // What the run used, in tafs cloud's words, once KIFF has counted it.
                            if let used = request.creditsLine { Text(verbatim: used).font(.system(size: 12)).foregroundColor(Theme.dim) }
                            ForEach(Array(request.deliveries.enumerated()), id: \.offset) { _, delivery in
                                Text(verbatim: delivery.line).font(.system(size: 12)).foregroundColor(Theme.dim)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("runs.run.\(request.id)")
                case .skipped(let skipped):
                    // Dim: no run started, which isn't a run that failed.
                    Text(verbatim: skipped.words).font(.system(size: 13)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let error = cache.error {
            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
            Button(words("common.try_again")) { Task { await model.loadRunPage(all: all) } }
        }
        if all, let cursor = cache.pages.last?.nextCursor, cache.error == nil {
            ProgressView().controlSize(.small).task(id: cursor) { await model.loadRunPage(all: true, more: true) }
        } else if !all, let more = cache.pages.first?.moreTitle {
            Button { showAll = true } label: { Text(verbatim: more).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText) }
                .buttonStyle(.plain)
        }
        if cache.loading {
            ProgressView().controlSize(.small)
        } else if all, cache.error == nil, let end = cache.pages.last?.endWords {
            Text(verbatim: end).font(.system(size: 13)).foregroundColor(Theme.dim)
        }
    }
}
