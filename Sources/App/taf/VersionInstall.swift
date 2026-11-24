import SwiftUI

/// Installing a version, forward or back (`VersionSwitch`), from Versions' Install this version, Finish, Stop it and
/// install and Draft its Card again, and from the knob's Make it live, as the iPad's `prepareSwitch`, `useVersion` and
/// `VersionCardSheet`.
extension TafPagesModel {
    /// Whether this Mac installs versions: with KIFF's client and the security key, for someone who isn't view-only.
    var installsVersions: Bool { account != nil && confirmWithKey != nil && !viewOnly }

    /// Begins switching to `v`, as the iPad's `prepareSwitch`: the switch, with the KIFF draft its Card waits for, if any.
    func prepareSwitch(_ v: TafVersions.Version, redraft: Bool = false, stopBlocking: Bool = false) async -> TafVersions.Switching? {
        guard installsVersions, !v.live, installing == nil else { return nil }
        versionError = nil
        blockedInstall = nil
        stoppedWords = nil
        let cloud = cloud, taf = taf
        switch await VersionSwitch.prepare(n: v.n, words: Words.app, begin: {
            try await cloud.beginSwitch(of: taf, version: v.n, redraft: redraft, stopBlocking: stopBlocking)
        }) {
        case .begun(let begun):
            switching = begun.switching
            stoppedWords = begun.stoppedWords
            staleCard = nil
            return begun.switching
        case .blocked(let words):
            blockedInstall = v.n
            versionError = words
        case .failed(let why):
            versionError = why
        }
        return nil
    }

    /// The Card the switch to `v` waits for, read by this Mac itself before anything is signed.
    func versionCard(_ v: TafVersions.Version) async throws -> AccountClient.Draft {
        guard let account, let id = switching.flatMap({ $0.n == v.n ? $0.draft : nil }) else { throw KIFFError.unreadable }
        if let changed = changedCard, changed.id == id { return changed }
        return try await account.draft(id: id)
    }

    /// Installs `v`, as the iPad's `useVersion`. `shownDraft` is the Card's version the owner read: changed since, nothing
    /// is signed. Answers `.read` when the version brings a Card no one was shown, for the caller to show it.
    @discardableResult
    func useVersion(_ v: TafVersions.Version, shownDraft: String? = nil) async -> VersionSwitch.Done? {
        guard let account, let confirmKey = confirmWithKey, installsVersions, !v.live, installing == nil else { return nil }
        installing = v.n
        defer { installing = nil }
        versionError = nil
        changedCard = nil
        let cloud = cloud, taf = taf, name = tafName, owner = confirmOwner
        let done = await VersionSwitch.use(
            n: v.n, shownDraft: shownDraft, words: Words.app,
            begin: { try await cloud.beginSwitch(of: taf, version: v.n) },
            readDraft: { try await account.draft(id: $0) },
            confirmOwner: { try await owner(VersionSwitch.prompt(n: v.n, taf: name, withCard: false, words: Words.app)) },
            confirm: { try await confirmKey($0, VersionSwitch.prompt(n: v.n, taf: name, withCard: true, words: Words.app)) },
            cancel: { _ = try? await cloud.cancelSwitch(of: taf) },
            makeLive: { try await cloud.makeLive(of: taf, version: v.n) })
        await loadVersions()
        switch done {
        case .live(let begun):
            if begun.switching.draft != nil { await refreshTafs?() }
        case .read, .closed:
            break
        case .changed(let draft):
            changedCard = draft
            versionError = Words.app("version.out_of_date_card")
        case .stale(let line):
            staleCard = v.n
            versionError = line
        case .failed(let line):
            versionError = line
        }
        return done
    }

    /// Install this version, Finish, Stop it and install, or Draft its Card again: the switch begins, and a version that
    /// brings a Card answers it, to be read first; one with none goes live after the owner confirms. Nil when nothing is
    /// left to read.
    func install(_ v: TafVersions.Version, redraft: Bool = false, stopBlocking: Bool = false) async -> TafVersions.Version? {
        guard let sw = await prepareSwitch(v, redraft: redraft, stopBlocking: stopBlocking) else { return nil }
        if sw.draft != nil { return v }
        return await useVersion(v) == .read ? v : nil
    }
}

/// The Card a version brings, read before the security key confirms it, as the iPad's `VersionCardSheet`: each Card it
/// revises as it is now and as it will be, its new ones as one, and each it removes. Install this version confirms exactly
/// what this sheet shows; Cancel drops the switch, and the taf runs as it was.
struct VersionCardSheet: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let version: TafVersions.Version
    let close: () -> Void
    @State private var draft: AccountClient.Draft?
    @State private var unread: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(words("card.its_card")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: version.note.map { words("version.number_note", ["version": String(version.n), "note": $0]) }
                         ?? words("version.number", ["version": String(version.n)]))
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if let draft, draft.cards != nil {
                        DraftCardsView(draft: draft)
                        Text(words(draft.retires?.isEmpty == false ? "version.card_note.removes" : "version.card_note.issues"))
                            .font(.system(size: 12)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    } else if draft != nil || unread != nil {
                        Text(verbatim: unread ?? words("version.card_unreadable")).font(.system(size: 13)).foregroundColor(Theme.no)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let error = model.versionError {
                        Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                // Not now: the switch it began is dropped, and the taf runs as it was.
                Button(words("common.cancel")) {
                    close()
                    Task { await model.cancelSwitch() }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.installing == version.n ? words("version.installing") : words("version.install_this")) {
                    guard let shown = draft?.version else { return }
                    Task {
                        let done = await model.useVersion(version, shownDraft: shown)
                        switch done {
                        case .live?, .closed?: close()
                        // Changed since it was shown: read again, so the person reads what they'd approve.
                        case .changed(let changed)?: draft = changed
                        default: break
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
                .disabled(draft?.cards == nil || model.installing != nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .background(Theme.background)
        .task {
            do { draft = try await model.versionCard(version) } catch {
                unread = words("version.card_not_read", ["why": NeedsYouModel.why(error)])
            }
        }
    }
}

/// The Cards a draft brings, as the owner reads them before the security key, as the iPad's `DraftCardsView`.
struct DraftCardsView: View {
    @Environment(\.words) private var words
    let draft: AccountClient.Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(draft.shown(words).enumerated()), id: \.offset) { _, shown in
                switch shown {
                case .new(let lines):
                    panel {
                        Eyebrow(text: words("version.new_card"))
                        strong(lines)
                    }
                case .one(let now, let after, let unchanged):
                    panel {
                        if unchanged {
                            // Re-issued as it is: its terms once, not a now and after.
                            Eyebrow(text: words("version.unchanged"))
                            soft(after)
                        } else {
                            Eyebrow(text: words("version.changes_card"))
                            label(words("version.now"))
                            soft(now)
                            label(words("version.after"))
                            strong(after)
                        }
                    }
                }
            }
            ForEach(draft.retires ?? [], id: \.id) { retired in
                panel {
                    Eyebrow(text: words("version.removes_card"))
                    ForEach(Array((retired.current.map { AccountClient.Draft.lines(of: $0, words) } ?? []).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.system(size: 14)).strikethrough().foregroundColor(Theme.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(words("version.cant_any_more")).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim)
    }

    private func strong(_ lines: [String]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(verbatim: line).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func soft(_ lines: [String]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(verbatim: line).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
        }
    }
}
