import SwiftUI

/// One run's request, read when its sheet opens, as the iPad's `KnobRequestDetail` (`TafDialPanel.swift:171-230`). Send again
/// (a reply given up on after its tries) goes once more, then the request is read again. A read that fails says why and
/// offers Try again.
@MainActor
final class RequestDetailModel: ObservableObject, Identifiable {
    @Published private(set) var detail: RequestDetail?
    /// Why the last read or Send again failed: tafs cloud's words, else the shared line.
    @Published private(set) var error: String?
    @Published private(set) var sending = false

    private let cloud: CloudClient
    let taf: String
    let run: String
    nonisolated var id: String { run }

    init(cloud: CloudClient, taf: String, run: String) {
        self.cloud = cloud
        self.taf = taf
        self.run = run
    }

    func load() async {
        do {
            detail = try await cloud.request(of: taf, run: run)
            error = nil
        } catch {
            self.error = TafCreditsModel.words(error, what: Words.app("knob.request_title"))
        }
    }

    /// Send again, as the iPad's `sendAgain(_:run:place:)`: it does no work and signs nothing. Then the request is read again.
    func sendAgain(_ delivery: TafRuns.Delivery) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await cloud.sendAgain(of: taf, run: run, place: delivery.sendPlace)
        } catch {
            self.error = TafCreditsModel.words(error, what: Words.app("work.request.try_reply_now"))
            return
        }
        await load()
    }
}

/// A run's request as a sheet: who it came from and its line, each step with its state, and Send again for a delivery tafs
/// cloud offers it on, only for whoever manages the taf ([manages]). Every word is tafs cloud's, drawn as plain text.
struct RequestDetailView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: RequestDetailModel
    let manages: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(words("knob.request_title")).font(Theme.display(22)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
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
            ForEach(Array(detail.deliveries.enumerated()), id: \.offset) { _, delivery in
                if delivery.sendAgain, manages {
                    Button(model.sending ? words("work.sending_again") : words("work.request.try_reply_now")) {
                        Task { await model.sendAgain(delivery) }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(model.sending)
                }
            }
        } else if model.error == nil {
            panel { ProgressView().controlSize(.small) }
        }
        if let error = model.error {
            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            Button(words("common.try_again")) { Task { await model.load() } }.buttonStyle(OutlineButtonStyle())
        }
    }

    /// One step, as the iPad's: done, next, or anything else marked as needing a look; its label, then its line.
    private func stepRow(_ step: RequestDetail.Step) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.state == "done" ? "checkmark.circle.fill" : step.state == "next" ? "clock" : "exclamationmark.circle")
                .foregroundColor(step.state == "done" ? Theme.ok : Theme.amberText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: step.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = step.line {
                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
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
