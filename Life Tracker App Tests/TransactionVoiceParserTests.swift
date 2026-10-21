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
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private let today = day(2026, 10, 21)

/// The built-in categories as a pt-BR user sees them.
private let defaultCategories: [VoiceCategoryCandidate] = TransactionCategory.makeDefaults().map {
    VoiceCategoryCandidate(id: $0.id, storedName: $0.name, displayName: $0.displayName(locale: Locale(identifier: "pt-BR")), type: $0.type, isDefault: true)
}

private func category(_ storedName: String, _ type: TransactionCategoryType = .expense) -> UUID? {
    defaultCategories.first { $0.storedName == storedName && $0.type == type }?.id
}

private let azulGold = VoiceCardCandidate(id: UUID(), name: "Azul Gold")
private let nubank = VoiceCardCandidate(id: UUID(), name: "Nubank")
private let itauAzul = VoiceCardCandidate(id: UUID(), name: "Itaú Azul")

@MainActor
private func parse(_ phrase: String, cards: [VoiceCardCandidate] = [azulGold, nubank], categories: [VoiceCategoryCandidate] = defaultCategories) -> VoiceTransactionDraft {
    TransactionVoiceParser(categories: categories, creditCards: cards, today: today, calendar: utc).parse(phrase)
}

@Suite("Voice parser – amounts")
@MainActor
struct VoiceAmountTests {
    @Test(arguments: [
        ("Farmácia R$ 89,90 no Pix", "89.90"),
        ("Mercado 129 reais e 90 centavos no débito", "129.90"),
        ("Mercado 129 e 90 no débito", "129.90"),
        ("Uber, trinta e cinco reais no cartão", "35"),
        ("Almoço, quarenta e dois e cinquenta no Pix", "42.50"),
        ("Mercado, cento e vinte e nove reais e noventa centavos no débito", "129.90"),
        ("Restaurante cento e vinte reais no débito", "120"),
        ("Investi dois mil reais em CDB", "2000"),
        ("Aluguel mil duzentos e cinquenta reais no boleto", "1250"),
        ("Notebook dois mil e quinhentos reais no pix", "2500"),
        ("Farmácia 89 vírgula 90 no débito", "89.90"),
        ("Farmácia oitenta e nove vírgula noventa no débito", "89.90"),
        ("Mercado R$ 1.250,90 no débito", "1250.90"),
        ("Mercado 89.90 no débito", "89.90"),
        ("Farmácia, oitenta e nove reais em dinheiro", "89"),
        ("Padaria cem e cinquenta no pix", "100.50"),
        ("Comprei 2 pizzas de 50 reais no pix", "50")
    ])
    func recognizesBrazilianAmounts(phrase: String, expected: String) {
        let draft = parse(phrase)
        #expect(draft.amount == Decimal(string: expected)!, "\(phrase)")
        #expect(!draft.issues.contains(.missingAmount))
        #expect(!draft.issues.contains(.ambiguousAmount))
    }

    @Test func amountAndInstallmentsAreKeptApart() {
        let draft = parse("Comprei um tênis de seiscentos reais em três vezes no cartão Itaú", cards: [VoiceCardCandidate(id: UUID(), name: "Itaú")])
        #expect(draft.amount == 600)
        #expect(draft.installmentCount == 3)
        #expect(draft.title == "Tênis")
        #expect(parse("Geladeira 3000 reais em 10x no cartão Nubank").installmentCount == 10)
        #expect(parse("Geladeira 3000 reais parcelado em seis vezes no cartão Nubank").amount == 3000)
        #expect(parse("Sofá 1800 reais em 6 parcelas no cartão Nubank").installmentCount == 6)
    }

    @Test func missingAmountIsNeverInvented() {
        let draft = parse("Mercado no débito")
        #expect(draft.amount == nil)
        #expect(draft.issues.contains(.missingAmount))
    }

