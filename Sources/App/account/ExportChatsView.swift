import AppKit
import SwiftUI

/// Export my chats, as the iPad's `ExportChatsSection` and `exportChats`: the person's own
/// chats, written as two files and offered to share or save, as macOS's share menu does.
@MainActor
final class ExportChatsModel: ObservableObject {
    @Published private(set) var preparing = false
    /// Why the last export didn't happen; nil after one that did.
    @Published private(set) var why: String?
    /// The files the last export made, to name them and share them again.
    @Published private(set) var made: [URL]?
    /// The files to offer now: the share menu opens for them, then this is cleared.
    @Published var sharing: [URL]?

    private let cloud: CloudClient
    private let folder: URL

    init(cloud: CloudClient, folder: URL = ChatsExport.folder) {
        self.cloud = cloud
        self.folder = folder
    }

    func export(words: Words) async {
        guard !preparing else { return }
        preparing = true
        why = nil
        defer { preparing = false }
        let export: (json: Data, text: String)
        do { export = try await cloud.exportChats() } catch {
            why = words("connect.chats_were_not_exported_check")
            return
        }
        do {
            let files = try ChatsExport.write(export, in: folder)
            made = files
            sharing = files
        } catch {
            why = words("chat.chats_were_not_exported_could", ["device": words("device.mac")])
        }
    }

    func shareAgain() { sharing = made }
}

/// The row: Export my chats (Try again after a failure), then why it failed, or the files it
/// made, to share again; and what the export holds, under it.
struct ExportChatsRow: View {
    @Environment(\.words) private var words
    @ObservedObject var model: ExportChatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { Task { await model.export(words: words) } } label: {
                HStack(spacing: 10) {
                    if model.preparing {
                        ProgressView().controlSize(.small)
                        Text(words("export.preparing")).foregroundColor(Theme.dim)
                    } else {
                        Text(words(model.why == nil ? "export.row" : "common.try_again")).foregroundColor(Theme.amberText)
                    }
                }
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.preparing)
            .background(SharePicker(files: $model.sharing))
            if let why = model.why {
                Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).padding(.bottom, 10)
            } else if let made = model.made, !model.preparing {
                Button { model.shareAgain() } label: {
                    Text(words("export.ready_share_again", ["files": made.map(\.lastPathComponent).joined(separator: ", ")]))
                        .font(.system(size: 13)).foregroundColor(Theme.dim)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
    }
}

/// macOS's share menu for files, shown from the view it sits behind when `files` is set.
struct SharePicker: NSViewRepresentable {
    @Binding var files: [URL]?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard files != nil else { return }
        DispatchQueue.main.async {
            // Read again here: two updates before this runs show the menu once.
            guard let urls = files else { return }
            files = nil
            NSSharingServicePicker(items: urls).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}
