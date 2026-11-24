import SwiftUI

/// Account › KIFF account, as the iPad's `AccountView` (SignInView.swift:404-450): the account's
/// name, its id and who is signed in; its time zone, with "Use this Mac's" when the Mac's is
/// another; Export my chats; and at the bottom, set apart, Delete account.
struct KiffAccountPage: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    /// Export my chats; nil leaves it out.
    var exportChats: ExportChatsModel? = nil
    let openZone: () -> Void
    /// Delete account was clicked: deleting is signed by the device key on the iPad, which this
    /// Mac doesn't do, so it says where to do it, and sends nothing.
    @State private var deleteRefused = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(words("settings.kiff_account")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                AccountGroup(nil) { names }
                AccountGroup(nil) { zone }
                AccountRow.footer(words("settings.time_zone.uses_this"))
                if let exportChats {
                    AccountGroup(nil) { ExportChatsRow(model: exportChats) }
                    AccountRow.footer(words("export.own_chats_each_taf_coach"))
                }
                if model.me?.mayDeleteAccount ?? false { delete }
            }
            .padding(.horizontal, Look.inset)
            .padding(.top, 18)
            .padding(.bottom, Look.inset)
            .pageColumn(.reading)
        }
        .background(Theme.background)
    }

    @ViewBuilder private var names: some View {
        AccountRow.value(words("settings.kiff_account"), model.me?.account ?? "")
        if let id = model.me?.accountID {
            AccountRow.divider
            AccountRow.value(words("settings.account_id"), id)
        }
        if let email = model.me?.signedInAs {
            AccountRow.divider
            AccountRow.value(words("settings.signed_in_as"), email)
        }
    }

    /// The account's zone, which a Card's day ends by and every time is read in.
    @ViewBuilder private var zone: some View {
        AccountRow.link(words("settings.time_zone_title"), value: model.zone, openZone)
        let device = TimeZone.current.identifier
        if AccountZone.offersDevice(model.me, device: device) {
            AccountRow.divider
            AccountRow.action(words("settings.use_device_zone", ["device": words("device.mac"), "identifier": device]), color: Theme.amberText) {
                Task { await model.saveZone(device, words: words) }
            }
            .disabled(model.savingZone)
        }
        if let why = model.zoneError {
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Delete account…, in red, apart from every everyday action, and what it deletes.
    @ViewBuilder private var delete: some View {
        AccountGroup(nil) {
            AccountRow.action(words("settings.delete_account.row"), color: Theme.no) { deleteRefused = true }
            if deleteRefused {
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            }
        }
        AccountRow.footer(words("sign_in.deletes_every_taf_runs_chats"))
    }
}

/// Account › Time zone, as the iPad's `TimeZonePicker` (AccountPreferencesView.swift:52-75): Use
/// this Mac's zone, then tafs cloud's zones for the search, the account's ticked. A choice is
/// saved to KIFF as the iPad saves it (`AccountModel.saveZone`).
struct TimeZonePicker: View {
    @Environment(\.words) private var words
    @ObservedObject var model: AccountModel
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(words("settings.time_zone_title")).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                search
                AccountGroup(nil) { device }
                if !model.zones.isEmpty { AccountGroup(nil) { zones } }
            }
            .padding(.horizontal, Look.inset)
            .padding(.top, 18)
            .padding(.bottom, Look.inset)
            .pageColumn(.reading)
        }
        .background(Theme.background)
        // The list for the search, once typing pauses, as the iPad's `.task(id: query)`.
        .task(id: query) {
            let asked = query
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            await model.loadZones(asked, words: words)
        }
    }

    /// A plain search field, as the iPad's `.searchable` prompt says.
    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(Theme.dim).accessibilityHidden(true)
            TextField(words("settings.find_time_zone"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 15))
                .accessibilityLabel(words("settings.search_time_zones"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.raised))
        .padding(.top, 6)
    }

    @ViewBuilder private var device: some View {
        let zone = TimeZone.current.identifier
        AccountRow.action(words("settings.use_device_zone", ["device": words("device.mac"), "identifier": zone]), color: Theme.amberText) {
            Task { await model.saveZone(zone, words: words) }
        }
        .disabled(model.savingZone)
        if let why = model.zoneError {
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var zones: some View {
        ForEach(Array(model.zones.enumerated()), id: \.element.id) { index, zone in
            VStack(spacing: 0) {
                if index > 0 { AccountRow.divider }
                ZoneRow(zone: zone, chosen: model.zone == zone.id) { Task { await model.saveZone(zone.id, words: words) } }
                    .disabled(model.savingZone)
            }
        }
    }
}

/// One zone of the picker: its title, ticked when it's the account's.
private struct ZoneRow: View {
    let zone: TimeZoneChoice
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(verbatim: zone.title).font(.system(size: 17)).foregroundColor(Theme.ink)
                Spacer()
                if chosen { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText) }
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
