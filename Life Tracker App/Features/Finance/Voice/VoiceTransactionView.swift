import SwiftData
import SwiftUI

#if os(iOS)
/// Voice entry: listen, show what was heard, then open the regular Add
/// Transaction form prefilled for review. Nothing is saved until the user taps
/// Save in that form.
struct VoiceTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]

    @State private var service = VoiceTransactionService()
    @State private var draft: VoiceTransactionDraft?
    @State private var entersManually = false

    var body: some View {
        if let draft {
            AddTransactionView(voiceDraft: draft, onTryAgain: tryAgain)
                .id(draft.originalTranscript)
        } else if entersManually {
            AddTransactionView()
        } else {
            NavigationStack {
                listeningContent
                    .navigationTitle("Add by Voice")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                service.cancel()
                                dismiss()
                            }
                        }
                    }
            }
            .task { await service.start() }
            .onChange(of: service.state) {
                if service.state == .finished {
                    draft = parser.parse(service.transcript)
                }
            }
            .onDisappear { service.cancel() }
        }
    }

    private var parser: TransactionVoiceParser {
        TransactionVoiceParser(
            categories: categories.map { VoiceCategoryCandidate($0) },
            creditCards: creditCards.filter(\.isActive).map { VoiceCardCandidate($0) }
        )
    }

    private func tryAgain() {
        draft = nil
        Task { await service.start() }
    }

    // MARK: States

    @ViewBuilder
    private var listeningContent: some View {
        VStack(spacing: 24) {
            Spacer()

            switch service.state {
            case .failed(let failure):
                failureContent(failure)
            default:
                microphone
                transcriptView
                hint
            }

            Spacer()

            if service.state == .listening {
                HStack(spacing: 16) {
                    Button("Cancel", role: .cancel) {
                        service.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Stop", systemImage: "stop.fill") {
                        service.stop()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }

            privacyNote
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var microphone: some View {
        let isListening = service.state == .listening
        return Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: 88))
            .foregroundStyle(isListening ? .red : .accentColor)
            .symbolEffect(.pulse, isActive: isListening)
            .accessibilityLabel(isListening ? Text("Listening") : Text("Preparing microphone"))
    }

    @ViewBuilder
    private var transcriptView: some View {
        if service.transcript.isEmpty {
            Text(service.state == .listening ? "Listening…" : "Preparing microphone…")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else {
            Text(service.transcript)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .accessibilityLabel(Text("Heard: \(service.transcript)"))
        }
    }

    private var hint: some View {
        VStack(spacing: 6) {
            Text("Speak in Brazilian Portuguese, for example:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: "“Mercado, cento e vinte e nove reais no débito”")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var privacyNote: some View {
        if service.allowsServerRecognition {
            Label("Recognized by Apple's servers for this session. Audio is not stored.", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("Recognized on this iPhone. Audio is not stored.", systemImage: "lock.iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func failureContent(_ failure: VoiceTransactionService.Failure) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(failureMessage(failure))
                .multilineTextAlignment(.center)

            switch failure {
            case .speechDenied, .microphoneDenied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            case .onDeviceUnavailable:
                Button("Use Apple's Servers This Time") {
                    service.allowServerRecognition()
                    Task { await service.start() }
                }
                .buttonStyle(.borderedProminent)
            default:
                Button("Try Again") {
                    Task { await service.start() }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Enter Manually") {
                service.cancel()
                entersManually = true
            }
        }
    }

    private func failureMessage(_ failure: VoiceTransactionService.Failure) -> LocalizedStringKey {
        switch failure {
        case .speechDenied:
            "Speech recognition is turned off for LifeTracker. Allow it in Settings to add transactions by voice."
        case .microphoneDenied:
            "Microphone access is turned off for LifeTracker. Allow it in Settings to add transactions by voice."
        case .restricted:
            "Speech recognition is restricted on this device."
        case .recognizerUnavailable:
            "Speech recognition for Brazilian Portuguese is not available right now."
        case .onDeviceUnavailable:
            "This iPhone cannot recognize Brazilian Portuguese on device. You can let Apple's servers recognize this phrase, or enter it manually."
        case .dictationDisabled:
            "Voice recognition on this iPhone needs Dictation. Turn it on in Settings › General › Keyboard › Enable Dictation, then try again."
        case .nothingHeard:
            "Nothing was heard. Try again closer to the microphone."
        case .recognition(let message):
            "Speech recognition failed: \(message)"
        case .audio(let message):
            "The microphone could not start: \(message)"
        }
    }
}
#endif

/// Top of the review form: what was heard and what still needs checking.
struct VoiceDraftReviewSection: View {
    let draft: VoiceTransactionDraft
    let onTryAgain: (() -> Void)?

    var body: some View {
        Section {
            Label {
                Text(verbatim: "“\(draft.originalTranscript)”")
                    .italic()
            } icon: {
                Image(systemName: "waveform")
            }
            .accessibilityLabel(Text("Heard: \(draft.originalTranscript)"))

            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            }

            if let onTryAgain {
                Button("Try Again", systemImage: "mic", action: onTryAgain)
            }
        } header: {
            Text("Voice Entry")
        } footer: {
            Text("Check the fields below, then tap Save. Nothing is saved until you do.")
        }
    }

    private var messages: [String] {
        Self.order.compactMap { kind in
            draft.issues.first { Self.kind(of: $0) == kind }.map { Self.message($0) }
        }
    }

    private static let order = ["amount", "type", "method", "card", "installments", "category", "title"]

    private static func kind(of issue: VoiceTransactionDraft.Issue) -> String {
        switch issue {
        case .missingAmount, .ambiguousAmount: "amount"
        case .unknownType: "type"
        case .unknownPaymentMethod, .conflictingPaymentMethods, .creditCardNotAllowed: "method"
        case .cardNotRecognized, .ambiguousCard: "card"
        case .installmentsWithoutCard, .unsupportedInstallmentCount: "installments"
        case .missingCategory: "category"
        case .missingTitle: "title"
        }
    }

    private static func message(_ issue: VoiceTransactionDraft.Issue) -> String {
        switch issue {
        case .missingAmount:
            AppLocalization.string("No amount was recognized. Enter the amount.")
        case .ambiguousAmount:
            AppLocalization.string("More than one amount was heard. Enter the correct amount.")
        case .unknownType:
            AppLocalization.string("Check whether this is an expense, income or investment.")
        case .unknownPaymentMethod:
            AppLocalization.string("No payment method was recognized. Check the payment method.")
        case .conflictingPaymentMethods:
            AppLocalization.string("More than one payment method was heard. Choose the right one.")
        case .creditCardNotAllowed:
            AppLocalization.string("Investments cannot be paid by credit card. Choose another payment method.")
        case .cardNotRecognized(let spokenName?):
            AppLocalization.string("No registered card matches “\(spokenName)”. Choose the card.")
        case .cardNotRecognized(nil):
            AppLocalization.string("Choose which credit card was used.")
        case .ambiguousCard:
            AppLocalization.string("More than one card matches. Choose the card.")
        case .installmentsWithoutCard:
            AppLocalization.string("Installments need a credit card. Choose the card or remove the installments.")
        case .unsupportedInstallmentCount:
            AppLocalization.string("The number of installments was not understood. Check the installments.")
        case .missingCategory:
            AppLocalization.string("Choose a category.")
        case .missingTitle:
            AppLocalization.string("Enter a title.")
        }
    }
}
