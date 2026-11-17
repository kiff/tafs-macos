import SwiftUI

/// The sidebar's Halt all, as the iPad's `haltAllRow` (HomeSplitView.swift:257-270), in its own
/// section under Connect apps (:318-323): a red hand, filled once halted or halting, "Halt all",
/// and where it stands in red unless every taf runs. It opens the Halt all screen (`HaltView`).
/// Shown only where the iPad shows it (`AccountHalt.shown`).
struct HaltAllItem: View {
    @Environment(\.words) private var words
    @ObservedObject var model: HaltModel
    /// Reads the list again after a halt tafs cloud answered.
    var halted: () async -> Void = {}
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: model.halt.state == .running ? "hand.raised" : "hand.raised.fill")
                    .font(.system(size: 17)).foregroundColor(Theme.no)
                    .frame(width: 24, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(words("taf.halt.title_all")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    if model.halt.state != .running {
                        Text(model.halt.headline(words)).font(.system(size: 13)).foregroundColor(Theme.no)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        // Where it stands, read when it shows, as the iPad's row reads it.
        .task { await model.refresh() }
        .sheet(isPresented: $open) {
            HaltView(model: model, name: nil, halted: halted) { open = false }.environment(\.words, words)
        }
    }
}
