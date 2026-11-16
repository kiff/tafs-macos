import SwiftUI

/// A label chip, as the iPad's `LabelChip` (BriefView.swift:142-169): its name and count, an amber
/// dot while one of its tafs waits; inverted when chosen.
struct LabelChip: View {
    let words: String
    let count: Int?
    let waiting: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if waiting { Circle().fill(Theme.amber).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(verbatim: words).font(.system(size: 13, weight: .medium))
                if let count { Text(verbatim: "\(count)").font(.system(size: 12)).opacity(0.7) }
            }
            .lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 28)
            .foregroundColor(selected ? Theme.onFill : Theme.ink)
            .background(Capsule().fill(selected ? Theme.ink : Theme.panel))
            .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of label chips, as the iPad's `LabelChips` (BriefView.swift:378-404): All, two labels, then
/// "+N" for the rest, which shows them all once clicked. The chosen one is inverted; clicked again,
/// it goes back to All.
struct LabelChips: View {
    let labels: [HomeLabel]
    let selected: String?
    /// tafs cloud's word for All, else the app's own.
    let all: String
    let choose: (String?) -> Void
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? labels : Array(labels.prefix(2))
        let hidden = labels.count - shown.count
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                LabelChip(words: all, count: nil, waiting: false, selected: selected == nil) { choose(nil) }
                ForEach(shown) { label in
                    LabelChip(words: label.name, count: label.count, waiting: label.waiting > 0, selected: selected == label.id) {
                        choose(selected == label.id ? nil : label.id)
                    }
                }
                if hidden > 0 { LabelChip(words: "+\(hidden)", count: nil, waiting: false, selected: false) { expanded = true } }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A taf's labels, as the iPad's `TafLabels` (BriefView.swift:406-427): small grey chips under its
/// name, two, then "+N"; nothing without labels.
struct TafLabelChips: View {
    let labels: [HomeLabel]

    var body: some View {
        if !labels.isEmpty {
            // Two, then "+1" (kiff/tafs docs/labels.md: a taf carries at most three).
            HStack(spacing: 4) {
                ForEach(labels.prefix(2)) { label in chip(label.name) }
                if labels.count > 2 { chip("+\(labels.count - 2)") }
            }
        }
    }

    private func chip(_ words: String) -> some View {
        Text(verbatim: words).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.soft)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Theme.raised))
    }
}
