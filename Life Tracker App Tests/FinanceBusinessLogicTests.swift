import Foundation
import SwiftData
import Testing
@testable import Life_Tracker_App

private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func category(_ name: String = "Food") -> TransactionCategory {
    TransactionCategory(name: name, iconName: "fork.knife", colorName: "orange", type: .expense)
}

@Suite("Financial cycle")
struct FinancialCycleTests {
    @Test func dayNineStartsAndDayEightEndsCycle() throws {
        let cycle = try #require(FinancialCycle(containing: date(2026, 10, 9), calendar: testCalendar))
        #expect(cycle.start == date(2026, 10, 9))
        #expect(cycle.contains(date(2026, 11, 8)))
        #expect(!cycle.contains(date(2026, 11, 9)))
        let prior = try #require(FinancialCycle(containing: date(2026, 10, 8), calendar: testCalendar))
        #expect(prior.start == date(2026, 9, 9))
    }

    @Test func decemberRollsIntoJanuary() throws {
        let cycle = try #require(FinancialCycle(containing: date(2026, 12, 20), calendar: testCalendar))
        #expect(cycle.start == date(2026, 12, 9))
        #expect(cycle.end == date(2027, 1, 9))
    }
}

@Suite("Credit cards and installments")
struct CreditCardTests {
    @Test @MainActor func invoicePaymentRequiresClosureAndReleasesLimitWhenPaid() throws {
        let context = try TestStore.context()
        let food = category()
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 1_000)
        let invoice = CreditCardInvoice(invoiceIdentifier: "card-2026-11", creditCard: card, referenceMonth: date(2026, 11, 1), closingDate: date(2026, 11, 2), dueDate: date(2026, 11, 9))
        let transaction = Transaction(title: "Purchase", amount: 200, date: date(2026, 10, 14), type: .expense, category: food, paymentMethod: .creditCard, creditCard: card, creditCardInvoice: invoice)
        context.insert(food)
        context.insert(card)
        context.insert(invoice)
        context.insert(transaction)
        try context.save()

