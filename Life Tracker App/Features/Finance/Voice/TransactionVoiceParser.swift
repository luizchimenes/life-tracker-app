import Foundation

/// Deterministic interpretation of a spoken Brazilian Portuguese phrase such as
/// "Mercado, cento e vinte e nove reais e noventa centavos no débito".
///
/// It recognizes everyday patterns only and never guesses: anything missing,
/// ambiguous or contradictory is left empty and reported as an issue for the
/// review form. It does not apply finance rules; saving goes through the
/// regular transaction form and services.
struct TransactionVoiceParser {
    let categories: [VoiceCategoryCandidate]
    let creditCards: [VoiceCardCandidate]
    var today: Date = .now
    var calendar: Calendar = .current

    func parse(_ transcript: String) -> VoiceTransactionDraft {
        var tokens = Tokenizer.tokenize(transcript)
        var draft = VoiceTransactionDraft(originalTranscript: transcript, transactionDate: today)

        draft.type = detectType(tokens)
        if draft.type == nil {
            draft.issues.insert(.unknownType)
        }

        detectPaymentMethod(&tokens, draft: &draft)
        detectInstallments(&tokens, draft: &draft)
        detectDate(&tokens, draft: &draft)
        detectAmount(&tokens, draft: &draft)
        draft.title = extractTitle(tokens)
        if draft.title == nil {
            draft.issues.insert(.missingTitle)
        }
        draft.categoryID = suggestCategory(tokens, type: draft.type ?? .expense, title: draft.title)
        if draft.categoryID == nil {
            draft.issues.insert(.missingCategory)
        }
        return draft
    }

    // MARK: Type

    private static let investmentWords: Set<String> = ["investi", "investir", "investimento", "aporte", "aportei", "apliquei", "aplicacao"]
    private static let incomeWords: Set<String> = ["recebi", "recebido", "recebimento", "ganhei", "salario", "rendimento", "rendimentos"]
    private static let spendingWords: Set<String> = ["comprei", "paguei", "gastei", "compra", "pagamento", "conta"]

    private func detectType(_ tokens: [Token]) -> TransactionType? {
        let words = Set(tokens.compactMap(\.word))
        if !words.isDisjoint(with: Self.investmentWords) {
            return .investment
        }
        // "pagamento" alone is ambiguous, so income needs an income verb or word.
        if !words.isDisjoint(with: Self.incomeWords) && !words.contains("paguei") && !words.contains("gastei") {
            return .income
        }
        let mentionsMethod = !words.isDisjoint(with: ["pix", "debito", "credito", "cartao", "dinheiro", "boleto", "especie"])
        if mentionsMethod || !words.isDisjoint(with: Self.spendingWords) || matchesExpenseKeyword(words) {
            return .expense
        }
        return nil
    }

    // MARK: Payment method and card

    private func detectPaymentMethod(_ tokens: inout [Token], draft: inout VoiceTransactionDraft) {
        var found: Set<PaymentMethod> = []
        for index in tokens.indices {
            guard let word = tokens[index].word else { continue }
            switch word {
            case "pix": found.insert(.pix); tokens[index].consumed = true
            case "debito": found.insert(.debit); tokens[index].consumed = true
            case "dinheiro", "especie": found.insert(.cash); tokens[index].consumed = true
            case "boleto": found.insert(.bankSlip); tokens[index].consumed = true
            case "credito": found.insert(.creditCard); tokens[index].consumed = true
            case "cartao":
                tokens[index].consumed = true
                // "cartão de débito" is debit, not a credit card.
                if !Self.followingWords(tokens, after: index, count: 2).contains("debito") {
                    found.insert(.creditCard)
                }
            default: break
            }
        }

        guard !found.isEmpty else {
            if draft.type == .expense || draft.type == .investment {
                draft.issues.insert(.unknownPaymentMethod)
            }
            return
        }
        guard found.count == 1, let method = found.first else {
            draft.issues.insert(.conflictingPaymentMethods)
            return
        }
        if draft.type == .income {
            return
        }
        if method == .creditCard && draft.type == .investment {
            draft.issues.insert(.creditCardNotAllowed)
            return
        }
        draft.paymentMethod = method
        if method == .creditCard {
            matchCard(&tokens, draft: &draft)
        }
    }

