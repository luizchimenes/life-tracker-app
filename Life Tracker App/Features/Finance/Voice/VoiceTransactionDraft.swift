import Foundation

/// What the voice parser understood from one spoken phrase.
///
/// Transient: it never touches SwiftData. It only prefills the regular Add
/// Transaction form, which validates and saves through the same path as a
/// manual entry. A `nil` field means "not understood"; the user fills it in.
struct VoiceTransactionDraft: Equatable {
    enum Issue: Hashable {
        case missingAmount
        case ambiguousAmount
        case unknownType
        case unknownPaymentMethod
        case conflictingPaymentMethods
        case cardNotRecognized(spokenName: String?)
        case ambiguousCard
        case installmentsWithoutCard
        case unsupportedInstallmentCount
        case creditCardNotAllowed
        case missingCategory
        case missingTitle
    }

    var originalTranscript: String
    var title: String?
    var amount: Decimal?
    var type: TransactionType?
    var categoryID: UUID?
    var paymentMethod: PaymentMethod?
    var creditCardID: UUID?
    /// Cards that matched equally well; the user picks one.
    var creditCardCandidateIDs: [UUID] = []
    var installmentCount: Int?
    var transactionDate: Date
    var issues: Set<Issue> = []
}

/// A category the parser may suggest, without exposing SwiftData models.
struct VoiceCategoryCandidate: Equatable {
    let id: UUID
    /// Stored name; identifies built-in categories ("Food", "Transport", …).
    let storedName: String
    /// Name shown to the user (localized for built-ins, as typed for custom).
    let displayName: String
    let type: TransactionCategoryType
    let isDefault: Bool
}

/// An active card the parser may match by name.
struct VoiceCardCandidate: Equatable {
    let id: UUID
    let name: String
}

extension VoiceCategoryCandidate {
    init(_ category: TransactionCategory) {
        self.init(
            id: category.id,
            storedName: category.name,
            displayName: category.displayName(),
            type: category.type,
            isDefault: category.isDefault
        )
    }
}

extension VoiceCardCandidate {
    init(_ card: CreditCard) {
        self.init(id: card.id, name: card.name)
    }
}