        #expect(throws: CreditCardInvoicePaymentError.self) {
            try CreditCardInvoicePaymentService.markPaid(invoice, paidDate: date(2026, 11, 1), in: context, calendar: testCalendar)
        }
        #expect(invoice.effectiveStatus(on: date(2026, 11, 1), calendar: testCalendar) == .open)
        #expect(CreditCardBalanceCalculator.availableLimit(for: card, invoices: [invoice], transactions: [transaction], on: date(2026, 11, 1), calendar: testCalendar) == 800)

        // Payable on the closing day itself.
        #expect(invoice.effectiveStatus(on: date(2026, 11, 2), calendar: testCalendar) == .closed)
        try CreditCardInvoicePaymentService.markPaid(invoice, paidDate: date(2026, 11, 2), in: context, calendar: testCalendar)
        #expect(invoice.effectiveStatus(on: date(2027, 1, 1), calendar: testCalendar) == .paid)
        #expect(invoice.paidDate == date(2026, 11, 2))
        #expect(CreditCardBalanceCalculator.availableLimit(for: card, invoices: [invoice], transactions: [transaction], on: date(2026, 11, 2), calendar: testCalendar) == 1_000)
    }

    @Test @MainActor func purchaseCountsAsActualSpendingInPurchaseCycle() throws {
        let context = try TestStore.context()
        let shopping = category("Shopping")
        let card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 1_000)
        context.insert(shopping)
        context.insert(card)

        try CreditCardPurchaseService.createPurchase(
            title: "Apple Store",
            totalAmount: 200,
            purchaseDate: date(2026, 10, 14),
            category: shopping,
            notes: "Phone accessory",
            creditCard: card,
            installmentCount: 1,
            in: context,
            calendar: testCalendar
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let transaction = try #require(transactions.first)
        #expect(transactions.count == 1)
        #expect(transaction.date == date(2026, 10, 14))
        #expect(transaction.effectiveFinancialDate == date(2026, 10, 14))
        #expect(transaction.invoiceDueDate == date(2026, 11, 9))
        #expect(TransactionActivity.recent(from: transactions, limit: 5).map(\.id) == [transaction.id])
        #expect(TransactionAmountPresentation.sign(for: transaction.type) == "−")

        let currentCycle = try #require(FinancialCycle(containing: date(2026, 10, 14), calendar: testCalendar))
        #expect(TransactionActivity.belongs(transaction, to: currentCycle))
        let snapshot = MonthlyFinanceSnapshot(transactions: transactions, date: date(2026, 10, 14), calendar: testCalendar)
        #expect(snapshot.expenses == 200)

        let invoices = try context.fetch(FetchDescriptor<CreditCardInvoice>())
        #expect(invoices.count == 1)
        #expect(transactions.reduce(Decimal.zero) { $0 + $1.amount } == 200)
        #expect(CreditCardBalanceCalculator.availableLimit(for: card, invoices: invoices, transactions: transactions, on: date(2026, 10, 14), calendar: testCalendar) == 800)
    }

    @Test @MainActor func recentActivityUsesPurchaseDateAndCollapsesFutureInstallments() {
        let shopping = category("Shopping")
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 10_000)
        let purchaseID = UUID()
        let olderDirect = Transaction(title: "Pix", amount: 20, date: date(2026, 10, 13), type: .expense, category: shopping, paymentMethod: .pix)
        let first = Transaction(title: "Phone", amount: 200, date: date(2026, 10, 14), type: .expense, category: shopping, paymentMethod: .creditCard, creditCard: card, installmentNumber: 1, totalInstallments: 2, sourcePurchaseID: purchaseID)
        let future = Transaction(title: "Phone", amount: 200, date: date(2026, 10, 14), type: .expense, category: shopping, paymentMethod: .creditCard, creditCard: card, installmentNumber: 2, totalInstallments: 2, sourcePurchaseID: purchaseID)

        let recent = TransactionActivity.recent(from: [olderDirect, future, first], limit: 5)
        #expect(recent.count == 2)
        #expect(recent.first?.id == first.id)
        #expect(!recent.contains { $0.id == future.id })
    }

    @Test func closingBoundaryAndRollover() throws {
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 10_000)
        let beforeClosing = try #require(CreditCardInvoiceResolver.invoiceDates(for: date(2026, 10, 1), creditCard: card, calendar: testCalendar))
        let onClosing = try #require(CreditCardInvoiceResolver.invoiceDates(for: date(2026, 10, 2), creditCard: card, calendar: testCalendar))
        #expect(beforeClosing.closingDate == date(2026, 10, 2))
        #expect(beforeClosing.dueDate == date(2026, 10, 9))
        // Purchases on the closing day go to the next invoice.
        #expect(onClosing.closingDate == date(2026, 11, 2))
        #expect(onClosing.dueDate == date(2026, 11, 9))
    }

    @Test @MainActor func payableInvoicesListOnlyClosedUnpaidInvoicesWithCharges() {
        let food = category()
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 10_000)
        let closed = CreditCardInvoice(invoiceIdentifier: "nov", creditCard: card, referenceMonth: date(2026, 11, 1), closingDate: date(2026, 11, 9), dueDate: date(2026, 11, 15))
        let open = CreditCardInvoice(invoiceIdentifier: "dec", creditCard: card, referenceMonth: date(2026, 12, 1), closingDate: date(2026, 12, 9), dueDate: date(2026, 12, 15))
        let paid = CreditCardInvoice(invoiceIdentifier: "oct", creditCard: card, referenceMonth: date(2026, 10, 1), closingDate: date(2026, 10, 9), dueDate: date(2026, 10, 15))
        paid.status = .paid
        let empty = CreditCardInvoice(invoiceIdentifier: "sep", creditCard: card, referenceMonth: date(2026, 9, 1), closingDate: date(2026, 9, 9), dueDate: date(2026, 9, 15))
        let transactions = [closed, open, paid].map {
            Transaction(title: "Purchase", amount: 50, date: date(2026, 10, 20), type: .expense, category: food, paymentMethod: .creditCard, creditCard: card, creditCardInvoice: $0)
        }

        let payable = CreditCardInvoicePaymentService.payableInvoices([open, empty, paid, closed], transactions: transactions, on: date(2026, 11, 9), calendar: testCalendar)
        #expect(payable.map(\.invoiceIdentifier) == ["nov"])
        #expect(closed.total(in: transactions) == 50)
        #expect(!closed.isOverdue(on: date(2026, 11, 15), calendar: testCalendar))
        #expect(closed.isOverdue(on: date(2026, 11, 16), calendar: testCalendar))
    }

    @Test func lowerDueDayAndShortMonthAreSafe() throws {
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 31, dueDay: 5, creditLimit: 10_000)
        let dates = try #require(CreditCardInvoiceResolver.invoiceDates(for: date(2027, 2, 10), creditCard: card, calendar: testCalendar))
        #expect(dates.closingDate == date(2027, 2, 28))
        #expect(dates.dueDate == date(2027, 3, 5))
    }

    @Test @MainActor func installmentAllocationRoundingAndSummary() throws {
        let context = try TestStore.context()
        let food = category()
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 10_000)
        context.insert(food)
        context.insert(card)
        try CreditCardPurchaseService.createPurchase(title: "Phone", totalAmount: Decimal(string: "100.00")!, purchaseDate: date(2026, 10, 3), category: food, notes: "", creditCard: card, installmentCount: 3, in: context, calendar: testCalendar)
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        #expect(transactions.count == 3)
        #expect(transactions.reduce(0) { $0 + $1.amount } == Decimal(string: "100.00")!)
        #expect(transactions.map(\.amount) == [Decimal(string: "33.33")!, Decimal(string: "33.33")!, Decimal(string: "33.34")!])
        #expect(Set(transactions.compactMap(\.sourcePurchaseID)).count == 1)
        let summary = try #require(InstallmentPurchaseSummary(transaction: transactions[0], allTransactions: transactions))
        #expect(summary.originalTotal == 100)
        #expect(summary.remainingAmount == 100)
        #expect(summary.finalInstallmentDate == date(2027, 1, 9))
        #expect(throws: TransactionDeletionError.self) {
            _ = try TransactionDeletionService.transactionsForSafeDeletion(of: transactions[0], from: Array(transactions.dropLast()))
        }
    }

    @Test func effectiveFinancialDateUsesPurchaseDateNotInvoiceDueDate() {
        let food = category()
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 10_000)
        let invoice = CreditCardInvoice(invoiceIdentifier: "invoice", creditCard: card, referenceMonth: date(2026, 11, 1), closingDate: date(2026, 11, 2), dueDate: date(2026, 11, 9))
        let transaction = Transaction(title: "Purchase", amount: 10, date: date(2026, 10, 15), type: .expense, category: food, paymentMethod: .creditCard, creditCard: card, creditCardInvoice: invoice)
        #expect(transaction.effectiveFinancialDate == date(2026, 10, 15))
        #expect(transaction.invoiceDueDate == date(2026, 11, 9))
    }

    @Test @MainActor func installmentsCountOnePerCycleFromPurchaseDate() throws {
        let context = try TestStore.context()
        let shopping = category("Shopping")
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 2, dueDay: 9, creditLimit: 10_000)
        context.insert(shopping)
        context.insert(card)

        try CreditCardPurchaseService.createPurchase(title: "Phone", totalAmount: 300, purchaseDate: date(2026, 10, 14), category: shopping, notes: "", creditCard: card, installmentCount: 3, in: context, calendar: testCalendar)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        for (offset, expected) in [(0, Decimal(100)), (1, 100), (2, 100), (3, 0)] {
            let day = try #require(testCalendar.date(byAdding: .month, value: offset, to: date(2026, 10, 14)))
            let snapshot = MonthlyFinanceSnapshot(transactions: transactions, date: day, calendar: testCalendar)
            #expect(snapshot.expenses == expected)
        }
    }
}

