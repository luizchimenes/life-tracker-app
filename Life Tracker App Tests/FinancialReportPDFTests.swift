import Foundation
import PDFKit
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

private let english = Locale(identifier: "en")
private let portuguese = Locale(identifier: "pt-BR")

/// Cycle Oct 9 – Nov 8, 2026:
/// salary 5.000, Pix groceries 300, a 3× card purchase of 600 (200 in this
/// cycle), Netflix 59,90 recurring on the card, rent 1.000 paid as a fixed
/// bill, power (~200) still pending, an investment of 2.000. Previous cycle
/// has 100 of food; Nov 10 has a purchase outside the cycle.
@MainActor
private struct ReportFixture {
    let context: ModelContext
    let cycle: FinancialCycle

    init(extraTransactions: Int = 0, longTitle: String? = nil) throws {
        context = try TestStore.context()
        cycle = try #require(FinancialCycle(containing: day(2026, 10, 20), calendar: utc))

        let food = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true)
        let shopping = TransactionCategory(name: "Shopping", iconName: "bag.fill", colorName: "pink", type: .expense, isDefault: true)
        let housing = TransactionCategory(name: "Housing", iconName: "house.fill", colorName: "brown", type: .expense, isDefault: true)
        let salary = TransactionCategory(name: "Salary", iconName: "banknote.fill", colorName: "green", type: .income, isDefault: true)
        let invest = TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "indigo", type: .investment, isDefault: true)
        let card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 10_000)
        [food, shopping, housing, salary, invest].forEach(context.insert)
        context.insert(card)

        context.insert(Transaction(title: "Salário Outubro", amount: 5_000, date: day(2026, 10, 9), type: .income, category: salary))
        context.insert(Transaction(title: "Mercado São João", amount: 300, date: day(2026, 10, 12), type: .expense, category: food, paymentMethod: .pix))
        context.insert(Transaction(title: "Tesouro Selic", amount: 2_000, date: day(2026, 10, 15), type: .investment, category: invest, paymentMethod: .pix))
        context.insert(Transaction(title: "Previous cycle food", amount: 100, date: day(2026, 9, 20), type: .expense, category: food, paymentMethod: .pix))
        context.insert(Transaction(title: "Next cycle purchase", amount: 999, date: day(2026, 11, 10), type: .expense, category: food, paymentMethod: .pix))
        try CreditCardPurchaseService.createPurchase(title: "Notebook", totalAmount: 600, purchaseDate: day(2026, 10, 20), category: shopping, notes: "", creditCard: card, installmentCount: 3, in: context, calendar: utc)

        context.insert(RecurringTransaction(title: "Netflix", amount: Decimal(string: "59.90")!, type: .expense, category: shopping, startDate: day(2026, 10, 1), dayOfMonth: 15, paymentMethod: .creditCard, creditCard: card))
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: day(2026, 10, 20), calendar: utc)

        let rent = FixedBill(name: "Aluguel", category: housing, dueDay: 10, estimatedAmount: 1_000, amountMode: .fixed, startDate: day(2026, 1, 1))
        let power = FixedBill(name: "Energia", category: housing, dueDay: 25, estimatedAmount: 200, amountMode: .variable, startDate: day(2026, 1, 1))
        context.insert(rent)
        context.insert(power)
        let rentOccurrence = FixedBillOccurrence(occurrenceIdentifier: "rent-oct", fixedBill: rent, dueDate: day(2026, 10, 10), financialCycleIdentifier: cycle.identifier(calendar: utc))
        context.insert(rentOccurrence)
        context.insert(FixedBillOccurrence(occurrenceIdentifier: "power-oct", fixedBill: power, dueDate: day(2026, 10, 25), financialCycleIdentifier: cycle.identifier(calendar: utc)))
        try FixedBillPaymentService.markPaid(occurrence: rentOccurrence, actualAmount: 1_000, paidDate: day(2026, 10, 10), paymentMethod: .bankSlip, category: housing, note: "", in: context)

        for index in 0..<extraTransactions {
            context.insert(Transaction(title: "Compra extra \(index + 1)", amount: 10, date: day(2026, 10, 9 + index % 25), type: .expense, category: food, paymentMethod: .debit))
        }
        if let longTitle {
            context.insert(Transaction(title: longTitle, amount: 1, date: day(2026, 10, 30), type: .expense, category: food, paymentMethod: .cash))
        }
        try context.save()
    }

    func content(
        locale: Locale = english,
        generatedAt: Date = day(2026, 10, 20),
        cycle: FinancialCycle? = nil
    ) throws -> FinancialReportPDFContent {
        try #require(FinancialReportPDFContent.make(
            cycle: cycle ?? self.cycle,
            transactions: try context.fetch(FetchDescriptor<Transaction>()),
            categoryBudgets: try context.fetch(FetchDescriptor<CategoryBudget>()),
            monthlyBudget: 3_000,
            fixedBillOccurrences: try context.fetch(FetchDescriptor<FixedBillOccurrence>()),
            creditCardInvoices: try context.fetch(FetchDescriptor<CreditCardInvoice>()),
            recurringTransactions: try context.fetch(FetchDescriptor<RecurringTransaction>()),
            generatedAt: generatedAt,
            locale: locale,
            calendar: utc
        ))
    }

    func transactions(titled title: String) throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>()).filter { $0.title == title }
    }
}

