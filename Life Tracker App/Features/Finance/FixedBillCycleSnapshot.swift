import Foundation

struct FixedBillCycleSnapshot {
    let occurrences: [FixedBillOccurrence]

    var paidCount: Int {
        occurrences.count { $0.status == .paid }
    }

    var pendingCount: Int {
        occurrences.count { $0.status == .pending }
    }

    var paidAmount: Decimal {
        occurrences
            .filter { $0.status == .paid }
            .compactMap(\.actualAmount)
            .reduce(Decimal.zero, +)
    }

    var estimatedRemaining: Decimal {
        occurrences
            .filter { $0.status == .pending }
            .compactMap { $0.fixedBill.estimatedAmount }
            .reduce(Decimal.zero, +)
    }

    var pendingWithoutEstimateCount: Int {
        occurrences.count {
            $0.status == .pending && $0.fixedBill.estimatedAmount == nil
        }
    }

    var pendingOccurrences: [FixedBillOccurrence] {
        occurrences.filter { $0.status == .pending }
    }

    init(
        occurrences: [FixedBillOccurrence],
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let cycle = FinancialCycle(containing: date, calendar: calendar) else {
            self.occurrences = []
            return
        }

        self.occurrences = occurrences
            .filter { Self.belongsToCurrentList($0, cycle: cycle) }
            .sorted { lhs, rhs in
                let lhsRank = Self.sortRank(lhs, date: date, calendar: calendar)
                let rhsRank = Self.sortRank(rhs, date: date, calendar: calendar)

                if lhsRank == rhsRank {
                    return lhs.dueDate < rhs.dueDate
                }
                return lhsRank < rhsRank
            }
    }

    /// Bills due in this cycle, plus unpaid bills from earlier cycles so
    /// overdue obligations stay visible until they are paid or skipped.
    static func belongsToCurrentList(
        _ occurrence: FixedBillOccurrence,
        cycle: FinancialCycle
    ) -> Bool {
        if cycle.contains(occurrence.dueDate) {
            return true
        }
        return occurrence.status == .pending && occurrence.dueDate < cycle.start
    }

    private static func sortRank(
        _ occurrence: FixedBillOccurrence,
        date: Date,
        calendar: Calendar
    ) -> Int {
        if occurrence.isOverdue(on: date, calendar: calendar) {
            return 0
        }
        if occurrence.status == .pending {
            return 1
        }
        if occurrence.status == .paid {
            return 2
        }
        return 3
    }
}