@Suite("Recurring transactions")
struct RecurringTests {
    @Test @MainActor func generationIsIdempotentAndRespectsInactiveRules() throws {
        let context = try TestStore.context()
        let food = category()
        let active = RecurringTransaction(title: "Gym", amount: 100, type: .expense, category: food, startDate: date(2026, 1, 1), dayOfMonth: 31)
        let inactive = RecurringTransaction(title: "Old", amount: 50, type: .expense, category: food, startDate: date(2026, 1, 1), dayOfMonth: 5, isActive: false)
        context.insert(food)
        context.insert(active)
        context.insert(inactive)
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: date(2026, 2, 28), calendar: testCalendar)
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: date(2026, 2, 28), calendar: testCalendar)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 2)
        #expect(transactions.contains { $0.date == date(2026, 2, 28) })
        #expect(!transactions.contains { $0.title == "Old" })
    }

    @Test @MainActor func deletedHistoryDoesNotRegenerate() throws {
        let context = try TestStore.context()
        let food = category()
        let rule = RecurringTransaction(title: "Gym", amount: 100, type: .expense, category: food, startDate: date(2026, 1, 1), dayOfMonth: 5)
        context.insert(food)
        context.insert(rule)
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: date(2026, 1, 6), calendar: testCalendar)
        let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first)
        context.delete(transaction)
        try context.save()
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: date(2026, 1, 6), calendar: testCalendar)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).count == 1)
    }
}

