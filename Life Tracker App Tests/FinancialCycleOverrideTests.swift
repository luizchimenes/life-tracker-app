import Foundation
import SwiftData
import Testing
@testable import Life_Tracker_App

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}

private func cycle(_ year: Int, _ month: Int) -> FinancialCycle {
    FinancialCycle(containing: day(year, month, 15), calendar: utc)!
}

/// The value the form stores when the user picks the cycle starting that day.
@MainActor
private func choice(_ year: Int, _ month: Int) -> Date {
    FinancialCycleAllocation.storedValue(for: FinancialCycle(containing: day(year, month, 9), calendar: utc)!, calendar: utc)
}

@MainActor
private func cycleStart(_ transaction: Transaction) -> Date? {
    FinancialCycle(containing: transaction.effectiveFinancialDate, calendar: utc)?.start
}

@MainActor
private struct Ledger {
    let context: ModelContext
    let food: TransactionCategory
    let salary: TransactionCategory
    let invest: TransactionCategory
    let card: CreditCard

    init(context: ModelContext? = nil) throws {
        self.context = try context ?? TestStore.context()
        food = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true)
        salary = TransactionCategory(name: "Salary", iconName: "banknote.fill", colorName: "green", type: .income, isDefault: true)
        invest = TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "indigo", type: .investment, isDefault: true)
        card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 5_000)
        [food, salary, invest].forEach(self.context.insert)
        self.context.insert(card)
        try self.context.save()
    }

    func save(
        _ title: String,
        _ amount: Decimal,
        on date: Date,
        type: TransactionType = .expense,
        method: PaymentMethod = .pix,
        installments: Int = 1,
        override: Date? = nil
    ) throws {
        try TransactionEntry(
            title: title,
            amount: amount,
            type: type,
            category: type == .income ? salary : type == .investment ? invest : food,
            date: date,
            notes: "",
            paymentMethod: method,
            creditCard: method == .creditCard ? card : nil,
            installmentCount: installments,
            financialCycleOverrideStart: override
        )
        .save(in: context, calendar: utc)
    }

    var transactions: [Transaction] {
        get throws {
            try context.fetch(FetchDescriptor<Transaction>()).sorted { ($0.installmentNumber ?? 0, $0.date) < ($1.installmentNumber ?? 0, $1.date) }
        }
    }

    func snapshot(_ cycle: FinancialCycle) throws -> MonthlyFinanceSnapshot {
        MonthlyFinanceSnapshot(transactions: try transactions, date: cycle.start, calendar: utc)
    }
}

@Suite("Financial cycle allocation – boundary")
@MainActor
struct FinancialCycleBoundaryTests {
    @Test func dayEightIsAutomaticallyInThePrecedingCycleAndMayMoveForward() {
        let options = FinancialCycleAllocation.options(for: day(2026, 10, 8), calendar: utc)
        #expect(options.map(\.kind) == [.automatic, .next])
        #expect(options[0].cycle.start == day(2026, 9, 9))
        #expect(options[1].cycle.start == day(2026, 10, 9))
        #expect(options[0].overrideStart == nil)
        #expect(options[1].overrideStart == choice(2026, 10))
    }

    @Test func dayNineIsAutomaticallyInTheNewCycleAndMayMoveBack() {
        let options = FinancialCycleAllocation.options(for: day(2026, 10, 9), calendar: utc)
        #expect(options.map(\.kind) == [.automatic, .previous])
        #expect(options[0].cycle.start == day(2026, 10, 9))
        #expect(options[1].cycle.start == day(2026, 9, 9))
    }

    @Test func onlyDaysSixToElevenOfferAChoice() {
        for value in 1...31 {
            guard let date = utc.date(from: DateComponents(year: 2026, month: 10, day: value)) else { continue }
            let offered = !FinancialCycleAllocation.options(for: date, calendar: utc).isEmpty
            #expect(offered == (6...11).contains(value), "day \(value)")
        }
    }

    @Test func yearBoundariesAreCalendarSafe() {
        #expect(FinancialCycleAllocation.options(for: day(2027, 1, 7), calendar: utc).last?.cycle.start == day(2027, 1, 9))
        #expect(FinancialCycleAllocation.options(for: day(2027, 1, 10), calendar: utc).last?.cycle.start == day(2026, 12, 9))
        #expect(FinancialCycleAllocation.options(for: day(2026, 12, 8), calendar: utc).last?.cycle.start == day(2026, 12, 9))
    }