    @Test func conflictingAmountsAreLeftForTheUser() {
        let draft = parse("Mercado 50 reais e 60 reais no pix")
        #expect(draft.amount == nil)
        #expect(draft.issues.contains(.ambiguousAmount))
    }

    @Test func cardNamesWithDigitsAreNotAmounts() {
        let c6 = VoiceCardCandidate(id: UUID(), name: "C6")
        let draft = parse("Uber 35 reais no cartão C6", cards: [c6, nubank])
        #expect(draft.amount == 35)
        #expect(draft.creditCardID == c6.id)
    }
}

@Suite("Voice parser – type and method")
@MainActor
struct VoiceTypeAndMethodTests {
    @Test(arguments: [
        ("Almoço quarenta reais no Pix", PaymentMethod.pix),
        ("Mercado cinquenta reais no débito", PaymentMethod.debit),
        ("Mercado cinquenta reais no cartão de débito", PaymentMethod.debit),
        ("Uber trinta reais no crédito", PaymentMethod.creditCard),
        ("Farmácia oitenta reais em dinheiro", PaymentMethod.cash),
        ("Paguei cento e cinquenta reais de internet no boleto", PaymentMethod.bankSlip)
    ])
    func recognizesPaymentMethods(phrase: String, method: PaymentMethod) {
        let draft = parse(phrase)
        #expect(draft.paymentMethod == method, "\(phrase)")
        #expect(draft.type == .expense)
    }

    @Test func recognizesIncome() {
        let draft = parse("Recebi três mil reais de pagamento")
        #expect(draft.type == .income)
        #expect(draft.amount == 3000)
        #expect(draft.title == "Pagamento")
        #expect(draft.categoryID == category("Salary", .income))
        #expect(parse("Recebi três mil reais de salário").type == .income)
    }

    @Test func recognizesInvestmentSeparately() {
        let draft = parse("Investi dois mil reais em CDB")
        #expect(draft.type == .investment)
        #expect(draft.title == "CDB")
        #expect(draft.categoryID == category("Investments", .investment))
        #expect(draft.categoryID != category("Investments", .income))
        #expect(draft.paymentMethod == nil)
        #expect(parse("Investi mil reais no cartão Nubank").issues.contains(.creditCardNotAllowed))
    }

    @Test func unrelatedWordsDoNotImplyIncomeOrInvestment() {
        let draft = parse("Xpto quarenta reais")
        #expect(draft.type == nil)
        #expect(draft.issues.contains(.unknownType))
        #expect(parse("Paguei o salário da diarista 200 reais no pix").type == .expense)
    }

    @Test func conflictingMethodsAreNotGuessed() {
        let draft = parse("Mercado 50 reais no pix e no dinheiro")
        #expect(draft.paymentMethod == nil)
        #expect(draft.issues.contains(.conflictingPaymentMethods))
    }
}

@Suite("Voice parser – cards, categories, titles, dates")
@MainActor
struct VoiceMatchingTests {
    @Test func matchesAKnownCardByShortName() {
        let draft = parse("Uber, 35 reais no cartão Azul")
        #expect(draft.paymentMethod == .creditCard)
        #expect(draft.creditCardID == azulGold.id)
        #expect(draft.title == "Uber")
    }

    @Test func ambiguousCardIsLeftForTheUser() {
        let draft = parse("Uber 35 reais no cartão Azul", cards: [azulGold, itauAzul])
        #expect(draft.creditCardID == nil)
        #expect(Set(draft.creditCardCandidateIDs) == [azulGold.id, itauAzul.id])
        #expect(draft.issues.contains(.ambiguousCard))
        // The full name resolves it.
        #expect(parse("Uber 35 reais no cartão Itaú Azul", cards: [azulGold, itauAzul]).creditCardID == itauAzul.id)
    }

