import SwiftData
import SwiftUI

struct CreditCardsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]
    @Query private var invoices: [CreditCardInvoice]
    @Query private var transactions: [Transaction]

    @State private var showsAddCard = false
    @State private var cardToEdit: CreditCard?

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        NavigationStack {
            List {
                if creditCards.isEmpty {
                    ContentUnavailableView(
                        "No Credit Cards",
                        systemImage: "creditcard",
                        description: Text("Add a card to record credit-card purchases.")
                    )
                } else {
                    ForEach(creditCards) { card in
                        NavigationLink {
                            CreditCardDetailView(creditCard: card)
                        } label: {
                            cardRow(card)
                        }
                        .contextMenu {
                            Button("Edit") {
                                cardToEdit = card
                            }
                        }
                    }
                }
            }
            .navigationTitle("Credit Cards")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Add Credit Card", systemImage: "plus") {
                        showsAddCard = true
                    }
                }
            }
            .sheet(isPresented: $showsAddCard) {
                AddCreditCardView()
            }
            .sheet(item: $cardToEdit) { card in
                AddCreditCardView(creditCard: card)
            }
        }
#if os(macOS)
        .frame(minWidth: 680, minHeight: 620)
#endif
    }

    private func cardRow(_ card: CreditCard) -> some View {
        let dueInvoice = dueInvoice(for: card)
        let nextInvoice = nextInvoice(for: card)
        let availableLimit = CreditCardBalanceCalculator.availableLimit(
            for: card,
            invoices: invoices,
            transactions: transactions
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(Color.category(named: card.colorName))

                Text(card.name)
                    .font(.headline)

                Spacer()

                Text("•••• \(card.lastFourDigits)")
                    .foregroundStyle(.secondary)
            }

            if let dueInvoice {
                invoiceSummary(
                    title: "Current / Due Invoice",
                    invoice: dueInvoice,
                    dateLabel: "Due",
                    date: dueInvoice.dueDate
                )
            }

            if let nextInvoice {
                invoiceSummary(
                    title: "Next / Open Invoice",
                    invoice: nextInvoice,
                    dateLabel: "Closes",
                    date: nextInvoice.closingDate
                )
            }

            LabeledContent(
                "Available limit",
                value: availableLimit.formatted(currencyFormat)
            )
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private func dueInvoice(for card: CreditCard) -> CreditCardInvoice? {
        invoices
            .filter {
                $0.creditCard.id == card.id
                    && $0.effectiveStatus() == .closed
            }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    private func nextInvoice(for card: CreditCard) -> CreditCardInvoice? {
        invoices
            .filter {
                $0.creditCard.id == card.id
                    && $0.effectiveStatus() == .open
            }
            .sorted { $0.closingDate < $1.closingDate }
            .first
    }

    private func invoiceTotal(_ invoice: CreditCardInvoice) -> Decimal {
        invoice.total(in: transactions)
    }

    private func invoiceSummary(
        title: LocalizedStringKey,
        invoice: CreditCardInvoice,
        dateLabel: LocalizedStringKey,
        date: Date
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(invoiceTotal(invoice).formatted(currencyFormat))
                    .fontWeight(.semibold)
            }
            Spacer()
            LabeledContent(dateLabel) {
                Text(date, format: .dateTime.month(.abbreviated).day())
            }
            .font(.caption)
        }
    }

}
