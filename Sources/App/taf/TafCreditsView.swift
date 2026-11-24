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

    let cloud: CloudClient
    let taf: String
    /// The last period, not this one, as the iPad's `TafCreditsView(previous:)`: the period
    /// Plan & usage showed when the taf's line was opened.
    let previous: Bool

    init(cloud: CloudClient, taf: String, previous: Bool = false) {
        self.cloud = cloud
        self.taf = taf
        self.previous = previous
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
/// (CreditsViews.swift:103-147): tafs cloud's words for each. A run's request isn't on this Mac
/// yet, so a run's row doesn't open.
struct TafCreditsView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafCreditsModel
    let name: String
    /// Whether this person manages the taf: a run's Send again.
    var manages = false
    let close: () -> Void
    /// The run opened from its row.
    @State private var opened: OpenRun?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: name).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.background)
        .task { await model.load() }
        .sheet(item: $opened) { open in
            TafRunSheet(model: open.model, manages: manages) { opened = nil }.environment(\.words, words)
        }
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

    /// One run, as the iPad's `CreditsRunRow`: tafs cloud's words, and when it ended. One tafs cloud says opens
    /// (`opens`) opens the run itself (`KnobRequestDetail`), with a chevron.
    @ViewBuilder private func run(_ run: TafCredits.Run) -> some View {
        if run.opens {
            Button { opened = OpenRun(model: TafRunModel(cloud: model.cloud, taf: model.taf, run: run.run)) } label: {
                HStack(alignment: .firstTextBaseline) {
                    runLines(run)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("credits.run.\(run.run)")
        } else {
            runLines(run)
        }
    }

    private func runLines(_ run: TafCredits.Run) -> some View {
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
