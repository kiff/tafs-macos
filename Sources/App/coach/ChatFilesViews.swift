import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Files a person attaches to a message, as the iPad's `AttachViews.swift`: the paperclip in the
// message bar, the tray above the box, and the files in the thread, opened full size.

/// The paperclip, as the iPad's `AttachButton` (AttachViews.swift:11-89): choose photos, or
/// choose a file. Each file goes up as soon as it's picked, and waits in the tray for the
/// message. With as many files as a message carries, it's off and says so.
struct AttachButton: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel

    var body: some View {
        let room = max(0, FilePrep.perMessage - model.files.count)
        Menu {
            Button { choose(photos: true, room: room) } label: { Label(words("chat.file.choose_photos"), systemImage: "photo.on.rectangle") }
            Button { choose(photos: false, room: room) } label: { Label(words("chat.file.choose_file"), systemImage: "doc") }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.panel))
                .overlay(Circle().stroke(Theme.line))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(room == 0)
        .accessibilityLabel(room == 0 ? words.count("chat.file.attach_full", FilePrep.perMessage) : words("chat.file.attach"))
    }

    /// The open panel: photos, or the kinds of file tafs takes, as many as the message has room
    /// for. Each is read, made ready and uploaded on its own.
    private func choose(photos: Bool, room: Int) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = photos ? [.image] : FilePrep.pickable
        panel.begin { response in
            guard response == .OK else { return }
            let urls = Array(panel.urls.prefix(room))
            Task { @MainActor in
                for url in urls { await add(url) }
            }
        }
    }

    @MainActor
    private func add(_ url: URL) async {
        let say = Words.app
        do {
            let file = try FilePrep.read(url, say: say)
            await model.attach(file)
        } catch {
            model.refuseFile(error)
        }
    }
}

/// The files waiting for the next message, above the box, as the iPad's `FileTray`
/// (AttachViews.swift:125-151): each with Remove, going up, ready, or saying why it can't go.
struct FileTray: View {
    @ObservedObject var model: CoachModel

    var body: some View {
        if !model.files.isEmpty || model.fileNotice != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !model.files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.files.files) { file in
                                FileChip(name: file.name, mediaType: file.mediaType, thumbnail: file.thumbnail, state: file.state) {
                                    model.removeFile(file.id)
                                }
                            }
                        }
                        .padding(.horizontal, 2).padding(.vertical, 2)
                    }
                }
                if let notice = model.fileNotice {
                    Text(verbatim: notice).font(.system(size: 13)).foregroundColor(Theme.no)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
        }
    }
}

/// One file in the tray, as the iPad's `FileChip` (AttachViews.swift:154-193).
struct FileChip: View {
    @Environment(\.words) private var words
    let name: String
    let mediaType: String
    let thumbnail: Data?
    let state: PendingFile.State
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FileIcon(mediaType: mediaType, thumbnail: thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                status
            }
            .frame(maxWidth: 180, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words("chat.file.remove", ["name": name]))
        }
        .padding(.leading, 6).padding(.trailing, 2).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(words("chat.file.uploading")).font(.system(size: 12)).foregroundColor(Theme.dim)
            }
        case .ready:
            Text(words("chat.file.ready")).font(.system(size: 12)).foregroundColor(Theme.dim)
        case .failed(let why):
            Text(verbatim: why).font(.system(size: 12)).foregroundColor(Theme.no).lineLimit(2)
        }
    }
}

/// A file's picture: a photo's thumbnail, else a symbol for its kind, as the iPad's `FileIcon`.
struct FileIcon: View {
    let mediaType: String
    var thumbnail: Data? = nil

    var body: some View {
        Group {
            if let thumbnail, let image = NSImage(data: thumbnail) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: FilePrep.symbol(mediaType))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.line.opacity(0.4))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The files sent with a message, in the thread, as the iPad's `MessageFiles`
/// (AttachViews.swift:229-266): each opens full size, in the app this Mac opens its kind with.
struct MessageFiles: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CoachModel
    let files: [AttachmentRef]
    @State private var opening: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(files) { file in
                Button {
                    guard opening == nil else { return }
                    opening = file.id
                    Task {
                        if let url = await model.openFile(file) { NSWorkspace.shared.open(url) }
                        opening = nil
                    }
                } label: {
                    HStack(spacing: 8) {
                        FileIcon(mediaType: file.mediaType)
                        Text(verbatim: file.name).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.ink).lineLimit(1)
                        if opening == file.id { ProgressView().controlSize(.small) }
                    }
                    .padding(6).padding(.trailing, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words("chat.file.open", ["name": file.name]))
            }
        }
    }
}
