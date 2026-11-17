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
    /// The account's passkeys, as KIFF lists them, as the iPad's `passkeys`; read-only here.
    @Published private(set) var passkeys: [Passkey] = []
    /// Why they couldn't be read; nil once they were.
    @Published private(set) var passkeysUnread: String?

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

    /// The account's passkeys, as the iPad's `refreshPasskeys()`: read unsigned, as the devices
    /// are. A read that fails keeps what was read, and says why.
    func loadPasskeys() async {
        let account = self.account
        do {
            passkeys = try await account.passkeys()
            passkeysUnread = nil
        } catch {
            passkeysUnread = NeedsYouModel.why(error)
        }
    }

    /// A device's red Sign out, clicked: true to ask to confirm it. A Mac that can't approve
    /// sends nothing and says that it takes a device that can approve, as signing a device out
    /// is an approval (the iPad's `removeDevice` signs it with the approval key).
    func signOutClicked(_ device: Device) -> Bool {
        guard !device.thisDevice else { return false }
        guard canRemoveOthers else {
            notRemoved = nil
            needsApprover = true
            return false
        }
        return true
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
    /// Signs this Mac out of KIFF, as Account's Sign out does: KIFF ends the session, and the
    /// Mac forgets it. A view-only device can always leave.
    var signOutThisMac: () -> Void = {}
    /// This Mac's own pairing, in the place of the iPad's Add a device: adding this view-only
    /// Mac with the phone (Account's Add this Mac). Nil leaves it out.
    var addThisMac: (() -> Void)? = nil
    @State private var removing: Device?
    /// Another device whose row's Sign out was clicked, to confirm.
    @State private var signingOut: Device?
    /// The device whose sheet is open.
    @State private var chosen: Device?
    @State private var confirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(words("settings.devices.title")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                list
                if model.needsApprover {
                    Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.no)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let why = model.notRemoved {
                    Text(words("sign_in.not_signed_out_device", ["why": why, "device": words("device.mac")]))
                        .font(.system(size: 13)).foregroundColor(Theme.no)
                }
                // The iPad's footer, under the list.
                Text(words("settings.devices.note_device", ["device": words("device.mac")]))
                    .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if let addThisMac { addRow(addThisMac) }
                DevicesPasskeys(model: model)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task {
            await model.load()
            await model.loadPasskeys()
        }
        .sheet(item: $chosen) { device in deviceSheet(device) }
        .alert(signingOut.map { words("settings.devices.sign_out_named", ["device": $0.name ?? words("settings.devices.unnamed")]) } ?? "",
               isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } })) {
            Button(words("settings.devices.sign_out"), role: .destructive) {
                if let device = signingOut { Task { await model.remove(device) } }
                signingOut = nil
            }
            Button(words("common.cancel"), role: .cancel) { signingOut = nil }
        }
    }

    @ViewBuilder private var list: some View {
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
    }

    /// A device, as the iPad's row: its name (15 semibold) and when it was last used (13 dim),
    /// which open its sheet; at the end, This device, or another's red Sign out.
    private func row(_ device: Device) -> some View {
        HStack(spacing: 12) {
            Button { chosen = device } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name ?? words("settings.devices.unnamed")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(lastUsed(device.lastUsed)).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if device.thisDevice {
                Text(words("settings.devices.this_device_title")).font(.system(size: 13)).foregroundColor(Theme.dim)
            } else {
                // Drawn on every other device, as on the iPad; a Mac that can't approve says why
                // when it's clicked, and sends nothing.
                Button(words("settings.devices.sign_out")) { if model.signOutClicked(device) { signingOut = device } }
                    .buttonStyle(.plain).font(.system(size: 15)).foregroundColor(Theme.no)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// This Mac's own pairing, with the iPad's computer mark, in a panel of its own.
    private func addRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(.system(size: 15)).accessibilityHidden(true)
                Text(words("pair.view_only.add", ["device": words("device.mac")])).font(.system(size: 15))
                Spacer()
            }
            .foregroundColor(Theme.amberText)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    /// One device: its name and when it was last used. This Mac signs out of KIFF here, as
    /// Account's Sign out does. Another device has Sign out when this Mac may sign it out;
    /// else the shared line that it takes a device that can approve.
    func deviceSheet(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(device.name ?? words("settings.devices.unnamed")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
            Text(lastUsed(device.lastUsed)).font(.system(size: 13)).foregroundColor(Theme.dim)
            if device.thisDevice {
                Text(words("settings.devices.this_device_title")).font(.system(size: 13)).foregroundColor(Theme.dim)
                Button(words("settings.sign_out")) { confirmingSignOut = true }
                    .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.no)
            } else if model.canRemoveOthers {
                Button(words("settings.devices.sign_out")) { removing = device }
                    .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.no)
            } else {
                Text(words("settings.devices.signout_needs_approver")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(words("common.done")) { chosen = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380, alignment: .leading)
        .background(Theme.background)
        .alert(removing.map { words("settings.devices.sign_out_named", ["device": $0.name ?? words("settings.devices.unnamed")]) } ?? "",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(words("settings.devices.sign_out"), role: .destructive) {
                if let device = removing { Task { await model.remove(device) } }
                removing = nil
                chosen = nil
            }
            Button(words("common.cancel"), role: .cancel) { removing = nil }
        }
        // Confirmed on the sheet itself, so a stray click never ends the session.
        .alert(words("settings.sign_out_of_kiff.title"), isPresented: $confirmingSignOut) {
            Button(words("settings.sign_out"), role: .destructive) { chosen = nil; signOutThisMac() }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("settings.sign_out_of_kiff.body_device", ["device": words("device.mac")]))
        }
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

/// Devices' Passkeys, as the iPad's `passkeys` section (DevicesView.swift:86-128), read-only on
/// this Mac: each passkey by its name, a computer's own saying it goes with its computer. Remove
/// and Add are the iPad's for a session that approves, which this Mac isn't.
struct DevicesPasskeys: View {
    @Environment(\.words) private var words
    @ObservedObject var model: DevicesModel

    /// Drawn only with something in it: an empty heading reads as broken.
    var body: some View {
        if !model.passkeys.isEmpty || model.passkeysUnread != nil { section }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(words("settings.devices.passkeys_title")).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.soft)
                .padding(.top, 10)
            if let why = model.passkeysUnread {
                Text(words("settings.devices.passkeys_not_loaded", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.passkeys.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.passkeys.enumerated()), id: \.offset) { index, passkey in
                        row(passkey)
                        if index < model.passkeys.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
        }
    }

    /// A passkey: its name, else Unnamed; a computer's own says it goes with its computer.
    private func row(_ passkey: Passkey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(passkey.name ?? words("settings.devices.unnamed")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
            if !passkey.removable {
                Text(words("settings.devices.passkey_with_computer")).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