@Suite("Fixed bills and projections")
struct FixedBillTests {
    @Test @MainActor func occurrenceCatchUpCreatesEveryMissingMonthWithoutExpenses() throws {
        let context = try TestStore.context()
        let housing = category("Housing")
        let bill = FixedBill(name: "Apartment", category: housing, dueDay: 10, estimatedAmount: 700, amountMode: .variable, startDate: date(2026, 7, 1))
        context.insert(housing)
        context.insert(bill)

        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: date(2026, 10, 20), calendar: testCalendar)
        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: date(2026, 10, 20), calendar: testCalendar)

        let occurrences = try context.fetch(FetchDescriptor<FixedBillOccurrence>()).sorted { $0.dueDate < $1.dueDate }
        #expect(occurrences.map(\.dueDate) == [date(2026, 7, 10), date(2026, 8, 10), date(2026, 9, 10), date(2026, 10, 10)])
        #expect(occurrences.map(\.financialCycleIdentifier) == ["2026-7-9", "2026-8-9", "2026-9-9", "2026-10-9"])
        #expect(occurrences.allSatisfy { $0.status == .pending })
        #expect(occurrences.dropLast().allSatisfy { $0.isOverdue(on: date(2026, 10, 20), calendar: testCalendar) })
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

    @Test @MainActor func occurrenceCatchUpStartsAfterExistingOccurrenceAndRespectsStartDate() throws {
        let context = try TestStore.context()
        let housing = category("Housing")
        let bill = FixedBill(name: "Apartment", category: housing, dueDay: 10, estimatedAmount: 700, amountMode: .variable, startDate: date(2026, 7, 15))
        let august = FixedBillOccurrence(occurrenceIdentifier: FixedBillOccurrenceGenerator.occurrenceIdentifier(fixedBillID: bill.id, dueDate: date(2026, 8, 10), calendar: testCalendar), fixedBill: bill, dueDate: date(2026, 8, 10), financialCycleIdentifier: "2026-8-9")
        context.insert(housing)
        context.insert(bill)
        context.insert(august)
        try context.save()

        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: date(2026, 10, 20), calendar: testCalendar)
        let occurrences = try context.fetch(FetchDescriptor<FixedBillOccurrence>()).sorted { $0.dueDate < $1.dueDate }
        #expect(occurrences.map(\.dueDate) == [date(2026, 8, 10), date(2026, 9, 10), date(2026, 10, 10)])
    }

    @Test @MainActor func lateFixedBillPaymentKeepsObligationCycleAndUsesPaymentCycleForSpending() throws {
        let context = try TestStore.context()
        let housing = category("Housing")
        let bill = FixedBill(name: "Apartment", category: housing, dueDay: 8, estimatedAmount: 700, amountMode: .variable, startDate: date(2026, 11, 1))
        context.insert(housing)
        context.insert(bill)
        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: date(2026, 11, 10), calendar: testCalendar)
        let occurrence = try #require(
            try context.fetch(FetchDescriptor<FixedBillOccurrence>())
                .first { $0.dueDate == date(2026, 11, 8) }
        )
        #expect(occurrence.financialCycleIdentifier == "2026-10-9")

        try FixedBillPaymentService.markPaid(occurrence: occurrence, actualAmount: 712, paidDate: date(2026, 11, 10), paymentMethod: .bankSlip, category: housing, note: "", in: context)
        let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first)
        let obligationCycle = try #require(FinancialCycle(containing: occurrence.dueDate, calendar: testCalendar))
        let paymentCycle = try #require(FinancialCycle(containing: transaction.effectiveFinancialDate, calendar: testCalendar))
        #expect(obligationCycle.identifier(calendar: testCalendar) == "2026-10-9")
        #expect(paymentCycle.identifier(calendar: testCalendar) == "2026-11-9")
        #expect(!obligationCycle.contains(transaction.effectiveFinancialDate))
    }

    @Test @MainActor func occurrencePaymentUnpayAndSkipAreIdempotent() throws {
        let context = try TestStore.context()
        let housing = category("Housing")
        let bill = FixedBill(name: "Apartment", category: housing, dueDay: 10, estimatedAmount: 700, amountMode: .variable, startDate: date(2026, 10, 1))
        context.insert(housing)
        context.insert(bill)
        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: date(2026, 10, 20), calendar: testCalendar)
        let occurrence = try #require(try context.fetch(FetchDescriptor<FixedBillOccurrence>()).first)
        try FixedBillPaymentService.markPaid(occurrence: occurrence, actualAmount: 712, paidDate: date(2026, 10, 10), paymentMethod: .pix, category: housing, note: "", in: context)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(throws: FixedBillPaymentError.self) {
            try FixedBillPaymentService.markPaid(occurrence: occurrence, actualAmount: 712, paidDate: date(2026, 10, 10), paymentMethod: .pix, category: housing, note: "", in: context)
        }
        try FixedBillPaymentService.revertToPending(occurrence: occurrence, in: context)
        #expect(occurrence.status == .pending)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        try FixedBillPaymentService.skip(occurrence: occurrence, in: context)
        #expect(occurrence.status == .skipped)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

    @Test func projectionUsesEstimateUntilPaidAndHandlesUnknown() {
        let housing = category("Housing")
        let estimatedBill = FixedBill(name: "Apartment", category: housing, dueDay: 10, estimatedAmount: 700, amountMode: .variable, startDate: date(2026, 10, 1))
        let unknownBill = FixedBill(name: "Water", category: housing, dueDay: 15, estimatedAmount: nil, amountMode: .variable, startDate: date(2026, 10, 1))
        let estimated = FixedBillOccurrence(occurrenceIdentifier: "a", fixedBill: estimatedBill, dueDate: date(2026, 10, 10), financialCycleIdentifier: "2026-10-9")
        let unknown = FixedBillOccurrence(occurrenceIdentifier: "b", fixedBill: unknownBill, dueDate: date(2026, 10, 15), financialCycleIdentifier: "2026-10-9")
        let projection = MonthlyFinanceProjection(transactions: [], recurringTransactions: [], fixedBillOccurrences: [estimated, unknown], date: date(2026, 10, 9), calendar: testCalendar)
        #expect(projection.pendingFixedBillExpenses == 700)
        #expect(projection.projectedExpenses == 700)
        estimated.status = .paid
        let paidTransaction = Transaction(title: "Apartment", amount: 712, date: date(2026, 10, 10), type: .expense, category: housing, sourceFixedBillOccurrenceID: estimated.id)
        let paidProjection = MonthlyFinanceProjection(transactions: [paidTransaction], recurringTransactions: [], fixedBillOccurrences: [estimated, unknown], date: date(2026, 10, 10), calendar: testCalendar)
        #expect(paidProjection.actualExpenses == 712)
        #expect(paidProjection.pendingFixedBillExpenses == 0)
        #expect(paidProjection.projectedExpenses == 712)
    }

    @Test func overdueBillsFromEarlierCyclesStayVisibleAndProjected() {
        let housing = category("Housing")
        let bill = FixedBill(name: "Rent", category: housing, dueDay: 5, estimatedAmount: 1_000, amountMode: .fixed, startDate: date(2026, 8, 1))
        let overdue = FixedBillOccurrence(occurrenceIdentifier: "sep", fixedBill: bill, dueDate: date(2026, 9, 5), financialCycleIdentifier: "2026-8-9")
        let paidEarlier = FixedBillOccurrence(occurrenceIdentifier: "aug", fixedBill: bill, dueDate: date(2026, 8, 5), financialCycleIdentifier: "2026-7-9", status: .paid, actualAmount: 1_000)
        let skippedEarlier = FixedBillOccurrence(occurrenceIdentifier: "jul", fixedBill: bill, dueDate: date(2026, 7, 5), financialCycleIdentifier: "2026-6-9", status: .skipped)
        let current = FixedBillOccurrence(occurrenceIdentifier: "nov", fixedBill: bill, dueDate: date(2026, 11, 5), financialCycleIdentifier: "2026-10-9")
        let all = [current, skippedEarlier, paidEarlier, overdue]

        let snapshot = FixedBillCycleSnapshot(occurrences: all, date: date(2026, 10, 20), calendar: testCalendar)
        #expect(snapshot.occurrences.map(\.occurrenceIdentifier) == ["sep", "nov"])
        #expect(snapshot.pendingCount == 2)
        #expect(snapshot.estimatedRemaining == 2_000)

        let projection = MonthlyFinanceProjection(transactions: [], recurringTransactions: [], fixedBillOccurrences: all, date: date(2026, 10, 20), calendar: testCalendar)
        #expect(projection.pendingFixedBillExpenses == 2_000)
        #expect(projection.pendingFixedBillExpenses(for: housing) == 2_000)
    }

    @Test func projectionIncludesPendingRecurringWithoutDoubleCounting() {
        let food = category()
        let rule = RecurringTransaction(title: "Gym", amount: 120, type: .expense, category: food, startDate: date(2026, 10, 1), dayOfMonth: 20)
        let beforeDue = MonthlyFinanceProjection(transactions: [], recurringTransactions: [rule], date: date(2026, 10, 10), calendar: testCalendar)
        #expect(beforeDue.pendingRecurringExpenses == 120)
        let occurrenceID = RecurringTransactionGenerator.occurrenceIdentifier(ruleID: rule.id, occurrenceDate: date(2026, 10, 20), calendar: testCalendar)
        let generated = Transaction(title: "Gym", amount: 120, date: date(2026, 10, 20), type: .expense, category: food, sourceRecurringTransactionID: rule.id, recurringOccurrenceID: occurrenceID)
        let generatedProjection = MonthlyFinanceProjection(transactions: [generated], recurringTransactions: [rule], date: date(2026, 10, 10), calendar: testCalendar)
        #expect(generatedProjection.pendingRecurringExpenses == 0)
        #expect(generatedProjection.projectedExpenses == 120)
    }
}

