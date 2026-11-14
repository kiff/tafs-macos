import SwiftUI

/// What is to come on the days shown, for the Calendar screen: a week, or one day.
@MainActor
final class CalendarModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Agenda.Page)
        case unread(why: String)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var titleKey: String { self == .day ? "calendar.mode.day" : "calendar.mode.week" }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var mode: Mode = .week
    /// The day the screen is on: the one shown in Day, and the one whose week is shown in Week.
    @Published private(set) var day: String
    /// The month the small month card shows.
    @Published private(set) var monthShown: String
    /// Today in the account's zone, once tafs cloud has named it; in the Mac's zone until then.
    @Published private(set) var today: String

    private let cloud: CloudClient
    private let now: () -> Date
    private var asked = 0

    init(cloud: CloudClient, now: @escaping () -> Date = Date.init) {
        self.cloud = cloud
        self.now = now
        let start = Days.today(in: TimeZone.current.identifier, now: now())
        today = start
        day = start
        monthShown = start
    }

    /// The seven days of the week the screen is on, Monday first.
    var week: [String] { Days.week(of: day) }
    /// The days the grid shows.
    var days: [String] { mode == .week ? week : [day] }
    var showsToday: Bool { days.contains(today) }

    func load() async {
        guard let from = days.first, let to = days.last else { return }
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.calendar(from: from, to: to)
            guard mine == asked else { return }
            let first = today
            today = Days.today(in: page.timeZone, now: now())
            // The first read names the account's zone: if its today is another day, go there.
            if first != today, day == first {
                day = today
                monthShown = today
                state = .loaded(page)
                await load()
                return
            }
            state = .loaded(page)
        } catch {
            guard mine == asked else { return }
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// Moves by a week in Week, by a day in Day. A slower answer for days left behind is dropped.
    func move(_ steps: Int) async {
        guard let next = Days.adding(steps * (mode == .week ? 7 : 1), to: day) else { return }
        await go(to: next)
    }

    func go(to next: String) async {
        guard Days.date(next) != nil else { return }
        day = next
        monthShown = next
        state = .loading
        await load()
    }

    func goToToday() async { await go(to: today) }

    func show(_ mode: Mode) async {
        guard mode != self.mode else { return }
        self.mode = mode
        state = .loading
        await load()
    }

    /// Turns the month card's page, without changing the days shown.
    func turnMonth(_ offset: Int) {
        if let next = Days.month(offset, from: monthShown) { monthShown = next }
    }
}

