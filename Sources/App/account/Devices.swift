import SwiftUI

/// The account's devices, for Account → Devices: each one listed, with its own Sign out.
@MainActor
final class DevicesModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([Device])
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// Why the last removal wasn't taken.
    @Published private(set) var notRemoved: String?
    /// The last removal needs a device that can approve: signing out a device that approves
    /// is itself an approval, which this Mac can't give.
    @Published private(set) var needsApprover = false

    /// KIFF's refusals that mean "this needs an approval".
    static let approvalCodes: Set<String> = ["approval_key_required", "critical_key_required"]

    private let account: AccountClient
    /// Whether this Mac may sign another device out. Signing out a device that approves is an
    /// approval, so only a Mac that can sign one may: without it no button is drawn, and
    /// nothing is ever sent.
    let canRemoveOthers: Bool

    init(account: AccountClient, canRemoveOthers: Bool = false) {
        self.account = account
        self.canRemoveOthers = canRemoveOthers
    }

    func load() async {
        do { state = .loaded(try await account.devices()) } catch { state = .unread(why: NeedsYouModel.why(error)) }
    }

    /// Signs another device out, then reads the list again. This Mac is never removed here:
    /// it signs out with Sign out, which also forgets its session.
    func remove(_ device: Device) async {
        guard canRemoveOthers, !device.thisDevice else { return }
        do {
            try await account.removeDevice(device.id)
            notRemoved = nil
            needsApprover = false
            await load()
        } catch KIFFError.refused(status: 403, code: let code) where Self.approvalCodes.contains(code) {
            notRemoved = nil
            needsApprover = true
        } catch {
            needsApprover = false
            notRemoved = NeedsYouModel.why(error)
        }
    }
}

struct DevicesView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: DevicesModel
    var now = Date()
    @State private var removing: Device?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("settings.devices.title")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("settings.devices.not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                case .loaded(let devices):
                    VStack(spacing: 0) {
                        ForEach(devices) { device in
                            row(device)
                            if device.id != devices.last?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                }
                if model.needsApprover {
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.no)
                }
                if let why = model.notRemoved {
                    Text(words("sign_in.not_signed_out_device", ["why": why, "device": words("device.mac")]))
                        .font(.system(size: 13)).foregroundColor(Theme.no)
                }
                if model.canRemoveOthers {
                    Text(words("settings.devices.note_device", ["device": words("device.mac")]))
                        .font(.system(size: 13)).foregroundColor(Theme.dim)
                } else {
                    // Where another device is signed out: on a device that can approve.
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
        .alert(removing.map { words("settings.devices.sign_out_named", ["device": $0.name ?? words("settings.devices.unnamed")]) } ?? "",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(words("settings.devices.sign_out"), role: .destructive) {
                if let device = removing { Task { await model.remove(device) } }
                removing = nil
            }
            Button(words("common.cancel"), role: .cancel) { removing = nil }
        }
    }

    private func row(_ device: Device) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name ?? words("settings.devices.unnamed")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Text(lastUsed(device.lastUsed)).font(.system(size: 13)).foregroundColor(Theme.dim)
                if let fingerprint = device.keyFingerprint {
                    Text(verbatim: fingerprint).font(Theme.mono(12)).foregroundColor(Theme.dim).textSelection(.enabled)
                }
            }
            Spacer()
            if device.thisDevice {
                Text(words("settings.devices.this_device_title")).font(.system(size: 13)).foregroundColor(Theme.dim)
            } else if model.canRemoveOthers {
                Button(words("settings.devices.sign_out")) { removing = device }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    .accessibilityLabel(words("settings.devices.sign_out_prompt", ["device": device.name ?? words("settings.devices.unnamed")]))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// "Last used 3 hours ago", or "Not used yet".
    private func lastUsed(_ date: Date?) -> String {
        guard let date else { return words("settings.devices.not_used") }
        guard now.timeIntervalSince(date) >= 60 else { return words("settings.devices.used_just_now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: words.language)
        return words("settings.devices.last_used", ["ago": formatter.localizedString(for: date, relativeTo: now)])
    }
}
