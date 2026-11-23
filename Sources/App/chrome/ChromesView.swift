import SwiftUI

/// Account › Chrome, as the iPad's `ChromesView` (tafs docs/chrome.md) and Linux's (tafs-linux#89): the Chromes paired to
/// the account, each named with its browser and system, and Unpair, which ends that Chrome's connections at planque
/// ("Your Chrome" 3). Read and unpaired on planque's safe routes, each signed by this Mac's device key for that one request
/// (`PlanqueClient.Safe`). Pairing a Chrome stays the phone's: it binds the phone's approval key, which the extension trusts.
@MainActor
final class ChromesModel: ObservableObject {
    /// The Chromes; nil until planque offers them (404) or for someone who may only view (403): Account shows no row.
    @Published private(set) var chromes: [PlanqueClient.Chrome]?
    @Published private(set) var error: String?
    @Published private(set) var unpairing: String?
    private let read: () async throws -> [PlanqueClient.Chrome]?
    private let unpair: (String) async throws -> Void

    init(read: @escaping () async throws -> [PlanqueClient.Chrome]?, unpair: @escaping (String) async throws -> Void) {
        self.read = read
        self.unpair = unpair
    }

    func load() async {
        do {
            chromes = try await read()
            error = nil
        } catch {
            // A read that fails keeps what was shown, and says why.
            self.error = Words.app("common.could_not_read_why", ["what": Words.app("chrome.title"), "why": NeedsYouModel.why(error)])
        }
    }

    /// Unpairs one Chrome, then reads the list again either way, so it shows what planque keeps.
    func remove(_ chrome: PlanqueClient.Chrome) async {
        guard unpairing == nil else { return }
        unpairing = chrome.id
        defer { unpairing = nil }
        do {
            try await unpair(chrome.id)
            error = nil
        } catch {
            self.error = Words.app("common.didnt_go_through", ["what": Words.app("chrome.remove_named", ["name": chrome.name]), "why": NeedsYouModel.why(error)])
        }
        await load()
    }
}

struct ChromesView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: ChromesModel
    @State private var removing: PlanqueClient.Chrome?
    @State private var pairAsked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenTitle(title: words("chrome.title"), size: 28, rounded: false).padding(.top, 24)
                if let error = model.error {
                    Text(verbatim: error).font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if (model.chromes ?? []).isEmpty {
                        Text(words("chrome.none")).font(.system(size: 15)).foregroundColor(Theme.dim).padding(.vertical, 12)
                    }
                    ForEach(model.chromes ?? []) { chrome in row(chrome) }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
                Text(words("chrome.footer")).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                // Pairing binds the phone's approval key, which the extension trusts: it stays the phone's.
                Button(words("chrome.pair")) { pairAsked = true }.buttonStyle(OutlineButtonStyle()).frame(maxWidth: 260)
                    .accessibilityIdentifier("chrome.pair")
                if pairAsked {
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(words("chrome.profile_note")).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Look.inset).padding(.bottom, Look.inset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
        .confirmationDialog(removing.map { words("chrome.remove_named", ["name": $0.name]) } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible,
                            presenting: removing) { chrome in
            Button(words("chrome.remove"), role: .destructive) { Task { await model.remove(chrome) } }
            Button(words("common.cancel"), role: .cancel) {}
        }
    }

    private func row(_ chrome: PlanqueClient.Chrome) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: chrome.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if let browser = chrome.browser, let os = chrome.os {
                    Text(words("chrome.browser_on", ["browser": browser, "system": os])).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }
            Spacer()
            Button(words("chrome.remove")) { removing = chrome }
                .buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.no)
                .disabled(model.unpairing != nil)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
