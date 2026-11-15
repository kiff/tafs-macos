import SwiftUI

/// One halt, a taf's or with none the account's: read when shown, halted with one click, and
/// read again every 2 seconds while it is halting, for up to 2 minutes, as the iPad's.
@MainActor
final class HaltModel: ObservableObject {
    @Published private(set) var halt: Halt = .running
    @Published private(set) var busy = false
    /// Why the last halt wasn't taken, in the shared words.
    @Published private(set) var notHalted: String?

    private let cloud: CloudClient
    /// tafs cloud's id for the taf; nil for every taf of the account.
    let taf: String?
    private let sleep: (UInt64) async -> Void

    init(cloud: CloudClient, taf: String?, sleep: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }) {
        self.cloud = cloud
        self.taf = taf
        self.sleep = sleep
    }

    func refresh() async {
        if let read = try? await cloud.halted(taf) { halt = read }
    }

    /// One click, no key: it only takes authority away. True when tafs cloud answered: then the
    /// list is read again at once (`halted`), still busy, as the iPad's `halt` with its `refresh()`,
    /// and the halt followed while it is halting.
    @discardableResult
    func halt(words: Words, halted: () async -> Void = {}) async -> Bool {
        guard !busy else { return false }
        busy = true
        notHalted = nil
        do {
            halt = try await cloud.halt(taf)
        } catch {
            // tafs cloud's words, else its error, else its status, as the iPad's `CloudError`.
            notHalted = words(taf == nil ? "taf.halt.not_halted_all" : "taf.halt.not_halted", ["why": NeedsYouModel.why(error)])
            busy = false
            return false
        }
        await halted()
        busy = false
        return true
    }

    /// While it is halting: read again every 2 seconds, at most 60 times.
    func follow() async {
        for _ in 0..<60 where halt.state == .halting {
            await sleep(2_000_000_000)
            await refresh()
        }
    }
}

/// The row that opens a halt, with where it stands, as the iPad's `HaltRow`.
struct HaltRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: HaltModel
    @State private var open = false
    /// The taf's name; nil for every taf.
    let name: String?
    /// Shown while every taf runs; else only once halted or halting, as the account's row is
    /// shown with no taf while the account is halted, where it is resumed from.
    var whileRunning = true
    /// Reads the list again after a halt tafs cloud answered, so it reads halted at once, as
    /// the iPad's `halt` refreshes (kiff/tafs#236, item 13).
    var halted: () async -> Void = {}

    var body: some View {
        if whileRunning || model.halt.state != .running {
            row
        } else {
            // Nothing to show yet, but where it stands is still read.
            Color.clear.frame(height: 0).task { await model.refresh() }
        }
    }

    private var row: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: model.halt.state == .running ? "hand.raised" : "hand.raised.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.no)
                VStack(alignment: .leading, spacing: 2) {
                    Text(words(model.taf == nil ? "taf.halt.title_all" : "taf.halt.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(model.halt.state == .running ? words("halt.row_running") : model.halt.headline(words))
                        .font(.system(size: 13)).foregroundColor(model.halt.state == .running ? Theme.dim : Theme.no)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.dim)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            // The whole row opens it, padding too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await model.refresh() }
        .sheet(isPresented: $open) { HaltView(model: model, name: name, halted: halted) { open = false } }
    }
}

/// A halt's own screen, as the iPad's `HaltScreen`: where it stands, who holds it, and Halt now.
/// Resuming is signed, so on this Mac it says where to resume instead.
struct HaltView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: HaltModel
    let name: String?
    var halted: () async -> Void = {}
    let close: () -> Void

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let h = model.halt
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(words(model.taf == nil ? "taf.halt.title_all" : "taf.halt.title")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            panel {
                Eyebrow(text: name ?? words("taf.halt.all_tafs"), color: h.state == .running ? Theme.dim : Theme.no)
                Text(h.headline(words)).font(Theme.display(26)).foregroundColor(Theme.ink)
                Text(h.explanation(all: model.taf == nil, words, time: { Self.clock.string(from: $0) }))
                    .font(.system(size: 15)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            if h.state != .running {
                panel {
                    Eyebrow(text: words("taf.halt.who_holds"))
                    hold(words("taf.halt.no_run_starts"), h.runtime)
                    hold(words("taf.halt.kiff_refuses"), h.kiff)
                    hold(words("taf.halt.connection_sends_nothing"), h.planque)
                    if h.account, model.taf != nil {
                        Text(words("taf.halt.halted_with_all")).font(.system(size: 13)).foregroundColor(Theme.dim)
                    }
                }
            }
            switch h.state {
            case .running:
                Button(model.busy ? words("taf.halt.halting") : words(model.taf == nil ? "halt.all_now" : "halt.now")) {
                    Task { if await model.halt(words: words, halted: halted) { await model.follow() } }
                }
                .buttonStyle(OutlineButtonStyle(color: Theme.no))
                .disabled(model.busy)
            case .halting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(words("taf.halt.halting_wait")).font(.system(size: 14)).foregroundColor(Theme.dim)
                }
                // Halt again: a part that didn't take it the first time is asked again.
                Button(words("halt.again")) { Task { if await model.halt(words: words, halted: halted) { await model.follow() } } }
                    .buttonStyle(OutlineButtonStyle(color: Theme.no))
                    .disabled(model.busy)
            case .halted:
                // Resuming gives authority back, so it's signed: until this Mac can sign it, the
                // iPad's line for an approval that can't be made here (`Biometry.short`).
                if !(h.account && model.taf != nil) {
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let why = model.notHalted {
                Text(verbatim: why).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .background(Theme.background)
        .task { await model.refresh(); await model.follow() }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
    }

    /// One part of a halt, and whether it holds it yet, as the iPad's `HoldRow`.
    private func hold(_ text: String, _ held: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: held ? "checkmark.circle.fill" : "circle.dotted").foregroundColor(held ? Theme.ok : Theme.dim)
            Text(text).font(.system(size: 15)).foregroundColor(Theme.ink)
            Spacer()
            Text(words(held ? "taf.halt.part_held" : "taf.halt.part_waiting")).font(.system(size: 13)).foregroundColor(Theme.dim)
        }
    }
}
