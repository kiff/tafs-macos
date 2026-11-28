import AppKit
import SwiftUI

// A taf's doors on the Mac, ported from the iPad's `DoorsView.swift`, `TafSetupViews.swift`
// (`DoorsList`) and `TafPresentationViews.swift` (`TafKnocksPanel`). Nothing here is signed:
// tafs cloud takes every change with the person's session.

/// A door's app, as a small round badge: filled while open, as the iPad's `DoorBadge`.
struct DoorBadge: View {
    let app: String
    let open: Bool
    var size: CGFloat = 24

    var body: some View {
        Circle().fill(open ? Self.color(app) : Theme.panel)
            .overlay(Circle().stroke(open ? Color.clear : Theme.ink.opacity(0.25), lineWidth: 1.5))
            .overlay(Text(verbatim: TafDoors.mark(app)).font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
                .foregroundColor(open ? .white : Theme.dim))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// As the iPad's `DoorNames.color`: the same colour on every launch, from the name's letters.
    static func color(_ app: String) -> Color {
        switch app {
        case "email": return Theme.sky
        case "whatsapp": return Theme.ok
        default: return Theme.tafColor(app.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        }
    }
}

/// A panel as the iPad's `Panel`: 16 in, on the panel's fill, with an edge when asked.
struct DoorPanel<Content: View>: View {
    var stroke: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).stroke(stroke ?? Color.clear))
    }
}

