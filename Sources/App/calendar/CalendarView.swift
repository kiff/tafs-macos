import SwiftUI

/// What is to come on the days shown, for the Calendar screen: a day, a week or a month.
@MainActor
final class CalendarModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Agenda.Page)
        case unread(why: String)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var titleKey: String { "calendar.mode.\(rawValue)" }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var mode: Mode = .week
    /// The day the screen is on: the one shown in Day, and the one whose week, month and month
    /// card are shown.
    @Published private(set) var day: String
    /// Today in the account's zone, once tafs cloud has named it; in the Mac's zone until then.
    @Published private(set) var today: String

    private let cloud: CloudClient
    private let now: () -> Date
    private var asked = 0
    /// The range the page in `state` answers.
    private var read: String?

    init(cloud: CloudClient, now: @escaping () -> Date = Date.init) {
        self.cloud = cloud
        self.now = now
        let start = Days.today(in: TimeZone.current.identifier, now: now())
        today = start
        day = start
    }

    /// The seven days of the week the screen is on, Monday first.
    var week: [String] { Days.week(of: day) }
    /// The days shown: the day, its week, or its month's days.
    var days: [String] {
        switch mode {
        case .day: return [day]
        case .week: return week
        case .month: return Days.month(of: day)
        }
    }
    var showsToday: Bool { days.contains(today) }

    /// Reads the month card's six weeks around the day, as the iPad does.
    func load() async {
        guard let range = Days.range(of: day) else { return }
        asked += 1
        let mine = asked
        do {
            let page = try await cloud.calendar(from: range.from, to: range.to)
            guard mine == asked else { return }
            let first = today
            today = Days.today(in: page.timeZone, now: now())
            read = "\(range.from)|\(range.to)"
            state = .loaded(page)
            // The first read names the account's zone: if its today is another day, go there.
            if first != today, day == first { await go(to: today) }
        } catch {
            guard mine == asked else { return }
            read = nil
            state = .unread(why: NeedsYouModel.why(error))
        }
    }

    /// Moves by a day, a week or a month, as the view is. A slower answer for days left behind
    /// is dropped.
    func move(_ steps: Int) async {
        let next: String?
        switch mode {
        case .day: next = Days.adding(steps, to: day)
        case .week: next = Days.adding(steps * 7, to: day)
        case .month: next = Days.adding(months: steps, to: day)
        }
        if let next { await go(to: next) }
    }

    /// Goes to a day; reads only when its six weeks are not the ones already read.
    func go(to next: String) async {
        guard Days.date(next) != nil, let range = Days.range(of: next) else { return }
        day = next
        if case .loaded = state, read == "\(range.from)|\(range.to)" { return }
        state = .loading
        await load()
    }

    func goToToday() async { await go(to: today) }

    /// Changes the view only: every view's days are in the six weeks already read.
    func show(_ mode: Mode) { self.mode = mode }

    /// The month card's arrows: the same day a month before or after, as on the iPad.
    func turnMonth(_ offset: Int) async {
        if let next = Days.adding(months: offset, to: day) { await go(to: next) }
    }
}

