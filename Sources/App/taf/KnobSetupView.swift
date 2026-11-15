import SwiftUI

/// A taf's dial, as Setup's Starts when and Results go to read and change it: the iPad's
/// `loadKnob`, `adjustKnob`, `changeKnob`, `setResultPlaces`, `removeFollowUp` and `setPaused`
/// (`App/AppModel.swift:2372-2394, 2528-2562, 3215-3268`).
@MainActor
final class TafKnobModel: ObservableObject {
    /// The dial as tafs cloud last sent it; nil until it's read.
    @Published private(set) var knob: Knob?
    /// The dial's last change, its next version, until the owner switches to it.
    @Published private(set) var change: Knob.Change?
    /// What went wrong last, where the iPad says it in its error line.
    @Published var lastError: String?
    /// The error shown is the dial's own read's: a read that works clears it.
    private var errorFromKnob = false

    private let cloud: CloudClient
    let taf: String

    init(cloud: CloudClient, taf: String) {
        self.cloud = cloud
        self.taf = taf
    }

    /// Reads the dial; with a change waiting, that version's, else (installed or replaced
    /// meanwhile, 404) the dial as it is now.
    func load(words: Words) async {
        do {
            var read = try await cloud.knob(of: taf)
            if let pending = read.pending {
                do { read = try await cloud.knob(of: taf, version: pending.version) }
                catch KIFFError.refused(let status, _) where status == 404 { read = try await cloud.knob(of: taf) }
            }
            knob = read
            if errorFromKnob { lastError = nil; errorFromKnob = false }
            // Its change is live now: nothing left to switch to.
            if let made = change, let live = read.version, live >= made.version { change = nil }
        } catch {
            lastError = words("knob.dial_could_not_read", ["why": NeedsYouModel.why(error)])
            errorFromKnob = true
        }
    }

    /// Whether a stop's size can move that way: the newest draft known here allows a choice.
    func canMove(_ item: Knob.Item, _ direction: Int) -> Bool {
        guard let knob else { return false }
        return knob.acceptsChoices(waitingFor: change?.version) && item.size?.choice(moving: direction) != nil
    }

    /// A fixed size offered by tafs cloud, with every other setting as it is.
    @discardableResult
    func adjust(_ item: Knob.Item, _ direction: Int, manages: Bool, words: Words) async -> Bool {
        guard manages, let knob, knob.acceptsChoices(waitingFor: change?.version),
              let current = Knob.Ring.allCases.flatMap({ knob.items($0) }).first(where: { $0.id == item.id }),
              current == item, let choice = current.size?.choice(moving: direction) else { return false }
        guard await changeKnob({ $0 = choice.setting }, manages: manages, words: words) else { return false }
        await load(words: words)
        return true
    }

    /// Changes one thing of the dial: its live `setting` copied, changed, and sent whole
    /// (`PUT …/knob`). tafs cloud makes the next version; nothing runs from it until the owner
    /// switches to it.
    func changeKnob(_ edit: (inout Knob.Setting) -> Void, manages: Bool, words: Words) async -> Bool {
        guard manages, let setting = knob?.setting else { return false }
        var changed = setting
        edit(&changed)
        guard changed != setting else { return false }
        do {
            change = try await cloud.putKnob(of: taf, changed)
            return true
        } catch {
            lastError = words("knob.dial_did_not_change", ["why": NeedsYouModel.why(error)])
            return false
        }
    }

    /// tafs' own places for its results (`PUT …/results`), live at once; then the tafs and the
    /// dial are read again.
    @discardableResult
    func setResultPlaces(_ places: [String], manages: Bool, words: Words, refreshed: () async -> Void) async -> Bool {
        guard manages, !places.isEmpty else { return false }
        do {
            try await cloud.putResults(of: taf, places: places)
            await refreshed()
            await load(words: words)
            return true
        } catch {
            lastError = words("setup.results_not_changed", ["why": NeedsYouModel.why(error)])
            return false
        }
    }

    /// A follow-up the taf set itself, removed before it fires.
    func removeFollowUp(_ followUp: String, manages: Bool, words: Words) async {
        guard manages else { return }
        do { try await cloud.removeFollowUp(of: taf, followUp) }
        catch { lastError = words("knob.follow_up_not_removed", ["why": NeedsYouModel.why(error)]) }
        await load(words: words)
    }

