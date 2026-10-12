import SwiftUI

struct CalendarView: View {
    @Environment(DataStore.self) private var store
    @State private var month = Date()
    @State private var selected = Date()
    @State private var mode: Mode = .month

    enum Mode: String, CaseIterable, Identifiable {
        case month, agenda
        var id: String { rawValue }
        var title: String { self == .month ? "Mese" : "Giorni" }
    }

    private var cal: Calendar { store.calendar }

    private var withDeadline: [Purchase] {
        store.purchases.filter { !$0.isArchived && $0.deadline != nil && $0.status.deadlineMatters }
    }

    private func items(on day: Date) -> [Purchase] {
        withDeadline.filter { cal.isDate($0.deadline!.date, inSameDayAs: day) }
    }

    var body: some View {
        List {
            Section {
                Picker("Vista", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if mode == .month {
                Section {
                    monthHeader
                    MonthGrid(month: month, selected: $selected, calendar: cal) { day in
                        let list = items(on: day)
                        guard !list.isEmpty else { return nil }
                        let now = Date()
                        if list.contains(where: { DeadlineEngine.daysRemaining(until: $0.deadline!.date, now: now, calendar: cal) < 0 }) { return .red }
                        if list.contains(where: { DeadlineEngine.daysRemaining(until: $0.deadline!.date, now: now, calendar: cal) <= 3 }) { return .orange }
                        if list.contains(where: { $0.deadline?.verification == .proposed }) { return .yellow }
                        return .green
                    }
                }
                Section(Formatters.date(selected, timeZone: store.settings.timeZone)) {
                    let list = items(on: selected)
                    if list.isEmpty {
                        Text("Nessuna scadenza").foregroundStyle(.secondary)
                    }
                    ForEach(list) { p in
                        NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                    }
                }
                legend
            } else {
                let groups = Dictionary(grouping: withDeadline) { cal.startOfDay(for: $0.deadline!.date) }
                let today = cal.startOfDay(for: Date())
                let days = groups.keys.sorted().filter { $0 >= cal.date(byAdding: .day, value: -30, to: today)! }
                if days.isEmpty {
                    EmptyStateView(title: "Nessuna scadenza", message: "Le scadenze dei resi compariranno qui.", symbol: "calendar")
                }
                ForEach(days, id: \.self) { day in
                    Section {
                        ForEach(groups[day] ?? []) { p in
                            NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                        }
                    } header: {
                        Text(Formatters.date(day, timeZone: store.settings.timeZone) + (cal.isDateInToday(day) ? " · oggi" : ""))
                            .foregroundStyle(day < today ? Color.red : Color.secondary)
                    }
                }
            }
        }
        .navigationTitle("Calendario")
    }

    private var monthHeader: some View {
        HStack {
            Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = store.settings.timeZone
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    private var legend: some View {
        Section {
            HStack(spacing: 14) {
                LegendDot(color: .red, text: "Scaduta")
                LegendDot(color: .orange, text: "≤ 3 giorni")
                LegendDot(color: .yellow, text: "Da verificare")
                LegendDot(color: .green, text: "Ok")
            }
            .font(.caption)
        }
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

struct MonthGrid: View {
    let month: Date
    @Binding var selected: Date
    let calendar: Calendar
    let marker: (Date) -> Color?

    private var days: [Date?] {
        var cal = calendar
        cal.firstWeekday = 2 // lunedì
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var result: [Date?] = Array(repeating: nil, count: leading)
        for i in 0..<count { result.append(cal.date(byAdding: .day, value: i, to: first)) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        let symbols = ["L", "M", "M", "G", "V", "S", "D"]
        VStack(spacing: 6) {
            HStack {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isSelected = calendar.isDate(day, inSameDayAs: selected)
                        let isToday = calendar.isDateInToday(day)
                        Button { selected = day } label: {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.callout.weight(isToday ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                                Circle().fill(marker(day) ?? .clear).frame(width: 6, height: 6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }
}
