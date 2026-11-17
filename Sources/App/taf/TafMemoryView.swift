import SwiftUI

/// What a taf remembers, as the iPad's `memories` and `memoryErrors` with `loadAllMemory` and
/// `forget` (AppModel.swift:204-211, 4422-4479): every note on See all, newest first. Forget takes
/// a note from the list at once and puts it back if tafs cloud refuses; one already gone (404)
/// stays gone.
@MainActor
final class TafMemoryModel: ObservableObject {
    @Published private(set) var notes: [TafMemory.Note]?
    @Published private(set) var error: String?

    private let cloud: CloudClient
    let taf: String

    init(cloud: CloudClient, taf: String) {
        self.cloud = cloud
        self.taf = taf
    }

    /// Reads every note.
    func loadAll() async {
        let client = cloud
        let id = taf
        do {
            let read = try await client.memory(of: id, all: true)
            notes = read
            error = nil
        } catch {
            self.error = Words.app("taf.memory.not_loaded", ["why": NeedsYouModel.why(error)])
        }
    }

    /// Forgets one note. True once tafs cloud forgot it, or it was already gone.
    @discardableResult
    func forget(_ note: TafMemory.Note) async -> Bool {
        guard let before = notes, before.contains(note) else { return false }
        notes = TafMemory.without(note, in: before)
        error = nil
        let client = cloud
        let id = taf
        let noteID = note.id
        do {
            try await client.forget(note: noteID, of: id)
            return true
        } catch let refusal as CloudRefusal where refusal.status == 404 {
            return true
        } catch {
            notes = TafMemory.putting(note, backInto: notes ?? [])
            self.error = Words.app("taf.memory.not_forgotten", ["why": NeedsYouModel.why(error)])
            return false
        }
    }
}

/// A taf's notes, all of them, as the iPad's `MemoryPanel` with `loadAll` (TafDetailView.swift:1132-1181):
/// each note's words, its name and when; Forget, confirmed first, since it can't be undone.
struct TafMemoryView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafMemoryModel
    let close: () -> Void
    /// The note waiting for the person's yes.
    @State private var forgetting: TafMemory.Note?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(words("taf.memory.title")).font(Theme.display(22)).foregroundColor(Theme.ink)
                Spacer()
                Button(words("common.done"), action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.background)
        .task { await model.loadAll() }
        .confirmationDialog(words("taf.memory.forget_title"), isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { note in
            Button(words("taf.memory.forget"), role: .destructive) { Task { await model.forget(note) } }
            Button(words("common.cancel"), role: .cancel) {}
        } message: { note in
            Text(words("taf.memory.forget_body", ["note": note.content]))
        }
    }

    @ViewBuilder private var content: some View {
        Eyebrow(text: words("taf.memory.title"))
        if let notes = model.notes {
            if notes.isEmpty {
                Text(words("taf.memory.empty")).font(.system(size: 14)).foregroundColor(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(notes) { note($0) }
            Text(words("taf.memory.explains")).font(.system(size: 12)).foregroundColor(Theme.soft)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.error == nil {
            ProgressView().controlSize(.small)
        }
        if let error = model.error {
            Text(verbatim: error).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ note: TafMemory.Note) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: note.content).font(.system(size: 15)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: note.byline(AppDates.formatter(words, time: .short).string(from: note.updatedAt)))
                    .font(.system(size: 12)).foregroundColor(Theme.soft)
            }
            Spacer(minLength: 0)
            Button(words("taf.memory.forget")) { forgetting = note }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.soft)
                .accessibilityLabel(words("taf.memory.forget_label", ["note": note.content]))
        }
    }
}