    @Test func unknownCardIsNeverSilentlyPicked() {
        let draft = parse("Uber 35 reais no cartão Inter")
        #expect(draft.creditCardID == nil)
        #expect(draft.issues.contains(.cardNotRecognized(spokenName: "Inter")))
        let unnamed = parse("Uber 35 reais no cartão de crédito")
        #expect(unnamed.creditCardID == nil)
        #expect(unnamed.issues.contains(.cardNotRecognized(spokenName: nil)))
        #expect(parse("Uber 35 reais no cartão de crédito", cards: [nubank]).creditCardID == nubank.id)
    }

    @Test func installmentsNeedACard() {
        let draft = parse("Tênis 600 reais em 3 vezes no pix")
        #expect(draft.amount == 600)
        #expect(draft.installmentCount == nil)
        #expect(draft.issues.contains(.installmentsWithoutCard))
    }

    @Test func suggestsBuiltInCategoriesConservatively() {
        #expect(parse("Mercado 50 reais no pix").categoryID == category("Food"))
        #expect(parse("Uber 30 reais no pix").categoryID == category("Transport"))
        #expect(parse("Farmácia 80 reais no pix").categoryID == category("Health"))
        #expect(parse("Paguei 150 reais de internet no boleto").categoryID == category("Housing"))
        let explicit = parse("Lanche 20 reais no pix categoria educação")
        #expect(explicit.categoryID == category("Education"))
    }

    @Test func unknownCategoryIsLeftEmpty() {
        let draft = parse("Xpto 50 reais no pix")
        #expect(draft.categoryID == nil)
        #expect(draft.issues.contains(.missingCategory))
    }

    @Test func customCategoriesMatchByTheirOwnName() {
        let custom = VoiceCategoryCandidate(id: UUID(), storedName: "Padaria do Zé", displayName: "Padaria do Zé", type: .expense, isDefault: false)
        let draft = parse("Pão 12 reais no pix padaria do zé", categories: defaultCategories + [custom])
        #expect(draft.categoryID == custom.id)
    }

    @Test(arguments: [
        ("Mercado, 129 reais no débito", "Mercado"),
        ("Uber de 35 reais no cartão Nubank", "Uber"),
        ("Comprei um tênis de 600 reais em 3 vezes no cartão Nubank", "Tênis"),
        ("Investi dois mil reais em CDB", "CDB"),
        ("Paguei cento e cinquenta reais de internet no boleto", "Internet")
    ])
    func extractsConciseTitles(phrase: String, title: String) {
        #expect(parse(phrase).title == title, "\(phrase)")
    }

    @Test func datesDefaultToTodayAndSupportSimpleWords() {
        #expect(parse("Mercado 50 reais no pix").transactionDate == today)
        #expect(utc.isDate(parse("Mercado 50 reais no pix ontem").transactionDate, inSameDayAs: day(2026, 10, 20)))
        #expect(utc.isDate(parse("Mercado 50 reais no pix anteontem").transactionDate, inSameDayAs: day(2026, 10, 19)))
        #expect(utc.isDate(parse("Mercado 50 reais no pix dia 15").transactionDate, inSameDayAs: day(2026, 10, 15)))
        // A day after today means last month.
        #expect(utc.isDate(parse("Mercado 50 reais no pix dia 25").transactionDate, inSameDayAs: day(2026, 9, 25)))
        #expect(parse("Mercado 50 reais no pix dia 15").amount == 50)
    }

    @Test func targetPhraseProducesACompleteDraft() {
        let draft = parse("Mercado, cento e vinte e nove reais e noventa centavos no débito")
        #expect(draft.title == "Mercado")
        #expect(draft.amount == Decimal(string: "129.90")!)
        #expect(draft.type == .expense)
        #expect(draft.categoryID == category("Food"))
        #expect(draft.paymentMethod == .debit)
        #expect(draft.transactionDate == today)
        #expect(draft.issues.isEmpty)
    }
}

