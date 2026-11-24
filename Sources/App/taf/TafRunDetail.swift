import SwiftUI

/// One run, opened from its line, as the iPad's `KnobRequestDetail` (`TafDialPanel.swift:171-238`): read when it opens,
/// with Try again when it can't be; Send again for a delivery that offers it, for whoever manages the taf, and the run
/// read again after.
@MainActor
final class TafRunModel: ObservableObject {
    @Published private(set) var detail: TafRequest?
    /// Why the read failed, in tafs cloud's words.
    @Published private(set) var error: String?
    /// Send again is on its way: a second click sends nothing.
    @Published private(set) var sending = false

    private let cloud: CloudClient
    let taf: String
    let run: String

    init(cloud: CloudClient, taf: String, run: String) {
        self.cloud = cloud
        self.taf = taf
        self.run = run
    }

    func load() async {
        do {
            detail = try await cloud.request(of: taf, run: run)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = NeedsYouModel.why(error)
        }
    }

    /// Send again, as the iPad's `sendAgain(_:run:place:)`: the delivery once more, then the run read again, whatever came
    /// of it. Only for whoever manages the taf; tafs cloud checks it too.
    func sendAgain(_ delivery: TafRuns.Delivery, manages: Bool) async {
        guard manages, delivery.sendAgain, !sending else { return }
        sending = true
        var failed: String?
        do { try await cloud.sendAgain(of: taf, run: run, place: delivery.sendPlace) } catch {
            failed = Words.app("work.not_sent_again", ["why": NeedsYouModel.why(error)])
        }
        sending = false
        await load()
        if let failed { error = failed }
    }
}

/// The run's sheet: tafs cloud's heading and line, its steps marked done, next or failed, Send again, and Ask Coach.
struct TafRunSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafRunModel
    /// Whether this person manages the taf: Send again, and Ask Coach with `askCoach`.
    var manages = false
    /// Opens Coach, for someone who may use it; nil draws no Ask Coach.
    var askCoach: (() -> Void)? = nil
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(words("knob.request_title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.background)
        .task(id: model.run) { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if let detail = model.detail {
            panel {
                Eyebrow(text: detail.from)
                Text(verbatim: detail.line).font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if !detail.steps.isEmpty {
                panel { ForEach(Array(detail.steps.enumerated()), id: \.offset) { _, step in stepRow(step) } }
            }
            ForEach(Array(detail.sendsAgain(manages: manages).enumerated()), id: \.offset) { _, delivery in
                Button(model.sending ? words("work.sending_again") : words("work.request.try_reply_now")) {
                    Task { await model.sendAgain(delivery, manages: manages) }
                }
                .buttonStyle(OutlineButtonStyle()).fixedSize().disabled(model.sending)
            }
            if manages, let askCoach {
                Button(words("coach.ask")) {
                    close()
                    askCoach()
                }
                .buttonStyle(OutlineButtonStyle()).fixedSize()
            }
        } else if model.error == nil {
            ProgressView().controlSize(.small)
        }
        if let error = model.error {
            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            Button(words("common.try_again")) { Task { await model.load() } }.buttonStyle(OutlineButtonStyle()).fixedSize()
        }
    }

    private func stepRow(_ step: TafRequest.Step) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.mark == .done ? "checkmark.circle.fill" : step.mark == .next ? "clock" : "exclamationmark.circle")
                .foregroundColor(step.mark == .done ? Theme.ok : Theme.amberText)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: step.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = step.line {
                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }
}

/// A run opened: its model, for a sheet.
struct OpenRun: Identifiable {
    let model: TafRunModel
    var id: String { model.run }
}
