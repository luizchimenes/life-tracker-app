import SwiftData
import SwiftUI

struct CreditCardDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let creditCard: CreditCard

    @Query private var invoices: [CreditCardInvoice]
    @Query private var transactions: [Transaction]

    @State private var showsPaymentError = false
    @State private var paymentErrorMessage = ""

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var cardInvoices: [CreditCardInvoice] {
        invoices
            .filter { $0.creditCard.id == creditCard.id }
            .sorted { $0.dueDate > $1.dueDate }
    }

    var body: some View {
        List {
            if cardInvoices.isEmpty {
                ContentUnavailableView(
                    "No Invoices",
                    systemImage: "doc.text",
                    description: Text("Invoices appear after the first credit-card purchase.")
                )
            } else {
                ForEach(cardInvoices) { invoice in
                    invoiceSection(invoice)
                }
            }
        }
        .navigationTitle(creditCard.name)
        .alert("Unable to Update Invoice", isPresented: $showsPaymentError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paymentErrorMessage)
        }
    }

    @ViewBuilder
    private func invoiceSection(_ invoice: CreditCardInvoice) -> some View {
        let purchases = purchases(for: invoice)
        let total = purchases.reduce(Decimal.zero) { $0 + $1.amount }
        let status = invoice.effectiveStatus()

        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(total.formatted(currencyFormat))
                        .font(.title3.bold())

                    Spacer()

                    Text(status.displayName)
                        .font(.caption)
                        .foregroundStyle(status == .paid ? .green : .secondary)
                }

                Text("Closes \(invoice.closingDate.formatted(date: .abbreviated, time: .omitted))")
                Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")

                if status == .closed {
                    Button("Mark as Paid") {
                        markAsPaid(invoice)
                    }
                    .padding(.top, 4)
                } else if status == .open {
                    Label(
                        "Payment becomes available after this invoice closes.",
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .font(.subheadline)

            ForEach(purchases) { purchase in
                NavigationLink {
                    TransactionDetailView(transaction: purchase)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(purchase.title)

                            if let number = purchase.installmentNumber,
                               let count = purchase.totalInstallments,
                               count > 1 {
                                Text("\(number)/\(count) • Financial \(purchase.effectiveFinancialDate, format: .dateTime.day().month())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(purchase.amount.formatted(currencyFormat))
                            .fontWeight(.medium)
                    }
                }
            }
        } header: {
            Text(
                invoice.referenceMonth,
                format: .dateTime.month(.wide).year()
            )
        }
    }

    private func purchases(
        for invoice: CreditCardInvoice
    ) -> [Transaction] {
        transactions
            .filter { $0.creditCardInvoice?.id == invoice.id }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    private func markAsPaid(_ invoice: CreditCardInvoice) {
        do {
            try CreditCardInvoicePaymentService.markPaid(
                invoice,
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }
}