/// Calendar, to the iPad's layout: the month's card and the agenda on the left, and the
/// days' hour grid on the right.
struct CalendarView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CalendarModel

    private static let hourHeight: CGFloat = 44
    private static let hoursWidth: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(words("calendar.heading")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 22) {
                        monthCard
                        agenda
                    }
                    .frame(width: 268)
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        modes
                        grid
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Look.inset - 8)
            .padding(.bottom, Look.inset)
        }
        .background(Theme.background)
        .task { await model.load() }
    }

    // MARK: The top line

    private var header: some View {
        HStack(spacing: 10) {
            Button(words("calendar.today")) { Task { await model.goToToday() } }
                .buttonStyle(.plain).font(.system(size: 14)).foregroundColor(Theme.soft)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().stroke(Theme.line))
            arrow("chevron.left", model.mode == .week ? "calendar.previous_week" : "calendar.previous_day") { await model.move(-1) }
            arrow("chevron.right", model.mode == .week ? "calendar.next_week" : "calendar.next_day") { await model.move(1) }
            Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if let p = Days.parts(model.today) {
                Text(verbatim: "\(p.day) \(words("calendar.month_name.\(p.monthKey)").prefix(3)) \(p.year)")
                    .font(.system(size: 14)).foregroundColor(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.raised))
            }
        }
    }

    private func arrow(_ symbol: String, _ key: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amberText)
                .frame(width: 22, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words(key))
    }

    /// "9 – 15 November 2026", across two months or years too; a day's own date in Day.
    private var title: String {
        guard let first = model.days.first.flatMap(Days.parts), let last = model.days.last.flatMap(Days.parts) else { return "" }
        func month(_ key: String) -> String { words("calendar.month_title.\(key)") }
        if model.mode == .day {
            return words("calendar.title.day", ["weekday": words("calendar.weekday.\(first.weekdayKey)"), "day": String(first.day),
                                                "month": month(first.monthKey), "year": String(first.year)])
        }
        let values = ["from_day": String(first.day), "to_day": String(last.day), "from_month": month(first.monthKey),
                      "to_month": month(last.monthKey), "month": month(last.monthKey),
                      "from_year": String(first.year), "to_year": String(last.year), "year": String(last.year)]
        if first.year != last.year { return words("calendar.title.week_across_years", values) }
        if first.month != last.month { return words("calendar.title.week_across_months", values) }
        return words("calendar.title.week", values)
    }

    private var modes: some View {
        HStack(spacing: 0) {
            ForEach(CalendarModel.Mode.allCases) { mode in
                let chosen = model.mode == mode
                Button { Task { await model.show(mode) } } label: {
                    Text(words(mode.titleKey)).font(.system(size: 13, weight: chosen ? .semibold : .regular)).foregroundColor(Theme.ink)
                        .frame(width: 96).padding(.vertical, 6)
                        .background(Capsule().fill(chosen ? Theme.panel : Color.clear)).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.raised))
        .accessibilityLabel(words("calendar.view_picker"))
    }

    // MARK: The hour grid

    @ViewBuilder private var grid: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(words("calendar.reading")).font(.system(size: 14)).foregroundColor(Theme.soft)
            }
        case .unread(let why):
            Text(words("home.calendar_not_read", ["why": why])).font(.system(size: 14)).foregroundColor(Theme.no)
            Button(words("common.try_again")) { Task { await model.load() } }
        case .loaded(let page):
            let hours = Days.hours(covering: page.events.map(\.minute))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: Self.hoursWidth, height: 1)
                    ForEach(model.days, id: \.self) { day in dayHeading(day).frame(maxWidth: .infinity) }
                }
                .padding(.bottom, 8)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(Array(hours), id: \.self) { hour in
                            HStack(alignment: .top, spacing: 0) {
                                Text(verbatim: String(format: "%02d:00", hour)).font(Theme.mono(11)).foregroundColor(Theme.soft)
                                    .frame(width: Self.hoursWidth, alignment: .leading).padding(.top, 3)
                                Spacer(minLength: 0)
                            }
                            .frame(height: Self.hourHeight, alignment: .top)
                            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
                        }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: Self.hoursWidth, height: 1)
                        ForEach(model.days, id: \.self) { day in
                            ZStack(alignment: .topLeading) {
                                Color.clear
                                ForEach(page.events(on: day)) { event in
                                    block(event).offset(y: CGFloat(event.minute - hours.lowerBound * 60) / 60 * Self.hourHeight)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: CGFloat(hours.count) * Self.hourHeight, alignment: .top)
                .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
                // tafs cloud's line for a halt; else the app's line for an empty range.
                if page.halted, !page.words.isEmpty {
                    Text(page.words).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.no).padding(.top, 12)
                } else if page.events.isEmpty {
                    Text(words(model.mode == .week ? "calendar.nothing_this_week" : "calendar.nothing_on_day"))
                        .font(.system(size: 14)).foregroundColor(Theme.soft).padding(.top, 12)
                }
            }
        }
    }

    private func dayHeading(_ day: String) -> some View {
        let isToday = day == model.today
        let p = Days.parts(day)
        return VStack(spacing: 2) {
            Text(p.map { words("calendar.weekday.\($0.weekdayKey)") } ?? "").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.soft)
            Text(verbatim: p.map { String($0.day) } ?? "").font(.system(size: 15, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? Theme.amberText : Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }

    /// One event in its day's column, at its time: its taf's colour, its time and its name.
    private func block(_ event: Agenda.Event) -> some View {
        HStack(spacing: 4) {
            // In a week's narrow column the hour lines say the time; a day's column has room for it.
            if model.mode == .day { Text(verbatim: event.time).font(Theme.mono(10, weight: .semibold)) }
            Text(verbatim: event.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if event.count > 1 { Text(words.count("calendar.times", event.count)).font(.system(size: 10)) }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5).frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.tafColor(event.color)))
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.count > 1 ? words.count("calendar.slot_times", event.count, ["name": event.name, "first": event.time])
                                            : words("calendar.slot_at", ["name": event.name, "first": event.time]))
    }

    // MARK: The month card and the agenda

    private var monthCard: some View {
        let grid = Days.monthGrid(of: model.monthShown)
        let shown = Days.parts(model.monthShown)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(shown.map { words("calendar.title.month", ["month": words("calendar.month_title.\($0.monthKey)"), "year": String($0.year)]) } ?? "")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer()
                monthArrow("chevron.left", "calendar.previous_month", -1)
                monthArrow("chevron.right", "calendar.next_month", 1)
            }
            HStack(spacing: 0) {
                ForEach(["mon", "tue", "wed", "thu", "fri", "sat", "sun"], id: \.self) { key in
                    Text(words("calendar.weekday.\(key)")).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.soft).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if grid.count == 42 { monthDay(grid[week * 7 + column], inMonth: shown?.month) }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    private func monthArrow(_ symbol: String, _ key: String, _ offset: Int) -> some View {
        Button { model.turnMonth(offset) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amberText).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words(key))
    }

    private func monthDay(_ day: String, inMonth month: Int?) -> some View {
        let p = Days.parts(day)
        let isToday = day == model.today
        let shown = model.days.contains(day)
        return Button { Task { await model.go(to: day) } } label: {
            Text(verbatim: p.map { String($0.day) } ?? "")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(p?.month == month ? Theme.ink : Theme.soft.opacity(0.6))
                .frame(maxWidth: .infinity).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(isToday ? Theme.amber.opacity(0.18) : (shown ? Theme.raised.opacity(0.6) : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isToday ? Theme.amber : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(heading(day))
    }

    @ViewBuilder private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("calendar.agenda"))
            if case .loaded(let page) = model.state {
                if page.events.isEmpty {
                    // tafs cloud's own line for the range; the app's when it sent none.
                    Text(page.words.isEmpty ? words("calendar.nothing_these_days") : page.words).font(.system(size: 13)).foregroundColor(Theme.soft)
                }
                ForEach(model.days.filter { !page.events(on: $0).isEmpty }, id: \.self) { day in
                    Text(heading(day)).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.soft)
                    ForEach(page.events(on: day)) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: event.time).font(Theme.mono(12, weight: .semibold)).foregroundColor(Theme.ink)
                            Circle().fill(Theme.tafColor(event.color)).frame(width: 7, height: 7).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: event.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink)
                                if !event.words.isEmpty { Text(event.words).font(.system(size: 11)).foregroundColor(Theme.soft) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    private func heading(_ day: String) -> String {
        guard let p = Days.parts(day) else { return day }
        return words("calendar.day_heading", ["weekday": words("calendar.weekday.\(p.weekdayKey)"), "day": String(p.day),
                                              "month": words("calendar.month_name.\(p.monthKey)")])
    }
}
