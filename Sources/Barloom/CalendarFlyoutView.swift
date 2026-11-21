import SwiftUI

struct CalendarFlyoutView: View {
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 14, weight: .semibold))
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            HStack {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                stepButton("chevron.up", by: -1)
                stepButton("chevron.down", by: 1)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Always six weeks so the flyout never changes height.
    private var days: [Date] {
        let weekday = calendar.component(.weekday, from: month)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: month)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 12, weight: isToday ? .semibold : .regular))
            .foregroundStyle(isToday ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.6))
            .frame(width: 34, height: 34)
            .background(Circle().fill(isToday ? Color.accentColor : Color.clear))
    }

    private func stepButton(_ symbol: String, by offset: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                month = calendar.date(byAdding: .month, value: offset, to: month)!
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle())
    }
}