    private func matchCard(_ tokens: inout [Token], draft: inout VoiceTransactionDraft) {
        let words = tokens.map { $0.word ?? "" }
        let cards = creditCards.map { (card: $0, words: Tokenizer.tokenize($0.name).compactMap(\.word)) }

        // 1. A registered card name said in full ("Itaú Azul").
        let full = cards.compactMap { entry -> (VoiceCardCandidate, Range<Int>)? in
            guard !entry.words.isEmpty, let range = Self.find(entry.words, in: words) else { return nil }
            return (entry.card, range)
        }
        if !full.isEmpty {
            let longest = full.map(\.1.count).max() ?? 0
            let best = full.filter { $0.1.count == longest }
            if best.count == 1 {
                draft.creditCardID = best[0].0.id
                best[0].1.forEach { tokens[$0].consumed = true }
            } else {
                draft.creditCardCandidateIDs = best.map(\.0.id)
                draft.issues.insert(.ambiguousCard)
            }
            return
        }

        // 2. A shortened name right after "cartão" ("cartão Azul").
        if let cartao = words.firstIndex(of: "cartao"),
           let spokenIndex = Self.nextNameWord(tokens, after: cartao) {
            let spoken = words[spokenIndex]
            let partial = cards.filter { $0.words.contains(spoken) }.map(\.card)
            switch partial.count {
            case 1:
                draft.creditCardID = partial[0].id
                tokens[spokenIndex].consumed = true
            case 0:
                draft.issues.insert(.cardNotRecognized(spokenName: tokens[spokenIndex].original))
                tokens[spokenIndex].consumed = true
            default:
                draft.creditCardCandidateIDs = partial.map(\.id)
                draft.issues.insert(.ambiguousCard)
                tokens[spokenIndex].consumed = true
            }
            return
        }

        // 3. No name: only a single registered card is unambiguous.
        if creditCards.count == 1 {
            draft.creditCardID = creditCards[0].id
        } else {
            draft.creditCardCandidateIDs = creditCards.map(\.id)
            draft.issues.insert(.cardNotRecognized(spokenName: nil))
        }
    }

    private static let nameSkipWords: Set<String> = ["de", "do", "da", "credito", "meu", "minha", "o", "a"]
    private static let nameStopWords: Set<String> = ["em", "no", "na", "parcelado", "parcelada", "vezes", "x", "e", "hoje", "ontem", "dia"]