@Suite("Analytics projections")
struct AnalyticsProjectionTests {
    @Test func projectedOnlyCategoryDoesNotAlterActualCategoryTotals() {
        let subscriptions = category("Subscriptions")
        let rule = RecurringTransaction(title: "Netflix", amount: 120, type: .expense, category: subscriptions, startDate: date(2026, 10, 1), dayOfMonth: 20)
        let analytics = MonthlyFinanceAnalytics(transactions: [], recurringTransactions: [rule], categoryBudgets: [], monthlyBudget: nil, date: date(2026, 10, 10), calendar: testCalendar)

        #expect(analytics.categorySpending.isEmpty)
        #expect(analytics.projection.actualExpenses == 0)
        #expect(analytics.projectedCategorySpending.count == 1)
        #expect(analytics.projectedCategorySpending.first?.name == "Subscriptions")
        #expect(analytics.projectedCategorySpending.first?.amount == 0)
        #expect(analytics.projectedCategorySpending.first?.pendingAmount == 120)
        #expect(analytics.projectedCategorySpending.first?.projectedAmount == 120)
    }
}

@Suite("Source-aware deletion")
struct DeletionTests {
    @Test @MainActor func manualDeletionAndFixedBillRestoration() throws {
        let context = try TestStore.context()
        let food = category()
        let bill = FixedBill(name: "Bill", category: food, dueDay: 10, estimatedAmount: 50, amountMode: .fixed, startDate: date(2026, 10, 1))
        let occurrence = FixedBillOccurrence(occurrenceIdentifier: "bill", fixedBill: bill, dueDate: date(2026, 10, 10), financialCycleIdentifier: "2026-10-9", status: .paid, actualAmount: 55, paidDate: date(2026, 10, 10), paymentMethod: .pix)
        let manual = Transaction(title: "Manual", amount: 20, date: date(2026, 10, 10), type: .expense, category: food)
        let fixed = Transaction(title: "Bill", amount: 55, date: date(2026, 10, 10), type: .expense, category: food, paymentMethod: .pix, sourceFixedBillOccurrenceID: occurrence.id)
        occurrence.generatedTransactionID = fixed.id
        context.insert(food)
        context.insert(bill)
        context.insert(occurrence)
        context.insert(manual)
        context.insert(fixed)
        try context.save()
        try TransactionDeletionService.delete([manual], from: [manual, fixed], in: context)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        try TransactionDeletionService.delete([fixed], from: [fixed], in: context)
        #expect(occurrence.status == .pending)
        #expect(occurrence.generatedTransactionID == nil)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }
}

@Suite("Reporting reconciliation")
struct ReportingTests {
    @Test func reportBreakdownsReconcile() throws {
        let food = category()
        let cycle = try #require(FinancialCycle(containing: date(2026, 10, 20), calendar: testCalendar))
        let recurring = Transaction(title: "Gym", amount: 100, date: date(2026, 10, 10), type: .expense, category: food, sourceRecurringTransactionID: UUID(), paymentMethod: .pix)
        let manual = Transaction(title: "Food", amount: 200, date: date(2026, 10, 11), type: .expense, category: food, paymentMethod: .debit)
        let income = Transaction(title: "Salary", amount: 1_000, date: date(2026, 10, 9), type: .income, category: food)
        let report = try #require(FinancialCycleReport(cycle: cycle, transactions: [recurring, manual, income], categoryBudgets: [], monthlyBudget: nil, fixedBillOccurrences: [], calendar: testCalendar))
        #expect(report.snapshot.expenses == 300)
        #expect(report.categoryReports.reduce(0) { $0 + $1.amount } == report.snapshot.expenses)
        #expect(report.paymentMethods.reduce(0) { $0 + $1.amount } == report.snapshot.expenses)
        #expect(report.spendingTypes.fixedOrRecurring + report.spendingTypes.variable == report.snapshot.expenses)
        #expect(report.creditCards.installmentAmount + report.creditCards.oneTimeAmount == report.creditCards.total)
        #expect(report.expenseChange.previous == 0)
    }
}

@Suite("Localization")
struct LocalizationTests {
    private let english = Locale(identifier: "en")
    private let portuguese = Locale(identifier: "pt-BR")