/// The iPad's main button: its brand fill, white 16 semibold, 54 high; neutral when disabled.
private struct DoorPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Look(configuration: configuration) }

    private struct Look: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundColor(isEnabled ? .white : Theme.soft)
                .background(Group {
                    if isEnabled { Theme.brand.opacity(configuration.isPressed ? 0.8 : 1) } else { Theme.dim.opacity(0.22) }
                })
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Setup's doors, as the iPad's `DoorsList`: each door, open or closed, with Edit (its own
/// screen), then Add a door.
struct DoorsListPanel: View {
    @Environment(\.words) private var words
    let taf: Home.Taf
    @ObservedObject var doors: DoorsModel
    let myEmail: String?
    @State private var editing: TafDoors.Door?
    @State private var adding = false

    var body: some View {
        DoorPanel {
            Eyebrow(text: words("setup.doors"))
            ForEach(doors.doors) { door in
                HStack(spacing: 12) {
                    DoorBadge(app: door.app, open: door.open, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: door.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                        Text(verbatim: door.words?.state ?? (door.open ? words("setup.open") : words("door.status.closed")))
                            .font(.system(size: 13)).foregroundColor(Theme.soft)
                    }
                    Spacer()
                    Button(words("setup.edit")) { editing = door }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                }
            }
            Button { adding = true } label: {
                Label(words("setup.add_door"), systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.amberText)
            }
            .buttonStyle(.plain)
            .disabled(!doors.loaded || doors.addable.isEmpty)
        }
        .task { await doors.load() }
        .sheet(item: $editing) { door in
            DoorScreen(taf: taf, doors: doors, doorID: door.id, myEmail: myEmail, close: { editing = nil })
                .environment(\.words, words)
        }
        .sheet(isPresented: $adding) { AddDoorSheet(doors: doors, close: { adding = false }).environment(\.words, words) }
    }
}

/// One door's own screen, as the iPad's `DoorsView` with `.only(door)`: its settings words,
/// its address, who may give it work and its day; the knocks waiting; its footer.
struct DoorScreen: View {
    @Environment(\.words) private var words
    let taf: Home.Taf
    @ObservedObject var doors: DoorsModel
    let doorID: String
    /// This person's sign-in: their own key, paired for them, reads "You"; anyone else's doesn't.
    let myEmail: String?
    let close: () -> Void
    @State private var pairing: TafDoors.Door?
    @State private var confirmRemove: TafDoors.Door?
    @State private var copied = false

    private var door: TafDoors.Door? { doors.doors.first { $0.id == doorID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: door.map { words("door.named", ["door": $0.label]) } ?? words("door.title_plain"))
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            .padding(16)
            ScrollView { details.padding(.horizontal, 16).padding(.vertical, 12) }
        }
        .frame(width: 480, height: 620)
        .background(Theme.background)
        .task { await doors.load() }
        .sheet(item: $pairing) { PairSheet(door: $0, doors: doors, close: { pairing = nil }).environment(\.words, words) }
        .alert(words("door.remove_title", ["door": confirmRemove?.label.lowercased() ?? ""]),
               isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button(words("door.remove"), role: .destructive) {
                if let d = confirmRemove { Task { await doors.remove(d) } }
                // A Slack door's planque subscription is stopped first, signed by the device key, as the iPad's
                // `removeSlackDoor` (`DoorsModel.remove`); if it isn't, the door stays and says why.
            }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            // An API door's keys stop working with it, in its own words; any other door's line otherwise.
            Text(confirmRemove?.kind == "api" ? words("door.api.remove_body", ["app": confirmRemove?.label ?? "", "taf": taf.name])
                 : words("door.remove_body", ["taf": taf.name]))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let settings = door?.words?.settings {
                Text(verbatim: settings).font(.system(size: 12)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
            }
            if let door, door.kind == "api" {
                APIDoorPanel(door: door, taf: taf, doors: doors, remove: { confirmRemove = door })
            } else if let door { panel(door) } else {
                Text(words("door.door_removed")).font(.system(size: 15)).foregroundColor(Theme.soft)
            }
            // Strangers' knocks wait on the owner; a paired sender's message, kept from its knock,
            // waits for Do it or Ignore, apart and calmly.
            let paired = doors.openKnocks.filter { !$0.isLine && $0.paired }
            let waiting = doors.openKnocks.filter { !$0.isLine && !$0.paired }
            if !paired.isEmpty {
                DoorPanel {
                    Eyebrow(text: words("door.paired"))
                    ForEach(paired) { KnockCard(knock: $0, taf: taf, doors: doors, compact: true) }
                }
            }
            if !waiting.isEmpty {
                DoorPanel(stroke: Theme.amber.opacity(0.45)) {
                    Eyebrow(text: words("door.knocks_waiting"), color: Theme.amber)
                    ForEach(waiting) { KnockCard(knock: $0, taf: taf, doors: doors, compact: true) }
                }
            }
            if let error = doors.error {
                Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
            }
            Text(words("door.footer", ["taf": taf.name])).font(.system(size: 13)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func panel(_ door: TafDoors.Door) -> some View {
        Group {
            DoorPanel {
                HStack(spacing: 12) {
                    DoorBadge(app: door.app, open: door.open, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: words("door.named", ["door": door.label]))
                        Text(verbatim: door.words?.state ?? (door.open ? (door.resting ? words("door.status.resting") : words("door.status.open")) : words("door.status.closed")))
                            .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle(words("door.status.open"), isOn: Binding(get: { door.open }, set: { on in Task { await doors.setOpen(door, on) } }))
                        .labelsHidden().toggleStyle(.switch).disabled(doors.busy)
                }
                Text(verbatim: door.address).font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundColor(Theme.ink).textSelection(.enabled)
                if door.kind == "email" {
                    Button(copied ? words("common.copied") : words("door.copy_address")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(door.address, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(nanoseconds: 1_400_000_000); copied = false }
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                Meter(fraction: Double(door.today) / Double(max(door.limit, 1)), color: door.resting ? Theme.dim : Theme.tafColor(taf.color))
                Text(door.resting ? words("door.paired_senders_today_more_dropped", ["limit": String(door.limit), "limit_2": String(door.limit)])
                     : words("door.paired_senders_today_text_only", ["today": String(door.today), "limit": String(door.limit)]))
                    .font(.system(size: 12)).foregroundColor(Theme.dim)
                if let others = door.othersToday, let cap = door.othersLimit {
                    Text(words("door.anyone_else_today", ["others": String(others), "cap": String(cap)]))
                        .font(.system(size: 12)).foregroundColor(Theme.dim)
                }
            }
            DoorPanel {
                Eyebrow(text: door.holdsKeys ? words("door.key.paired") : words("door.key.no_one_paired"))
                if door.holdsKeys {
                    ForEach(door.keys) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                // The address once, when the name is only the address; "You" only on
                                // this person's own key.
                                let mine = key.auto && key.id.lowercased() == myEmail?.lowercased()
                                let name = mine ? words("door.key.you") : key.name.flatMap { $0.lowercased() == key.id.lowercased() ? nil : $0 }
                                Text(verbatim: name ?? key.id).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                                if name != nil {
                                    Text(verbatim: key.id).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.dim)
                                }
                            }
                            Spacer()
                            if !key.auto {
                                Button(words("door.unpair")) { Task { await doors.unpair(door, key) } }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.soft)
                            }
                        }
                    }
                    Text(words("door.key.foot", ["how": door.how])).font(.system(size: 12)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(words("door.pair_someone")) { pairing = door }.buttonStyle(OutlineButtonStyle())
                } else {
                    Text(words("door.key.none", ["how": door.how, "taf": taf.name]))
                        .font(.system(size: 15)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                Button(role: .destructive) { confirmRemove = door } label: {
                    Text(words("door.remove_door")).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.no)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Picks the app a new door opens on, as the iPad's `AddDoorSheet`: those that can tell who's
/// writing first. WhatsApp's signup runs on a phone, and a Slack door is approved, so on this
/// Mac their rows say so in place of adding.
struct AddDoorSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var doors: DoorsModel
    let close: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(words("door.add_door")).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            TextField(words("connect.apps.search"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section(words("door.proven_section"), doors.addable.filter { $0.proof == "proven" && matches($0) })
                    section(words("door.unproven_section"), doors.addable.filter { $0.proof != "proven" && matches($0) })
                    if doors.addable.filter(matches).isEmpty {
                        Text(query.isEmpty ? words("door.no_more") : words("door.no_app_called", ["query": query]))
                            .font(.system(size: 13)).foregroundColor(Theme.dim)
                    }
                    Text(words("door.replies_only")).font(.system(size: 12)).foregroundColor(Theme.dim).padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                    // Why the last door didn't go on (WhatsApp's signup that didn't finish, or tafs cloud's refusal).
                    if let why = doors.error {
                        Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .background(Theme.background)
    }

    private func matches(_ app: TafDoors.App) -> Bool {
        query.isEmpty || app.label.localizedCaseInsensitiveContains(query)
    }

    /// What stands in for adding, on this Mac: a Slack door is approved where an approval can be made. WhatsApp's is
    /// added here, through its signup (`DoorsModel.addWhatsApp`).
    private func elsewhere(_ app: TafDoors.App) -> String? {
        switch app.kind {
        case "slack": return words("approval.device_can_not_approve_approve")
        default: return nil
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ apps: [TafDoors.App]) -> some View {
        if !apps.isEmpty {
            Eyebrow(text: title).padding(.top, 6)
            ForEach(apps) { app in
                let instead = elsewhere(app)
                Button {
                    Task {
                        // WhatsApp's starts with Meta's signup on tafs cloud's page; any other door turns on at once.
                        let added = app.kind == "whatsapp" ? await doors.addWhatsApp(app) : await doors.add(app)
                        if added != nil { close() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        DoorBadge(app: app.id, open: true, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: app.label).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                            Text(verbatim: instead ?? app.how).font(.system(size: 12)).foregroundColor(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(doors.busy || instead != nil)
            }
        }
    }
}

/// Pairs a sender with a door: they can give the taf work from now on.
struct PairSheet: View {
    @Environment(\.words) private var words
    let door: TafDoors.Door
    @ObservedObject var doors: DoorsModel
    let close: () -> Void
    @State private var sender = ""
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(words("door.pair_someone")).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
            Text(words("door.pair_intro", ["door": door.label.lowercased()]))
                .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            TextField(door.kind == "email" ? words("door.pair_hint.email") : door.kind == "whatsapp" ? words("door.pair_hint.phone")
                      : door.kind == "slack" ? words("door.pair_hint.slack") : words("door.pair_hint.other", ["door": door.label]), text: $sender)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            TextField(words("door.name_optional"), text: $name).textFieldStyle(.roundedBorder)
            Button(words("door.pair")) {
                Task {
                    await doors.pair(door, sender: sender, name: name)
                    if doors.error == nil { close() }
                }
            }
            .buttonStyle(DoorPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(sender.trimmingCharacters(in: .whitespaces).isEmpty || doors.busy)
            Button(words("common.cancel"), action: close).buttonStyle(.plain).frame(maxWidth: .infinity).keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 380)
        .background(Theme.background)
    }
}

/// Someone without a key wrote, as the iPad's `KnockCard`: who, what they want, and the
/// owner's three answers.
/// A door's reply waiting for the owner to send it: tafs cloud's line, the subject, the exact text that would go, and
/// Send (on the security key, behind tafs cloud's prompt) and Don't send, every word tafs cloud's.
struct HeldReplyCard: View {
    let reply: TafDoors.HeldReply
    @ObservedObject var doors: DoorsModel

    var body: some View {
        DoorPanel(stroke: Theme.amber.opacity(0.45)) {
            Text(verbatim: reply.words.line).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subject = reply.subject {
                Text(verbatim: subject).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.soft)
            }
            // The exact text that would go, selectable, in its own box.
            Text(verbatim: reply.text).font(.system(size: 14)).foregroundColor(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.soft.opacity(0.08)))
                .accessibilityIdentifier("held_reply.text")
            HStack(spacing: 10) {
                Button { Task { await doors.send(reply) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").accessibilityHidden(true)
                        Text(verbatim: reply.words.send)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("held_reply.send")
                Button(reply.words.discard) { Task { await doors.discard(reply) } }
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityIdentifier("held_reply.discard")
            }
            .disabled(doors.busy)
        }
    }
}

/// A writer the taf couldn't help, on its Activity: tafs cloud's line for why, then the owner's own answer, typed here and
/// sent on the security key as typed, or Ignore. Connect an app comes only when the app it needs isn't connected, and only
/// for someone who manages the taf. The writer has had nothing, and gets nothing until the owner acts.
struct UnansweredCard: View {
    let item: TafDoors.Unanswered
    @ObservedObject var doors: DoorsModel
    /// Connect apps, for `no_app`; nil for someone who doesn't manage the taf.
    var openConnect: (() -> Void)? = nil
    @State private var text = ""

    var body: some View {
        DoorPanel(stroke: Theme.amber.opacity(0.45)) {
            Text(verbatim: item.words.line).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subject = item.subject {
                Text(verbatim: subject).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.soft)
            }
            // The owner's own words, sent exactly as typed.
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(minHeight: 72, maxHeight: 160)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.soft.opacity(0.08)))
                .accessibilityLabel(Text(verbatim: item.words.reply))
                .accessibilityIdentifier("unanswered.text")
            HStack(spacing: 10) {
                Button { Task { if await doors.sendOwn(item, text: text) { text = "" } } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").accessibilityHidden(true)
                        Text(verbatim: item.words.reply)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
                .disabled(!TafDoors.Unanswered.sendable(text))
                .accessibilityIdentifier("unanswered.send")
                if let connect = item.words.connect, let openConnect {
                    Button(connect, action: openConnect)
                        .buttonStyle(OutlineButtonStyle())
                        .fixedSize()
                        .accessibilityIdentifier("unanswered.connect")
                }
                Button(item.words.ignore) { Task { await doors.ignore(item) } }
                    .buttonStyle(OutlineButtonStyle())
                    .fixedSize()
                    .accessibilityIdentifier("unanswered.ignore")
                Spacer(minLength: 0)
            }
            .disabled(doors.busy)
        }
    }
}

struct KnockCard: View {
    @Environment(\.words) private var words
    let knock: TafDoors.Knock
    let taf: Home.Taf?
    @ObservedObject var doors: DoorsModel
    var compact = false
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: (knock.paired ? words("door.knock.paired_by", ["app": TafDoors.label(knock.app).uppercased()]) : words("door.knock.by", ["app": TafDoors.label(knock.app).uppercased()]))
                 + (knock.proof == "fail" ? " · " + words("door.knock.didnt_check_out") : ""))
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(knock.paired ? Theme.soft : Theme.amberText)
            if knock.paired {
                Text(words("door.knock.paired_line")).font(.system(size: 12)).foregroundColor(Theme.dim)
            }
            if let rest = knock.rest {
                Text(rest == "keys" ? words.count("door.knock.rest_keys", knock.dropped) : words.count("door.knock.rest_others", knock.dropped))
                    .font(.system(size: 14)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Button(words("common.ok")) { Task { await doors.answer(knock, "ignore") } }.buttonStyle(OutlineButtonStyle())
            } else {
                Text(knock.subject.map { words("door.knock.wrote_about", ["who": knock.who, "subject": $0]) } ?? words("door.knock.wrote", ["who": knock.who]))
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: knock.text).font(.system(size: 14)).foregroundColor(Theme.soft).lineLimit(compact ? 3 : 8).textSelection(.enabled)
                if knock.attachments > 0 {
                    Text(words.count("door.knock.attachments", knock.attachments)).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                if let note = proofNote {
                    Text(note).font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if knock.proof != "fail" {
                        Button { asking = true } label: {
                            Text(words("door.do_it_button")).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Theme.amber).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if knock.proof == "pass", !knock.paired {
                        Button { Task { await doors.answer(knock, "pair") } } label: {
                            Text(verbatim: knock.name?.components(separatedBy: " ").first.map { words("door.knock.pair", ["name": $0]) } ?? words("door.knock.pair_them"))
                                .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.ink)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay(Capsule().stroke(Theme.ink.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { Task { await doors.answer(knock, "ignore") } } label: {
                        Text(words("door.ignore")).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.soft)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(doors.busy)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A paired sender's message waits too, but it isn't a stranger at the door: it reads
        // calmly, not in amber.
        .background(knock.paired ? Theme.panel : Theme.amber.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(knock.paired ? Theme.ink.opacity(0.2) : Theme.amber.opacity(0.45)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $asking) { DoItSheet(knock: knock, taf: taf, doors: doors, close: { asking = false }).environment(\.words, words) }
    }

    private var proofNote: String? {
        switch knock.proof {
        case "fail": return words("door.knock.proof_failed", ["from": knock.from])
        case "none": return words("door.knock.proof_none")
        default: return nil
        }
    }
}

/// "Do it", as the iPad's `DoItSheet`: what the owner tells the taf to do about a knock. Their
/// words are the instruction.
struct DoItSheet: View {
    @Environment(\.words) private var words
    let knock: TafDoors.Knock
    let taf: Home.Taf?
    @ObservedObject var doors: DoorsModel
    let close: () -> Void
    @State private var say: String?

    var body: some View {
        let text = Binding(get: { say ?? words("door.do_it.default") }, set: { say = $0 })
        VStack(alignment: .leading, spacing: 14) {
            Text(words("door.do_it.title", ["taf": taf?.name ?? words("chat.your_taf")]))
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
            Text(words("door.do_it.intro", ["who": knock.who, "taf": taf?.name ?? words("chat.it_fallback")]))
                .font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: text)
                .font(.system(size: 15))
                .frame(minHeight: 110)
                .padding(6)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                .accessibilityLabel(words("door.what_do"))
            // Why it wasn't sent, here where the owner is, not on the screen behind the sheet.
            if let error = doors.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 14)).foregroundColor(Theme.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(doors.busy ? words("common.sending") : words("door.send_to", ["taf": taf?.name ?? words("chat.your_taf")])) {
                Task {
                    await doors.answer(knock, "do", say: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines))
                    if doors.error == nil { close() }
                }
            }
            .buttonStyle(DoorPrimaryButtonStyle())
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || doors.busy)
            Button(words("common.cancel"), action: close).buttonStyle(.plain).frame(maxWidth: .infinity).keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 440)
        .background(Theme.background)
        .onAppear { doors.error = nil }
    }
}

/// What waits for the owner at the taf's doors, on its Activity, as the iPad's
/// `TafKnocksPanel`: strangers' knocks (Do it, Pair them, Ignore), then a paired sender's
/// message kept from its knock, apart and calmly. Read when the Activity opens, where tafs
/// cloud offers doors.
struct TafKnocksPanel: View {
    @Environment(\.words) private var words
    let taf: Home.Taf
    @ObservedObject var doors: DoorsModel
    /// tafs cloud offers doors here.
    let offered: Bool
    /// Connect apps, for a writer the taf couldn't help because an app isn't connected; nil for someone who doesn't
    /// manage the taf.
    var openConnect: (() -> Void)? = nil

    var body: some View {
        let open = doors.openKnocks.filter { !$0.isLine }
        let waiting = open.filter { !$0.paired }, paired = open.filter(\.paired)
        VStack(alignment: .leading, spacing: 14) {
            // Replies waiting for the owner to send them, before the knocks, as on Android.
            ForEach(doors.replies) { HeldReplyCard(reply: $0, doors: doors) }
            // Then the writers it couldn't help, each waiting for the owner's own answer.
            ForEach(doors.unanswered) { UnansweredCard(item: $0, doors: doors, openConnect: openConnect) }
            if !waiting.isEmpty {
                DoorPanel(stroke: Theme.amber.opacity(0.45)) {
                    Eyebrow(text: words("door.knocks_waiting"), color: Theme.amber)
                    ForEach(waiting) { KnockCard(knock: $0, taf: taf, doors: doors, compact: true) }
                }
            }
            if !paired.isEmpty {
                DoorPanel {
                    Eyebrow(text: words("door.paired"))
                    ForEach(paired) { KnockCard(knock: $0, taf: taf, doors: doors, compact: true) }
                }
            }
            if !open.isEmpty || !doors.replies.isEmpty || !doors.unanswered.isEmpty, let error = doors.error {
                Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no)
            }
        }
        .task(id: taf.id) { if offered { await doors.load() } }
    }
}