    private static func nextNameWord(_ tokens: [Token], after index: Int) -> Int? {
        var cursor = index + 1
        while cursor < tokens.count {
            guard let word = tokens[cursor].word else { return nil }
            if nameStopWords.contains(word) { return nil }
            if !nameSkipWords.contains(word) && NumberWords.value(of: word) == nil {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    // MARK: Installments

    private static let installmentWords: Set<String> = ["vezes", "vez", "parcelas", "parcela", "x"]

    private func detectInstallments(_ tokens: inout [Token], draft: inout VoiceTransactionDraft) {
        let numbers = NumberGrouping.group(tokens)
        var count: Int?
        for number in numbers {
            let next = number.range.upperBound
            let isInstallment = number.explicitInstallment
                || (next < tokens.count && tokens[next].word.map(Self.installmentWords.contains) == true)
            guard isInstallment, let value = number.integerValue else { continue }
            count = value
            number.range.forEach { tokens[$0].consumed = true }
            if next < tokens.count, tokens[next].word.map(Self.installmentWords.contains) == true {
                tokens[next].consumed = true
            }
        }
        if count == nil, tokens.contains(where: { $0.word == "parcelado" || $0.word == "parcelada" }) {
            draft.issues.insert(.unsupportedInstallmentCount)
        }
        guard let count else { return }

        if count == 1 { return }
        guard (2...36).contains(count) else {
            draft.issues.insert(.unsupportedInstallmentCount)
            return
        }
        guard draft.paymentMethod == .creditCard else {
            draft.issues.insert(.installmentsWithoutCard)
            return
        }
        draft.installmentCount = count
    }

    // MARK: Date

    private func detectDate(_ tokens: inout [Token], draft: inout VoiceTransactionDraft) {
        for index in tokens.indices {
            switch tokens[index].word {
            case "hoje":
                tokens[index].consumed = true
            case "ontem":
                tokens[index].consumed = true
                draft.transactionDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            case "anteontem":
                tokens[index].consumed = true
                draft.transactionDate = calendar.date(byAdding: .day, value: -2, to: today) ?? today
            case "dia":
                let numbers = NumberGrouping.group(tokens).filter { $0.range.lowerBound == index + 1 }
                guard let number = numbers.first, let day = number.integerValue, (1...31).contains(day),
                      let date = mostRecentDate(onDay: day) else { continue }
                tokens[index].consumed = true
                number.range.forEach { tokens[$0].consumed = true }
                draft.transactionDate = date
            default:
                break
            }
        }
    }

    /// "Dia 15" means the latest 15th that is not in the future.
    private func mostRecentDate(onDay day: Int) -> Date? {
        let todayDay = calendar.component(.day, from: today)
        let monthOffset = day <= todayDay ? 0 : -1
        guard let month = calendar.date(byAdding: .month, value: monthOffset, to: today),
              let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
        var components = calendar.dateComponents([.year, .month, .hour, .minute], from: month)
        components.day = min(day, range.count)
        return calendar.date(from: components)
    }

    // MARK: Amount

    private func detectAmount(_ tokens: inout [Token], draft: inout VoiceTransactionDraft) {
        let candidates = AmountCandidates.find(in: tokens)
        let marked = candidates.filter(\.isMarked)
        let pool = marked.isEmpty ? candidates : marked
        let values = Set(pool.map(\.value))

        guard let value = values.first else {
            draft.issues.insert(.missingAmount)
            return
        }
        guard values.count == 1, value > 0 else {
            draft.issues.insert(.ambiguousAmount)
            return
        }
        draft.amount = value
        for candidate in pool {
            candidate.range.forEach { tokens[$0].consumed = true }
        }
        // Currency words never belong to the title.
        for index in tokens.indices where tokens[index].word.map(AmountCandidates.currencyWords.contains) == true {
            tokens[index].consumed = true
        }
    }

    // MARK: Title

    private static let titleStopWords: Set<String> = [
        "de", "do", "da", "dos", "das", "em", "no", "na", "nos", "nas", "o", "a", "os", "as",
        "um", "uma", "uns", "umas", "e", "com", "por", "para", "pra", "pro", "foi", "ou",
        "comprei", "paguei", "gastei", "investi", "investir", "apliquei", "aportei", "recebi", "ganhei",
        "reais", "real", "centavos", "centavo", "virgula", "vezes", "vez", "parcelas", "parcela",
        "parcelado", "parcelada", "avista", "vista", "hoje", "ontem", "anteontem", "dia", "valor", "r$"
    ]

    private func extractTitle(_ tokens: [Token]) -> String? {
        // "Mercado, 129 reais…": the words before the first comma name it.
        if let comma = tokens.firstIndex(where: \.isComma) {
            let segment = Array(tokens[..<comma])
            if !segment.isEmpty, segment.allSatisfy({ $0.word != nil && NumberWords.value(of: $0.word!) == nil }) {
                if let title = Self.title(from: segment.filter { !Self.titleStopWords.contains($0.word ?? "") }) {
                    return title
                }
            }
        }
        let remaining = tokens.filter { token in
            guard let word = token.word, !token.consumed else { return false }
            return !Self.titleStopWords.contains(word) && NumberWords.value(of: word) == nil
        }
        return Self.title(from: remaining)
    }

    private static func title(from tokens: [Token]) -> String? {
        let text = tokens.map(\.original).joined(separator: " ")
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Category

    /// Conservative keywords for built-in categories, keyed by stored name.
    private static let keywords: [String: Set<String>] = [
        "Food": ["mercado", "supermercado", "restaurante", "almoco", "jantar", "lanche", "padaria", "ifood", "cafe", "pizza", "acougue", "feira", "hortifruti"],
        "Transport": ["uber", "taxi", "onibus", "metro", "gasolina", "combustivel", "estacionamento", "pedagio", "posto", "trem"],
        "Health": ["farmacia", "remedio", "remedios", "medico", "consulta", "dentista", "exame", "hospital"],
        "Housing": ["aluguel", "condominio", "luz", "energia", "agua", "gas", "internet", "iptu"],
        "Entertainment": ["cinema", "show", "teatro", "ingresso", "bar"],
        "Shopping": ["roupa", "roupas", "tenis", "sapato", "loja", "presente", "shopping"],
        "Education": ["curso", "escola", "faculdade", "livro", "livros", "mensalidade"],
        "Subscriptions": ["netflix", "spotify", "icloud", "assinatura", "streaming", "youtube", "disney"],
        "Salary": ["salario", "pagamento"],
        "Freelance": ["freela", "freelance", "freelancer"],
        "Refund": ["reembolso", "estorno"]
    ]

    private func matchesExpenseKeyword(_ words: Set<String>) -> Bool {
        let expenseNames: Set<String> = ["Food", "Transport", "Health", "Housing", "Entertainment", "Shopping", "Education", "Subscriptions"]
        return Self.keywords.contains { expenseNames.contains($0.key) && !$0.value.isDisjoint(with: words) }
    }

    private func suggestCategory(_ tokens: [Token], type: TransactionType, title: String?) -> UUID? {
        let compatible = categories.filter { $0.type.supports(type) }
        let words = tokens.compactMap(\.word)

        // 1. A category name said explicitly (built-in or custom).
        let named = compatible.filter { candidate in
            [candidate.displayName, candidate.storedName].contains { name in
                let nameWords = Tokenizer.tokenize(name).compactMap(\.word)
                return !nameWords.isEmpty && Self.find(nameWords, in: words) != nil
            }
        }
        if named.count == 1 {
            return named[0].id
        }

        // 2. A single category of that type is unambiguous (e.g. Investments).
        if type == .investment, compatible.count == 1 {
            return compatible[0].id
        }

        // 3. Keywords for built-in categories.
        let wordSet = Set(words)
        let matches = compatible.filter { candidate in
            candidate.isDefault && (Self.keywords[candidate.storedName].map { !$0.isDisjoint(with: wordSet) } ?? false)
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    // MARK: Helpers

    fileprivate static func followingWords(_ tokens: [Token], after index: Int, count: Int) -> [String] {
        tokens.dropFirst(index + 1).prefix(count).compactMap(\.word)
    }

    fileprivate static func find(_ needle: [String], in haystack: [String]) -> Range<Int>? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return start..<(start + needle.count)
        }
        return nil
    }
}

// MARK: - Tokens

fileprivate struct Token {
    enum Kind {
        case word(String)
        case digits(Decimal, hasFraction: Bool, fractionDigits: Int)
        case installmentDigits(Int)
        case currency
        case comma
    }

    let kind: Kind
    let original: String
    var consumed = false

    var word: String? {
        if case .word(let word) = kind { return word }
        if case .currency = kind { return "r$" }
        return nil
    }

    var isComma: Bool {
        if case .comma = kind { return true }
        return false
    }
}

fileprivate enum Tokenizer {
    // Order matters: "3x" before plain digits, digits before alphanumeric words
    // so names like "C6" stay one word.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)(\d+x)(?![\p{L}\p{N}])|(r\$)|(\d+(?:[.,]\d+)*)(?![\p{L}])|([\p{L}\p{N}]*\p{L}[\p{L}\p{N}]*)|(,)"#
    )

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt-BR")).lowercased()
    }

    static func tokenize(_ text: String) -> [Token] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let original = ns.substring(with: match.range)
            if match.range(at: 1).location != NSNotFound {
                return Int(original.dropLast()).map { Token(kind: .installmentDigits($0), original: original) }
            }
            if match.range(at: 2).location != NSNotFound {
                return Token(kind: .currency, original: original)
            }
            if match.range(at: 3).location != NSNotFound {
                return digitsToken(original)
            }
            if match.range(at: 4).location != NSNotFound {
                return Token(kind: .word(normalize(original)), original: original)
            }
            return Token(kind: .comma, original: original)
        }
    }