    @Test func changingTheDateKeepsOnlyStillValidChoices() {
        let next = choice(2026, 10)
        #expect(FinancialCycleAllocation.revalidated(next, for: day(2026, 10, 7), calendar: utc) == next)
        // On Oct 10 that cycle is the automatic one, so the choice resets.
        #expect(FinancialCycleAllocation.revalidated(next, for: day(2026, 10, 10), calendar: utc) == nil)
        #expect(FinancialCycleAllocation.revalidated(next, for: day(2026, 10, 20), calendar: utc) == nil)
        // An unrelated cycle is never accepted.
        #expect(!FinancialCycleAllocation.isValid(choice(2026, 12), for: day(2026, 10, 8), calendar: utc))
        #expect(FinancialCycleAllocation.isValid(nil, for: day(2026, 10, 20), calendar: utc))
    }
}

@Suite("Financial cycle allocation – accounting")
@MainActor
struct FinancialCycleOverrideAccountingTests {
    @Test func movesAnExpenseWithoutChangingItsDate() throws {
        let ledger = try Ledger()
        try ledger.save("Mercado", 100, on: day(2026, 10, 8), override: choice(2026, 10))
        let saved = try #require(try ledger.transactions.first)
        #expect(saved.date == day(2026, 10, 8))
        #expect(saved.hasManualFinancialCycle)
        #expect(try ledger.snapshot(cycle(2026, 10)).expenses == 100)
        #expect(try ledger.snapshot(cycle(2026, 9)).expenses == 0)
        #expect(try ledger.snapshot(cycle(2026, 10)).expenses(for: ledger.food) == 100)
        #expect(try ledger.snapshot(cycle(2026, 9)).expenses(for: ledger.food) == 0)
    }

    @Test func movesADayNineExpenseBack() throws {
        let ledger = try Ledger()
        try ledger.save("Farmácia", 40, on: day(2026, 10, 9), override: choice(2026, 9))
        #expect(try ledger.snapshot(cycle(2026, 9)).expenses == 40)
        #expect(try ledger.snapshot(cycle(2026, 10)).expenses == 0)
    }

