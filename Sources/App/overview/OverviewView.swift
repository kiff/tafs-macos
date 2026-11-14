import SwiftUI

@MainActor
final class OverviewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Home.Page)
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// tafs cloud's line for an account with no taf yet, for the sidebar.
    @Published private(set) var noTafsLine: String?
    private let cloud: CloudClient

    init(cloud: CloudClient) { self.cloud = cloud }

    var tafs: [Home.Taf] {
        if case .loaded(let page) = state { return page.tafs }
        return []
    }

    func load() async {
        do { state = .loaded(try await cloud.home()) } catch { state = .unread(why: NeedsYouModel.why(error)) }
        // The line is only an invitation: if it can't be read, the sidebar just doesn't show one.
        noTafsLine = (try? await cloud.homeWords())?.line
    }
}

/// Overview: today, across the person's tafs, one line each.
struct OverviewView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: OverviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(words("home.overview.title")).font(Theme.display(30)).foregroundColor(Theme.ink)
                    Text(words("home.overview.subtitle")).font(.system(size: 14)).foregroundColor(Theme.dim)
                }
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_tafs")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.dim)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let page):
                    if let headline = page.headline {
                        Text(headline).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.ink)
                    }
                    if let needs = page.needsYouWords, (page.needsYouCount ?? 0) > 0 {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(needs).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                        }
                    }
                    table(page.tafs)
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func table(_ tafs: [Home.Taf]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                heading("home.overview.column_taf")
                heading("home.overview.column_now")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if tafs.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text(words("home.no_tafs")).font(.system(size: 14)).foregroundColor(Theme.dim).padding(16)
            }
            ForEach(tafs) { taf in
                Rectangle().fill(Theme.line).frame(height: 1)
                row(taf)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func heading(_ key: String) -> some View {
        Text(words(key)).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ taf: Home.Taf) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Theme.tafColor(taf.color)).frame(width: 28, height: 28)
                    .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundColor(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: taf.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    if let job = taf.jobSummary { Text(job).font(.system(size: 12)).foregroundColor(Theme.dim).lineLimit(2) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(taf.now ?? "–").font(.system(size: 13)).foregroundColor(taf.attention ? Theme.amberText : Theme.ink)
                if let trouble = taf.trouble { Text(trouble).font(.system(size: 12)).foregroundColor(Theme.no) }
                if taf.waiting > 0 {
                    Text(words.count("needs_you.count", taf.waiting)).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amberText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
