import AppKit
import SwiftUI

/// Files (tafs docs/files.md), as the iPad's `FilesView` at its full width: the account's files, or one taf's, newest
/// first, the list and the open file side by side. Account's row opens the account's, with All, By taf and By run and a
/// chip per taf; a taf's page opens its own, by run.
struct FilesView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: FilesModel
    /// One taf's files, by tafs cloud's id; nil for the account's.
    var taf: String? = nil
    /// The account's time zone, which a run's day is in.
    var zone: TimeZone = .current
    @State private var grouping: Grouping = .all
    /// A chip's taf, narrowing the account's files to one.
    @State private var chip: String?
    @State private var selected: String?

    enum Grouping: Hashable, CaseIterable {
        case all, byTaf, byRun
        var key: String {
            switch self {
            case .all: return "files.all"
            case .byTaf: return "files.by_taf"
            case .byRun: return "files.by_run"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 380)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private var shown: [DeliveredFile] { model.files(taf: taf ?? chip) }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenTitle(title: words("files.title"), size: 28, rounded: false).padding(.top, 24)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                case .failed:
                    Text(words("common.could_not_read_why", ["what": words("files.title"), "why": words("error.offline")]))
                        .font(.system(size: 14)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let all) where all.isEmpty:
                    Text(words("files.empty")).font(.system(size: 14)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                case .loaded(let all):
                    if taf == nil { choices(all) }
                    groups
                    Text(words("files.kept_line")).font(.system(size: 12)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    /// All, By taf and By run, then one chip per taf with files, and All tafs.
    private func choices(_ all: [DeliveredFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(words("files.title"), selection: $grouping) {
                ForEach(Grouping.allCases, id: \.self) { Text(words($0.key)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let tafs = FilesGrouping.byTaf(all).compactMap { $0.files.first.map { ($0.tafID, $0.tafName) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(title: words("files.all_tafs"), chosen: chip == nil) { chip = nil }
                    ForEach(tafs, id: \.0) { id, name in Chip(title: name, chosen: chip == id) { chip = id } }
                }
            }
        }
    }

    @ViewBuilder private var groups: some View {
        let now = Date()
        switch taf == nil ? grouping : .byRun {
        case .all:
            ForEach(FilesGrouping.byDay(shown, zone: zone)) { group in section(day(group.files.first?.runAt), group.files, now: now) }
        case .byTaf:
            ForEach(FilesGrouping.byTaf(shown)) { group in section(group.files.first?.tafName ?? "", group.files, now: now) }
        case .byRun:
            ForEach(FilesGrouping.byRun(shown)) { group in
                let title = [group.files.first?.tafName, day(group.files.first?.runAt)].compactMap { $0 }.filter { !$0.isEmpty }
                section(title.joined(separator: " · "), group.files, now: now)
            }
        }
    }

    private func section(_ title: String, _ files: [DeliveredFile], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.dim).padding(.top, 6)
            ForEach(files) { file in
                Button { selected = file.id } label: {
                    FileRow(file: file, now: now)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected(file) ? Theme.raised : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected(file) ? .isSelected : [])
            }
        }
    }

    private func isSelected(_ file: DeliveredFile) -> Bool { file.id == (selected ?? shown.first?.id) }

    @ViewBuilder private var detail: some View {
        if let file = model.files().first(where: { $0.id == (selected ?? shown.first?.id) }) {
            FileDetailView(model: model, file: file) { selected = nil }.id(file.id)
        } else if case .loaded(let all) = model.state, !all.isEmpty {
            Text(words("files.pick_one")).font(.system(size: 14)).foregroundColor(Theme.soft)
        }
    }

    /// A run's day: its weekday, day and month, abbreviated, in the account's zone.
    private func day(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = AppDates.formatter(words, zone: zone)
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}

/// A file in the list, as the iPad's `FileRow`: its type, its name, the taf that made it with its size, and when it goes.
struct FileRow: View {
    @Environment(\.words) private var words
    let file: DeliveredFile
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            FileBadge(type: file.type)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(2)
                Text(verbatim: [file.tafName, FileSize.words(file.bytes)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundColor(Theme.dim)
                Text(verbatim: FilesGrouping.goes(FilesGrouping.daysLeft(file, now: now), words: words))
                    .font(.system(size: 12)).foregroundColor(Theme.amberText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The file's type as a small badge, as the iPad's: its own extension, never an icon that says more than it knows.
struct FileBadge: View {
    let type: String
    var size: CGFloat = 40

    var body: some View {
        Text(verbatim: type)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Theme.background)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 4).fill(Theme.soft))
            .accessibilityHidden(true)
    }
}

enum FileSize {
    /// A size as the system words it.
    static func words(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

/// An open file, as the iPad's `FileDetailView`: tafs cloud's cleaned start as plain text, Download, the taf and run it
/// came from, who sees it and when it goes; Delete now apart, at the end, behind a confirm.
struct FileDetailView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: FilesModel
    let file: DeliveredFile
    /// After Delete now: the side's selection clears.
    let deleted: () -> Void
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    FileBadge(type: file.type, size: 44)
                    Text(verbatim: file.name).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                preview
                HStack(spacing: 10) {
                    Button(words("files.download")) { save() }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 220)
                }
                if let note = model.notes[file.id] {
                    Text(verbatim: note).font(.system(size: 13)).foregroundColor(Theme.soft).fixedSize(horizontal: false, vertical: true)
                }
                facts
                Button(words("files.delete_now")) { confirming = true }
                    .buttonStyle(OutlineButtonStyle(color: Theme.no)).frame(maxWidth: 220)
                    .disabled(model.deleting.contains(file.id))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.preview(file) }
        .onDisappear { model.close(file) }
        .alert(words("files.delete_question", ["name": file.name]), isPresented: $confirming) {
            Button(words("files.delete_now"), role: .destructive) {
                Task { if await model.delete(file) { deleted() } }
            }
            Button(words("common.cancel"), role: .cancel) {}
        } message: {
            Text(words("files.delete_body"))
        }
    }

    @ViewBuilder private var preview: some View {
        switch model.previews[file.id] {
        case .text(let start)?:
            // tafs cloud's cleaned start, drawn as plain text: never Markdown, HTML or a viewer of the bytes.
            ScrollView {
                Text(verbatim: start.text).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            if start.truncated {
                Text(words("files.preview_start")).font(.system(size: 12)).foregroundColor(Theme.soft)
            }
        case .unreachable?:
            Text(words("common.could_not_read_why", ["what": words("files.title"), "why": words("error.offline")]))
                .font(.system(size: 14)).foregroundColor(Theme.no)
        case .noPreview?:
            EmptyView()
        case nil:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !file.tafName.isEmpty { fact("files.made_by", file.tafName) }
            fact("files.in_run", AppDates.formatter(words, date: .medium, time: .short).string(from: file.runAt))
            fact("files.type", file.type)
            fact("files.size", FileSize.words(file.bytes))
            fact("files.who_sees", words("files.everyone"))
            fact("files.goes_away", words("files.goes_on", ["date": AppDates.formatter(words, date: .medium).string(from: file.goesAt)]))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
    }

    private func fact(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(words(key)).font(.system(size: 14)).foregroundColor(Theme.soft)
            Spacer(minLength: 12)
            Text(verbatim: value).font(.system(size: 14)).foregroundColor(Theme.ink).multilineTextAlignment(.trailing)
        }
    }

    /// Download: where to, as the person picks, named as the file is; then its bytes, straight there.
    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.download(file, to: url) }
    }
}
