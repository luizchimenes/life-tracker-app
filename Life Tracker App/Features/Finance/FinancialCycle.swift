import Foundation

struct FinancialCycle {
    static let startDay = 9

    let start: Date
    let end: Date

    var interval: DateInterval {
        DateInterval(start: start, end: end)
    }

    init?(
        containing date: Date,
        calendar: Calendar = .current
    ) {
        let day = calendar.component(.day, from: date)
        let monthOffset = day >= Self.startDay ? 0 : -1

        guard let month = calendar.date(
            byAdding: .month,
            value: monthOffset,
            to: date
        ) else {
            return nil
        }

        var startComponents = calendar.dateComponents(
            [.year, .month],
            from: month
        )
        startComponents.day = Self.startDay

        guard let start = calendar.date(from: startComponents),
              let nextMonth = calendar.date(
                byAdding: .month,
                value: 1,
                to: start
              ) else {
            return nil
        }

        self.start = calendar.startOfDay(for: start)
        end = calendar.startOfDay(for: nextMonth)
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    func identifier(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: start)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(Self.startDay)"
    }

    func shifted(
        byMonths offset: Int,
        calendar: Calendar = .current
    ) -> FinancialCycle? {
        guard let shiftedStart = calendar.date(
            byAdding: .month,
            value: offset,
            to: start
        ) else {
            return nil
        }
        return FinancialCycle(containing: shiftedStart, calendar: calendar)
    }
}