@MainActor
private func render(_ content: FinancialReportPDFContent) throws -> (document: PDFDocument, text: String) {
    let data = FinancialReportPDFDocument(content: content).render()
    let document = try #require(PDFDocument(data: data))
    let text = (document.string ?? "")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\u{202F}", with: " ")
    return (document, text)
}

private func flattened(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

@Suite("Financial report PDF")
@MainActor
struct FinancialReportPDFTests {
    @Test func selectsOnlyTheRequestedCycle() throws {
        let fixture = try ReportFixture()
        let content = try fixture.content()
        let all = try fixture.context.fetch(FetchDescriptor<Transaction>())
        let expected = all.filter { fixture.cycle.contains($0.effectiveFinancialDate) }.map(\.id)
        #expect(Set(content.statementTransactionIDs) == Set(expected))
        #expect(content.statementTransactionIDs.count == 6)
        #expect(!content.statementTransactionIDs.contains(try #require(fixture.transactions(titled: "Next cycle purchase").first).id))
        #expect(!content.statementTransactionIDs.contains(try #require(fixture.transactions(titled: "Previous cycle food").first).id))
        #expect(content.fileName == "LifeTracker_Report_2026-10-09_2026-11-08.pdf")
        #expect(try fixture.content(locale: portuguese).fileName == "LifeTracker_Relatorio_2026-10-09_2026-11-08.pdf")
    }

    @Test func totalsMatchTheCycleRules() throws {
        let fixture = try ReportFixture()
        let text = try render(fixture.content(locale: portuguese)).text
        // Expenses: 300 + 200 (installment 1/3) + 59,90 + 1.000.
        #expect(text.contains("R$ 5.000,00"))
        #expect(text.contains("R$ 1.559,90"))
        #expect(text.contains("R$ 2.000,00"))
        #expect(text.contains("R$ 3.440,10"))
        #expect(text.contains("R$ 1.440,10"))
    }

    @Test func categoriesAndStatementReconcile() throws {
        let fixture = try ReportFixture()
        let content = try fixture.content()
        let statement = try #require(content.sections.first { $0.title == "Transaction Statement" })
        #expect(statement.notes.contains("Reconciled: statement and category totals match the cycle summary."))
        let categories = try #require(content.sections.first { $0.title == "Expenses by Category" })
        let table = try #require(categories.tables.first?.table)
        #expect(table.rows.count == 3)
        #expect(table.footer?[1] == Decimal(string: "1559.90")!.formatted(.currency(code: "BRL").locale(english)))
    }

    @Test func fixedRecurringIsNotDoubleCounted() throws {
        let fixture = try ReportFixture()
        let fixed = try #require(try fixture.content().sections.first { $0.title == "Fixed and Recurring Expenses" })
        let money = { (value: String) in Decimal(string: value)!.formatted(.currency(code: "BRL").locale(english)) }
        #expect(fixed.rows[0].value == money("1059.90"))
        #expect(fixed.rows[1].value == money("1000"))
        #expect(fixed.rows[2].value == money("0"))
        #expect(fixed.rows[3].value == money("59.90"))
        #expect(fixed.rows[4].value == money("500"))
        // C is estimates still due (power ~200), listed apart from recorded spending.
        #expect(fixed.rows.last?.value == money("200"))
    }

    @Test func payingAnInvoiceNeverDuplicatesPurchases() throws {
        let fixture = try ReportFixture()
        let invoice = try #require(try fixture.context.fetch(FetchDescriptor<CreditCardInvoice>()).first { $0.closingDate == day(2026, 11, 9) })
        let before = try fixture.content(generatedAt: day(2026, 11, 12))
        try CreditCardInvoicePaymentService.markPaid(invoice, paidDate: day(2026, 11, 12), in: fixture.context, calendar: utc)
        let after = try fixture.content(generatedAt: day(2026, 11, 12))
        #expect(after.statementTransactionIDs == before.statementTransactionIDs)
        #expect(after.sections[0].rows[2].value == before.sections[0].rows[2].value)
        let text = try render(after).text
        // Invoice total (200 + 59,90) is shown as an invoice, not added to spending.
        #expect(text.contains("Invoice total"))
        #expect(text.contains(Decimal(string: "1559.90")!.formatted(.currency(code: "BRL").locale(english))))
    }

    @Test func installmentsAppearOncePerCycleWithTheirOwnAmount() throws {
        let fixture = try ReportFixture()
        let notebook = try fixture.transactions(titled: "Notebook").sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        let content = try fixture.content()
        #expect(content.statementTransactionIDs.contains(notebook[0].id))
        #expect(!content.statementTransactionIDs.contains(notebook[1].id))
        #expect(!content.statementTransactionIDs.contains(notebook[2].id))
        let text = flattened(try render(content).text)
        #expect(text.contains("Installment 1 of 3"))
        #expect(!text.contains("Installment 2 of 3"))
        #expect(text.contains("Purchased 10/20/26"))
    }

    @Test func comparesWithThePreviousCycle() throws {
        let fixture = try ReportFixture()
        let comparison = try #require(try fixture.content().sections.first { $0.title == "Compared with Previous Cycle" })
        let expenses = try #require(comparison.tables.first?.table.rows.first { $0[0] == "Expenses" })
        let money = { (value: String) in Decimal(string: value)!.formatted(.currency(code: "BRL").locale(english)) }
        #expect(expenses[1] == money("100"))
        #expect(expenses[2] == money("1559.90"))
        #expect(expenses[3] == "+" + money("1459.90"))
    }

    @Test func emptyCycleExportsSuccessfully() throws {
        let fixture = try ReportFixture()
        let empty = try #require(FinancialCycle(containing: day(2025, 3, 15), calendar: utc))
        let content = try fixture.content(generatedAt: day(2026, 10, 20), cycle: empty)
        #expect(content.statementTransactionIDs.isEmpty)
        let (document, text) = try render(content)
        #expect(document.pageCount >= 1)
        #expect(text.contains("No transactions in this cycle."))
    }

    @Test func largeStatementsSpanPagesWithRepeatedHeaders() throws {
        let fixture = try ReportFixture(extraTransactions: 220)
        let content = try fixture.content()
        #expect(content.statementTransactionIDs.count == 226)
        let (document, text) = try render(content)
        #expect(document.pageCount > 4)
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let statementPages = pages.filter { $0.contains("Compra extra") }
        #expect(statementPages.count >= 3)
        // Column headers repeat on every page the statement continues to.
        for page in statementPages {
            #expect(flattened(page).contains("Description"), "\(page.prefix(600))")
            #expect(flattened(page).contains("Date Description Type Category"), "\(page.prefix(600))")
        }
        #expect(pages.last?.contains("Page \(document.pageCount) of \(document.pageCount)") == true)
        #expect(text.contains("Compra extra 1"))
        #expect(text.contains("Compra extra 220"))
    }

    @Test func longDescriptionsWrapWithoutTruncation() throws {
        let words = (1...60).map { "palavra\($0)" }.joined(separator: " ")
        let fixture = try ReportFixture(longTitle: "INICIO \(words) FIMDOTEXTO")
        let text = flattened(try render(fixture.content()).text)
        #expect(text.contains("INICIO"))
        #expect(text.contains("palavra30"))
        #expect(text.contains("FIMDOTEXTO"))
    }

    @Test func producesAValidSearchablePDFWithAllSections() throws {
        let fixture = try ReportFixture()
        let content = try fixture.content(locale: portuguese)
        let (document, text) = try render(content)
        #expect(document.pageCount >= 2)
        #expect(document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == "LifeTracker")
        let firstPage = try #require(document.page(at: 0))
        #expect(abs(firstPage.bounds(for: .mediaBox).width - 595.28) < 1)
        for section in content.sections {
            #expect(text.contains(section.title), "missing section \(section.title)")
        }
        #expect(content.sections.count == 8)
        #expect(text.contains("Mercado São João"))
        #expect(text.contains("Salário Outubro"))
        #expect(text.contains("Azul Gold"))
        #expect(text.contains("Aluguel"))
        #expect(text.contains("Energia"))
        #expect(text.contains("Prévia da fatura") || text.contains("Contas a Pagar"))
    }

    @Test func exportDoesNotModifyStoredData() throws {
        let fixture = try ReportFixture()
        let before = try fixture.context.fetchCount(FetchDescriptor<Transaction>())
        let invoices = try fixture.context.fetchCount(FetchDescriptor<CreditCardInvoice>())
        let url = try FinancialReportPDFExporter.export(try fixture.content())
        #expect(!fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Transaction>()) == before)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CreditCardInvoice>()) == invoices)
        #expect(FileManager.default.fileExists(atPath: url.path()))
        #expect(url.lastPathComponent == "LifeTracker_Report_2026-10-09_2026-11-08.pdf")
        FinancialReportPDFExporter.discard(url)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }
}