    @Test func rejectsChoicesOutsideTheWindowWithoutSaving() throws {
        let ledger = try Ledger()
        #expect(throws: FinancialCycleAllocationError.self) {
            try ledger.save("Mercado", 100, on: day(2026, 10, 20), override: choice(2026, 11))
        }
        #expect(try ledger.transactions.isEmpty)
    }

    @Test func oneTimeCardPurchaseKeepsInvoiceAndLimit() throws {
        let automatic = try Ledger()
        try automatic.save("Tênis", 300, on: day(2026, 10, 8), method: .creditCard)
        let moved = try Ledger()
        try moved.save("Tênis", 300, on: day(2026, 10, 8), method: .creditCard, override: choice(2026, 10))

        let a = try #require(try automatic.transactions.first)
        let m = try #require(try moved.transactions.first)
        #expect(m.date == a.date)
        #expect(m.creditCardInvoice?.closingDate == a.creditCardInvoice?.closingDate)
        #expect(m.creditCardInvoice?.dueDate == a.creditCardInvoice?.dueDate)
        let limit = { (ledger: Ledger) in
            CreditCardBalanceCalculator.availableLimit(for: ledger.card, invoices: try ledger.context.fetch(FetchDescriptor<CreditCardInvoice>()), transactions: try ledger.transactions, on: day(2026, 10, 8), calendar: utc)
        }
        #expect(try limit(moved) == limit(automatic))
        #expect(try moved.snapshot(cycle(2026, 10)).expenses == 300)
        #expect(try automatic.snapshot(cycle(2026, 9)).expenses == 300)
    }

    @Test func installmentPurchaseMovesAsAGroup() throws {
        let automatic = try Ledger()
        try automatic.save("Notebook", 600, on: day(2026, 10, 8), method: .creditCard, installments: 3)
        let moved = try Ledger()
        try moved.save("Notebook", 600, on: day(2026, 10, 8), method: .creditCard, installments: 3, override: choice(2026, 10))

        let a = try automatic.transactions
        let m = try moved.transactions
        #expect(m.count == 3)
        #expect(m.map(\.amount) == [200, 200, 200])
        #expect(m.map(\.date) == a.map(\.date))
        #expect(m.map { $0.creditCardInvoice?.closingDate } == a.map { $0.creditCardInvoice?.closingDate })
        #expect(m.map { $0.creditCardInvoice?.dueDate } == a.map { $0.creditCardInvoice?.dueDate })
        #expect(m.map(cycleStart) == [day(2026, 10, 9), day(2026, 11, 9), day(2026, 12, 9)])
        #expect(a.map(cycleStart) == [day(2026, 9, 9), day(2026, 10, 9), day(2026, 11, 9)])
        for month in [10, 11, 12] {
            #expect(try moved.snapshot(cycle(2026, month)).expenses == 200)
        }
        #expect(try moved.snapshot(cycle(2026, 9)).expenses == 0)
        #expect(try moved.snapshot(cycle(2027, 1)).expenses == 0)
    }

    @Test func changingAnExistingPurchaseUpdatesEveryInstallmentOnly() throws {
        let ledger = try Ledger()
        try ledger.save("Notebook", 600, on: day(2026, 10, 8), method: .creditCard, installments: 3)
        let before = try ledger.transactions
        let invoices = before.map { $0.creditCardInvoice?.id }
        let second = before[1]

        try FinancialCycleAllocationService.apply(choice(2026, 10), to: second, allTransactions: before, in: ledger.context, calendar: utc)
        var after = try ledger.transactions
        #expect(after.map(\.financialCycleOverrideStartDate) == [choice(2026, 10), choice(2026, 11), choice(2026, 12)])
        #expect(after.map { $0.creditCardInvoice?.id } == invoices)
        #expect(after.map(\.date) == before.map(\.date))
        #expect(FinancialCycleAllocationService.currentSelection(for: after[2], allTransactions: after) == choice(2026, 10))

        // Back to Automatic clears the whole group.
        try FinancialCycleAllocationService.apply(nil, to: after[0], allTransactions: after, in: ledger.context, calendar: utc)
        after = try ledger.transactions
        #expect(after.allSatisfy { $0.financialCycleOverrideStartDate == nil })
        #expect(try ledger.context.fetchCount(FetchDescriptor<Transaction>()) == 3)
    }

    @Test func earlySalaryCountsInTheNextCycle() throws {
        let ledger = try Ledger()
        try ledger.save("Salário", 5_000, on: day(2026, 11, 7), type: .income, override: choice(2026, 11))
        #expect(try ledger.snapshot(cycle(2026, 11)).income == 5_000)
        #expect(try ledger.snapshot(cycle(2026, 10)).income == 0)
        #expect(try ledger.transactions.first?.date == day(2026, 11, 7))
    }

    @Test func investmentMovesAndStaysAnInvestment() throws {
        let ledger = try Ledger()
        try ledger.save("CDB", 2_000, on: day(2026, 10, 7), type: .investment, override: choice(2026, 10))
        let october = try ledger.snapshot(cycle(2026, 10))
        #expect(october.investments == 2_000)
        #expect(october.expenses == 0)
        #expect(october.income == 0)
        #expect(try ledger.snapshot(cycle(2026, 9)).investments == 0)
    }

    @Test func budgetsProjectionsReportsAndPDFFollowTheChoice() throws {
        let ledger = try Ledger()
        ledger.context.insert(CategoryBudget(category: ledger.food, monthlyLimit: 500))
        try ledger.save("Mercado", 120, on: day(2026, 10, 8), override: choice(2026, 10))
        try ledger.save("Padaria", 30, on: day(2026, 10, 20))
        let all = try ledger.transactions
        let budgets = try ledger.context.fetch(FetchDescriptor<CategoryBudget>())

        let projection = MonthlyFinanceProjection(transactions: all, recurringTransactions: [], date: day(2026, 10, 20), calendar: utc)
        #expect(projection.actualExpenses == 150)

        let report = try #require(FinancialCycleReport(cycle: cycle(2026, 10), transactions: all, categoryBudgets: budgets, monthlyBudget: 1_000, fixedBillOccurrences: [], calendar: utc))
        #expect(report.snapshot.expenses == 150)
        #expect(report.previousSnapshot.expenses == 0)
        #expect(report.budgetPerformance.first?.spent == 150)
        #expect(report.spendingTypes.variable == 150)
        #expect(report.spendingTypes.fixedOrRecurring + report.spendingTypes.variable == report.snapshot.expenses)

        let september = try #require(FinancialCycleReport(cycle: cycle(2026, 9), transactions: all, categoryBudgets: budgets, monthlyBudget: 1_000, fixedBillOccurrences: [], calendar: utc))
        #expect(september.snapshot.expenses == 0)

        let moved = try #require(all.first { $0.title == "Mercado" })
        let pdf = try #require(FinancialReportPDFContent.make(cycle: cycle(2026, 10), transactions: all, categoryBudgets: budgets, monthlyBudget: 1_000, fixedBillOccurrences: [], creditCardInvoices: [], recurringTransactions: [], generatedAt: day(2026, 10, 20), locale: Locale(identifier: "en"), calendar: utc))
        #expect(pdf.statementTransactionIDs.contains(moved.id))
        let pdfSeptember = try #require(FinancialReportPDFContent.make(cycle: cycle(2026, 9), transactions: all, categoryBudgets: budgets, monthlyBudget: 1_000, fixedBillOccurrences: [], creditCardInvoices: [], recurringTransactions: [], generatedAt: day(2026, 10, 20), locale: Locale(identifier: "en"), calendar: utc))
        #expect(!pdfSeptember.statementTransactionIDs.contains(moved.id))
        let rendered = FinancialReportPDFDocument(content: pdf).render()
        #expect(!rendered.isEmpty)
    }

    @Test func recentActivityKeepsTheRealDate() throws {
        let ledger = try Ledger()
        try ledger.save("Mercado", 100, on: day(2026, 10, 8), override: choice(2026, 10))
        try ledger.save("Farmácia", 40, on: day(2026, 10, 9))
        let recent = TransactionActivity.recent(from: try ledger.transactions, limit: 5)
        #expect(recent.map(\.title) == ["Farmácia", "Mercado"])
        #expect(recent.last?.date == day(2026, 10, 8))
    }

    @Test func deletingAMovedPurchaseStillRemovesTheWholeGroup() throws {
        let ledger = try Ledger()
        try ledger.save("Notebook", 600, on: day(2026, 10, 8), method: .creditCard, installments: 3, override: choice(2026, 10))
        let all = try ledger.transactions
        let records = try TransactionDeletionService.transactionsForSafeDeletion(of: all[0], from: all)
        try TransactionDeletionService.delete(records, from: all, in: ledger.context)
        #expect(try ledger.transactions.isEmpty)
        #expect(try ledger.context.fetchCount(FetchDescriptor<CreditCardInvoice>()) == 0)
    }

    @Test func generatedEntriesKeepTheirAutomaticCycle() throws {
        let ledger = try Ledger()
        let rule = RecurringTransaction(title: "Netflix", amount: 59, type: .expense, category: ledger.food, startDate: day(2026, 10, 1), dayOfMonth: 8)
        ledger.context.insert(rule)
        try RecurringTransactionGenerator.generateDueTransactions(in: ledger.context, through: day(2026, 10, 20), calendar: utc)
        let generated = try #require(try ledger.transactions.first)
        #expect(!FinancialCycleAllocationService.canChangeAllocation(of: generated))
        #expect(throws: FinancialCycleAllocationError.self) {
            try FinancialCycleAllocationService.apply(choice(2026, 10), to: generated, allTransactions: [generated], in: ledger.context, calendar: utc)
        }
        #expect(generated.financialCycleOverrideStartDate == nil)
    }

    @Test func voicePrefilledEntryUsesTheSameChoice() throws {
        let ledger = try Ledger()
        let parser = TransactionVoiceParser(
            categories: [VoiceCategoryCandidate(ledger.food)],
            creditCards: [VoiceCardCandidate(ledger.card)],
            today: day(2026, 10, 21),
            calendar: utc
        )
        let draft = parser.parse("Mercado 80 reais no pix dia 8")
        #expect(utc.isDate(draft.transactionDate, inSameDayAs: day(2026, 10, 8)))
        let options = FinancialCycleAllocation.options(for: draft.transactionDate, calendar: utc)
        let next = try #require(options.first { $0.kind == .next })
        try TransactionEntry(
            title: try #require(draft.title),
            amount: try #require(draft.amount),
            type: draft.type ?? .expense,
            category: ledger.food,
            date: draft.transactionDate,
            notes: "",
            paymentMethod: draft.paymentMethod ?? .debit,
            creditCard: nil,
            installmentCount: 1,
            financialCycleOverrideStart: next.overrideStart
        )
        .save(in: ledger.context, calendar: utc)
        #expect(try ledger.snapshot(cycle(2026, 10)).expenses == 80)
        #expect(try ledger.snapshot(cycle(2026, 9)).expenses == 0)
    }

    @Test func choiceSurvivesReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LifeTrackerOverride-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        try autoreleasepool {
            let ledger = try Ledger(context: ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url)))
            try ledger.save("Mercado", 100, on: day(2026, 10, 8), override: choice(2026, 10))
        }
        let reopened = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
        let saved = try #require(try reopened.fetch(FetchDescriptor<Transaction>()).first)
        #expect(saved.financialCycleOverrideStartDate == choice(2026, 10))
        #expect(saved.date == day(2026, 10, 8))
    }
}
