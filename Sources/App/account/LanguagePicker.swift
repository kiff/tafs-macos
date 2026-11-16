import SwiftUI

/// The rows of Account › Language: the Mac's own language first (when the shared line for it
/// is at the pin), then every shipped language by its own name ("Deutsch", "Polski"), the
/// current one marked. Pure, so a test reads them without drawing.
struct LanguageRows {
    struct Row: Equatable, Identifiable {
        /// The language's code, or nil for the Mac's own language.
        let code: String?
        let title: String
        let current: Bool
        var id: String { code ?? "device" }
    }

    static func rows(chosen: String?, shipped: [String], words: Words) -> [Row] {
        var rows: [Row] = []
        // A kept code that's no longer shipped counts as no choice, as `LanguageChoice.language`.
        let valid = chosen.flatMap { shipped.contains($0) ? $0 : nil }
        // "This Mac's language" is a shared line (`settings.language_device`); until it's at the
        // pin, the row isn't offered rather than worded here, and the language in use is marked.
        let device = words.lines["settings.language_device"] != nil
        if device {
            rows.append(Row(code: nil, title: words("settings.language_device", ["device": words("device.mac")]), current: valid == nil))
        }
        let current = valid ?? (device ? nil : words.language)
        for code in shipped {
            rows.append(Row(code: code, title: AppInfo.languageName(code), current: code == current))
        }
        return rows
    }
}

/// Account › Language: the app's own list of its languages. Choosing one applies it at once
/// (`AppLanguage.choose`); the window comes back on Account in that language.
struct LanguagePickerView: View {
    @Environment(\.words) private var words
    @Environment(\.languageChooser) private var chooser

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenTitle(title: words("settings.language_title"), size: 34, rounded: false).padding(.top, 24)
                VStack(alignment: .leading, spacing: 0) {
                    let rows = LanguageRows.rows(chosen: chooser?.chosen, shipped: chooser?.shipped ?? [words.language], words: words)
                    ForEach(rows) { row in
                        if row.id != rows.first?.id { Rectangle().fill(Theme.line).frame(height: 1) }
                        rowView(row)
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: Look.panelRadius).fill(Theme.panel))
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private func rowView(_ row: LanguageRows.Row) -> some View {
        Button { if !row.current { chooser?.choose(row.code) } } label: {
            HStack {
                Text(verbatim: row.title).font(.system(size: 17)).foregroundColor(Theme.ink)
                Spacer()
                if row.current { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText) }
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(row.current ? .isSelected : [])
    }
}
