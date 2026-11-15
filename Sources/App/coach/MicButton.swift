import AppKit
import SwiftUI

/// The mic in a chat's message bar, the same in a taf's chat and in Coach, as the iPad's
/// `MicButton` (Views/MicButton.swift:4-61): click to dictate into the box, click again (or
/// send) to stop. Nothing is sent by voice: the words wait in the box until the person sends
/// them. It's always there, so dictating can go on after what's already in the box.
struct MicButton: View {
    @Environment(\.words) private var words
    @ObservedObject var dictation: Dictation
    @Binding var text: String
    /// The words the person is likely to say (`Dictating.hints`).
    var hints: [String] = []

    var body: some View {
        HStack(spacing: 4) {
            if dictation.languages.count > 1 {
                // The language, a switch among the person's own, before dictating or while.
                Button {
                    Task { await dictation.switchLanguage(text: text, hints: hints) { text = $0 } }
                } label: {
                    Text(verbatim: dictation.language.label)
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 8).frame(height: 28)
                        .overlay(Capsule().stroke(Theme.line))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 40, minHeight: 40)
                .accessibilityLabel(words("voice.dictation_in", ["language": dictation.language.name]))
            }
            Button {
                Task { await dictation.toggle(text: text, hints: hints) { text = $0 } }
            } label: {
                Image(systemName: dictation.listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(dictation.listening ? Theme.onFill : Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(dictation.listening ? Theme.no : Theme.panel)
                    .overlay(Circle().stroke(Theme.line))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(words(dictation.listening ? "voice.stop" : "voice.dictate"))
            .accessibilityHint(words(dictation.listening ? "voice.what_you_said_stays_message" : "voice.voice_becomes_text_device_not"))
        }
        .alert(words("voice.title"), isPresented: Binding(get: { blocked != nil }, set: { if !$0 { dictation.dismiss() } })) {
            // As the iPad's: a way to the settings when the words name them; on a Mac, its
            // Security & Privacy pane, where the microphone and speech recognition are allowed.
            if blocked?.contains("Settings") == true, let url = Self.privacy {
                Button(words("voice.open_settings")) {
                    dictation.dismiss()
                    NSWorkspace.shared.open(url)
                }
            }
            Button(words("common.ok"), role: .cancel) { dictation.dismiss() }
        } message: {
            Text(verbatim: blocked ?? "")
        }
    }

    /// Why dictation can't run, while the person reads it.
    private var blocked: String? {
        if case .blocked(let why) = dictation.state { return why }
        return nil
    }

    /// System Preferences' Security & Privacy › Privacy, the Mac's place for these permissions.
    static let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
}

/// Under the message bar while dictating, as the iPad's `DictationBar` (Views/MicButton.swift:63-96):
/// the microphone's sound as it comes, so it's plain that dictation is on, with cancel (the box
/// goes back as it was). Stop is the mic's own, in the bar.
struct DictationBar: View {
    @Environment(\.words) private var words
    @ObservedObject var dictation: Dictation

    var body: some View {
        if dictation.listening {
            HStack(spacing: 12) {
                Button { dictation.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.panel)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words("voice.cancel_dictating"))
                .accessibilityHint(words("voice.puts_message_box_back"))
                Waveform(levels: dictation.levels)
                    .frame(height: 28)
                    .accessibilityElement()
                    .accessibilityLabel(words("voice.listening_in", ["name": dictation.language.name]))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.panel.opacity(0.6))
            .overlay(Capsule().stroke(Theme.line))
            .clipShape(Capsule())
            .padding(.horizontal, 16).padding(.bottom, 8)
            .transition(.opacity)
        }
    }
}

/// The latest levels as bars, newest on the right; dots where it was quiet.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = Dictation.levelCount
            let step = geo.size.width / CGFloat(count)
            let shown = Array(repeating: Float(0), count: max(0, count - levels.count)) + levels.suffix(count)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(level > 0.05 ? Theme.ink : Theme.dim)
                        .frame(width: max(2, step * 0.45), height: max(2, geo.size.height * CGFloat(level)))
                        .frame(width: step)
                }
            }
            .frame(height: geo.size.height)
            .animation(.linear(duration: 0.08), value: levels)
        }
    }
}
