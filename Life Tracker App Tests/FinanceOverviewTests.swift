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

private func expenseCategory(_ name: String = "Food") -> TransactionCategory {
    TransactionCategory(name: name, iconName: "fork.knife", colorName: "orange", type: .expense)
}

private func incomeCategory() -> TransactionCategory {
    TransactionCategory(name: "Salary", iconName: "banknote.fill", colorName: "green", type: .income)
}

@Suite("Investment terminology")
struct InvestmentTerminologyTests {
    private let portuguese = Locale(identifier: "pt-BR")
    private let english = Locale(identifier: "en")

    @Test func investmentIncomeCategoryReadsAsRendimentos() {
        let category = TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "green", type: .income, isDefault: true)
        #expect(category.displayName(locale: portuguese) == "Rendimentos")
        #expect(category.displayName(locale: english) == "Investment Income")
        #expect(category.name == "Investments")
    }

    @Test func investmentCategoryStillReadsAsInvestimentos() {
        let category = TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "indigo", type: .investment, isDefault: true)
        #expect(category.displayName(locale: portuguese) == "Investimentos")
        #expect(category.displayName(locale: english) == "Investments")
    }

    @Test func customCategoryNamedInvestmentsIsNotRenamed() {
        let custom = TransactionCategory(name: "Investments", iconName: "star", colorName: "green", type: .income)
        #expect(custom.displayName(locale: portuguese) == "Investments")
    }
}

@Suite("Available money")
struct AvailableMoneyTests {
    /// Income 5.000, expenses 1.000, invested 2.000, and a 300 recurring
    /// expense still due on Oct 25, seen on Oct 20.
    private func fixture() -> (transactions: [Transaction], rules: [RecurringTransaction]) {
        let food = expenseCategory()
        let salary = incomeCategory()
        let invest = TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "indigo", type: .investment)
        let transactions = [
            Transaction(title: "Salary", amount: 5_000, date: day(2026, 10, 9), type: .income, category: salary),
            Transaction(title: "Groceries", amount: 1_000, date: day(2026, 10, 12), type: .expense, category: food, paymentMethod: .pix),
            Transaction(title: "Fund", amount: 2_000, date: day(2026, 10, 15), type: .investment, category: invest)
        ]
        let rule = RecurringTransaction(title: "Gym", amount: 300, type: .expense, category: food, startDate: day(2026, 1, 1), dayOfMonth: 25)
        return (transactions, [rule])
    }

    @Test func actualAvailableAfterInvestmentsReconciles() {
        let data = fixture()
        let snapshot = MonthlyFinanceSnapshot(transactions: data.transactions, date: day(2026, 10, 20), calendar: utc)
        #expect(snapshot.balance == 4_000)
        #expect(snapshot.availableAfterInvestments == 2_000)
        #expect(snapshot.availableAfterInvestments == snapshot.income - snapshot.expenses - snapshot.investments)
    }

    @Test func projectedAvailableIncludesInvestments() {
        let data = fixture()
        let projection = MonthlyFinanceProjection(transactions: data.transactions, recurringTransactions: data.rules, date: day(2026, 10, 20), calendar: utc)
        #expect(projection.projectedExpenses == 1_300)
        #expect(projection.projectedInvestments == 2_000)
        #expect(projection.projectedBalance == 3_700)
        #expect(projection.projectedAvailableAfterInvestments == 1_700)
    }

    /// Home and Finance both render `FinanceOverview`; its parts must agree
    /// with the standalone calculations they wrap.
    @Test func overviewIsTheSingleSourceForHomeAndFinance() {
        let data = fixture()
        let overview = FinanceOverview(transactions: data.transactions, recurringTransactions: data.rules, fixedBillOccurrences: [], creditCardInvoices: [], monthlyBudget: nil, date: day(2026, 10, 20), calendar: utc)
        let projection = MonthlyFinanceProjection(transactions: data.transactions, recurringTransactions: data.rules, date: day(2026, 10, 20), calendar: utc)
        #expect(overview.actual.availableAfterInvestments == projection.actual.availableAfterInvestments)
        #expect(overview.projection.projectedExpenses == projection.projectedExpenses)
        #expect(overview.safeToSpend.cashAvailable == projection.projectedAvailableAfterInvestments)
        #expect(overview.safeToSpend.amount == 1_700)
    }
}

@Suite("Recurring credit-card charges")
@MainActor
struct RecurringCreditCardTests {
    private struct Setup {
        let context: ModelContext
        let card: CreditCard
        let otherCard: CreditCard
        let rule: RecurringTransaction
    }