    /// Brazilian formats: "1.250,90", "129,90", "89.90" (decimal when two
    /// digits follow the last separator), "1.250" (thousands).
    private static func digitsToken(_ text: String) -> Token? {
        let lastSeparator = text.lastIndex { $0 == "," || $0 == "." }
        var integerPart = text
        var fraction = ""
        if let lastSeparator {
            let tail = text[text.index(after: lastSeparator)...]
            if tail.count <= 2 {
                integerPart = String(text[..<lastSeparator])
                fraction = String(tail)
            }
        }
        integerPart.removeAll { $0 == "." || $0 == "," }
        let normalized = fraction.isEmpty ? integerPart : "\(integerPart).\(fraction)"
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Token(kind: .digits(value, hasFraction: !fraction.isEmpty, fractionDigits: fraction.count), original: text)
    }
}

// MARK: - Portuguese number words

fileprivate enum NumberWords {
    enum Magnitude: Int, Comparable {
        case closed = 0
        case unit = 1
        case ten = 2
        case hundred = 3
        case multiplier = 4

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let table: [String: (Int, Magnitude)] = [
        "zero": (0, .unit),
        "um": (1, .unit), "uma": (1, .unit), "dois": (2, .unit), "duas": (2, .unit), "tres": (3, .unit),
        "quatro": (4, .unit), "cinco": (5, .unit), "seis": (6, .unit), "sete": (7, .unit), "oito": (8, .unit), "nove": (9, .unit),
        // Teens close their group like units: nothing smaller can follow.
        "dez": (10, .unit), "onze": (11, .unit), "doze": (12, .unit), "treze": (13, .unit), "catorze": (14, .unit),
        "quatorze": (14, .unit), "quinze": (15, .unit), "dezesseis": (16, .unit), "dezasseis": (16, .unit),
        "dezessete": (17, .unit), "dezoito": (18, .unit), "dezenove": (19, .unit),
        "vinte": (20, .ten), "trinta": (30, .ten), "quarenta": (40, .ten), "cinquenta": (50, .ten),
        "sessenta": (60, .ten), "setenta": (70, .ten), "oitenta": (80, .ten), "noventa": (90, .ten),
        // "cem" is exactly 100: "cem e cinquenta" is R$ 100,50, not 150.
        "cem": (100, .closed), "cento": (100, .hundred),
        "duzentos": (200, .hundred), "duzentas": (200, .hundred), "trezentos": (300, .hundred), "trezentas": (300, .hundred),
        "quatrocentos": (400, .hundred), "quinhentos": (500, .hundred), "seiscentos": (600, .hundred),
        "setecentos": (700, .hundred), "oitocentos": (800, .hundred), "novecentos": (900, .hundred)
    ]

    static func value(of word: String) -> (value: Int, magnitude: Magnitude)? {
        table[word].map { (value: $0.0, magnitude: $0.1) }
    }
}

fileprivate struct SpokenNumber {
    let value: Decimal
    let range: Range<Int>
    let isInteger: Bool
    let fractionDigits: Int
    var explicitInstallment = false

    var integerValue: Int? {
        isInteger ? NSDecimalNumber(decimal: value).intValue : nil
    }
}

/// Groups digits and Portuguese number words into numbers, following how they
/// are spoken: "cento e vinte e nove" is 129, while "quarenta e dois e
/// cinquenta" is two numbers (42 and 50) because 50 cannot follow a unit.
fileprivate enum NumberGrouping {
    static func group(_ tokens: [Token]) -> [SpokenNumber] {
        var numbers: [SpokenNumber] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.consumed {
                index += 1
                continue
            }
            switch token.kind {
            case .digits(let value, let hasFraction, let fractionDigits):
                numbers.append(SpokenNumber(value: value, range: index..<(index + 1), isInteger: !hasFraction, fractionDigits: fractionDigits))
                index += 1
            case .installmentDigits(let value):
                numbers.append(SpokenNumber(value: Decimal(value), range: index..<(index + 1), isInteger: true, fractionDigits: 0, explicitInstallment: true))
                index += 1
            case .word(let word) where word == "mil" || NumberWords.value(of: word) != nil:
                if let number = words(from: index, in: tokens) {
                    numbers.append(number)
                    index = number.range.upperBound
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        return numbers
    }

    private static func words(from start: Int, in tokens: [Token]) -> SpokenNumber? {
        var total = 0
        var group = 0
        var last: NumberWords.Magnitude?
        var usedThousand = false
        var end = start
        var cursor = start
        var pendingAnd = false

        while cursor < tokens.count, !tokens[cursor].consumed, let word = tokens[cursor].word {
            if word == "mil" {
                guard !usedThousand, !pendingAnd else { break }
                total += max(group, 1) * 1_000
                group = 0
                last = .multiplier
                usedThousand = true
                cursor += 1
                end = cursor
                continue
            }
            if word == "e", last != nil {
                guard cursor + 1 < tokens.count,
                      let next = tokens[cursor + 1].word,
                      let entry = NumberWords.value(of: next),
                      let previous = last,
                      entry.magnitude < previous || previous == .multiplier else { break }
                pendingAnd = true
                cursor += 1
                continue
            }
            guard let entry = NumberWords.value(of: word) else { break }
            if let previous = last {
                // Without "e", only a new group after "mil" continues the number.
                guard pendingAnd || previous == .multiplier,
                      entry.magnitude < previous || previous == .multiplier else { break }
            }
            group += entry.value
            last = entry.magnitude
            pendingAnd = false
            cursor += 1
            end = cursor
        }

        guard end > start else { return nil }
        let range = start..<end
        // A lone "um"/"uma" is an article ("um tênis") unless money follows it.
        if range.count == 1, let word = tokens[start].word, word == "um" || word == "uma" {
            let next = end < tokens.count ? tokens[end].word : nil
            guard let next, ["reais", "real", "mil", "centavos", "centavo"].contains(next) else { return nil }
        }
        return SpokenNumber(value: Decimal(total + group), range: range, isInteger: true, fractionDigits: 0)
    }
}

// MARK: - Amount candidates

fileprivate enum AmountCandidates {
    static let currencyWords: Set<String> = ["reais", "real", "centavos", "centavo", "r$"]

    struct Candidate {
        let value: Decimal
        let range: Range<Int>
        /// Said with a currency word, cents or a decimal separator.
        let isMarked: Bool
    }

    static func find(in tokens: [Token]) -> [Candidate] {
        let numbers = NumberGrouping.group(tokens).filter { !$0.explicitInstallment }
        var candidates: [Candidate] = []
        var index = 0

        func word(at position: Int) -> String? {
            position < tokens.count ? tokens[position].word : nil
        }
        func numberStarting(at position: Int) -> SpokenNumber? {
            numbers.first { $0.range.lowerBound == position }
        }

        while index < numbers.count {
            let number = numbers[index]
            let after = number.range.upperBound
            let precededByCurrency = number.range.lowerBound > 0 && word(at: number.range.lowerBound - 1) == "r$"

            if !number.isInteger {
                candidates.append(Candidate(value: number.value, range: number.range, isMarked: true))
                index += 1
                continue
            }

            var cursor = after
            var saidReais = false
            if ["reais", "real"].contains(word(at: cursor)) {
                saidReais = true
                cursor += 1
            }

            // "89 vírgula 90"
            if word(at: cursor) == "virgula", let cents = numberStarting(at: cursor + 1), let fraction = fraction(cents) {
                candidates.append(Candidate(value: number.value + fraction, range: number.range.lowerBound..<cents.range.upperBound, isMarked: true))
                index += 2
                continue
            }

            // "129 reais e 90 centavos", "129 e 90", "quarenta e dois e cinquenta"
            if word(at: cursor) == "e", let cents = numberStarting(at: cursor + 1), cents.isInteger,
               let centsValue = cents.integerValue, (1...99).contains(centsValue) {
                let afterCents = cents.range.upperBound
                let saidCentavos = ["centavos", "centavo"].contains(word(at: afterCents))
                let followedByReais = ["reais", "real", "mil"].contains(word(at: afterCents))
                if saidCentavos || !followedByReais {
                    candidates.append(Candidate(
                        value: number.value + Decimal(centsValue) / 100,
                        range: number.range.lowerBound..<(saidCentavos ? afterCents + 1 : afterCents),
                        isMarked: true
                    ))
                    index += 2
                    continue
                }
            }

            // "noventa centavos" on its own
            if ["centavos", "centavo"].contains(word(at: after)), let cents = number.integerValue, cents < 100 {
                candidates.append(Candidate(value: Decimal(cents) / 100, range: number.range, isMarked: true))
                index += 1
                continue
            }

            candidates.append(Candidate(value: number.value, range: number.range, isMarked: saidReais || precededByCurrency))
            index += 1
        }
        return candidates
    }

    /// "90" → 0.90, "9" said in digits → 0.9, "noventa" → 0.90.
    private static func fraction(_ number: SpokenNumber) -> Decimal? {
        guard number.isInteger, let value = number.integerValue, (0...99).contains(value) else { return nil }
        let isSingleDigit = number.range.count == 1 && value < 10
        return Decimal(value) / (isSingleDigit ? 10 : 100)
    }
}
