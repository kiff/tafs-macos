import SwiftUI

/// One week of what is to come, for the Calendar screen.
@MainActor
final class CalendarModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Agenda.Page)
        case unread(why: String)
    }

    @Published private(set) var state: State = .loading
    /// The seven days shown, Monday first.
    @Published private(set) var week: [String]
    /// Today in the account's zone, once tafs cloud has named it; in the Mac's zone until then.
    @Published private(set) var today: String

    private let cloud: CloudClient
    private let now: () -> Date
    private var asked = 0

    init(cloud: CloudClient, now: @escaping () -> Date = Date.init) {
        self.cloud = cloud
        self.now = now
        today = Days.today(in: TimeZone.current.identifier, now: now())
        week = Days.week(of: Days.today(in: TimeZone.current.identifier, now: now()))
    }

    func load() async {
        guard let from = week.first, let to = week.last else { return }
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.calendar(from: from, to: to)
            guard mine == asked else { return }
            today = Days.today(in: page.timeZone, now: now())
            state = .loaded(page)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// Moves by whole weeks. A slower answer for a week left behind is dropped.
    func move(weeks: Int) async {
        guard let first = week.first, let start = Days.adding(7 * weeks, to: first) else { return }
        week = Days.week(of: start)
        state = .loading
        await load()
    }

    func goToToday() async {
        week = Days.week(of: today)
        state = .loading
        await load()
    }

    var showsToday: Bool { week.contains(today) }
}

/// Calendar: the tafs' scheduled work to come, a week at a time, Monday to Sunday.
struct CalendarView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CalendarModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(words("calendar.heading")).font(Theme.display(28)).foregroundColor(Theme.ink)
                    Spacer()
                    arrow("chevron.left", "calendar.previous_week") { await model.move(weeks: -1) }
                    Button(words("calendar.today")) { Task { await model.goToToday() } }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(model.showsToday ? Theme.onFill : Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(model.showsToday ? Theme.ink : Theme.raised))
                    arrow("chevron.right", "calendar.next_week") { await model.move(weeks: 1) }
                }
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.soft)
                switch model.state {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(words("calendar.reading")).font(.system(size: 14)).foregroundColor(Theme.dim)
                    }
                case .unread(let why):
                    Text(words("home.calendar_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
                    Button(words("common.try_again")) { Task { await model.load() } }
                case .loaded(let page):
                    if !page.words.isEmpty {
                        Text(page.words).font(.system(size: 14, weight: page.halted ? .semibold : .regular))
                            .foregroundColor(page.halted ? Theme.no : Theme.dim)
                    }
                    if page.events.isEmpty, !page.halted, page.words.isEmpty {
                        Text(words("calendar.nothing_this_week")).font(.system(size: 14)).foregroundColor(Theme.dim)
                    }
                    ForEach(model.week, id: \.self) { day in dayCard(day, page.events(on: day)) }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    private func arrow(_ symbol: String, _ key: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.raised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words(key))
    }

    /// "9 – 15 November 2026", or across two months or two years, in the shared lines.
    private var title: String {
        guard let first = model.week.first.flatMap(Days.parts), let last = model.week.last.flatMap(Days.parts) else { return "" }
        let values = [
            "from_day": String(first.day), "to_day": String(last.day),
            "from_month": words("calendar.month_title.\(first.monthKey)"), "to_month": words("calendar.month_title.\(last.monthKey)"),
            "month": words("calendar.month_title.\(last.monthKey)"),
            "from_year": String(first.year), "to_year": String(last.year), "year": String(last.year),
        ]
        if first.year != last.year { return words("calendar.title.week_across_years", values) }
        if first.month != last.month { return words("calendar.title.week_across_months", values) }
        return words("calendar.title.week", values)
    }

    private func dayCard(_ day: String, _ events: [Agenda.Event]) -> some View {
        let isToday = day == model.today
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(heading(day)).font(.system(size: 13, weight: .bold)).foregroundColor(isToday ? Theme.ink : Theme.soft)
                if isToday {
                    Text(words("calendar.today")).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.onFill)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Theme.ink))
                }
            }
            if events.isEmpty {
                Text(words("calendar.nothing_on_day")).font(.system(size: 13)).foregroundColor(Theme.dim)
            }
            ForEach(events) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: event.time).font(Theme.mono(13, weight: .semibold)).foregroundColor(Theme.ink).frame(width: 52, alignment: .leading)
                    Circle().fill(Theme.tafColor(event.color)).frame(width: 8, height: 8).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: event.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                            if event.count > 1 {
                                Text(words.count("calendar.times", event.count)).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.soft)
                            }
                        }
                        if !event.words.isEmpty { Text(event.words).font(.system(size: 12)).foregroundColor(Theme.dim) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isToday ? Theme.ink.opacity(0.35) : Theme.line))
    }

    private func heading(_ day: String) -> String {
        guard let p = Days.parts(day) else { return day }
        return words("calendar.day_heading", ["weekday": words("calendar.weekday.\(p.weekdayKey)"), "day": String(p.day),
                                              "month": words("calendar.month_name.\(p.monthKey)")])
    }
}
