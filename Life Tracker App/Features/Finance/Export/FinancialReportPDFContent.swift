import Foundation

/// Everything the PDF shows for one financial cycle, already localized and
/// formatted. Built from `FinancialCycleReport` and the existing finance
/// snapshots so the export never applies accounting rules of its own; the
/// layout layer only draws these values.
struct FinancialReportPDFContent {
    struct Row {
        let label: String
        let value: String
        var detail: String? = nil
        var emphasized = false
    }

    struct Table {
        let columns: [Column]
        let rows: [[String]]
        var footer: [String]? = nil
    }

    struct Column {
        enum Alignment {
            case leading
            case trailing
        }

        let title: String
        let width: Double
        var alignment: Alignment = .leading
    }

    struct ChartBar {
        let label: String
        let value: Double
        let valueText: String
        let colorName: String
    }

    struct CardSection {
        let title: String
        let rows: [Row]
        let invoices: Table
        let installments: Table?
    }

    struct Section {
        let title: String
        var rows: [Row] = []
        var notes: [String] = []
        var chart: [ChartBar] = []
        var tables: [(title: String?, table: Table)] = []
        var cards: [CardSection] = []
        var bullets: [String] = []
    }

    let documentTitle: String
    let periodText: String
    let generatedText: String
    let fileName: String
    let sections: [Section]
    let locale: Locale
    let calendar: Calendar

    /// Every transaction attributed to the cycle, in statement order.
    let statementTransactionIDs: [UUID]
}