    /// Pauses or resumes every start at tafs cloud; then the tafs are read again. A 502 while
    /// pausing: its own schedule is paused, but a start may still come.
    func setPaused(_ paused: Bool, words: Words, refreshed: () async -> Void) async {
        lastError = nil
        do {
            try await cloud.setPaused(taf, paused)
            await refreshed()
        } catch let refusal as CloudRefusal where refusal.status == 502 && paused {
            lastError = words("setup.not_every_paused")
        } catch let refusal as CloudRefusal {
            lastError = refusal.why(words)
        } catch {
            lastError = words(paused ? "taf.schedule.not_paused" : "taf.schedule.not_resumed", ["why": NeedsYouModel.why(error)])
        }
    }
}

/// A panel as the iPad's `Panel`: 16 inside, on the panel colour, a continuous 18 corner with
/// its stroke.
private struct KnobPanel<Content: View>: View {
    var stroke: Color = Theme.line
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A Setup screen in its own sheet: its title and Done, the dial's last error, then its panels.
private struct KnobSheet<Content: View>: View {
    @Environment(\.words) private var words
    let title: String
    @ObservedObject var model: TafKnobModel
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.lastError {
                        Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .frame(width: 520, height: 600)
        .background(Theme.background)
    }
}

/// Setup › Starts when, as the iPad's `StartsWhenView` (`Views/TafSetupViews.swift:15-237`):
/// its schedule, the app events it listens to and the follow-ups it set itself, then Pause
/// every start. Every line is tafs cloud's (`GET …/knob` `wakes`); a change makes its next
/// version. A change waiting to go live and approving an app event are signed: here, the line
/// for an approval made on another device.
struct StartsWhenView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafKnobModel
    let taf: Home.Taf
    let manages: Bool
    /// The account's time zone, as KIFF says it.
    var timeZone: String? = nil
    /// Reads the tafs again after a pause or a resume.
    var refreshed: () async -> Void = {}
    let close: () -> Void
    @State private var busy = false

    var body: some View {
        KnobSheet(title: words("setup.starts_when"), model: model, close: close) {
            if let knob = model.knob {
                KnobPendingPanel(knob: knob, manages: manages)
                schedule(knob)
                events(knob)
                followUps(knob)
                pause(knob)
            } else {
                Text(words("setup.reading_starts")).font(.system(size: 15)).foregroundColor(Theme.dim)
            }
        }
        .task { await model.load(words: words) }
    }

    // MARK: Its schedule