    /// Netflix R$ 59,90 on day 15, card closes on 9 and is due on 15.
    private func setup() throws -> Setup {
        let context = try TestStore.context()
        let subscriptions = expenseCategory("Subscriptions")
        let card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 1_000)
        let otherCard = CreditCard(name: "Black", lastFourDigits: "9999", closingDay: 9, dueDay: 15, creditLimit: 5_000)
        let rule = RecurringTransaction(title: "Netflix", amount: Decimal(string: "59.90")!, type: .expense, category: subscriptions, startDate: day(2026, 10, 1), dayOfMonth: 15, paymentMethod: .creditCard, creditCard: card)
        context.insert(subscriptions)
        context.insert(card)
        context.insert(otherCard)
        context.insert(rule)
        try context.save()
        return Setup(context: context, card: card, otherCard: otherCard, rule: rule)
    }

    private func transactions(_ context: ModelContext) throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>()).sorted { $0.date < $1.date }
    }

    @Test func legacyRuleWithoutMethodStillGeneratesDebit() throws {
        let context = try TestStore.context()
        let food = expenseCategory()
        let rule = RecurringTransaction(title: "Gym", amount: 100, type: .expense, category: food, startDate: day(2026, 10, 1), dayOfMonth: 5)
        rule.paymentMethodRawValue = nil
        context.insert(food)
        context.insert(rule)
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: day(2026, 10, 20), calendar: utc)
        let generated = try #require(try transactions(context).first)
        #expect(rule.paymentMethod == .debit)
        #expect(generated.paymentMethod == .debit)
        #expect(generated.creditCard == nil)
        #expect(generated.creditCardInvoice == nil)
    }

    @Test func cardRuleCreatesOneCardPurchaseOnTheRightInvoice() throws {
        let s = try setup()
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)

        let all = try transactions(s.context)
        let charge = try #require(all.first)
        #expect(all.count == 1)
        #expect(charge.paymentMethod == .creditCard)
        #expect(charge.creditCard?.id == s.card.id)
        #expect(charge.creditCardInvoice?.closingDate == day(2026, 11, 9))
        #expect(charge.creditCardInvoice?.dueDate == day(2026, 11, 15))
        #expect(charge.sourceRecurringTransactionID == s.rule.id)
        #expect(charge.recurringOccurrenceID != nil)
        #expect(charge.totalInstallments == 1)

        let invoice = try #require(charge.creditCardInvoice)
        #expect(invoice.total(in: all) == Decimal(string: "59.90")!)
        let invoices = try s.context.fetch(FetchDescriptor<CreditCardInvoice>())
        #expect(CreditCardBalanceCalculator.availableLimit(for: s.card, invoices: invoices, transactions: all, on: day(2026, 10, 20), calendar: utc) == Decimal(string: "940.10")!)

        #expect(SpendingClassification.classify(charge) == .fixedOrRecurring)
        #expect(charge.sourceKind == .recurring)
        // Counted in the cycle of the charge date, under the current card rule.
        let snapshot = MonthlyFinanceSnapshot(transactions: all, date: day(2026, 10, 20), calendar: utc)
        #expect(snapshot.expenses == Decimal(string: "59.90")!)
    }

    @Test func generationIsIdempotent() throws {
        let s = try setup()
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)
        let all = try transactions(s.context)
        #expect(all.count == 1)
        #expect(try #require(all.first?.creditCardInvoice).total(in: all) == Decimal(string: "59.90")!)
    }

    @Test func deletedChargeDoesNotRegenerateAndRuleSurvives() throws {
        let s = try setup()
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)
        let all = try transactions(s.context)
        let records = try TransactionDeletionService.transactionsForSafeDeletion(of: all[0], from: all)
        #expect(records.count == 1)
        try TransactionDeletionService.delete(records, from: all, in: s.context)

        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)
        #expect(try transactions(s.context).isEmpty)
        #expect(try s.context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 1)
    }

    @Test func editingTheRuleOnlyAffectsFutureCharges() throws {
        let s = try setup()
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 10, 20), calendar: utc)
        let octoberInvoiceID = try #require(try transactions(s.context).first?.creditCardInvoice?.id)

        s.rule.creditCard = s.otherCard
        s.rule.amount = 69
        s.rule.dayOfMonth = 16
        try RecurringTransactionGenerator.generateDueTransactions(in: s.context, through: day(2026, 11, 20), calendar: utc)

        let all = try transactions(s.context)
        #expect(all.count == 2)
        #expect(all[0].creditCard?.id == s.card.id)
        #expect(all[0].amount == Decimal(string: "59.90")!)
        #expect(all[0].creditCardInvoice?.id == octoberInvoiceID)
        #expect(all[1].creditCard?.id == s.otherCard.id)
        #expect(all[1].amount == 69)
        #expect(all[1].date == day(2026, 11, 16))
    }
}

