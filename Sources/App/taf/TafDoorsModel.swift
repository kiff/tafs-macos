import Foundation

/// One taf's doors, for its Setup and its Activity, read from tafs cloud with the person's
/// session, as the iPad's `DoorsModel`.
@MainActor
final class DoorsModel: ObservableObject {
    @Published private(set) var doors: [TafDoors.Door] = []
    @Published private(set) var apps: [TafDoors.App] = []
    @Published private(set) var knocks: [TafDoors.Knock] = []
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?

    private let cloud: CloudClient
    /// tafs cloud's id for the taf.
    private let taf: String

    init(cloud: CloudClient, taf: String) {
        self.cloud = cloud
        self.taf = taf
    }

    var openKnocks: [TafDoors.Knock] { knocks.filter { $0.state == "open" } }

    /// The apps that can still be turned on: one door of each per taf.
    var addable: [TafDoors.App] {
        apps.filter { app in !doors.contains { $0.kind == app.kind } }
    }

    /// Waits between tries of a read that failed: a first request after waking often times out.
    var retryDelays: [UInt64] = [1_000_000_000, 3_000_000_000]

    /// Reads the doors, trying again quietly when a read fails; only a read that keeps
    /// failing says so, in plain words.
    func load() async {
        for attempt in 0...retryDelays.count {
            do {
                let page = try await cloud.doors(of: taf)
                doors = page.doors
                apps = page.apps
                knocks = page.knocks
                loaded = true
                error = nil
                return
            } catch is CancellationError {
                // The screen went away before the read ended: nothing went wrong.
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard attempt < retryDelays.count else { break }
                // Read before the await: Swift 5.7 refuses an actor's property passed into an async call
                // ("cannot be passed 'inout' to 'async' function call").
                let delay = retryDelays[attempt]
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
        }
        error = Words.app("door.not_read")
    }

    /// Turns a door on. WhatsApp's signup runs on a phone: its row says so, and never comes here.
    func add(_ app: TafDoors.App) async -> TafDoors.Door? {
        let cloud = cloud, taf = taf
        return await work { try await cloud.addDoor(taf, app: app.id) }
    }

    func setOpen(_ door: TafDoors.Door, _ open: Bool) async {
        let cloud = cloud, taf = taf
        _ = await work { try await cloud.setDoorOpen(taf, door: door.id, open: open) }
    }

    /// An API door's acts on this Mac's security key, through its PIN sheet, set by the window; nil where this Mac has no
    /// key, and each says to approve on another device.
    var signWithKey: ((KeyAct, String) async throws -> String)?

    /// Opens a paused API door again, on the key, as the iPad's `reopen`: it re-admits a caller the owner may have paused
    /// for misuse. Pausing is `setOpen(false)`, never signed.
    func reopenAPI(_ door: TafDoors.Door) async {
        _ = await signed(.reopenAPIDoor(taf: taf, door: door.id), named: door.label)
    }

    /// Revokes one of an API door's keys, on the key, as the iPad's `revoke`: its next request is refused.
    func revokeAPIKey(_ door: TafDoors.Door, _ key: TafDoors.Door.Key) async {
        guard let changed = await signed(.revokeAPIDoorKey(taf: taf, door: door.id, key: key.id), named: key.shownName) else { return }
        if changed == nil, let i = doors.firstIndex(where: { $0.id == door.id }) { doors[i].keys.removeAll { $0.id == key.id } }
    }

    /// One API door act on the key: the act's request, with the key's assertion over it. Nil when it didn't go (a closed
    /// sheet says nothing; anything else says why), else the door tafs cloud answered, when it answered one.
    private func signed(_ act: KeyAct, named: String) async -> TafDoors.Door?? {
        guard let sign = signWithKey else {
            error = Words.app("approval.device_can_not_approve_approve")
            return nil
        }
        let cloud = cloud
        busy = true
        defer { busy = false }
        do {
            let assertion = try await sign(act, act.title(Words.app, device: named))
            let door = try await cloud.signedDoorChange(act, assertion: assertion)
            if let door, let i = doors.firstIndex(where: { $0.id == door.id }) { doors[i] = door }
            error = nil
            return .some(door)
        } catch is CancellationError {
            return nil
        } catch {
            self.error = NeedsYouModel.why(error)
            return nil
        }
    }

    func remove(_ door: TafDoors.Door) async {
        // An API door is removed on the key, as the iPad's `removeAPI`: its keys stop working with it.
        if door.kind == "api" {
            if await signed(.removeAPIDoor(taf: taf, door: door.id), named: door.label) != nil { doors.removeAll { $0.id == door.id } }
            return
        }
        // A Slack door with a channel subscription: the iPad takes planque's subscription back
        // first, signed (`removeSlackDoor`); with no planque connection it says to start
        // connected tools first and removes nothing. This Mac has none.
        if door.kind == "slack", door.grant != nil, door.trigger != nil {
            error = Words.app("door.start_connected_tools_first_slack", ["device": Words.app("device.mac")])
            return
        }
        let cloud = cloud, taf = taf
        _ = await work { () -> TafDoors.Door? in
            try await cloud.removeDoor(taf, door: door.id)
            self.doors.removeAll { $0.id == door.id }
            return nil
        }
    }

    func pair(_ door: TafDoors.Door, sender: String, name: String) async {
        let sender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else { return }
        let cloud = cloud, taf = taf
        _ = await work { try await cloud.pair(taf, door: door.id, sender: sender, name: name) }
    }

    func unpair(_ door: TafDoors.Door, _ key: TafDoors.Door.Key) async {
        let cloud = cloud, taf = taf
        _ = await work { try await cloud.unpair(taf, door: door.id, sender: key.id) }
    }

    /// The owner's answer to a knock. "do" starts the taf's run from their words.
    func answer(_ knock: TafDoors.Knock, _ action: String, say: String? = nil) async {
        busy = true
        defer { busy = false }
        do {
            try await cloud.answerKnock(taf, knock: knock.id, action: action, say: say)
            // Pairing keeps the message waiting, with Do it and Ignore.
            if action == "pair" { await load() } else { knocks.removeAll { $0.id == knock.id } }
            error = nil
        } catch let refusal as CloudRefusal where refusal.status == 429 && refusal.words == nil {
            // In the app's words, as the chat says it, not tafs cloud's.
            self.error = Words.app("door.knock.too_many")
        } catch {
            self.error = NeedsYouModel.why(error)
        }
    }

    /// A change on tafs cloud that answers with the door: it replaces the one shown.
    private func work(_ change: @escaping () async throws -> TafDoors.Door?) async -> TafDoors.Door? {
        busy = true
        defer { busy = false }
        do {
            guard let door = try await change() else { return nil }
            if let i = doors.firstIndex(where: { $0.id == door.id }) { doors[i] = door } else { doors.append(door) }
            return door
        } catch {
            self.error = NeedsYouModel.why(error)
            return nil
        }
    }
}

/// Each taf's doors, one model per taf, made the first time it's asked for: none for a taf
/// tafs cloud doesn't run, as the iPad's `AppModel.doors(for:)`.
@MainActor
final class DoorModels: ObservableObject {
    private var models: [String: DoorsModel] = [:]
    /// The security key's approval, handed to each taf's doors for an API door's acts; nil without a key.
    var signWithKey: ((KeyAct, String) async throws -> String)? {
        didSet { for model in models.values { model.signWithKey = signWithKey } }
    }

    func model(for taf: Home.Taf, cloud: CloudClient) -> DoorsModel? {
        if let model = models[taf.id] { return model }
        guard let id = taf.tafID else { return nil }
        let model = DoorsModel(cloud: cloud, taf: id)
        model.signWithKey = signWithKey
        models[taf.id] = model
        return model
    }
}