    private func resolve(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var localized = resource
        localized.locale = locale
        return String(localized: localized)
    }

    @Test func builtInCategoriesUseLocalizedDisplayNames() {
        let food = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true)
        let otherIncome = TransactionCategory(name: "Other Income", iconName: "plus.circle.fill", colorName: "mint", type: .income, isDefault: true)
        #expect(food.displayName(locale: portuguese) == "Alimentação")
        #expect(otherIncome.displayName(locale: portuguese) == "Outras Receitas")
        #expect(food.displayName(locale: english) == "Food")
        #expect(food.name == "Food")
    }

    @Test func customCategoriesAreNeverTranslated() {
        let custom = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense)
        let named = TransactionCategory(name: "Padaria do Zé", iconName: "fork.knife", colorName: "orange", type: .expense)
        #expect(custom.displayName(locale: portuguese) == "Food")
        #expect(named.displayName(locale: portuguese) == "Padaria do Zé")
    }

    @Test func enumsResolveLocalizedTitlesInsteadOfRawValues() {
        #expect(resolve(PaymentMethod.cash.displayName, portuguese) == "Dinheiro")
        #expect(resolve(PaymentMethod.creditCard.displayName, portuguese) == "Cartão de Crédito")
        #expect(resolve(PaymentMethod.bankSlip.displayName, english) == "Boleto")
        #expect(resolve(TransactionType.expense.displayName, portuguese) == "Despesa")
        #expect(resolve(FixedBillOccurrenceStatus.skipped.displayName, portuguese) == "Pulada")
        #expect(resolve(CreditCardInvoiceStatus.open.displayName, portuguese) == "Aberta")
    }

    @Test func pluralVariationsResolvePerCount() {
        #expect(resolve("\(1) bills", portuguese) == "1 conta")
        #expect(resolve("\(3) bills", portuguese) == "3 contas")
        #expect(resolve("\(1) bills", english) == "1 bill")
    }

    @Test func currencyStaysBRLAndOnlyPresentationChanges() {
        let amount: Decimal = 1_250.90
        let portugueseText = amount.formatted(.currency(code: "BRL").locale(portuguese))
        let englishText = amount.formatted(.currency(code: "BRL").locale(english))
        #expect(portugueseText.replacingOccurrences(of: "\u{00A0}", with: " ") == "R$ 1.250,90")
        #expect(englishText.contains("1,250.90"))
        #expect(englishText.contains("R$"))
    }

    @Test func cycleDatesUseLocalizedMonthNames() {
        let style = Date.FormatStyle(calendar: testCalendar, timeZone: testCalendar.timeZone)
            .month(.abbreviated)
            .day()
        #expect(date(2026, 10, 9).formatted(style.locale(english)) == "Oct 9")
        #expect(date(2026, 10, 9).formatted(style.locale(portuguese)) == "9 de out.")
    }

    @Test func languageSelectionMapsToNativeLocales() {
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.portugueseBrazil.locale.identifier == "pt-BR")
        #expect(AppLanguage(rawValue: "unknown") == nil)
    }
}

@MainActor
enum TestStore {
    /// Same versioned schema and migration plan as the app.
    static func context() throws -> ModelContext {
        ModelContext(try LifeTrackerPersistence.makeContainer(inMemory: true))
    }
}