@Suite("Safe to Spend")
struct SafeToSpendTests {
    private func projection(income: Decimal, expenses: Decimal, investments: Decimal = 0, on date: Date) -> MonthlyFinanceProjection {
        let food = expenseCategory()
        var transactions = [
            Transaction(title: "Salary", amount: income, date: day(2026, 10, 9), type: .income, category: incomeCategory()),
            Transaction(title: "Spend", amount: expenses, date: day(2026, 10, 10), type: .expense, category: food, paymentMethod: .pix)
        ]
        if investments > 0 {
            transactions.append(Transaction(title: "Fund", amount: investments, date: day(2026, 10, 10), type: .investment, category: food))
        }
        return MonthlyFinanceProjection(transactions: transactions, recurringTransactions: [], date: date, calendar: utc)
    }

    @Test func withoutBudgetUsesProjectedAvailableCash() {
        let p = projection(income: 5_000, expenses: 1_000, investments: 2_000, on: day(2026, 10, 20))
        let safe = SafeToSpend(projection: p, monthlyBudget: nil, date: day(2026, 10, 20), calendar: utc)
        #expect(safe.amount == 2_000)
        #expect(safe.constraint == .cash)
        #expect(safe.budgetRemaining == nil)
    }

    @Test func withBudgetUsesTheSmallerConstraint() {
        let p = projection(income: 5_000, expenses: 1_000, investments: 2_000, on: day(2026, 10, 20))
        let tight = SafeToSpend(projection: p, monthlyBudget: 1_500, date: day(2026, 10, 20), calendar: utc)
        #expect(tight.amount == 500)
        #expect(tight.constraint == .budget)

        let loose = SafeToSpend(projection: p, monthlyBudget: 10_000, date: day(2026, 10, 20), calendar: utc)
        #expect(loose.amount == 2_000)
        #expect(loose.constraint == .cash)
    }

    @Test func negativeValueBecomesAShortfall() {
        let p = projection(income: 1_000, expenses: 1_420, on: day(2026, 10, 20))
        let safe = SafeToSpend(projection: p, monthlyBudget: nil, date: day(2026, 10, 20), calendar: utc)
        #expect(safe.amount == -420)
        #expect(safe.isShortfall)
        #expect(safe.displayAmount == 0)
        #expect(safe.shortfall == 420)
        #expect(safe.perDay == 0)
    }

    @Test func perDayUsesDaysRemainingIncludingToday() {
        let p = projection(income: 2_850, expenses: 1_000, on: day(2026, 10, 20))
        let safe = SafeToSpend(projection: p, monthlyBudget: nil, date: day(2026, 10, 20), calendar: utc)
        // Oct 20 through Nov 8.
        #expect(safe.daysRemaining == 20)
        #expect(safe.perDay == Decimal(string: "92.5")!)
    }

    @Test func finalCycleDayCountsAsOneDay() throws {
        let cycle = try #require(FinancialCycle(containing: day(2026, 11, 8), calendar: utc))
        #expect(SafeToSpend.daysRemaining(in: cycle, from: day(2026, 11, 8), calendar: utc) == 1)
        #expect(SafeToSpend.daysRemaining(in: cycle, from: day(2026, 10, 9), calendar: utc) == 31)
    }
}

@Suite("Bills to Pay")
@MainActor
struct BillsToPayTests {
    /// Seen on Oct 20: rent 1.000 (fixed), power ~200 (variable estimate),
    /// water unknown, a September bill still unpaid, and a paid one.
    private func occurrences() -> [FixedBillOccurrence] {
        let housing = expenseCategory("Housing")
        func bill(_ name: String, _ amount: Decimal?, _ mode: FixedBillAmountMode) -> FixedBill {
            FixedBill(name: name, category: housing, dueDay: 1, estimatedAmount: amount, amountMode: mode, startDate: day(2026, 1, 1))
        }
        let paid = FixedBillOccurrence(occurrenceIdentifier: "paid", fixedBill: bill("Internet", 100, .fixed), dueDate: day(2026, 10, 10), financialCycleIdentifier: "", status: .paid, actualAmount: 100)
        return [
            FixedBillOccurrence(occurrenceIdentifier: "rent", fixedBill: bill("Rent", 1_000, .fixed), dueDate: day(2026, 10, 25), financialCycleIdentifier: ""),
            FixedBillOccurrence(occurrenceIdentifier: "power", fixedBill: bill("Power", 200, .variable), dueDate: day(2026, 10, 28), financialCycleIdentifier: ""),
            FixedBillOccurrence(occurrenceIdentifier: "water", fixedBill: bill("Water", nil, .variable), dueDate: day(2026, 11, 2), financialCycleIdentifier: ""),
            FixedBillOccurrence(occurrenceIdentifier: "september", fixedBill: bill("Condo", 100, .fixed), dueDate: day(2026, 9, 5), financialCycleIdentifier: ""),
            paid
        ]
    }

