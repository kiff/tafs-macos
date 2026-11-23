import SwiftUI

/// A taf's work, as the iPad's `WorkPanel` (TafDetailView.swift:604-680), read from `GET …/work`: "Its work", its line,
/// its health (`HealthLines`), its oldest waiting case, Answer within for whoever manages the taf, then its recent
/// requests and skipped firings, newest first, each in tafs cloud's words. A request needing the owner is amber, a
/// failed one red; a skipped firing isn't a failure, so it's dim. A delivery given up on offers Send again to whoever
/// manages the taf. Until the work is read, the health Home read stands in.
struct TafWorkPanel: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    /// Its health as Home read it, drawn until the work's own is read.
    let homeHealth: Home.Taf.Health?
    var manages = false
    /// Plan & usage, from the credits fix.
    var openUsage: () -> Void = {}
    /// Needs you's model, which answers a step a request waits on in place of its line; nil draws the line.
    var needsYou: NeedsYouModel? = nil
    /// Whether this person answers the account's held calls (KIFF's `holds.answer`), and the lists read again after.
    var answersHolds = true
    var answered: () async -> Void = {}

    var body: some View {
        Group {
            if model.work != nil || model.workFailure != nil || homeHealth?.needsAttention == true { panel }
        }
        .task { await model.loadWork() }
    }

    private var health: Home.Taf.Health? { model.work?.health ?? homeHealth }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("taf.its_work"))
            if let line = model.work?.shownLine(health: health) {
                Text(verbatim: line).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let health, health.needsAttention { healthLines(health) }
            waitingAndPromise
            ForEach(model.work?.rows ?? []) { row($0) }
            if let failure = model.workFailure {
                Text(verbatim: failure.line(words)).font(.system(size: 13)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .accessibilityIdentifier("taf.work")
    }

    /// Its oldest waiting case, amber once past the promise, then Answer within for whoever manages the taf.
    @ViewBuilder private var waitingAndPromise: some View {
        if let waiting = model.work?.oldestWaiting {
            Text(verbatim: waiting.words).font(.system(size: 14, weight: waiting.late ? .semibold : .regular))
                .foregroundColor(waiting.late ? Theme.amberText : Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("work.oldest-waiting")
        }
        if let work = model.work, manages { promiseRow(work.promiseHours) }
    }

    /// Answer within, as the iPad's `PromiseRow`: the promise as tafs cloud keeps it, or Not set, and a menu of whole
    /// hours to change or clear it. The phones that answer its holds are told when a case waits longer.
    private func promiseRow(_ hours: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(words("work.answer_within")).font(.system(size: 15)).foregroundColor(Theme.ink)
                Spacer(minLength: 8)
                Menu {
                    Button(words("work.answer_within_none")) { if hours != nil { Task { await model.setPromise(hours: nil) } } }
                    ForEach(TafWork.promiseChoices, id: \.self) { choice in
                        Button(TafWork.promise(choice, words: words)) { if choice != hours { Task { await model.setPromise(hours: choice) } } }
                    }
                } label: {
                    Text(verbatim: TafWork.promise(hours, words: words)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("work.answer-within")
            }
            Text(words("work.answer_within_line")).font(.system(size: 12)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One row: a request, with what it used and where its result went, or a skipped firing.
    @ViewBuilder private func row(_ row: TafRuns.Row) -> some View {
        switch row {
        case .skipped(let skipped):
            Text(verbatim: skipped.words).font(.system(size: 13)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        case .request(let request):
            VStack(alignment: .leading, spacing: 2) {
                // A step the taf handed its owner, answered here too, in place of its line, as the iPad's `request(_:)`:
                // Home's, which carries the vendor's link when tafs cloud vouched for it, else the request's own.
                if let step = request.yourStep, let needsYou {
                    RequestStep(needsYou: needsYou, step: step, line: Self.line(request), answersHolds: answersHolds, answered: answered)
                } else {
                    Self.line(request)
                }
                // What the run used, in tafs cloud's words, once KIFF has counted it.
                if let used = request.creditsLine {
                    Text(verbatim: used).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(request.deliveries.enumerated()), id: \.offset) { _, delivery in delivered(delivery, run: request.id) }
            }
        }
    }

    /// Where a result went, and Send again on one given up on, for whoever manages the taf.
    @ViewBuilder private func delivered(_ delivery: TafRuns.Delivery, run: String) -> some View {
        Text(verbatim: delivery.line).font(.system(size: 12)).foregroundColor(delivery.sendAgain ? Theme.amberText : Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
        if delivery.sendAgain, manages {
            let sending = model.sendingAgain.contains(run)
            Button(words(sending ? "work.sending_again" : "work.send_again")) {
                Task { await model.sendAgain(run: run, place: delivery.sendPlace) }
            }
            .buttonStyle(OutlineButtonStyle())
            .fixedSize()
            .disabled(sending)
        }
    }

    /// A taf that isn't healthy, as the iPad's `HealthLines`: each line, amber when at risk and red when failing, with
    /// the fixes tafs cloud decided for it. The credits fix opens Plan & usage. A fix of a kind the app doesn't know
    /// is no button.
    private func healthLines(_ health: Home.Taf.Health) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(health.lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(health.failing ? Theme.no : Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(health.fixes(for: index).enumerated()), id: \.offset) { _, fix in
                    if let act = TafActivityTab.action(fix, openUsage: openUsage) {
                        Button(action: act) { Text(verbatim: fix.words).padding(.horizontal, 16) }
                            .buttonStyle(OutlineButtonStyle())
                            .fixedSize()
                            .accessibilityIdentifier("taf.health.fix.\(fix.kind)")
                    }
                }
            }
        }
        .accessibilityIdentifier("taf.health")
    }

    /// A request's own line, by its state: amber while it needs its owner, red once failed.
    static func line(_ request: TafRuns.Request) -> some View {
        Text(verbatim: request.line).font(.system(size: 14))
            .foregroundColor(request.state == "needs_you" ? Theme.amberText : request.state == "failed" ? Theme.no : Theme.soft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A request that waits on a step its taf handed the owner: the step's card while it can still be
/// answered here (the iPad's `canAnswer(step:)`), Home's copy when listed; else the request's line.
private struct RequestStep<Line: View>: View {
    @ObservedObject var needsYou: NeedsYouModel
    let step: YourStep
    let line: Line
    let answersHolds: Bool
    let answered: () async -> Void

    var body: some View {
        if needsYou.canAnswer(step: step.handoff) {
            YourStepCard(model: needsYou, step: needsYou.listedStep(step.handoff) ?? step, answersHolds: answersHolds,
                         answered: answered, saysWhy: true)
        } else {
            line
        }
    }
}