@Suite("Voice entry persistence")
@MainActor
struct VoiceEntryPersistenceTests {
    private struct Store {
        let context: ModelContext
        let categories: [TransactionCategory]
        let card: CreditCard
        @MainActor var parser: TransactionVoiceParser {
            TransactionVoiceParser(categories: categories.map { VoiceCategoryCandidate($0) }, creditCards: [VoiceCardCandidate(card)], today: today, calendar: utc)
        }
    }

    private func store() throws -> Store {
        let context = try TestStore.context()
        let categories = TransactionCategory.makeDefaults()
        categories.forEach(context.insert)
        let card = CreditCard(name: "Itaú", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 10_000)
        context.insert(card)
        try context.save()
        return Store(context: context, categories: categories, card: card)
    }

    /// What the review form saves when the user taps Save without changes.
    private func entry(_ draft: VoiceTransactionDraft, in store: Store, paymentMethod: PaymentMethod? = nil) throws -> TransactionEntry {
        TransactionEntry(
            title: try #require(draft.title),
            amount: try #require(draft.amount),
            type: draft.type ?? .expense,
            category: try #require(store.categories.first { $0.id == draft.categoryID }),
            date: draft.transactionDate,
            notes: "",
            paymentMethod: paymentMethod ?? draft.paymentMethod ?? .debit,
            creditCard: draft.creditCardID == store.card.id ? store.card : nil,
            installmentCount: draft.installmentCount ?? 1
        )
    }

    @Test func parsingNeverPersistsAnything() throws {
        let store = try store()
        for _ in 0..<3 {
            _ = store.parser.parse("Mercado, cento e vinte e nove reais e noventa centavos no débito")
            _ = store.parser.parse("Comprei um tênis de seiscentos reais em três vezes no cartão Itaú")
        }
        #expect(try store.context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<CreditCardInvoice>()) == 0)
        #expect(!store.context.hasChanges)
    }

    @Test func confirmedDebitDraftSavesLikeAManualEntry() throws {
        let store = try store()
        let draft = store.parser.parse("Mercado, cento e vinte e nove reais e noventa centavos no débito")
        try entry(draft, in: store).save(in: store.context, calendar: utc)
        let saved = try #require(try store.context.fetch(FetchDescriptor<Transaction>()).first)
        #expect(saved.title == "Mercado")
        #expect(saved.amount == Decimal(string: "129.90")!)
        #expect(saved.paymentMethod == .debit)
        #expect(saved.category?.name == "Food")
        #expect(saved.creditCardInvoice == nil)
    }

    @Test func cardDraftUsesThePurchaseServiceForInstallments() throws {
        let store = try store()
        let draft = store.parser.parse("Comprei um tênis de seiscentos reais em três vezes no cartão Itaú")
        try entry(draft, in: store).save(in: store.context, calendar: utc)
        let installments = try store.context.fetch(FetchDescriptor<Transaction>()).sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        #expect(installments.count == 3)
        #expect(installments.map(\.amount) == [200, 200, 200])
        #expect(installments.allSatisfy { $0.creditCard?.id == store.card.id && $0.creditCardInvoice != nil })
        #expect(Set(installments.compactMap(\.sourcePurchaseID)).count == 1)
        #expect(installments.first?.creditCardInvoice?.closingDate == utc.date(from: DateComponents(year: 2026, month: 11, day: 9)))
    }

    @Test func voiceInvestmentStaysOutOfIncomeAndExpenses() throws {
        let store = try store()
        let draft = store.parser.parse("Investi dois mil reais em CDB")
        try entry(draft, in: store, paymentMethod: .pix).save(in: store.context, calendar: utc)
        let snapshot = MonthlyFinanceSnapshot(transactions: try store.context.fetch(FetchDescriptor<Transaction>()), date: today, calendar: utc)
        #expect(snapshot.investments == 2000)
        #expect(snapshot.expenses == 0)
        #expect(snapshot.income == 0)
    }
}