extension FinancialReportPDFContent {
    // swiftlint:disable:next function_body_length
    static func make(
        cycle: FinancialCycle,
        transactions: [Transaction],
        categoryBudgets: [CategoryBudget],
        monthlyBudget: Decimal?,
        fixedBillOccurrences: [FixedBillOccurrence],
        creditCardInvoices: [CreditCardInvoice],
        recurringTransactions: [RecurringTransaction],
        generatedAt: Date = .now,
        locale: Locale = AppLocalization.selectedLocale,
        calendar: Calendar = .current
    ) -> FinancialReportPDFContent? {
        guard let report = FinancialCycleReport(
            cycle: cycle,
            transactions: transactions,
            categoryBudgets: categoryBudgets,
            monthlyBudget: monthlyBudget,
            fixedBillOccurrences: fixedBillOccurrences,
            calendar: calendar
        ) else {
            return nil
        }

        let f = Formatter(locale: locale, calendar: calendar)
        let isCurrentCycle = cycle.contains(generatedAt)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        let statement = report.snapshot.transactions.sorted { statementOrder($0, $1) }

        var sections: [Section] = []

        // MARK: Summary

        let snapshot = report.snapshot
        var summary = Section(title: f.text("Financial Cycle Summary"))
        summary.rows = [
            Row(label: f.text("Period"), value: "\(f.date(cycle.start)) – \(f.date(lastDay))"),
            Row(label: f.text("Income"), value: f.money(snapshot.income), detail: f.change(report.incomeChange)),
            Row(label: f.text("Expenses"), value: f.money(snapshot.expenses), detail: f.change(report.expenseChange), emphasized: true),
            Row(label: f.text("Investments"), value: f.money(snapshot.investments), detail: f.change(report.investmentChange)),
            Row(label: f.text("Balance (Income − Expenses)"), value: f.money(snapshot.balance), detail: f.change(report.balanceChange)),
            Row(label: f.text("Available After Investments"), value: f.money(snapshot.availableAfterInvestments))
        ]
        if isCurrentCycle {
            let projection = MonthlyFinanceProjection(
                transactions: transactions,
                recurringTransactions: recurringTransactions,
                fixedBillOccurrences: fixedBillOccurrences,
                date: generatedAt,
                calendar: calendar
            )
            summary.rows.append(Row(label: f.text("Actual spending"), value: f.money(projection.actualExpenses)))
            summary.rows.append(Row(label: f.text("Known projected spending"), value: f.money(projection.projectedExpenses)))
            summary.notes.append(f.text("Projected spending adds recurring expenses and fixed-bill estimates still due in this cycle. It is not recorded spending."))
        } else {
            summary.notes.append(f.text("This cycle has ended, so projected spending equals recorded spending."))
        }
        if let budget = report.monthlyBudget {
            let usage = NSDecimalNumber(decimal: snapshot.expenses / budget).doubleValue
            summary.rows.append(Row(label: f.text("Financial Cycle Budget"), value: f.money(budget)))
            summary.rows.append(Row(label: f.text("Budget used"), value: f.percent(usage), detail: f.money(budget - snapshot.expenses)))
        }
        if report.monthlyBudget != nil || !categoryBudgets.isEmpty {
            summary.notes.append(f.text("Budget history is not stored: budget figures use the budgets configured today."))
        }
        sections.append(summary)

        // MARK: Categories

        var categories = Section(title: f.text("Expenses by Category"))
        let categoryRows = report.categoryReports.sorted { $0.amount > $1.amount }
        if categoryRows.isEmpty {
            categories.notes.append(f.text("No expense spending in this cycle."))
        } else {
            categories.chart = categoryRows.prefix(8).map {
                ChartBar(
                    label: $0.name,
                    value: NSDecimalNumber(decimal: $0.amount).doubleValue,
                    valueText: f.money($0.amount),
                    colorName: $0.colorName
                )
            }
            categories.tables.append((nil, Table(
                columns: [
                    Column(title: f.text("Category"), width: 0.26),
                    Column(title: f.text("Spent"), width: 0.16, alignment: .trailing),
                    Column(title: f.text("% of expenses"), width: 0.12, alignment: .trailing),
                    Column(title: f.text("Budget"), width: 0.15, alignment: .trailing),
                    Column(title: f.text("Used"), width: 0.11, alignment: .trailing),
                    Column(title: f.text("vs previous"), width: 0.20, alignment: .trailing)
                ],
                rows: categoryRows.map { category in
                    [
                        category.name,
                        f.money(category.amount),
                        f.percent(category.totalPercentage),
                        category.budgetLimit.map(f.money) ?? "—",
                        category.budgetPercentage.map(f.percent) ?? "—",
                        f.signedMoney(category.change.difference)
                    ]
                },
                footer: [f.text("Total"), f.money(snapshot.expenses), f.percent(snapshot.expenses > 0 ? 1 : 0), "", "", ""]
            )))
        }
        sections.append(categories)

        // MARK: Fixed and recurring

        let expenses = statement.filter { $0.type == .expense }
        let fixedBillPayments = expenses.filter { $0.sourceFixedBillOccurrenceID != nil }
        let recurringCharges = expenses.filter { $0.sourceRecurringTransactionID != nil }
        let recurringDirect = recurringCharges.filter { $0.paymentMethod != .creditCard }
        let recurringCard = recurringCharges.filter { $0.paymentMethod == .creditCard }

        var fixed = Section(title: f.text("Fixed and Recurring Expenses"))
        fixed.rows = [
            Row(label: f.text("A. Recorded fixed / recurring spending"), value: f.money(report.spendingTypes.fixedOrRecurring), emphasized: true),
            Row(label: "    " + f.text("Fixed bill payments"), value: f.money(sum(fixedBillPayments)), detail: f.count(fixedBillPayments.count)),
            Row(label: "    " + f.text("Automatic recurring expenses"), value: f.money(sum(recurringDirect)), detail: f.count(recurringDirect.count)),
            Row(label: "    " + f.text("Recurring credit-card charges"), value: f.money(sum(recurringCard)), detail: f.count(recurringCard.count)),
            Row(label: f.text("Variable spending"), value: f.money(report.spendingTypes.variable)),
            Row(label: f.text("Fixed / Recurring vs Variable"), value: "\(f.percent(report.spendingTypes.fixedPercentage)) / \(f.percent(report.spendingTypes.variablePercentage))")
        ]
        let cycleOccurrences = fixedBillOccurrences
            .filter { cycle.contains($0.dueDate) }
            .sorted { $0.dueDate < $1.dueDate }
        if !cycleOccurrences.isEmpty {
            fixed.tables.append((f.text("Fixed bills due in this cycle"), Table(
                columns: [
                    Column(title: f.text("Bill"), width: 0.30),
                    Column(title: f.text("Due"), width: 0.14),
                    Column(title: f.text("Status"), width: 0.16),
                    Column(title: f.text("Configured"), width: 0.20, alignment: .trailing),
                    Column(title: f.text("Paid"), width: 0.20, alignment: .trailing)
                ],
                rows: cycleOccurrences.map { occurrence in
                    [
                        occurrence.fixedBill.name,
                        f.shortDate(occurrence.dueDate),
                        f.occurrenceStatus(occurrence, on: generatedAt),
                        f.configuredAmount(occurrence.fixedBill),
                        occurrence.actualAmount.map(f.money) ?? "—"
                    ]
                }
            )))
        }
        if isCurrentCycle {
            let projection = MonthlyFinanceProjection(
                transactions: transactions,
                recurringTransactions: recurringTransactions,
                fixedBillOccurrences: fixedBillOccurrences,
                date: generatedAt,
                calendar: calendar
            )
            fixed.rows.append(Row(
                label: f.text("C. Estimated amounts still due (not recorded)"),
                value: f.money(projection.pendingRecurringExpenses + projection.pendingFixedBillExpenses)
            ))
        }
        fixed.notes.append(f.text("Recorded spending, unpaid obligations and estimates are listed separately and are never added together. Unpaid obligations are in Bills to Pay."))
        sections.append(fixed)

        // MARK: Credit cards

        var cards = Section(title: f.text("Credit Cards and Installments"))
        let cardExpenses = expenses.filter { $0.paymentMethod == .creditCard }
        let cardsInCycle = Dictionary(grouping: cardExpenses.compactMap(\.creditCard), by: \.id)
            .compactMap(\.value.first)
        let cardIDsWithDueInvoice = Set(creditCardInvoices.filter { cycle.contains($0.dueDate) }.map(\.creditCard.id))
        let allCards = (cardsInCycle + creditCardInvoices.map(\.creditCard).filter { cardIDsWithDueInvoice.contains($0.id) })
            .reduce(into: [UUID: CreditCard]()) { $0[$1.id] = $1 }
            .values
            .sorted { $0.name < $1.name }

        for card in allCards {
            let spending = cardExpenses.filter { $0.creditCard?.id == card.id }
            let installments = spending.filter { ($0.totalInstallments ?? 1) > 1 }
            let invoiceIDs = Set(spending.compactMap(\.creditCardInvoice?.id))
            let invoices = creditCardInvoices
                .filter { $0.creditCard.id == card.id && (invoiceIDs.contains($0.id) || cycle.contains($0.dueDate)) }
                .sorted { $0.dueDate < $1.dueDate }
            let futureCommitment = transactions
                .filter {
                    $0.type == .expense
                        && $0.paymentMethod == .creditCard
                        && $0.creditCard?.id == card.id
                        && ($0.totalInstallments ?? 1) > 1
                        && $0.effectiveFinancialDate >= cycle.end
                }
                .reduce(Decimal.zero) { $0 + $1.amount }

            let installmentsTable: Table? = installments.isEmpty ? nil : Table(
                columns: [
                    Column(title: f.text("Purchase"), width: 0.34),
                    Column(title: f.text("Installment"), width: 0.14),
                    Column(title: f.text("Purchase Date"), width: 0.16),
                    Column(title: f.text("Final Installment"), width: 0.18),
                    Column(title: f.text("Amount"), width: 0.18, alignment: .trailing)
                ],
                rows: installments.map { transaction in
                    let summary = InstallmentPurchaseSummary(transaction: transaction, allTransactions: transactions)
                    return [
                        transaction.title,
                        "\(transaction.installmentNumber ?? 1)/\(transaction.totalInstallments ?? 1)",
                        f.shortDate(transaction.date),
                        summary?.finalInstallmentDate.map(f.shortDate) ?? "—",
                        f.money(transaction.amount)
                    ]
                }
            )

            cards.cards.append(CardSection(
                title: "\(card.name) •••• \(card.lastFourDigits)",
                rows: [
                    Row(label: f.text("Spending attributed to this cycle"), value: f.money(sum(spending)), emphasized: true),
                    Row(label: f.text("One-time purchases"), value: f.money(sum(spending.filter { ($0.totalInstallments ?? 1) <= 1 }))),
                    Row(label: f.text("Installments in this cycle"), value: f.money(sum(installments))),
                    Row(label: f.text("Installments committed to future cycles"), value: f.money(futureCommitment))
                ],
                invoices: Table(
                    columns: [
                        Column(title: f.text("Invoice"), width: 0.20),
                        Column(title: f.text("Closes"), width: 0.17),
                        Column(title: f.text("Due"), width: 0.17),
                        Column(title: f.text("Status"), width: 0.16),
                        Column(title: f.text("Invoice total"), width: 0.30, alignment: .trailing)
                    ],
                    rows: invoices.map { invoice in
                        [
                            f.monthYear(invoice.referenceMonth),
                            f.shortDate(invoice.closingDate),
                            f.shortDate(invoice.dueDate),
                            f.text(invoice.effectiveStatus(on: generatedAt, calendar: calendar).displayName),
                            f.money(invoice.total(in: transactions))
                        ]
                    }
                ),
                installments: installmentsTable
            ))
        }
        if allCards.isEmpty {
            cards.notes.append(f.text("No credit-card spending in this cycle."))
        } else {
            cards.rows = [Row(label: f.text("Credit-card spending in this cycle"), value: f.money(report.creditCards.total), detail: f.percent(report.creditCards.percentage), emphasized: true)]
            cards.notes.append(f.text("Card purchases count as spending in the cycle they are attributed to. Invoice totals settle those same purchases and may include other cycles, so they are never added to spending."))
        }
        sections.append(cards)

        // MARK: Bills to pay

        var bills = Section(title: f.text("Bills to Pay"))
        bills.notes.append(f.text("Payment obligations as of \(f.date(generatedAt)). They are not spending: paying a card invoice does not create another expense."))
        let obligations = Obligations(
            cycle: cycle,
            isCurrentCycle: isCurrentCycle,
            fixedBillOccurrences: fixedBillOccurrences,
            creditCardInvoices: creditCardInvoices,
            transactions: transactions,
            date: generatedAt,
            calendar: calendar
        )
        if obligations.rows.isEmpty {
            bills.notes.append(f.text("Nothing left to pay"))
        } else {
            bills.tables.append((nil, Table(
                columns: [
                    Column(title: f.text("Bill"), width: 0.38),
                    Column(title: f.text("Due"), width: 0.16),
                    Column(title: f.text("Status"), width: 0.20),
                    Column(title: f.text("Amount"), width: 0.26, alignment: .trailing)
                ],
                rows: obligations.rows.map { row in
                    [row.name(f), f.shortDate(row.dueDate), row.status(f, on: generatedAt), row.amountText(f)]
                },
                footer: [
                    f.text("Total known unpaid obligations"),
                    "",
                    "",
                    (obligations.includesEstimates ? "~ " : "") + f.money(obligations.knownTotal)
                ]
            )))
            if obligations.unknownCount > 0 {
                bills.notes.append(f.text("+ \(obligations.unknownCount) amounts still unknown"))
            }
        }
        if !obligations.previews.isEmpty {
            bills.tables.append((f.text("Invoice Preview (open, not payable yet)"), Table(
                columns: [
                    Column(title: f.text("Card"), width: 0.38),
                    Column(title: f.text("Closes"), width: 0.16),
                    Column(title: f.text("Due"), width: 0.20),
                    Column(title: f.text("Amount"), width: 0.26, alignment: .trailing)
                ],
                rows: obligations.previews.map {
                    [$0.invoice.creditCard.name, f.shortDate($0.invoice.closingDate), f.shortDate($0.invoice.dueDate), f.money($0.total)]
                }
            )))
        }
        sections.append(bills)

        // MARK: Investments

        var investments = Section(title: f.text("Investments"))
        let investmentRows = statement.filter { $0.type == .investment }
        investments.rows = [
            Row(label: f.text("Total invested"), value: f.money(snapshot.investments), detail: f.change(report.investmentChange), emphasized: true),
            Row(label: f.text("Investment Percentage of Income"), value: report.investmentPercentageOfIncome.map(f.percent) ?? "—")
        ]
        if !investmentRows.isEmpty {
            investments.tables.append((nil, Table(
                columns: [
                    Column(title: f.text("Date"), width: 0.16),
                    Column(title: f.text("Description"), width: 0.40),
                    Column(title: f.text("Category"), width: 0.24),
                    Column(title: f.text("Amount"), width: 0.20, alignment: .trailing)
                ],
                rows: investmentRows.map {
                    [f.shortDate($0.date), $0.title, $0.category?.displayName(locale: locale) ?? f.text("Uncategorized"), f.money($0.amount)]
                }
            )))
        }
        sections.append(investments)

        // MARK: Statement

        var statementSection = Section(title: f.text("Transaction Statement"))
        let income = statement.filter { $0.type == .income }
        statementSection.rows = [
            Row(label: f.text("Transactions"), value: "\(statement.count)"),
            Row(label: f.text("Income"), value: f.money(sum(income)), detail: f.count(income.count)),
            Row(label: f.text("Expenses"), value: f.money(sum(expenses)), detail: f.count(expenses.count)),
            Row(label: f.text("Investments"), value: f.money(sum(investmentRows)), detail: f.count(investmentRows.count))
        ]
        let reconciles = sum(income) == snapshot.income
            && sum(expenses) == snapshot.expenses
            && sum(investmentRows) == snapshot.investments
            && categoryRows.reduce(Decimal.zero, { $0 + $1.amount }) == snapshot.expenses
        statementSection.notes.append(reconciles
            ? f.text("Reconciled: statement and category totals match the cycle summary.")
            : f.text("Warning: statement totals do not match the cycle summary."))
        statementSection.notes.append(f.text("Dates are the financial date that places each entry in this cycle. Card entries also show the purchase date and invoice due date; each installment is listed with its own amount."))
        if statement.isEmpty {
            statementSection.notes.append(f.text("No transactions in this cycle."))
        } else {
            statementSection.tables.append((nil, Table(
                columns: [
                    Column(title: f.text("Date"), width: 0.10),
                    Column(title: f.text("Description"), width: 0.25),
                    Column(title: f.text("Type"), width: 0.13),
                    Column(title: f.text("Category"), width: 0.14),
                    Column(title: f.text("Payment Method"), width: 0.12),
                    Column(title: f.text("Card"), width: 0.11),
                    Column(title: f.text("Amount"), width: 0.15, alignment: .trailing)
                ],
                rows: statement.map { transaction in
                    [
                        f.shortDate(transaction.effectiveFinancialDate),
                        f.statementDescription(transaction),
                        f.text(transaction.type.displayName),
                        transaction.category?.displayName(locale: locale) ?? f.text("Uncategorized"),
                        transaction.type == .income ? "—" : f.text(transaction.paymentMethod.displayName),
                        transaction.creditCard?.name ?? "—",
                        f.signedAmount(transaction)
                    ]
                }
            )))
        }
        sections.append(statementSection)

        // MARK: Comparison

        var comparison = Section(title: f.text("Compared with Previous Cycle"))
        comparison.tables.append((nil, Table(
            columns: [
                Column(title: "", width: 0.34),
                Column(title: f.text("Previous Cycle"), width: 0.22, alignment: .trailing),
                Column(title: f.text("This cycle"), width: 0.22, alignment: .trailing),
                Column(title: f.text("Difference"), width: 0.22, alignment: .trailing)
            ],
            rows: report.comparisons.map {
                [$0.title, f.money($0.change.previous), f.money($0.change.current), f.signedMoney($0.change.difference)]
            }
        )))
        let top = categoryRows.prefix(3).map { "\($0.name): \(f.money($0.amount))" }
        if !top.isEmpty {
            comparison.bullets.append(f.text("Largest spending categories: \(top.joined(separator: ", "))"))
        }
        let changed = report.categoryReports.filter { $0.change.difference != 0 }
        if let increase = changed.max(by: { $0.change.difference < $1.change.difference }), increase.change.difference > 0 {
            comparison.bullets.append(f.text("Biggest increase: \(increase.name) (\(f.signedMoney(increase.change.difference)))"))
        }
        if let decrease = changed.min(by: { $0.change.difference < $1.change.difference }), decrease.change.difference < 0 {
            comparison.bullets.append(f.text("Biggest decrease: \(decrease.name) (\(f.signedMoney(decrease.change.difference)))"))
        }
        comparison.bullets += report.insights.map(\.message)
        sections.append(comparison)

        let startStamp = Self.fileStamp(cycle.start, calendar: calendar)
        let endStamp = Self.fileStamp(lastDay, calendar: calendar)
        return FinancialReportPDFContent(
            documentTitle: f.text("LifeTracker Financial Report"),
            periodText: "\(f.date(cycle.start)) – \(f.date(lastDay))",
            generatedText: f.text("Generated on \(f.dateTime(generatedAt))"),
            fileName: "\(f.text("LifeTracker_Report"))_\(startStamp)_\(endStamp).pdf",
            sections: sections,
            locale: locale,
            calendar: calendar,
            statementTransactionIDs: statement.map(\.id)
        )
    }