/// Calendar, to the iPad's layout: the month's card and the agenda on the left, and the
/// days' hour grid, or the month, on the right.
struct CalendarView: View {
    @Environment(\.words) private var words
    @ObservedObject var model: CalendarModel
    @State private var choosingDate = false

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
                        why
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
            todayPill
            arrow("chevron.left", "calendar.previous_\(step)") { await model.move(-1) }
            arrow("chevron.right", "calendar.next_\(step)") { await model.move(1) }
            Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            datePill
        }
    }

    /// The day shown, as the iPad's compact date pill ("Nov 15, 2026", a medium date in the
    /// app's language, on a raised capsule). macOS 12's compact picker is a numeric field, so
    /// the pill is a button that opens the month's calendar; choosing a day goes there. Days are
    /// dates with no zone, so the calendar reads them in UTC.
    private var datePill: some View {
        Button { choosingDate = true } label: {
            Text(verbatim: Days.medium(model.day, language: words.language)).font(.system(size: 15)).foregroundColor(Theme.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.raised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(words("calendar.date_picker"))
        .accessibilityValue(Days.medium(model.day, language: words.language))
        .accessibilityHint(words("calendar.choose_date"))
        .popover(isPresented: $choosingDate, arrowEdge: .bottom) {
            DatePicker(words("calendar.date_picker"), selection: chosenDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: words.language))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
                .padding(12)
        }
    }

    private var step: String { model.mode.rawValue }

    /// Today, as the iPad's pill, sized to its word in every language: the padding and the
    /// stroke on the label, and both fixed, so no width cuts its round ends. Quiet while today
    /// is shown, inked when it would move.
    private var todayPill: some View {
        Button { Task { await model.goToToday() } } label: {
            Text(words("calendar.today")).font(.system(size: 15, weight: .medium)).lineLimit(1).fixedSize()
                .foregroundColor(model.showsToday ? Theme.soft : Theme.ink)
                .padding(.horizontal, 16).frame(minHeight: 40)
                // Inside the label's bounds: a stroke on the edge is half outside them, and clipped
                // there it leaves a flat sliver at each round end.
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(model.showsToday ? 0.2 : 0.4), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(model.showsToday ? .isSelected : [])
    }

    private var chosenDay: Binding<Date> {
        Binding(get: { Days.date(model.day) ?? Date() },
                set: { date in
                    choosingDate = false
                    Task { await model.go(to: Days.string(date)) }
                })
    }

    /// tafs cloud's line when it halted, or cut the read at its most: under the top line, as
    /// on the iPad; red for a halt.
    @ViewBuilder private var why: some View {
        if case .loaded(let page) = model.state, page.saysWhy {
            Text(verbatim: page.words).font(.system(size: 13, weight: .semibold)).foregroundColor(page.halted ? Theme.no : Theme.soft)
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

    /// "9 – 15 November 2026", across two months or years too; a day's own date in Day; the
    /// month in Month.
    private var title: String {
        guard let first = model.days.first.flatMap(Days.parts), let last = model.days.last.flatMap(Days.parts) else { return "" }
        func month(_ key: String) -> String { words("calendar.month_title.\(key)") }
        if model.mode == .month { return monthTitle(model.day) }
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

    /// Day / Week / Month, segmented and at most 320 wide, as on the iPad.
    private var modes: some View {
        Picker(words("calendar.view_picker"), selection: Binding(get: { model.mode }, set: { model.show($0) })) {
            ForEach(CalendarModel.Mode.allCases) { Text(words($0.titleKey)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
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
        case .loaded(let page) where model.mode == .month:
            monthCells(page, large: true)
        case .loaded(let page):
            let shown = model.days.flatMap { page.events(on: $0) }
            let hours = Days.hours(covering: shown.map(\.minute))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: Self.hoursWidth, height: 1)
                    ForEach(model.days, id: \.self) { day in dayHeading(day).frame(maxWidth: .infinity) }
                }
                .padding(.bottom, 8)
                // One row an hour: its label, then each day's events in that hour, stacked so
                // that two at the same time both stay readable. A busy hour grows its row.
                VStack(spacing: 0) {
                    ForEach(Array(hours), id: \.self) { hour in
                        HStack(alignment: .top, spacing: 0) {
                            Text(verbatim: String(format: "%02d:00", hour)).font(Theme.mono(11)).foregroundColor(Theme.soft)
                                .frame(width: Self.hoursWidth, alignment: .leading).padding(.top, 3)
                            ForEach(model.days, id: \.self) { day in
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(page.events(on: day, hour: hour)) { block($0) }
                                }
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .frame(minHeight: Self.hourHeight, alignment: .top)
                        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
                    }
                }
                .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
                // The app's line for an empty range, centred under the grid as on the iPad.
                if shown.isEmpty, !page.halted {
                    Text(words(model.mode == .week ? "calendar.nothing_this_week" : "calendar.nothing_on_day"))
                        .font(.system(size: 13)).foregroundColor(Theme.dim).padding(.top, 12)
                        .frame(maxWidth: .infinity)
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

    /// One event in its hour's cell, as the iPad's chip: its taf's dot and name on its colour,
    /// lightly; in Day, "09:00 · Name".
    private func block(_ event: Agenda.Event) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.tafColor(event.color)).frame(width: 7, height: 7)
            Text(verbatim: model.mode == .day ? "\(event.time) · \(event.name)" : event.name)
                .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
            // "×N" stays whole on the name's line; the name gives way to it.
            if event.count > 1 {
                Text(words.count("calendar.times", event.count)).font(.system(size: 11)).foregroundColor(Theme.soft)
                    .lineLimit(1).fixedSize().layoutPriority(1)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.tafColor(event.color).opacity(0.16)))
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.count > 1 ? words.count("calendar.slot_times", event.count, ["name": event.name, "first": event.time])
                                            : words("calendar.slot_at", ["name": event.name, "first": event.time]))
    }

    // MARK: The month: the card on the left, and the Month view

    /// The month card, as the iPad's navigator: the day's month, its arrows, and its six weeks.
    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthTitle(model.day)).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                Spacer()
                monthArrow("chevron.left", "calendar.previous_month", -1)
                monthArrow("chevron.right", "calendar.next_month", 1)
            }
            monthCells(page, large: false)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    private var page: Agenda.Page? {
        if case .loaded(let page) = model.state { return page }
        return nil
    }

    private func monthTitle(_ day: String) -> String {
        guard let p = Days.parts(day) else { return "" }
        return words("calendar.title.month", ["month": words("calendar.month_title.\(p.monthKey)"), "year": String(p.year)])
    }

    private func monthArrow(_ symbol: String, _ key: String, _ offset: Int) -> some View {
        Button { Task { await model.turnMonth(offset) } } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amberText).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words(key))
    }

    /// Six weeks under the weekday letters (11 bold, dim), as the iPad's `monthCells`: in the
    /// card, and larger in Month with each day's count.
    private func monthCells(_ page: Agenda.Page?, large: Bool) -> some View {
        let grid = Days.monthGrid(of: model.day)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(["mon", "tue", "wed", "thu", "fri", "sat", "sun"], id: \.self) { key in
                    Text(words("calendar.weekday.\(key)")).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        if grid.count == 42 { dayCell(grid[week * 7 + column], page, large: large) }
                    }
                }
            }
        }
    }

    /// A day: its number (13, 15 in Month), up to three 5-pt dots in its tafs' colours, and in
    /// Month how many firings it holds. The chosen day is filled amber, today ringed.
    private func dayCell(_ day: String, _ page: Agenda.Page?, large: Bool) -> some View {
        let p = Days.parts(day)
        let inMonth = p?.month == Days.parts(model.day)?.month
        let chosen = day == model.day
        let count = page?.count(on: day) ?? 0
        return Button { Task { await model.go(to: day) } } label: {
            VStack(spacing: 3) {
                Text(verbatim: p.map { String($0.day) } ?? "")
                    .font(.system(size: large ? 15 : 13, weight: chosen ? .bold : .regular))
                    .foregroundColor(inMonth ? Theme.ink : Theme.dim.opacity(0.6))
                HStack(spacing: 2) {
                    ForEach(Array((page?.marks(on: day) ?? []).enumerated()), id: \.offset) { mark in
                        Circle().fill(Theme.tafColor(mark.element)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                if large, count > 0 { Text(verbatim: words.number(count)).font(.system(size: 11)).foregroundColor(Theme.soft) }
            }
            .frame(maxWidth: .infinity, minHeight: large ? 64 : 38)
            .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Theme.amber.opacity(0.18) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(day == model.today ? Theme.amber : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? words.count("calendar.day_scheduled", count, ["day": heading(day)]) : heading(day))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: The agenda

    /// The days shown that hold work, each under its heading (14 semibold, amber for today),
    /// each event on a panel as the iPad's `eventRow`.
    @ViewBuilder private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: words("calendar.agenda"))
            if let page {
                if model.days.allSatisfy({ page.events(on: $0).isEmpty }) {
                    // tafs cloud's own line for the range; the app's when it sent none.
                    Text(verbatim: page.words.isEmpty ? words("calendar.nothing_these_days") : page.words)
                        .font(.system(size: 13)).foregroundColor(Theme.dim).padding(.vertical, 6)
                }
                ForEach(model.days.filter { !page.events(on: $0).isEmpty }, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(heading(day)).font(.system(size: 14, weight: .semibold))
                            .foregroundColor(day == model.today ? Theme.amberText : Theme.ink)
                        ForEach(page.events(on: day)) { eventRow($0) }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: Agenda.Event) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: event.time).font(Theme.mono(13)).foregroundColor(Theme.soft).frame(width: 46, alignment: .leading)
            Circle().fill(Theme.tafColor(event.color)).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                if !event.words.isEmpty { Text(verbatim: event.words).font(.system(size: 12)).foregroundColor(Theme.dim).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    private func heading(_ day: String) -> String {
        guard let p = Days.parts(day) else { return day }
        return words("calendar.day_heading", ["weekday": words("calendar.weekday.\(p.weekdayKey)"), "day": String(p.day),
                                              "month": words("calendar.month_name.\(p.monthKey)")])
    }
}