    @ViewBuilder private func schedule(_ knob: Knob) -> some View {
        let schedules = knob.wakes.filter { $0.kind == "schedule" }
        KnobPanel {
            Eyebrow(text: words("setup.schedule"))
            if schedules.isEmpty {
                Text(words(taf.unscheduled ? "setup.no_start" : "setup.no_schedule"))
                    .font(.system(size: 15)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(schedules) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: item.words.isEmpty ? item.label : item.words)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if let size = item.size {
                        SizeStepper(label: size.choices.indices.contains(size.index) ? "\(size.label) · \(size.choices[size.index].label)" : size.label,
                                    canLower: manages && !busy && model.canMove(item, -1),
                                    canRaise: manages && !busy && model.canMove(item, 1),
                                    move: { adjust(item, $0) })
                    }
                }
            }
            if let next = taf.nextRun, taf.state != "paused" {
                Text(verbatim: (taf.nextRunWords ?? words("taf.next_run_at", ["time": Self.time(next, zone: timeZone)])) + " · " + (timeZone ?? "UTC"))
                    .font(.system(size: 13)).foregroundColor(Theme.dim)
            }
            if !schedules.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(words("setup.if_busy")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Picker(words("setup.if_still_working"), selection: Binding(
                        get: { knob.setting?.busy ?? "skip" },
                        set: { value in change { $0.busy = value } })) {
                        Text(words("setup.skip_it")).tag("skip")
                        Text(words("setup.run_after")).tag("latest")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!manages || busy || knob.setting == nil)
                }
            }
        }
    }

    /// A time as the account's clock reads it, when KIFF names its zone.
    static func time(_ date: Date, zone: String?) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if let zone, let timeZone = TimeZone(identifier: zone) { formatter.timeZone = timeZone }
        return formatter.string(from: date)
    }

    private func adjust(_ item: Knob.Item, _ direction: Int) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            await model.adjust(item, direction, manages: manages, words: words)
        }
    }

    private func change(_ edit: @escaping (inout Knob.Setting) -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if await model.changeKnob(edit, manages: manages, words: words) { await model.load(words: words) }
        }
    }

    // MARK: App events

    @ViewBuilder private func events(_ knob: Knob) -> some View {
        let events = knob.wakes.filter { $0.kind == "app_event" }
        if !events.isEmpty {
            KnobPanel {
                Eyebrow(text: words("setup.app_events"))
                ForEach(events) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                        if !item.words.isEmpty {
                            Text(verbatim: item.words).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                        }
                        if item.approval?.state == "needed", item.ok == "approve" {
                            // Approving signs, behind Face ID on the iPad: here, the line for an
                            // approval made on another device.
                            Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if item.approval?.state == "approved" || item.on {
                            HStack {
                                Label(words("setup.listening"), systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ok)
                                Spacer()
                                if manages, let trigger = item.trigger {
                                    Button(words("setup.stop")) { change { $0.wakes.removeAll { $0 == trigger } } }
                                        .buttonStyle(OutlineButtonStyle(color: Theme.no))
                                        .fixedSize()
                                        .disabled(busy || knob.setting == nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Follow-ups

    @ViewBuilder private func followUps(_ knob: Knob) -> some View {
        let followUps = knob.wakes.filter { $0.kind == "follow_up" }
        if !followUps.isEmpty {
            KnobPanel {
                Eyebrow(text: words("setup.follow_ups"))
                ForEach(followUps) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.words.isEmpty ? item.label : item.words)
                                .font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            if let at = item.expires.flatMap(Self.date) {
                                Text(verbatim: Self.when(at, zone: timeZone)).font(.system(size: 12)).foregroundColor(Theme.dim)
                            }
                        }
                        Spacer()
                        if manages, let id = item.followUp {
                            Button(words("setup.remove")) {
                                busy = true
                                Task { await model.removeFollowUp(id, manages: manages, words: words); busy = false }
                            }
                            .buttonStyle(OutlineButtonStyle(color: Theme.no))
                            .fixedSize()
                            .disabled(busy)
                        }
                    }
                }
            }
        }
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// A date and time as the account's clock reads it, when KIFF names its zone.
    static func when(_ date: Date, zone: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let zone, let timeZone = TimeZone(identifier: zone) { formatter.timeZone = timeZone }
        return formatter.string(from: date)
    }

    // MARK: Pause every start

    @ViewBuilder private func pause(_ knob: Knob) -> some View {
        if manages, knob.canPause {
            let paused = taf.state == "paused"
            Button(words(paused ? "setup.resume_every" : "setup.pause_every")) {
                busy = true
                Task {
                    await model.setPaused(!paused, words: words, refreshed: refreshed)
                    await model.load(words: words)
                    busy = false
                }
            }
            .buttonStyle(OutlineButtonStyle(color: paused ? Theme.ok : Theme.no))
            .disabled(busy)
        }
    }
}

/// − and + through the choices tafs cloud offers for a stop, its value between them, as the
/// iPad's `SizeStepper`.
struct SizeStepper: View {
    @Environment(\.words) private var words
    let label: String
    let canLower: Bool
    let canRaise: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Image(systemName: "minus").frame(width: 44, height: 36) }
                .buttonStyle(OutlineButtonStyle()).frame(width: 60).disabled(!canLower)
                .accessibilityLabel(words("common.less"))
            Text(verbatim: label).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
            Button { move(1) } label: { Image(systemName: "plus").frame(width: 44, height: 36) }
                .buttonStyle(OutlineButtonStyle()).frame(width: 60).disabled(!canRaise)
                .accessibilityLabel(words("common.more"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(label)
    }
}

/// Setup › Results go to, as the iPad's `ResultsGoToView` (`Views/TafSetupViews.swift:300-467`):
/// tafs' own places, set at once (`PUT …/results`), then each place in a connected app, turned
/// through the dial's next version. At least one of tafs' own places stays on: tafs cloud takes
/// no change without one, so its last switch is disabled.
struct ResultsGoToView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafKnobModel
    let taf: Home.Taf
    let manages: Bool
    /// The person's email, for Email me's line.
    var email: String? = nil
    /// Reads the tafs again after tafs' own places changed.
    var refreshed: () async -> Void = {}
    let close: () -> Void
    @State private var busy = false

    private struct BuiltIn {
        let place: String
        let title: String
        let line: String
    }

    /// tafs' own places, in the same words as on Android.
    private var builtIns: [BuiltIn] {
        [BuiltIn(place: "door_reply", title: words("setup.place.reply_title"), line: words("setup.place.reply_words")),
         BuiltIn(place: "app", title: words("setup.place.app_title"), line: words("setup.place.app_words")),
         BuiltIn(place: "owner_email", title: words("setup.place.email_title"),
                 line: email.map { words("setup.place.email_words", ["email": $0]) } ?? words("setup.place.email_words_yours"))]
    }

    private static let builtInPlaces: Set<String> = ["door_reply", "app", "owner_email"]
    static let builtInOrder = ["door_reply", "app", "owner_email"]

    /// tafs' own places on, as the live taf has them: its `results` as tafs cloud last sent
    /// them, never a waiting version's, which goes live only with Make it live. Without them,
    /// the dial's when it shows the live version; nil when they aren't known.
    static func liveBuiltIns(_ live: [JSONValue]?, knob: Knob?) -> [String]? {
        if let live {
            let on = Set(live.compactMap(Knob.Setting.place(of:)))
            return builtInOrder.filter(on.contains)
        }
        guard let knob, knob.pending == nil else { return nil }
        return builtInOrder.filter { p in knob.results.first { $0.place == p }?.on ?? knob.setting?.sends(to: p) ?? false }
    }

    /// What `PUT …/results` is sent when one of tafs' places is switched: the live ones with
    /// that one changed, nothing else; nil when it would leave none.
    static func places(_ live: [String], switching place: String, on: Bool) -> [String]? {
        var places = live.filter { $0 != place }
        if on { places.append(place) }
        let sent = builtInOrder.filter(places.contains)
        return sent.isEmpty ? nil : sent
    }

    /// A place's other choice: on to off, off to on, as tafs cloud offers it.
    static func toggled(_ item: Knob.Item) -> Knob.Item.Size.Choice? {
        guard let size = item.size, size.choices.count == 2, size.choices.indices.contains(size.index) else { return nil }
        return size.choices[1 - size.index]
    }

    var body: some View {
        KnobSheet(title: words("setup.results_go_to"), model: model, close: close) {
            if let knob = model.knob {
                let actions = knob.results.filter { !Self.builtInPlaces.contains($0.place ?? "") }
                let live = Self.liveBuiltIns(taf.results, knob: knob)
                Text(words("setup.at_least_one")).font(.system(size: 13)).foregroundColor(Theme.dim)
                KnobPendingPanel(knob: knob, manages: manages)
                KnobPanel {
                    Eyebrow(text: words("setup.from_tafs"))
                    ForEach(builtIns, id: \.place) { b in
                        let on = live?.contains(b.place) ?? false
                        placeRow(title: b.title, line: b.line, on: on,
                                 disabled: !manages || busy || live == nil || (on && (live?.count ?? 0) <= 1)) { setBuiltIn(live, b.place, $0) }
                    }
                }
                KnobPanel {
                    Eyebrow(text: words("setup.in_apps"))
                    ForEach(actions) { item in
                        placeRow(title: item.label, line: item.words, on: item.on,
                                 disabled: !manages || busy || Self.toggled(item) == nil) { _ in
                            if let choice = Self.toggled(item) { change { $0 = choice.setting } }
                        }
                    }
                }
            } else {
                Text(words("setup.reading_results")).font(.system(size: 15)).foregroundColor(Theme.dim)
            }
        }
        .task { await model.load(words: words) }
    }

    private func placeRow(title: String, line: String, on: Bool, disabled: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                if !line.isEmpty {
                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Theme.ok)
        .disabled(disabled)
    }

    /// tafs' own places change at once, from the live taf's; the last one on can't be turned off.
    private func setBuiltIn(_ live: [String]?, _ place: String, _ on: Bool) {
        guard let live, let places = Self.places(live, switching: place, on: on) else { return }
        busy = true
        Task {
            await model.setResultPlaces(places, manages: manages, words: words, refreshed: refreshed)
            busy = false
        }
    }

    private func change(_ edit: @escaping (inout Knob.Setting) -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if await model.changeKnob(edit, manages: manages, words: words) { await model.load(words: words) }
        }
    }
}

/// A change to the dial waits as its next version, as the iPad's `KnobPendingPanel`
/// (`Views/TafSetupViews.swift:469-512`): its words, and where the iPad has Make it live, which
/// begins the version switch and is signed, the line for an approval made on another device.
struct KnobPendingPanel: View {
    @Environment(\.words) private var words
    let knob: Knob
    let manages: Bool

    var body: some View {
        if let pending = knob.pending, manages {
            KnobPanel(stroke: Theme.amber.opacity(0.45)) {
                Text(words("knob.not_live", ["version": String(pending.version)])).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.amberText)
                ForEach(Array((knob.draft?.words ?? []).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
                Text(words("approval.device_can_not_approve_approve")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
