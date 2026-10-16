import Foundation

/// Single source for the cycle figures shown on Finance and Home, so both
/// screens always present the same numbers.
struct FinanceOverview {
    let projection: MonthlyFinanceProjection
    let safeToSpend: SafeToSpend
    let bills: BillsToPaySummary

    var actual: MonthlyFinanceSnapshot {
        projection.actual
    }

    init(
        transactions: [Transaction],
        recurringTransactions: [RecurringTransaction],
        fixedBillOccurrences: [FixedBillOccurrence],
        creditCardInvoices: [CreditCardInvoice],
        monthlyBudget: Decimal?,
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        projection = MonthlyFinanceProjection(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences,
            date: date,
            calendar: calendar
        )
        safeToSpend = SafeToSpend(
            projection: projection,
            monthlyBudget: monthlyBudget,
            date: date,
            calendar: calendar
        )
        bills = BillsToPaySummary(
            fixedBillOccurrences: fixedBillOccurrences,
            creditCardInvoices: creditCardInvoices,
            transactions: transactions,
            date: date,
            calendar: calendar
        )
    }
}

/// How much can still be spent in the current financial cycle.
///
/// A planning figure, not a bank balance or card limit: projected income minus
/// actual and scheduled expenses minus investments, capped by the remaining
/// cycle budget when one is set. It can be negative; screens show the
/// shortfall instead of a negative allowance.
struct SafeToSpend {
    nonisolated enum Constraint {
        case cash
        case budget
    }

    /// Projected income − projected expenses − projected investments.
    let cashAvailable: Decimal
    /// Cycle budget − projected expenses, when a budget exists.
    let budgetRemaining: Decimal?
    let amount: Decimal
    let constraint: Constraint
    /// Calendar days from today through the cycle's last day, inclusive.
    let daysRemaining: Int

    var isShortfall: Bool {
        amount < 0
    }

    var displayAmount: Decimal {
        max(amount, 0)
    }

    var shortfall: Decimal {
        max(-amount, 0)
    }

    var perDay: Decimal {
        guard amount > 0, daysRemaining > 0 else {
            return 0
        }
        return amount / Decimal(daysRemaining)
    }

    init(
        projection: MonthlyFinanceProjection,
        monthlyBudget: Decimal?,
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        cashAvailable = projection.projectedAvailableAfterInvestments
        budgetRemaining = monthlyBudget.map {
            projection.projectedBudgetRemaining(monthlyBudget: $0)
        }

        if let budgetRemaining, budgetRemaining < cashAvailable {
            amount = budgetRemaining
            constraint = .budget
        } else {
            amount = cashAvailable
            constraint = .cash
        }

        daysRemaining = projection.actual.cycle.map {
            Self.daysRemaining(in: $0, from: date, calendar: calendar)
        } ?? 0
    }

    static func daysRemaining(
        in cycle: FinancialCycle,
        from date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: cycle.end).day ?? 0
        return max(days, 0)
    }
}

/// Payment obligations: money that still has to leave the account.
///
/// Deliberately separate from spending. A card invoice here settles purchases
/// that were already counted as expenses when made, so these totals never feed
/// expenses, projections or Safe to Spend.
struct BillsToPaySummary {
    struct InvoiceItem: Identifiable {
        let invoice: CreditCardInvoice
        let total: Decimal

        var id: UUID {
            invoice.id
        }
    }

    /// Pending fixed bills of this cycle plus overdue ones from earlier cycles.
    let pendingFixedBills: [FixedBillOccurrence]
    /// Closed, unpaid invoices: payable now.
    let payableInvoices: [InvoiceItem]
    /// Next open invoice per card: informational only, not payable yet.
    let upcomingInvoices: [InvoiceItem]
    let overdueCount: Int

    var pendingCount: Int {
        pendingFixedBills.count + payableInvoices.count
    }

    /// Invoices plus every pending bill with a known or estimated amount.
    var knownTotal: Decimal {
        payableInvoices.reduce(Decimal.zero) { $0 + $1.total }
            + pendingFixedBills
                .compactMap { $0.fixedBill.estimatedAmount }
                .reduce(Decimal.zero, +)
    }

    /// True when the total relies on an estimate of a variable bill.
    var includesEstimates: Bool {
        pendingFixedBills.contains {
            $0.fixedBill.amountMode == .variable && $0.fixedBill.estimatedAmount != nil
        }
    }

    /// Pending bills with no amount at all; they are not guessed into the total.
    var unknownAmountCount: Int {
        pendingFixedBills.count { $0.fixedBill.estimatedAmount == nil }
    }

    init(
        fixedBillOccurrences: [FixedBillOccurrence],
        creditCardInvoices: [CreditCardInvoice],
        transactions: [Transaction],
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        pendingFixedBills = FixedBillCycleSnapshot(
            occurrences: fixedBillOccurrences,
            date: date,
            calendar: calendar
        ).pendingOccurrences

        payableInvoices = CreditCardInvoicePaymentService.payableInvoices(
            creditCardInvoices,
            transactions: transactions,
            on: date,
            calendar: calendar
        )
        .map { InvoiceItem(invoice: $0, total: $0.total(in: transactions)) }

        let openInvoicesByCard = Dictionary(
            grouping: creditCardInvoices.filter {
                $0.effectiveStatus(on: date, calendar: calendar) == .open
            },
            by: { $0.creditCard.id }
        )
        upcomingInvoices = openInvoicesByCard.values
            .compactMap { invoices in
                invoices.min { $0.closingDate < $1.closingDate }
            }
            .map { InvoiceItem(invoice: $0, total: $0.total(in: transactions)) }
            .filter { $0.total > 0 }
            .sorted { $0.invoice.closingDate < $1.invoice.closingDate }

        overdueCount = pendingFixedBills.count {
            $0.isOverdue(on: date, calendar: calendar)
        } + payableInvoices.count {
            $0.invoice.isOverdue(on: date, calendar: calendar)
        }
    }
}