    private static func statementOrder(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.effectiveFinancialDate != rhs.effectiveFinancialDate {
            return lhs.effectiveFinancialDate < rhs.effectiveFinancialDate
        }
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func sum(_ transactions: [Transaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private static func fileStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Obligations

/// Unpaid obligations for the report. The current cycle uses the same
/// `BillsToPaySummary` as the app (including overdue bills carried over and
/// open-invoice previews); a past cycle lists what is still unpaid from it.
private struct Obligations {
    enum Item {
        case bill(FixedBillOccurrence)
        case invoice(CreditCardInvoice, Decimal)

        var dueDate: Date {
            switch self {
            case .bill(let occurrence): occurrence.dueDate
            case .invoice(let invoice, _): invoice.dueDate
            }
        }

        func name(_ f: FinancialReportPDFContent.Formatter) -> String {
            switch self {
            case .bill(let occurrence): occurrence.fixedBill.name
            case .invoice(let invoice, _): f.text("\(invoice.creditCard.name) Invoice")
            }
        }

        func status(_ f: FinancialReportPDFContent.Formatter, on date: Date) -> String {
            switch self {
            case .bill(let occurrence):
                f.occurrenceStatus(occurrence, on: date)
            case .invoice(let invoice, _):
                invoice.isOverdue(on: date, calendar: f.calendar) ? f.text("Overdue") : f.text("Closed")
            }
        }

        func amountText(_ f: FinancialReportPDFContent.Formatter) -> String {
            switch self {
            case .bill(let occurrence): f.configuredAmount(occurrence.fixedBill)
            case .invoice(_, let total): f.money(total)
            }
        }
    }

    let rows: [Item]
    let previews: [BillsToPaySummary.InvoiceItem]
    let knownTotal: Decimal
    let includesEstimates: Bool
    let unknownCount: Int

    init(
        cycle: FinancialCycle,
        isCurrentCycle: Bool,
        fixedBillOccurrences: [FixedBillOccurrence],
        creditCardInvoices: [CreditCardInvoice],
        transactions: [Transaction],
        date: Date,
        calendar: Calendar
    ) {
        let bills: [FixedBillOccurrence]
        let invoices: [BillsToPaySummary.InvoiceItem]
        if isCurrentCycle {
            let summary = BillsToPaySummary(
                fixedBillOccurrences: fixedBillOccurrences,
                creditCardInvoices: creditCardInvoices,
                transactions: transactions,
                date: date,
                calendar: calendar
            )
            bills = summary.pendingFixedBills
            invoices = summary.payableInvoices
            previews = summary.upcomingInvoices
        } else {
            bills = fixedBillOccurrences.filter { $0.status == .pending && cycle.contains($0.dueDate) }
            invoices = CreditCardInvoicePaymentService.payableInvoices(
                creditCardInvoices,
                transactions: transactions,
                on: date,
                calendar: calendar
            )
            .filter { cycle.contains($0.dueDate) }
            .map { BillsToPaySummary.InvoiceItem(invoice: $0, total: $0.total(in: transactions)) }
            previews = []
        }

        rows = (invoices.map { Item.invoice($0.invoice, $0.total) } + bills.map(Item.bill))
            .sorted { $0.dueDate < $1.dueDate }
        knownTotal = invoices.reduce(Decimal.zero) { $0 + $1.total }
            + bills.compactMap(\.fixedBill.estimatedAmount).reduce(Decimal.zero, +)
        includesEstimates = bills.contains { $0.fixedBill.amountMode == .variable && $0.fixedBill.estimatedAmount != nil }
        unknownCount = bills.count { $0.fixedBill.estimatedAmount == nil }
    }
}

// MARK: - Formatting

extension FinancialReportPDFContent {
    /// Locale-bound formatting so the PDF matches the app language.
    struct Formatter {
        let locale: Locale
        let calendar: Calendar

        func text(_ resource: LocalizedStringResource) -> String {
            var localized = resource
            localized.locale = locale
            return String(localized: localized)
        }

        func money(_ value: Decimal) -> String {
            value.formatted(.currency(code: "BRL").locale(locale))
        }

        func signedMoney(_ value: Decimal) -> String {
            let prefix = value > 0 ? "+" : value < 0 ? "−" : ""
            return prefix + money(abs(value))
        }

        func signedAmount(_ transaction: Transaction) -> String {
            switch transaction.type {
            case .income: "+" + money(transaction.amount)
            case .expense: "−" + money(transaction.amount)
            case .investment: money(transaction.amount)
            }
        }

        func percent(_ value: Double) -> String {
            value.formatted(.percent.precision(.fractionLength(1)).locale(locale))
        }

        func count(_ value: Int) -> String {
            text("\(value) transactions")
        }

        func change(_ change: ReportChange) -> String {
            text("\(signedMoney(change.difference)) vs previous cycle")
        }

        private var dateStyle: Date.FormatStyle {
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).locale(locale)
        }

        func date(_ value: Date) -> String {
            value.formatted(dateStyle.day().month(.abbreviated).year())
        }

        func shortDate(_ value: Date) -> String {
            value.formatted(dateStyle.day(.twoDigits).month(.twoDigits).year(.twoDigits))
        }

        func monthYear(_ value: Date) -> String {
            value.formatted(dateStyle.month(.abbreviated).year())
        }

        func dateTime(_ value: Date) -> String {
            value.formatted(dateStyle.day().month(.abbreviated).year().hour().minute())
        }

        func configuredAmount(_ bill: FixedBill) -> String {
            guard let amount = bill.estimatedAmount else {
                return text("Unknown amount")
            }
            return bill.amountMode == .variable ? "~ " + money(amount) : money(amount)
        }

        func occurrenceStatus(_ occurrence: FixedBillOccurrence, on date: Date) -> String {
            occurrence.isOverdue(on: date, calendar: calendar)
                ? text("Overdue")
                : text(occurrence.status.displayName)
        }

        func statementDescription(_ transaction: Transaction) -> String {
            var details: [String] = []
            if transaction.paymentMethod == .creditCard {
                details.append(text("Purchased \(shortDate(transaction.date))"))
                if let number = transaction.installmentNumber,
                   let total = transaction.totalInstallments,
                   total > 1 {
                    details.append(text("Installment \(number) of \(total)"))
                }
                if let due = transaction.invoiceDueDate {
                    details.append(text("Invoice due \(shortDate(due))"))
                }
            }
            if transaction.hasManualFinancialCycle {
                if transaction.paymentMethod != .creditCard {
                    details.append(text("Date \(shortDate(transaction.date))"))
                }
                details.append(text("Cycle set manually"))
            }
            switch transaction.sourceKind {
            case .recurring: details.append(text("Recurring"))
            case .fixedBill: details.append(text("Fixed bill"))
            case .installment, .manual: break
            }
            guard !details.isEmpty else {
                return transaction.title
            }
            return transaction.title + "\n" + details.joined(separator: " • ")
        }
    }
}