    @Test func countsTotalsAndUnknownAmounts() {
        let bills = BillsToPaySummary(fixedBillOccurrences: occurrences(), creditCardInvoices: [], transactions: [], date: day(2026, 10, 20), calendar: utc)
        #expect(bills.pendingCount == 4)
        #expect(bills.overdueCount == 1)
        #expect(bills.knownTotal == 1_300)
        #expect(bills.includesEstimates)
        #expect(bills.unknownAmountCount == 1)
    }

    /// Card closes on 9: a purchase on Oct 20 lands on the Nov 9 invoice, a
    /// purchase on Nov 10 on the Dec 9 invoice. Seen on Nov 10.
    private func cardContext() throws -> (ModelContext, CreditCard) {
        let context = try TestStore.context()
        let food = expenseCategory()
        let card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 5_000)
        context.insert(food)
        context.insert(card)
        try CreditCardPurchaseService.createPurchase(title: "Market", totalAmount: 300, purchaseDate: day(2026, 10, 20), category: food, notes: "", creditCard: card, installmentCount: 1, in: context, calendar: utc)
        try CreditCardPurchaseService.createPurchase(title: "Uber", totalAmount: 40, purchaseDate: day(2026, 11, 10), category: food, notes: "", creditCard: card, installmentCount: 1, in: context, calendar: utc)
        return (context, card)
    }

    @Test func closedInvoiceIsPayableAndOpenInvoiceIsOnlyAPreview() throws {
        let (context, _) = try cardContext()
        let invoices = try context.fetch(FetchDescriptor<CreditCardInvoice>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let bills = BillsToPaySummary(fixedBillOccurrences: [], creditCardInvoices: invoices, transactions: transactions, date: day(2026, 11, 10), calendar: utc)

        #expect(bills.payableInvoices.map(\.total) == [300])
        #expect(bills.pendingCount == 1)
        #expect(bills.knownTotal == 300)
        #expect(bills.upcomingInvoices.map(\.total) == [40])
        #expect(bills.upcomingInvoices.first?.invoice.closingDate == day(2026, 12, 9))
        #expect(bills.overdueCount == 0)
    }

    @Test func invoicesNeverAddSpendingAndPayingKeepsTotals() throws {
        let (context, _) = try cardContext()
        let invoices = try context.fetch(FetchDescriptor<CreditCardInvoice>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let date = day(2026, 11, 10)

        let withInvoices = FinanceOverview(transactions: transactions, recurringTransactions: [], fixedBillOccurrences: [], creditCardInvoices: invoices, monthlyBudget: nil, date: date, calendar: utc)
        let withoutInvoices = FinanceOverview(transactions: transactions, recurringTransactions: [], fixedBillOccurrences: [], creditCardInvoices: [], monthlyBudget: nil, date: date, calendar: utc)
        #expect(withInvoices.actual.expenses == 40)
        #expect(withInvoices.projection.projectedExpenses == withoutInvoices.projection.projectedExpenses)
        #expect(withInvoices.safeToSpend.amount == withoutInvoices.safeToSpend.amount)

        let closed = try #require(withInvoices.bills.payableInvoices.first?.invoice)
        try CreditCardInvoicePaymentService.markPaid(closed, paidDate: date, in: context, calendar: utc)
        let after = FinanceOverview(transactions: try context.fetch(FetchDescriptor<Transaction>()), recurringTransactions: [], fixedBillOccurrences: [], creditCardInvoices: invoices, monthlyBudget: nil, date: date, calendar: utc)
        #expect(after.bills.pendingCount == 0)
        #expect(after.actual.expenses == withInvoices.actual.expenses)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)

        let previousCycle = MonthlyFinanceSnapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()), date: day(2026, 10, 20), calendar: utc)
        #expect(previousCycle.expenses == 300)
    }
}
