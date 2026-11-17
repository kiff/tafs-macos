import SwiftUI

/// A taf's connected apps as the iPad's `ConnectedToolsRing` (TafPresentationViews.swift:25-143):
/// the taf in the middle, which says its job, each app a node around it on a dashed spoke, a green
/// arc on the ones it's using now, and + to connect another for whoever manages the taf. Under the
/// ring, its workflow, which opens to Change the workflow with Coach. A node opens the app's sheet.
struct ConnectedToolsRing: View {
    @Environment(\.words) private var words
    @ObservedObject var model: TafPagesModel
    let taf: Home.Taf
    let manages: Bool
    let openActivity: (String) -> Void
    /// Connect apps; nil draws no +.
    var openConnect: (() -> Void)? = nil
    /// Coach on this taf; nil draws no way to change the workflow.
    var improveInCoach: (() -> Void)? = nil
    @State private var chosen: TafSetup.Node?
    @State private var job = false
    @State private var workflowOpen = false

    /// How tall the ring is drawn, as the iPad's.
    static let height: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("connect.connected_tools"))
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Look.panelRadius, style: .continuous).fill(Theme.panel))
        .sheet(item: $chosen) { node in
            ConnectedAppSheet(node: node, close: { chosen = nil }, openActivity: { query in
                chosen = nil
                openActivity(query)
            })
            .environment(\.words, words)
        }
        .alert(Text(verbatim: taf.name), isPresented: $job, actions: {
            Button(words("common.done"), role: .cancel) {}
        }, message: {
            Text(verbatim: taf.job(words))
        })
    }

    @ViewBuilder private var content: some View {
        switch model.setup {
        case .loading:
            ProgressView().controlSize(.small)
        case .unread(let why):
            failed(why)
        case .loaded(let setup):
            if let error = setup.connectionsError { failed(error) }
            ring(TafSetup.nodes(setup.connections))
            if let workflow = setup.workflow { self.workflow(workflow) }
        }
    }

    /// What couldn't be read, in red, with Try again, as the iPad's.
    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.no).fixedSize(horizontal: false, vertical: true)
            Button(words("common.try_again")) { Task { await model.loadSetup() } }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amberText)
        }
    }

    private func ring(_ nodes: [TafSetup.Node]) -> some View {
        GeometryReader { g in
            let count = nodes.count + (openConnect == nil ? 0 : 1)
            let center = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let radius = min(g.size.width, g.size.height) / 2 - 36
            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    spoke(node, angle: Self.angle(index, of: count), center: center, radius: radius)
                }
                if let openConnect { plus(openConnect, at: Self.point(Self.angle(nodes.count, of: count), center: center, radius: radius)) }
                Button { job = true } label: {
                    TafAvatar(name: taf.name, color: taf.color, size: 54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words("taf.job_label", ["taf": taf.name]))
                .position(center)
            }
        }
        .frame(height: Self.height)
    }

    /// Where the node at `index` of `count` sits: from the top, clockwise, as the iPad's.
    static func angle(_ index: Int, of count: Int) -> Double {
        -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(count, 1))
    }

    static func point(_ angle: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }

    /// One app: its dashed spoke, the green arc while the taf uses it, and its node.
    @ViewBuilder private func spoke(_ node: TafSetup.Node, angle: Double, center: CGPoint, radius: CGFloat) -> some View {
        let point = Self.point(angle, center: center, radius: radius)
        Path { p in p.move(to: center); p.addLine(to: point) }
            .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        if node.app.running {
            Circle().trim(from: 0, to: 0.1).stroke(Theme.ok, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.radians(angle)).frame(width: radius * 2, height: radius * 2).position(center)
        }
        Button { chosen = node } label: { nodeLabel(node.app) }
            .buttonStyle(.plain)
            .position(point)
    }

    private func nodeLabel(_ app: TafSetup.Connection) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: app.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(2)
            if let actions = app.actionWords {
                Text(verbatim: actions).font(.system(size: 11)).foregroundColor(app.running ? Theme.ok : Theme.soft).lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: 78)
        .padding(5)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    /// + : another app, from Connect apps.
    private func plus(_ open: @escaping () -> Void, at point: CGPoint) -> some View {
        Button(action: open) {
            Image(systemName: "plus").font(.system(size: 24)).foregroundColor(Theme.ink)
                .frame(width: 46, height: 46)
                .background(Theme.raised)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words("connect.connect_an_app"))
        .position(point)
    }

    /// Its workflow, as tafs cloud words it, opening to Change the workflow with Coach. Its steps
    /// aren't read on this Mac yet.
    private func workflow(_ workflow: TafSetup.Part) -> some View {
        DisclosureGroup(isExpanded: $workflowOpen) {
            if manages, let improveInCoach {
                Button(words("taf.workflow.change_with_coach"), action: improveInCoach)
                    .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: workflow.title).font(.system(size: 15)).foregroundColor(Theme.ink)
                if let summary = workflow.summary { Text(verbatim: summary).font(.system(size: 13)).foregroundColor(Theme.soft) }
            }
        }
    }
}
