import SwiftUI

/// A door "From another application" (`api`, docs/doors.md), as the iPad's `APIDoorPanel`: a company's own software
/// hands the taf work with a key. Today's count against its cap, its last request in tafs cloud's words, its keys (at most
/// two, each by its last four) with Revoke, and Remove door. Pausing is never signed; opening it again, Revoke and Remove
/// are approved on this Mac's security key, as a removal is. A new key stays the phone's: this Mac can't
/// keep a key shown once out of screen recording or the clipboard's history.
struct APIDoorPanel: View {
    @Environment(\.words) private var words
    let door: TafDoors.Door
    let taf: Home.Taf
    @ObservedObject var doors: DoorsModel
    /// Remove door, asked first by the door's screen.
    let remove: () -> Void
    @State private var revoking: TafDoors.Door.Key?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DoorPanel {
                HStack(spacing: 12) {
                    DoorBadge(app: door.app, open: door.open, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: words("door.api.kind"))
                        Text(verbatim: door.label).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    }
                    Spacer()
                    // Pausing is never signed; opening it again is, on the key.
                    Toggle(words("door.status.open"), isOn: Binding(get: { door.open }, set: { on in
                        Task { if on { await doors.reopenAPI(door) } else { await doors.setOpen(door, false) } }
                    }))
                    .labelsHidden().toggleStyle(.switch).disabled(doors.busy)
                    .accessibilityIdentifier("door.api.open")
                }
                if !door.open {
                    Text(words("door.api.paused")).font(.system(size: 14)).foregroundColor(Theme.amberText).fixedSize(horizontal: false, vertical: true)
                }
                Eyebrow(text: words("door.api.today"))
                Meter(fraction: Double(door.today) / Double(max(door.limit, 1)), color: Theme.tafColor(taf.color))
                Text(words.count("door.api.of_limit", door.today, ["limit": words.number(door.limit)]))
                    .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.soft)
                // Only in tafs cloud's words: the app never words a state itself.
                if let last = door.lastRequest, let said = last.shownWords {
                    Text(words("door.api.last_request", ["time": Self.when(last.at, words: words) ?? last.at, "status": said]))
                        .font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("door.api.last_request")
                }
            }
            DoorPanel {
                Eyebrow(text: words("door.api.keys"))
                ForEach(door.keys) { key in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: key.name ?? key.id).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                            Text(verbatim: Self.keyLine(key, words: words)).font(.system(size: 12)).foregroundColor(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(words("taf.revoke")) { revoking = key }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.no)
                            .disabled(doors.busy)
                            .accessibilityIdentifier("door.api.revoke." + key.id)
                    }
                }
                Text(words("door.api.two_keys")).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                Text(words("door.api.boundary", ["taf": taf.name])).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive, action: remove) {
                    Text(words("door.remove_door")).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.no)
                }
                .buttonStyle(.plain)
                .disabled(doors.busy)
            }
        }
        .confirmationDialog(words("door.api.revoke_title", ["key": revoking?.shownName ?? ""]),
                            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible, presenting: revoking) { key in
            Button(words("taf.revoke"), role: .destructive) { Task { await doors.revokeAPIKey(door, key) } }
            Button(words("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(words("door.api.revoke_body"))
        }
    }

    /// A time from tafs cloud, shown medium with a short time; nil when it isn't one.
    static func when(_ iso: String?, words: Words) -> String? {
        guard let iso else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        return AppDates.formatter(words, date: .medium, time: .short).string(from: date)
    }

    /// The key's line: made, last used or not yet, and its last four. Never the key.
    static func keyLine(_ key: TafDoors.Door.Key, words: Words) -> String {
        let made = when(key.madeAt, words: words) ?? "", last4 = key.last4 ?? ""
        if let used = when(key.lastUsedAt, words: words) { return words("door.api.key_line", ["made": made, "used": used, "last4": last4]) }
        return words("door.api.key_never_used", ["made": made, "last4": last4])
    }
}
