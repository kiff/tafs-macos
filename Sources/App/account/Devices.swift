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
    /// The account's passkeys, as KIFF lists them, as the iPad's `passkeys`.
    @Published private(set) var passkeys: [Passkey] = []
    /// Why they couldn't be read; nil once they were.
    @Published private(set) var passkeysUnread: String?
    /// Why the last Remove of a passkey didn't go through, as the iPad's `passkeysError`; nil once one did.
    @Published private(set) var passkeyNotRemoved: String?
    /// The passkey being removed now: its Remove waits.
    @Published private(set) var removingPasskey: String?
    /// Each read of the passkeys takes the next number, and so does a removal, as the iPad's `passkeysRead`: only the
    /// newest read's list is kept, so a read that started before a Remove never brings the removed passkey back.
    private var passkeysRead = 0
    /// Whether this person removes the account's passkeys (an owner or an admin, `Me.managesPasskeys`). Set by the
    /// window once KIFF says who is signed in.
    var managesPasskeys = false

    /// KIFF's refusals that mean "this needs an approval".
    static let approvalCodes: Set<String> = ["approval_key_required", "critical_key_required"]

    private let account: AccountClient
    /// Whether this Mac may sign another device out. Signing out a device that approves is an
    /// approval, so only a Mac that can sign one may: without it no button is drawn, and
    /// nothing is ever sent.
    let canRemoveOthers: Bool
    /// This Mac's security key, when it approves with one (kiff/cloud#96): signing another device out is then
    /// approved by the key, one request, named in the PIN sheet. Set by the window once its session is known.
    var approveWithKey: ((KeyAct, String) async throws -> Data)?

    init(account: AccountClient, canRemoveOthers: Bool = false) {
        self.account = account
        self.canRemoveOthers = canRemoveOthers
    }

    /// Whether this Mac may sign another device out: with an approval key, or with its security key.
    var mayRemoveOthers: Bool { canRemoveOthers || approveWithKey != nil }

    func load() async {
        do { state = .loaded(try await account.devices()) } catch { state = .unread(why: NeedsYouModel.why(error)) }
    }

    /// The account's passkeys, as the iPad's `refreshPasskeys()`: read unsigned, as the devices
    /// are. A read that fails keeps what was read, and says why.
    func loadPasskeys() async {
        let account = self.account
        passkeysRead += 1
        let read = passkeysRead
        do {
            let listed = try await account.passkeys()
            guard read == passkeysRead else { return }
            passkeys = listed
            passkeysUnread = nil
        } catch {
            guard read == passkeysRead else { return }
            passkeysUnread = NeedsYouModel.why(error)
        }
    }

    /// Why it didn't go through, in the app's words, as the iPad's `error.localizedDescription`: KIFF's refusal reads
    /// through `PlainError.words(status:)` (`StepRefusal.plainKey`), never KIFF's code; a 401 is signed out; the
    /// security key's own failures and "Approve on your phone instead" say theirs (`NeedsYouModel.why`).
    static func plainWhy(_ error: Error) -> String {
        if case KIFFError.refused(let status, _) = error, status != 0 {
            return Words.app(status == 401 ? "error.signed_out" : StepRefusal.plainKey(status: status))
        }
        return NeedsYouModel.why(error)
    }

    /// Whether a passkey's row offers Remove, as the iPad's (`passkey.removable, model.canAddPasskey`): one of the
    /// account's own (never a computer's, which goes with its computer), for an owner or admin, on a Mac that approves
    /// with its security key. Elsewhere there's no Remove, and nothing is ever sent.
    func offersRemove(_ passkey: Passkey) -> Bool {
        passkey.removable && managesPasskeys && approveWithKey != nil
    }

    /// Removes one of the account's own passkeys, as the iPad's `removePasskey`: KIFF's `DELETE /v1/me/passkeys/{id}`,
    /// approved by this Mac's security key once (`KeyAct.removePasskey`), named in its sheet as the iPad's prompt
    /// ("Remove the passkey {name} from your account"). Then it leaves the list and the list is read again; a read that
    /// started before it is dropped. A closed sheet sends nothing and says nothing; anything else says it didn't go
    /// through, with why, as the iPad's `didntGoThrough`.
    func removePasskey(_ passkey: Passkey) async {
        guard offersRemove(passkey), let id = passkey.passkeyID, let approveWithKey, removingPasskey == nil else { return }
        removingPasskey = id
        let act = KeyAct.removePasskey(id: id)
        let what = act.title(Words.app, device: passkey.name ?? Words.app("settings.devices.unnamed"))
        do {
            _ = try await approveWithKey(act, what)
        } catch is CancellationError {
            removingPasskey = nil
            return
        } catch {
            passkeyNotRemoved = Words.app("common.didnt_go_through", ["what": what, "why": Self.plainWhy(error)])
            removingPasskey = nil
            return
        }
        passkeyNotRemoved = nil
        passkeysRead += 1
        passkeys.removeAll { $0.passkeyID == id }
        removingPasskey = nil
        await loadPasskeys()
    }

    /// A device's red Sign out, clicked: true to ask to confirm it. A Mac that can't approve
    /// sends nothing and says that it takes a device that can approve, as signing a device out
    /// is an approval (the iPad's `removeDevice` signs it with the approval key).
    func signOutClicked(_ device: Device) -> Bool {
        guard !device.thisDevice else { return false }
        guard mayRemoveOthers else {
            notRemoved = nil
            needsApprover = true
            return false
        }
        return true
    }

    /// Signs another device out, then reads the list again. This Mac is never removed here:
    /// it signs out with Sign out, which also forgets its session.
    func remove(_ device: Device) async {
        guard mayRemoveOthers, !device.thisDevice else { return }
        do {
            if let approveWithKey {
                // The security key approves this one request (`DELETE /v1/me/devices/{id}`), named in its sheet.
                let act = KeyAct.signOutDevice(id: device.id)
                _ = try await approveWithKey(act, act.title(Words.app, device: device.name ?? Words.app("settings.devices.unnamed")))
            } else {
                try await account.removeDevice(device.id)
            }
            notRemoved = nil
            needsApprover = false
            await load()
        } catch is CancellationError {
            // The security key's sheet closed: nothing was sent, and nothing is said.
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
    /// Whether this person removes the account's passkeys (`Me.managesPasskeys`), as KIFF last said.
    var managesPasskeys = false
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
            .pageColumn(.reading)
        }
        .background(Theme.background)
        .task {
            model.managesPasskeys = managesPasskeys
            await model.load()
            await model.loadPasskeys()
        }
        .onChange(of: managesPasskeys) { model.managesPasskeys = $0 }
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
            } else if model.mayRemoveOthers {
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

/// Devices' Passkeys, as the iPad's `passkeys` section (DevicesView.swift:86-128): each passkey by its name, a
/// computer's own saying it goes with its computer, and Remove for one of the account's own where this Mac's security
/// key approves (`DevicesModel.offersRemove`), confirmed first, with the iPad's warning when it's the last one. Add is
/// the phone's: macOS 12 makes no platform passkey, and a second security key is paired from the phone.
struct DevicesPasskeys: View {
    @Environment(\.words) private var words
    @ObservedObject var model: DevicesModel
    /// The passkey whose Remove was clicked, to confirm.
    @State private var confirming: Passkey?

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
            if let line = model.passkeyNotRemoved {
                Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.no)
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

    /// A passkey: its name, else Unnamed; a computer's own says it goes with its computer. One of the account's own
    /// has a red Remove at its end where this Mac may remove it.
    private func row(_ passkey: Passkey) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(passkey.name ?? words("settings.devices.unnamed")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if !passkey.removable {
                    Text(words("settings.devices.passkey_with_computer")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if model.offersRemove(passkey) {
                if model.removingPasskey == passkey.passkeyID { ProgressView().controlSize(.small) }
                Button(words("settings.devices.passkey_remove")) { confirming = passkey }
                    .buttonStyle(.plain).font(.system(size: 15)).foregroundColor(Theme.no)
                    .disabled(model.removingPasskey != nil)
                    .accessibilityIdentifier("devices.passkey.remove")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .alert(confirming.map { words("settings.devices.passkey_remove_named", ["name": $0.name ?? words("settings.devices.unnamed")]) } ?? "",
               isPresented: Binding(get: { confirming?.isSamePasskey(as: passkey) == true }, set: { if !$0 { confirming = nil } })) {
            Button(words("settings.devices.passkey_remove"), role: .destructive) {
                Task { await model.removePasskey(passkey) }
                confirming = nil
            }
            Button(words("common.cancel"), role: .cancel) { confirming = nil }
        } message: {
            // The last passkey says so before it goes, as the iPad's.
            if Passkey.removesLast(passkey, among: model.passkeys) { Text(words("settings.devices.passkey_remove_last")) }
        }
    }
}
