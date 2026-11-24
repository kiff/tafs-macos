import AppKit
import SwiftUI

/// Coach mode on the Mac, as the iPad's `CoachPanel` (CoachMode.swift:34-111): Coach slides in from
/// the right over whatever is on screen, which stays in view. Every way into Coach opens it here,
/// on the right chat; its Back closes it, and closing never ends a conversation.
@MainActor
final class CoachPanelModel: ObservableObject {
    /// Coach is open over the screen, as the iPad's `coachOpen`.
    @Published private(set) var open = false
    /// Coach fills the window, as the iPad's ⤢ (`coach.full`); kept on this Mac.
    @Published var full: Bool {
        didSet { defaults.set(full, forKey: CoachPanelWidth.fullKey) }
    }
    /// The width the person chose, in points (`CoachPanelWidth`); kept on this Mac.
    @Published var width: Double {
        didSet { defaults.set(width, forKey: CoachPanelWidth.widthKey) }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _full = Published(initialValue: defaults.bool(forKey: CoachPanelWidth.fullKey))
        _width = Published(initialValue: CoachPanelWidth.remembered(defaults.object(forKey: CoachPanelWidth.widthKey) as? Double))
    }

    /// The sidebar's Coach and Connect apps' way to Coach, as the iPad's `openCoach`: it only opens
    /// Coach, on the chat it had.
    func openCoach() { open = true }

    /// Closes Coach, back to the screen under it, as the iPad's Coach mode's Back.
    func close() { open = false }

    /// Start a new taf, as the iPad's `startNewTaf`: a new conversation, so Coach mode's start shows.
    func startNewTaf(in coach: CoachModel) {
        coach.startNewTaf()
        open = true
    }

    /// Needs you's Open Coach, as the iPad's `openCoachWaiting`: Coach on that chat, where its card
    /// waits; Coach alone without one.
    func openWaiting(_ session: String, in coach: CoachModel) async {
        open = true
        guard !session.isEmpty else { return }
        await coach.open(waiting: session)
    }

    /// Improve in Coach on a taf's page, as the iPad's `improveTaf` with `coachOpen`: a new
    /// conversation on the taf, over its page.
    func improve(_ taf: CoachModel.Improving, in coach: CoachModel) {
        coach.improve(taf)
        open = true
    }

    /// Ask Coach on a taf's `ask_coach` card, as the iPad's `askCoachAbout`: Coach on the taf with
    /// the card's words in its box, nothing sent. Only for someone who may use Coach and manages
    /// the taf: for anyone else, Coach doesn't open.
    func ask(about taf: CoachModel.Improving, words: String, mayUseCoach: Bool, manages: Bool, in coach: CoachModel) {
        guard mayUseCoach, manages else { return }
        coach.ask(about: taf, words: words, mayUseCoach: mayUseCoach, manages: manages)
        open = true
    }

    /// The brief's next move, in the box of the chat shown, to edit and send, as the iPad's
    /// `startNextMove`. Nothing is sent.
    func hand(_ words: String, to coach: CoachModel) {
        coach.draft = words
        open = true
    }

    /// A job from the Overview or the gallery, as the iPad's `handRecipeToCoach`: a new
    /// conversation with its words in the box, to edit and send. Nothing is sent.
    func handRecipe(_ words: String, to coach: CoachModel) {
        coach.handRecipe(words)
        open = true
    }
}

/// The window with Coach over it: the screen fills it, and Coach, while open, sits at its right on
/// the background with a shadow to its left, `leading` (the sidebar) never covered unless it fills
/// the window. Where Coach isn't, the screen is drawn and used as ever: nothing dims it, and a click
/// on it doesn't close Coach (the iPad's tap outside does).
struct CoachPanelHost<Screen: View, Panel: View>: View {
    @Environment(\.words) private var words
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var panel: CoachPanelModel
    let leading: CGFloat
    let screen: Screen
    let coach: Panel
    /// How far the edge is dragged, in points, while it is.
    @State private var drag: CGFloat = 0

    init(panel: CoachPanelModel, leading: CGFloat, @ViewBuilder screen: () -> Screen, @ViewBuilder coach: () -> Panel) {
        self.panel = panel
        self.leading = leading
        self.screen = screen()
        self.coach = coach()
    }

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .trailing) {
                screen
                if panel.open { sliding(window: space.size.width) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: panel.open)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: panel.full)
        }
    }

    /// The screen's width beside the sidebar.
    private func detail(_ window: CGFloat) -> Double { Double(max(0, window - leading)) }

    /// Coach's width: the one chosen as drawn in this window, as the edge is dragged.
    private func shown(_ window: CGFloat) -> CGFloat {
        let base = CoachPanelWidth.drawn(panel.width, detail: detail(window))
        return CGFloat(CoachPanelWidth.drawn(base - Double(drag), detail: detail(window)))
    }

    private func sliding(window: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !panel.full { edge(window: window) }
            coach
        }
        .frame(width: panel.full ? window : shown(window))
        .frame(maxHeight: .infinity)
        // The shadow is the background's alone, so the words in it cast none.
        .background(Theme.background.shadow(color: Color.black.opacity(panel.full ? 0 : 0.18), radius: 24, x: -4, y: 0))
        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
    }

    /// The left edge, as the iPad's handle: a line and a grip, which a drag moves to make Coach
    /// wider or narrower, between its narrowest and what leaves the screen in view.
    private func edge(window: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.line).frame(width: 1)
            Capsule().fill(Theme.dim.opacity(0.5)).frame(width: 5, height: 44).frame(maxWidth: .infinity)
        }
        .frame(width: 12)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        // In the window's space: the edge moves under the pointer as Coach widens.
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in drag = value.translation.width }
            .onEnded { value in
                let from = CoachPanelWidth.drawn(panel.width, detail: detail(window))
                panel.width = CoachPanelWidth.dragged(from: from, moved: Double(value.translation.width), detail: detail(window))
                drag = 0
            })
        .accessibilityElement()
        .accessibilityLabel(words("coach.coach_mode_width"))
        .accessibilityHint(words("coach.drag_make_wider_narrower"))
    }
}
