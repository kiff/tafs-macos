import SwiftUI

@MainActor
final class OverviewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Home.Page)
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    private let cloud: CloudClient

    init(cloud: CloudClient) { self.cloud = cloud }

    func load() async {
        do { state = .loaded(try await cloud.home()) } catch { state = .unread(why: NeedsYouModel.why(error)) }
    }
}

/// Overview: today, across the person's tafs, one line each, to the iPad's layout: a large
/// title, the columns' headings, and plain rows with no panel behind them.
struct OverviewView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: OverviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(title: words("home.overview.title"), lead: words("home.overview.subtitle"))
                    .padding(.top, 56)
                switch model.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unread(let why):
                    Text(words("home.couldnt_load_tafs")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no)
                    Text(verbatim: why).font(.system(size: 13)).foregroundColor(Theme.soft)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let page):
                    if let needs = page.needsYouWords, (page.needsYouCount ?? 0) > 0 {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.amber).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(needs).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                        }
                    }
                    table(page.tafs)
                }
            }
            .padding(.horizontal, Look.inset)
            .padding(.bottom, Look.inset)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    /// The iPad's four columns. The Card and the last result aren't read yet, so their
    /// columns keep their place and their headings, and say nothing.
    private func table(_ tafs: [Home.Taf]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ForEach(["home.overview.column_taf", "home.overview.column_now", "home.overview.column_card", "home.overview.column_last_result"], id: \.self) { key in
                    Eyebrow(text: words(key)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if tafs.isEmpty {
                Text(words("home.no_tafs")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
            ForEach(tafs) { taf in
                Rectangle().fill(Theme.line).frame(height: 1)
                row(taf)
            }
        }
    }

    private func row(_ taf: Home.Taf) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.tafColor(taf.color)).frame(width: 30, height: 30)
                    .overlay(Text(verbatim: String(taf.name.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: taf.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    if let job = taf.jobSummary { Text(job).font(.system(size: 12)).foregroundColor(Theme.soft).lineLimit(2) }
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
            // The Card's and the last result's places, kept empty until they are read.
            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
